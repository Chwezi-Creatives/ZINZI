import os
from dotenv import load_dotenv
from datetime import datetime
import json
import asyncpg

load_dotenv()

class NotificationService:
    def __init__(self):
        pass  # No internal connection, all methods accept conn

    async def store_fcm_token(self, conn: asyncpg.Connection, user_id: str, token: str, platform: str, user_type: str) -> bool:
        """
        Store or update an FCM token for a user.
        """
        try:
            await conn.execute(
                """
                INSERT INTO fcm_tokens (user_id, token, platform, user_type, is_active)
                VALUES ($1, $2, $3, $4, TRUE)
                ON CONFLICT (user_id, platform)
                DO UPDATE SET 
                    token = EXCLUDED.token,
                    user_type = EXCLUDED.user_type,
                    is_active = TRUE,
                    updated_at = CURRENT_TIMESTAMP
                """,
                user_id, token, platform, user_type
            )
            return True
        except Exception as e:
            print(f"Error storing FCM token: {e}")
            return False

    async def get_fcm_tokens(self, conn: asyncpg.Connection, user_id: str, platform: str = None, user_type: str = None) -> list:
        """
        Get FCM tokens for a user.
        """
        try:
            query = """
                SELECT id, user_id, token, platform, user_type, created_at, updated_at, is_active
                FROM fcm_tokens
                WHERE user_id = $1 AND is_active = TRUE
            """
            params = [user_id]
            param_idx = 2
            if platform:
                query += f" AND platform = ${param_idx}"
                params.append(platform)
                param_idx += 1
            if user_type:
                query += f" AND user_type = ${param_idx}"
                params.append(user_type)
            rows = await conn.fetch(query, *params)
            return [{
                'id': row['id'],
                'user_id': row['user_id'],
                'token': row['token'],
                'platform': row['platform'],
                'user_type': row['user_type'],
                'created_at': row['created_at'],
                'updated_at': row['updated_at'],
                'is_active': row['is_active']
            } for row in rows]
        except Exception as e:
            print(f"Error getting FCM tokens: {e}")
            return []

    async def deactivate_fcm_token(self, conn: asyncpg.Connection, token_id: int) -> bool:
        """
        Deactivate an FCM token.
        """
        try:
            await conn.execute(
                """
                UPDATE fcm_tokens
                SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
                WHERE id = $1
                """,
                token_id
            )
            return True
        except Exception as e:
            print(f"Error deactivating FCM token: {e}")
            return False

    async def subscribe_to_topic(self, conn: asyncpg.Connection, user_id: str, topic: str) -> bool:
        """
        Subscribe a user to a notification topic.
        """
        try:
            await conn.execute(
                """
                INSERT INTO notification_subscriptions (user_id, topic, enabled)
                VALUES ($1, $2, TRUE)
                ON CONFLICT (user_id, topic)
                DO UPDATE SET enabled = TRUE, updated_at = CURRENT_TIMESTAMP
                """,
                user_id, topic
            )
            return True
        except Exception as e:
            print(f"Error subscribing to topic: {e}")
            return False

    async def unsubscribe_from_topic(self, conn: asyncpg.Connection, user_id: str, topic: str) -> bool:
        """
        Unsubscribe a user from a notification topic.
        """
        try:
            await conn.execute(
                """
                UPDATE notification_subscriptions
                SET enabled = FALSE, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $1 AND topic = $2
                """,
                user_id, topic
            )
            return True
        except Exception as e:
            print(f"Error unsubscribing from topic: {e}")
            return False

    async def log_notification(self, conn: asyncpg.Connection, user_id: str, token: str, notification_type: str, title: str, body: str, data: dict) -> str:
        """
        Log a notification in the history.
        """
        try:
            notification_id = await conn.fetchval(
                """
                INSERT INTO notification_history (user_id, token, notification_type, title, body, data, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
                RETURNING id
                """,
                user_id, token, notification_type, title, body, json.dumps(data)
            )
            return str(notification_id)
        except Exception as e:
            print(f"Error logging notification: {e}")
            return ""

    async def get_notification_history(self, conn: asyncpg.Connection, user_id: str, limit: int = 50) -> list:
        """
        Get notification history for a user.
        """
        try:
            rows = await conn.fetch(
                """
                SELECT id, user_id, token, notification_type, title, body, data, created_at
                FROM notification_history
                WHERE user_id = $1
                ORDER BY created_at DESC
                LIMIT $2
                """,
                user_id, limit
            )
            return [{
                'id': row['id'],
                'user_id': row['user_id'],
                'token': row['token'],
                'notification_type': row['notification_type'],
                'title': row['title'],
                'body': row['body'],
                'data': row['data'],
                'created_at': row['created_at']
            } for row in rows]
        except Exception as e:
            print(f"Error getting notification history: {e}")
            return []

    def store_fcm_token(self, user_id: str, token: str, platform: str, user_type: str) -> bool:
        """
        Store or update an FCM token for a user.
        
        Args:
            user_id: User's UUID
            token: FCM token
            platform: 'android' or 'ios'
            user_type: Type of user ('user', 'chef', 'producer', 'transporter')
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO fcm_tokens (user_id, token, platform, user_type, is_active)
                    VALUES (%s, %s, %s, %s, TRUE)
                    ON CONFLICT (user_id, platform)
                    DO UPDATE SET 
                        token = EXCLUDED.token,
                        user_type = EXCLUDED.user_type,
                        is_active = TRUE,
                        updated_at = CURRENT_TIMESTAMP
                """, (user_id, token, platform, user_type))
                self.connection.commit()
                return True
        except Exception as e:
            print(f"Error storing FCM token: {e}")
            self.connection.rollback()
            return False

    def get_fcm_tokens(self, user_id: str, platform: str = None, user_type: str = None) -> list:
        """
        Get FCM tokens for a user.
        
        Args:
            user_id: User's UUID
            platform: Optional platform filter ('android' or 'ios')
            user_type: Optional user type filter ('user', 'chef', 'producer', 'transporter')
        
        Returns:
            list: List of token dictionaries
        """
        try:
            with self.connection.cursor() as cursor:
                query = """
                    SELECT id, user_id, token, platform, user_type, created_at, updated_at, is_active
                    FROM fcm_tokens
                    WHERE user_id = %s
                    AND is_active = TRUE
                """
                params = [user_id]
                
                if platform:
                    query += " AND platform = %s"
                    params.append(platform)
                
                if user_type:
                    query += " AND user_type = %s"
                    params.append(user_type)
                
                cursor.execute(query, params)
                tokens = cursor.fetchall()
                
                return [{
                    'id': token[0],
                    'user_id': token[1],
                    'token': token[2],
                    'platform': token[3],
                    'user_type': token[4],
                    'created_at': token[5],
                    'updated_at': token[6],
                    'is_active': token[7]
                } for token in tokens]
        except Exception as e:
            print(f"Error getting FCM tokens: {e}")
            return []

    def deactivate_fcm_token(self, token_id: int) -> bool:
        """
        Deactivate an FCM token.
        
        Args:
            token_id: ID of the token to deactivate
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    UPDATE fcm_tokens
                    SET is_active = FALSE,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (token_id,))
                self.connection.commit()
                return True
        except Exception as e:
            print(f"Error deactivating FCM token: {e}")
            self.connection.rollback()
            return False

    def subscribe_to_topic(self, user_id: str, topic: str) -> bool:
        """
        Subscribe a user to a notification topic.
        
        Args:
            user_id: User's UUID
            topic: Topic name
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO notification_subscriptions (user_id, topic, enabled)
                    VALUES (%s, %s, TRUE)
                    ON CONFLICT (user_id, topic)
                    DO UPDATE SET 
                        enabled = TRUE,
                        updated_at = CURRENT_TIMESTAMP
                """, (user_id, topic))
                self.connection.commit()
                return True
        except Exception as e:
            print(f"Error subscribing to topic: {e}")
            self.connection.rollback()
            return False

    def unsubscribe_from_topic(self, user_id: str, topic: str) -> bool:
        """
        Unsubscribe a user from a notification topic.
        
        Args:
            user_id: User's UUID
            topic: Topic name
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    UPDATE notification_subscriptions
                    SET enabled = FALSE,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE user_id = %s
                    AND topic = %s
                """, (user_id, topic))
                self.connection.commit()
                return True
        except Exception as e:
            print(f"Error unsubscribing from topic: {e}")
            self.connection.rollback()
            return False

    def log_notification(self, user_id: str, token: str, notification_type: str, title: str, body: str, data: dict) -> str:
        """
        Log a notification in the history.
        
        Args:
            user_id: User's UUID
            token: FCM token
            notification_type: Type of notification
            title: Notification title
            body: Notification body
            data: Additional notification data
        
        Returns:
            str: Notification ID
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO notification_history (
                        user_id, token, type, title, body, data, status
                    ) VALUES (%s, %s, %s, %s, %s, %s, 'pending')
                    RETURNING notification_id
                """, (
                    user_id, token, notification_type, title, body, json.dumps(data)
                ))
                notification_id = cursor.fetchone()[0]
                self.connection.commit()
                return str(notification_id)
        except Exception as e:
            print(f"Error logging notification: {e}")
            self.connection.rollback()
            return None

    def update_notification_status(self, notification_id: str, status: str, error_message: str = None) -> bool:
        """
        Update notification delivery status.
        
        Args:
            notification_id: Notification ID
            status: New status
            error_message: Optional error message
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            with self.connection.cursor() as cursor:
                query = """
                    UPDATE notification_history
                    SET status = %s,
                        delivered_at = CASE WHEN %s = 'delivered' THEN CURRENT_TIMESTAMP ELSE delivered_at END,
                        error_message = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE notification_id = %s
                """
                cursor.execute(query, (status, status, error_message, notification_id))
                self.connection.commit()
                return True
        except Exception as e:
            print(f"Error updating notification status: {e}")
            self.connection.rollback()
            return False

    def get_notification_history(self, user_id: str, limit: int = 50) -> list:
        """
        Get notification history for a user.
        
        Args:
            user_id: User's UUID
            limit: Maximum number of notifications to return
        
        Returns:
            list: List of notification dictionaries
        """
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("""
                    SELECT 
                        id, notification_id, user_id, token, type, title, body,
                        data, sent_at, delivered_at, status, error_message
                    FROM notification_history
                    WHERE user_id = %s
                    ORDER BY sent_at DESC
                    LIMIT %s
                """, (user_id, limit))
                notifications = cursor.fetchall()
                
                return [{
                    'id': notification[0],
                    'notification_id': str(notification[1]),
                    'user_id': notification[2],
                    'token': notification[3],
                    'type': notification[4],
                    'title': notification[5],
                    'body': notification[6],
                    'data': json.loads(notification[7]),
                    'sent_at': notification[8],
                    'delivered_at': notification[9],
                    'status': notification[10],
                    'error_message': notification[11]
                } for notification in notifications]
        except Exception as e:
            print(f"Error getting notification history: {e}")
            return []

    def close(self):
        """Close database connection."""
        if self.connection:
            self.connection.close()

# Create a singleton instance
notification_service = NotificationService()
