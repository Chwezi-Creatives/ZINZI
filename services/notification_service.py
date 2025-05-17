#cspell:disable
# Standard library imports
import json
import logging
from typing import List, Optional, Dict, Tuple

# Third-party imports
import asyncpg
from dotenv import load_dotenv
from fastapi import HTTPException

# Local application/library specific imports
from .fcm_service import FirebaseMessagingService
from firebase_admin import messaging

# Load environment variables from .env file
load_dotenv()

# Configure logger
logger = logging.getLogger(__name__)

class NotificationService:
    def __init__(self, db_pool: asyncpg.Pool):
        """
        Initialize the NotificationService with an asyncpg connection pool.
        """
        if db_pool is None:
            raise ValueError("db_pool cannot be None")
        self.db_pool = db_pool
        self.fcm_service = FirebaseMessagingService(db_pool) # Initialize FCM service
        self._initialized = False

    async def _initialize(self):
        """Initialize any required resources."""
        if not self._initialized:
            # Add any initialization logic here
            # Ensure FCM service is initialized if needed here, or rely on its internal init
            self._initialized = True

    async def send_notifications(
        self, user_ids: Optional[List[str]] = None, user_types: Optional[List[str]] = None, broadcast: bool = False, title: str = "New Notification", body: str = "You have a new notification", notification_type: str = "general", metadata: Optional[dict] = None
    ) -> dict:
        """
        Send notifications to specified users or broadcast to all.
        Logs sent notifications to the 'notifications' table.
        """
        if not any([user_ids, user_types, broadcast]):
            raise HTTPException(status_code=400, detail="Must specify at least one target (user_ids, user_types, or broadcast).")

        try:
            # Get FCM tokens for the target audience
            # _get_target_tokens expects user_ids as List[str] and handles conversion if needed
            tokens = await self._get_target_tokens(user_ids, user_types, broadcast)

            if not tokens:
                logger.info("No FCM tokens found for the specified target. No notifications sent.")
                return {
                    "success": True,
                    "message": "No target tokens found.",
                    "sent_count": 0,
                    "failed_count": 0
                }

            # Create FCM messages for each token
            messages = []
            
            current_metadata = metadata or {}
            
            # Determine the effective notification type based on metadata/status
            effective_notification_type = self._determine_effective_notification_type(notification_type, current_metadata)

            for target_info in tokens:
                token = target_info.get('token')
                user_id_val = target_info.get('user_id')
                
                if not token:
                    logger.warning(f"Skipping notification for user_id {user_id_val} due to missing token.")
                    continue # Skip if token is missing or empty

                # Craft message title and body using the centralized function
                crafted_title, crafted_body = self._craft_notification_message(
                    notification_type=effective_notification_type,
                    metadata=current_metadata,
                    user_types=user_types,
                    default_title=title,
                    default_body=body
                )

                messages.append(messaging.Message(
                    token=token,
                    notification=messaging.Notification(
                        title=crafted_title,
                        body=crafted_body
                    ),
                    data=current_metadata # Use data field for custom payload
                ))

            logger.debug(f"Preparing to send %s notification to %d target tokens", effective_notification_type, len(tokens))

            # Log notifications to the 'notification_history' database table for each token
            logger.debug(f"Starting database transaction for inserting notifications into history table.")
            try:
                async with self.db_pool.acquire() as conn:
                    async with conn.transaction(isolation='serializable', readonly=False):
                        for target_info in tokens:
                            user_id_val = target_info['user_id']
                            token_val = target_info['token']
                            await conn.execute(
                                """
                                INSERT INTO notification_history (user_id, token, notification_type, title, body, data, created_at, status, delivered_at, error_message, updated_at)
                                VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, NULL, NULL, NOW())
                                """,
                                user_id_val,
                                token_val,
                                notification_type,
                                crafted_title,
                                crafted_body,
                                json.dumps(current_metadata), # Convert dict to JSON string for json/jsonb column
                                'sent'  # Assuming initial status is 'sent' for this log
                            )
                            logger.debug(f"Successfully inserted notification history log for user_id: {user_id_val}, token: {token_val[:10]}...")
                logger.debug("Database transaction for notification history logging completed.")
            except Exception as db_exc:
                logger.error(f"Database error during notification history logging: {db_exc}", exc_info=True)

            # Send push notifications via FCM using the FirebaseMessagingService
            success_count, failed_tokens = await self.fcm_service.send_each_multicast(messages)

            # Handle failed tokens (e.g., deactivate them in the database)
            if failed_tokens:
                logger.warning(f"Handling {len(failed_tokens)} failed tokens.")
                await self.fcm_service.handle_send_errors(failed_tokens)

            # Optionally, here you could use self.log_notification and self.update_notification_status
            # from the second file's features if send_each_multicast provided per-token results with user_ids.
            # For now, keeping the original distinct logging mechanisms.

            return {
                "success": True,
                "sent_count": success_count,
                "failed_count": len(failed_tokens)
            }
        except HTTPException: # Re-raise HTTPExceptions
            raise
        except Exception as e:
            logger.error(f"Notification send failed: {str(e)}", exc_info=True)
            # It's good practice to raise a specific exception or re-raise after logging
            raise HTTPException(status_code=500, detail=f"Notification delivery failed: {str(e)}")


    def _determine_effective_notification_type(self, notification_type: str, metadata: dict) -> str:
        """
        Determine the effective notification type based on provided type and metadata.
        This allows for more specific types derived from general ones based on context.
        """
        # Example: If notification_type is 'order_status' and metadata contains 'status', use that.
        if notification_type == 'order_status' and 'status' in metadata:
            return f"order_status_{metadata['status']}"
        # Add other specific type determinations here based on metadata
        
        return notification_type # Default to the provided type

    def _craft_notification_message(
        self,
        notification_type: str,
        metadata: Optional[dict] = None,
        user_types: Optional[List[str]] = None,
        default_title: str = "New Notification",
        default_body: str = "You have a new notification"
    ) -> Tuple[str, str]:
        """
        Craft notification title and body based on notification type, metadata, and user type.
        """
        metadata = metadata or {}
        
        # Default to provided title and body
        title = default_title
        body = default_body

        # Example crafting logic based on notification type and metadata
        if notification_type.startswith('order_status_'):
            order_id = metadata.get('order_id', 'an order')
            status = notification_type.replace('order_status_', '').lower()
            user_type_str = user_types[0].lower() if user_types and len(user_types) == 1 else 'user'

            # Craft messages based on status and user type
            if status == 'created':
                if user_type_str == 'user':
                    title = "Order created"
                    body = f"Your order {order_id} has been successfully created."
                elif user_type_str in ['chef', 'producer']:
                    title = "You have a new order!"
                    body = f"A new order {order_id} has been placed. Please review."
                elif user_type_str == 'transporter':
                     # Transporter doesn't get 'created' notification, but handle defensively
                     title = f"Order {order_id} Created (Transporter)"
                     body = "Order created notification."

            elif status == 'accepted':
                 if user_type_str == 'user':
                    title = "Order Accepted!"
                    body = f"Your order {order_id} has been accepted."
                 # Add logic for chef/producer if needed

            elif status == 'assigned':
                 if user_type_str == 'user':
                    title = "Your delivery is on the way!"
                    body = f"Your order {order_id} has been assigned to a transporter."
                 elif user_type_str == 'transporter':
                    title = "New Delivery Assignment: Order {order_id}!"
                    body = "You have been assigned a new order for delivery."
                 # Add logic for chef/producer if they need assignment notifications

            elif status == 'picked_up':
                 if user_type_str == 'user':
                    title = f"Order {order_id} Picked Up!"
                    body = "Your order is on its way."
                 elif user_type_str == 'transporter':
                    title = f"Order {order_id} Picked Up Confirmed"
                    body = "You have marked the order as picked up."
                 # Add logic for chef/producer if needed

            elif status == 'delivered':
                 if user_type_str == 'user':
                    title = f"Order {order_id} Delivered!"
                    body = "Your order has been successfully delivered."
                 elif user_type_str == 'transporter':
                    title = f"Order {order_id} Delivered Confirmed"
                    body = "You have marked the order as delivered."
                 # Add logic for chef/producer if needed

            elif status == 'cancelled':
                 if user_type_str == 'user':
                    title = f"Order {order_id} Cancelled"
                    body = "Your order has been cancelled."
                 # Add logic for other user types if needed

            elif status == 'ready_for_pickup':
                 if user_type_str == 'user':
                    title = f"Order {order_id} Ready for Pickup!"
                    body = "Your order is ready for pickup at the designated location."
                 elif user_type_str == 'chef':
                    title = f"Order {order_id} Ready for Pickup Confirmed"
                    body = "You have marked the order as ready for pickup."
                 # Add logic for producer/transporter if needed

            elif status == 'verification_needed':
                 if user_type_str == 'user':
                    title = f"Your order has arrived!"
                    body = f"Order {order_id} requires verification. Please check the app."
                 elif user_type_str in ['chef', 'producer', 'transporter']:
                    title = f"Order completion needs verification from customer"
                    body = f"Order {order_id} requires verification before proceeding."

            elif status == 'completed':
                 title = f"Order {order_id} Complete!"
                 body = "The order has been successfully completed."

        # Add crafting logic for other notification types here (e.g., 'broadcast', 'payment_received', etc.)
        # elif notification_type == 'broadcast':
        #     title = default_title # Or customize based on metadata
        #     body = default_body # Or customize based on metadata

        return title, body

    async def _get_target_tokens(self, user_ids_str: Optional[List[str]], user_types: Optional[List[str]], broadcast: bool) -> List[str]:
        """
        Get FCM tokens based on targeting parameters from the 'fcm_tokens' table.
        """
        query_conditions = []
        params = []
        param_idx = 1 # For PostgreSQL $1, $2 placeholders

        base_query = "SELECT user_id, token FROM fcm_tokens WHERE is_active = TRUE"
        
        if broadcast:
            # If broadcasting, specific user_ids_str are typically ignored.
            # Broadcast can be filtered by user_types.
            if user_types:
                query_conditions.append(f"user_type = ANY(${param_idx}::text[])")
                params.append(user_types)
                param_idx += 1
            # If no user_types for broadcast, query_conditions remains empty, targeting all active users.
        else: # Not a broadcast, so specific targeting by user_ids_str and/or user_types
            if not user_ids_str and not user_types:
                # This case should be caught by the initial check in send_notifications.
                logger.warning("_get_target_tokens called with no specific targets and not as broadcast.")
                return []

            processed_user_ids_int = []
            if user_ids_str:
                for uid_str_val in user_ids_str:
                    try:
                        processed_user_ids_int.append(int(uid_str_val))
                    except ValueError:
                        logger.warning(f"Invalid user ID format '{uid_str_val}' in _get_target_tokens, skipping.")
                
                if processed_user_ids_int:
                    query_conditions.append(f"user_id = ANY(${param_idx}::integer[])")
                    params.append(processed_user_ids_int)
                    param_idx += 1
                else:
                    # All user_ids_str were invalid. If no user_types, then no valid targets.
                    if not user_types:
                        logger.debug("No valid user_ids after conversion and no user_types for specific targeting.")
                        return []
            
            if user_types:
                query_conditions.append(f"user_type = ANY(${param_idx}::text[])")
                params.append(user_types)
                # param_idx += 1 # Not needed if this is the last possible condition appender

        final_query = base_query
        if query_conditions: # Add collected conditions
            # Enclose multiple AND conditions in parentheses if mixing with ORs, though here it's all ANDs
            final_query += " AND (" + " AND ".join(query_conditions) + ")" 
        
        logger.debug(f"Constructed token query: {final_query} with params: {params}")
        return await self._fetch_tokens_from_query(final_query, params)

    async def _fetch_tokens_from_query(self, query: str, params: list) -> List[str]:
        """
        Execute a given query and return a list of FCM tokens.
        Expects the query to select a column named 'token'.
        """
        try:
            async with self.db_pool.acquire() as conn:
                records = await conn.fetch(query, *params)
                # Return the full records (list of Record objects) which contain both user_id and token
                return records
        except Exception as e:
            logger.error(f"Token fetch error: {str(e)}", exc_info=True)
            return []

    # --- Methods from the second file, adapted for self.db_pool and logger ---

    async def store_fcm_token(self, user_id: int, token: str, platform: str, user_type: str):
        """
        Store a new FCM token for a user in the 'fcm_tokens' table.
        Each user_id/user_type combination can have multiple active tokens across different platforms.
        """
        try:
            async with self.db_pool.acquire() as conn:
                # Insert new token record
                # First check if the token already exists for this user
                existing = await conn.fetchrow(
                    """SELECT id FROM fcm_tokens WHERE user_id = $1 AND token = $2""",
                    user_id, token
                )
                
                if existing:
                    # Update existing token
                    await conn.execute(
                        """
                        UPDATE fcm_tokens SET
                            user_type = $1,
                            platform = $2,
                            is_active = TRUE,
                            updated_at = NOW()
                        WHERE user_id = $3 AND token = $4
                        """,
                        user_type, platform, user_id, token
                    )
                else:
                    # Insert new token
                    await conn.execute(
                        """
                        INSERT INTO fcm_tokens (
                            user_id, user_type, token, platform,
                            is_active
                        )
                        VALUES (
                            $1, $2, $3, $4,
                            TRUE
                        )
                        """,
                        user_id, user_type, token, platform
                    )
                
                # If this is a new token, deactivate any older tokens for this user_id/user_type combination
                # that haven't been updated in the last 30 days
                await conn.execute(
                    """
                    UPDATE fcm_tokens 
                    SET is_active = FALSE
                    WHERE user_id = $1 
                    AND user_type = $2
                    AND token != $3
                    AND updated_at < NOW() - INTERVAL '30 days'
                    """,
                    user_id, user_type, token
                )
                
                logger.info(f"FCM token stored for user {user_id} ({user_type}) on {platform}")
        except Exception as e:
            logger.error(f"Error storing FCM token: {str(e)}", exc_info=True)
            return False

    async def get_fcm_tokens(self, user_id: int, platform: Optional[str] = None, user_type: Optional[str] = None):
        """
        Get all active FCM tokens for a specific user from 'fcm_tokens' table.
        """
        try:
            async with self.db_pool.acquire() as conn:
                # Build base query
                query = """
                    SELECT DISTINCT token 
                    FROM fcm_tokens
                    WHERE user_id = $1
                    AND is_active = TRUE
                """
                params = [user_id]
                param_index = 2  # Start from $2 since $1 is already used for user_id
                
                # Add platform filter if provided
                if platform:
                    query += f" AND platform = ${param_index}"
                    params.append(platform)
                    param_index += 1  # Increment for next parameter
                
                # Add user_type filter if provided
                if user_type:
                    query += f" AND user_type = ${param_index}"
                    params.append(user_type)
                
                # Execute query - let asyncpg infer types from Python values
                records = await conn.fetch(query, *params)
            # Return list of dictionaries containing user_id and token
            return [{'user_id': r['user_id'], 'token': r['token']} for r in records if r['token']]
        except Exception as e:
            logger.error(f"Error getting FCM tokens: {str(e)}", exc_info=True)
            return []
        except Exception as e:
            logger.error(f"Error getting FCM tokens: {str(e)}", exc_info=True)
            return []
        except Exception as e:
            logger.error(f"Error getting FCM tokens: {str(e)}", exc_info=True)
            return []
        except Exception as e:
            logger.error(f"Error getting FCM tokens: {str(e)}", exc_info=True)
            return []
        except Exception as e:
            logger.error(f"Error getting FCM tokens: {str(e)}", exc_info=True)
            return []

    async def deactivate_fcm_token(self, token: str, user_id: int, user_type: str):
        """
        Deactivate an FCM token for a specific user in 'fcm_tokens' table.
        """
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE fcm_tokens 
                    SET is_active = FALSE, 
                        updated_at = NOW()
                    WHERE token = $1 
                    AND user_id = $2
                    """,
                    token, user_id, user_type
                )
                logger.info(f"Deactivated FCM token for user {user_id} ({user_type})")
        except Exception as e:
            logger.error(f"Error deactivating FCM token: {str(e)}", exc_info=True)
            return False

    async def subscribe_to_topic(self, user_id: str, topic: str) -> bool:
        """
        Subscribe a user to a notification topic in 'notification_subscriptions' table.
        Note: user_id is str here, ensure 'notification_subscriptions.user_id' type matches.
        """
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO notification_subscriptions (user_id, topic, enabled, updated_at)
                    VALUES ($1, $2, TRUE, CURRENT_TIMESTAMP)
                    ON CONFLICT (user_id, topic)
                    DO UPDATE SET enabled = TRUE, updated_at = CURRENT_TIMESTAMP
                    """,
                    user_id, topic
                )
            logger.info(f"User {user_id} successfully subscribed to topic: {topic}")
            return True
        except Exception as e:
            logger.error(f"Error subscribing user {user_id} to topic {topic}: {e}", exc_info=True)
            return False

    async def unsubscribe_from_topic(self, user_id: str, topic: str) -> bool:
        """
        Unsubscribe a user from a notification topic in 'notification_subscriptions' table.
        """
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE notification_subscriptions
                    SET enabled = FALSE, updated_at = CURRENT_TIMESTAMP
                    WHERE user_id = $1 AND topic = $2
                    """,
                    user_id, topic
                )
            logger.info(f"User {user_id} successfully unsubscribed from topic: {topic}")
            return True
        except Exception as e:
            logger.error(f"Error unsubscribing user {user_id} from topic {topic}: {e}", exc_info=True)
            return False

    async def log_notification_to_history(
        self, 
        user_id: int, 
        token: str, 
        notification_type: str, 
        title: str, 
        body: str, 
        data: dict,
        status: str = 'pending' # Default status when initially logging
    ) -> Optional[int]: # Changed to return Optional[int] for the ID
        """
        Log a notification send attempt to the 'notification_history' table.
        Returns the ID of the logged notification.
        """
        try:
            # Ensure user_id is int (already typed)
            # Convert data to JSON string if it's a dictionary
            if isinstance(data, dict):
                import json
                data = json.dumps(data)
            
            async with self.db_pool.acquire() as conn:
                notification_db_id = await conn.fetchval(
                    """
                    INSERT INTO notification_history (user_id, token, notification_type, title, body, data, status, created_at, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    RETURNING id
                    """,
                    user_id, token, notification_type, title, body, data, status
                )
            logger.info(f"Successfully logged notification to history for user_id {user_id}, token {token[:10]}... ID: {notification_db_id}")
            return notification_db_id
        except Exception as e:
            logger.error(f"Error logging notification to history for user_id {user_id}: {e}", exc_info=True)
            return None # Changed from "" to None for clarity

    async def get_notification_history(self, user_id: int, limit: int = 50) -> List[Dict]:
        """
        Get notification history for a user from 'notification_history' table.
        """
        try:
            # Ensure user_id is int (already typed)
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT id, user_id, token, notification_type, title, body, data, status, created_at, updated_at, delivered_at, error_message
                    FROM notification_history
                    WHERE user_id = $1
                    ORDER BY created_at DESC
                    LIMIT $2
                    """,
                    user_id, limit
                )
            
            return [dict(row) for row in rows] # Simpler conversion to list of dicts
        except Exception as e:
            logger.error(f"Error getting notification history for user_id {user_id}: {e}", exc_info=True)
            return []

    async def update_notification_status_in_history(
        self, 
        notification_db_id: int, # Assuming ID is int
        status: str, 
        error_message: Optional[str] = None
    ) -> bool:
        """
        Update notification delivery status in 'notification_history' table.
        """
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE notification_history
                    SET status = $1,
                        delivered_at = CASE WHEN $2 = 'delivered' THEN CURRENT_TIMESTAMP ELSE delivered_at END,
                        error_message = $3,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = $4
                    """,
                    status, status, error_message, notification_db_id # Pass status twice for CASE
                )
            logger.info(f"Successfully updated notification ID {notification_db_id} status to {status}")
            return True
        except Exception as e:
            logger.error(f"Error updating notification status for ID {notification_db_id}: {e}", exc_info=True)
            return False

class commented_out:
    # NOT USED CURRENTLY, just a leftover from old problematic code
    async def log_notification(self, user_id: int, message: str, notification_type: str):
        try:
            # Convert user_id to integer if coming from string source
            user_id = int(user_id)
            async with self.db_pool.acquire() as connection:
                await connection.execute('''
                    INSERT INTO notifications (user_id, message, type)
                    VALUES ($1, $2, $3)
                ''', user_id, message, notification_type)
        except Exception as e:
            self.logger.error(f"Failed to log notification for user {user_id}: {str(e)}")
