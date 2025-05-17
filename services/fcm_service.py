#cspell:disable
import json
import logging
import os
from tenacity import retry, wait_exponential, stop_after_attempt
from typing import List, Dict, Tuple
import firebase_admin
from firebase_admin import credentials, messaging
from google.auth.exceptions import TransportError
from google.auth import default
from google.oauth2 import service_account
import asyncpg


logger = logging.getLogger(__name__)

class FirebaseMessagingService:
    def __init__(self, db_pool: asyncpg.Pool):
        self.db_pool = db_pool
        self._firebase_initialized = False

    async def _initialize_firebase(self):
        """Initialize Firebase only when needed."""
        if not self._firebase_initialized:
            if not firebase_admin._apps:
                service_account_path = os.path.join(os.path.dirname(__file__), '..', 'zinzi-fcm2-firebase-adminsdk-fbsvc-d81e9633e7.json')
                cred = credentials.Certificate(service_account_path)
                firebase_admin.initialize_app(cred, {
                    'projectId': 'zinzi-fcm2'
                })
            self._firebase_initialized = True







    @retry(wait=wait_exponential(multiplier=1, min=4, max=10), stop=stop_after_attempt(3))
    async def send_each_multicast(self, messages: List[messaging.Message]) -> Tuple[int, List[str]]:
        """Initialize Firebase and send notifications."""
        # Ensure Firebase is initialized
        await self._initialize_firebase()
        
        try:
            batch_response = messaging.send_each(messages)
            successes = sum(1 for res in batch_response.responses if res.success)
            failed_tokens = [
                messages[i].token for i, res in enumerate(batch_response.responses)
                if not res.success
            ]
            return successes, failed_tokens
        except (TransportError, ValueError) as e:
            logger.error(f"FCM batch send failed: {str(e)}")
            raise

    async def get_valid_tokens_batch(self, user_identifiers: List[Dict[str, str]]) -> List[str]:
        async with self.db_pool.acquire() as conn:
            composite_keys = [
                f"{uid['user_id']}:{uid['user_type']}".lower()
                for uid in user_identifiers
            ]
            query = """
                SELECT token
                FROM fcm_tokens
                WHERE (user_id, user_type) IN (
                    SELECT unnest($1), unnest($2)
                )
                AND is_active = TRUE
                ORDER BY updated_at DESC
            """
            records = await conn.fetch(query, composite_keys)
            return [r['fcm_token'] for r in records if r['fcm_token']]

    async def handle_send_errors(self, failed_tokens: List[str]):
        if not failed_tokens:
            return
        
        async with self.db_pool.acquire() as conn:
            await conn.execute("""
                UPDATE fcm_tokens
                SET is_active = FALSE
                WHERE token = ANY($1)
            """, failed_tokens)