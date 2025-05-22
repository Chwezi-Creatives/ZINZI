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
                import urllib3
                
                # Configure connection pool with urllib3
                http_client = urllib3.PoolManager(
                    num_pools=1,  # Single pool for all requests
                    maxsize=30,    # Increased from default 10
                    block=True,    # Block when no free connections are available
                    timeout=urllib3.Timeout(connect=30.0, read=30.0),
                    retries=urllib3.Retry(
                        total=3,
                        backoff_factor=0.5,
                        status_forcelist=[500, 502, 503, 504]
                    )
                )
                
                service_account_path = os.path.join(os.path.dirname(__file__), '..', 'zinzi-fcm2-firebase-adminsdk-fbsvc-d81e9633e7.json')
                cred = credentials.Certificate(service_account_path)
                
                # Initialize Firebase with default HTTP client but configure it through environment
                firebase_admin.initialize_app(cred, {'projectId': 'zinzi-fcm2'})
                
                # Configure the default HTTP client used by firebase_admin
                import requests
                session = requests.Session()
                adapter = requests.adapters.HTTPAdapter(
                    pool_connections=30,
                    pool_maxsize=30,
                    max_retries=3,
                    pool_block=True
                )
                session.mount('https://', adapter)
                
                # This will ensure all firebase admin requests use our session
                firebase_admin._auth.get_auth_service()._session = session
                
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