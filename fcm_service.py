import firebase_admin
from firebase_admin import credentials, messaging
import json
import os

# Initialize Firebase Admin SDK
def initialize_firebase():
    try:
        # Check if already initialized
        if not firebase_admin._apps:
            # Load service account key
            service_account_key = os.path.join(os.path.dirname(__file__), 'bonobo-256-701b0bca5970.json')
            cred = credentials.Certificate(service_account_key)
            firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Error initializing Firebase: {e}")
        raise

def send_order_status_notification(token, order_id, new_status, user_type):
    """
    Send FCM notification for order status change
    
    Args:
        token (str): FCM token of the device
        order_id (str): ID of the order
        new_status (str): New order status
        user_type (str): Type of user (chef, transporter, producer, user)
    """
    try:
        # Create notification message with user-specific title and body
        title = f"Order Status Updated"
        body = f"Your order {order_id} status has been updated to {new_status}"
        
        # Customize message based on user type
        if user_type == 'chef':
            title = f"Chef Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"
        elif user_type == 'producer':
            title = f"Producer Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"
        elif user_type == 'transporter':
            title = f"Transporter Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body
            ),
            data={
                'type': 'order_status_changed',
                'order_id': order_id,
                'status': new_status,
                'user_type': user_type
            },
            token=token
        )

        # Send the message
        response = messaging.send(message)
        return response
    except Exception as e:
        print(f"Error sending notification: {e}")
        raise

import asyncio
from services.notification_service import notification_service

async def send_bulk_notifications(conn, token_dicts, order_id, new_status, user_type):
    """
    Send FCM notification to multiple devices and deactivate invalid tokens.
    Args:
        conn: asyncpg.Connection
        token_dicts (list): List of dicts with 'id' and 'token' fields
        order_id (str): ID of the order
        new_status (str): New order status
        user_type (str): Type of user
    """
    from firebase_admin import messaging
    try:
        title = f"Order Status Updated"
        body = f"Your order {order_id} status has been updated to {new_status}"
        if user_type == 'chef':
            title = f"Chef Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"
        elif user_type == 'producer':
            title = f"Producer Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"
        elif user_type == 'transporter':
            title = f"Transporter Order Status Update"
            body = f"Order {order_id} status changed to {new_status}"

        tokens = [td['token'] for td in token_dicts]
        ids = [td['id'] for td in token_dicts]
        message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=title,
                body=body
            ),
            data={
                'type': 'order_status_changed',
                'order_id': order_id,
                'status': new_status,
                'user_type': user_type
            },
            tokens=tokens
        )
        response = messaging.send_multicast(message)
        # Deactivate invalid tokens
        for idx, resp in enumerate(response.responses):
            if not resp.success:
                error_msg = str(resp.exception)
                if any(err in error_msg for err in [
                    'registration-token-not-registered',
                    'invalid-registration-token',
                    'invalid-argument',
                    'mismatch-sender-id',
                    'unregistered',
                ]):
                    token_id = ids[idx]
                    # Schedule async deactivation
                    asyncio.create_task(notification_service.deactivate_fcm_token(conn, token_id))
        return response
    except Exception as e:
        print(f"Error sending bulk notifications: {e}")
        raise
