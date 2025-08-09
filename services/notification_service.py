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
        self, 
        user_ids: Optional[List[str]] = None, 
        user_types: Optional[List[str]] = None, 
        broadcast: bool = False, 
        title: str = "New Notification", 
        body: str = "You have a new notification", 
        notification_type: str = "general", 
        metadata: Optional[dict] = None
    ) -> dict:
        """
        Send notifications to specified users or broadcast to all.
        
        Args:
            user_ids: List of user IDs to send notifications to
            user_types: List of user types (must match user_ids if provided)
            broadcast: If True, send to all users (ignores user_ids and user_types)
            title: Notification title
            body: Notification body
            notification_type: Type of notification (e.g., 'order_status_updated')
            metadata: Additional data for the notification
            
        Returns:
            Dict with success status and counts of sent/failed notifications
        """
        logger.info(
            f"Sending notifications - type: {notification_type}, "
            f"user_ids: {user_ids}, user_types: {user_types}, broadcast: {broadcast}"
        )
        """
        Send notifications to specified users or broadcast to all.
        Logs sent notifications to the 'notifications' table.
        """
        # If user_ids are provided, user_types must also be provided and match in length
        if user_ids is not None:
            if user_types is None:
                raise HTTPException(status_code=400, detail="user_types must be provided when user_ids is specified.")
            if len(user_ids) != len(user_types):
                raise HTTPException(status_code=400, detail="user_ids and user_types must have the same length.")
        elif user_types is not None and not broadcast:
            # If only user_types is provided (without broadcast), it's invalid
            raise HTTPException(status_code=400, detail="user_ids must be provided when user_types is specified.")
        elif not broadcast:
            raise HTTPException(status_code=400, detail="Must specify at least one target (user_ids with user_types, or broadcast).")

        try:
            # Get FCM tokens for the target audience
            logger.debug(f"Getting FCM tokens for user_ids: {user_ids}, user_types: {user_types}, broadcast: {broadcast}")
            tokens = await self._get_target_tokens(user_ids, user_types, broadcast)
            logger.debug(f"Found {len(tokens)} target tokens")

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
            
            logger.debug(f"Original notification_type: {notification_type}")
            # Determine the effective notification type based on metadata/status
            effective_notification_type = self._determine_effective_notification_type(notification_type, current_metadata)
            logger.debug(f"Effective notification_type: {effective_notification_type}")
            
            # Log the metadata being used
            logger.debug(f"Notification metadata: {current_metadata}")

            for target_info in tokens:
                token = target_info.get('token')
                user_id_val = target_info.get('user_id')
                
                if not token:
                    logger.warning(f"Skipping notification for user_id {user_id_val} due to missing token.")
                    continue # Skip if token is missing or empty

                # Craft message title and body using the centralized function
                try:
                    crafted_title, crafted_body = self._craft_notification_message(
                        notification_type=effective_notification_type,
                        metadata=current_metadata,
                        user_types=user_types,
                        default_title=title,
                        default_body=body
                    )
                    logger.debug(f"Crafted message - title: {crafted_title!r}, body: {crafted_body!r}")
                except Exception as e:
                    logger.error(f"Error crafting notification message: {str(e)}", exc_info=True)
                    # Fall back to default values
                    crafted_title, crafted_body = title, body

                # Ensure all values in metadata are strings
                safe_metadata = {}
                if current_metadata:
                    for key, value in current_metadata.items():
                        if value is not None:
                            safe_metadata[str(key)] = str(value)
                        else:
                            safe_metadata[str(key)] = ''

                messages.append(messaging.Message(
                    token=token,
                    notification=messaging.Notification(
                        title=crafted_title,
                        body=crafted_body
                    ),
                    data=safe_metadata  # Ensure all values are strings
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
        # For order_status_created, we want to keep it as is since it's already specific
        if notification_type == 'order_status_created':
            return notification_type
            
        # Handle other order status change notifications
        if notification_type.startswith(('order_status_', 'order_assigned_')):
            # Get the original status before normalization
            original_status = metadata.get('status', '')
            # Use the normalized status for consistent handling
            status = self._normalize_status(original_status)
            
            if status:
                # Convert notification_type like 'order_status_changed_user' to 'order_status_<status>_user'
                parts = notification_type.split('_')
                new_notification_type = None
                
                if len(parts) >= 3:  # We have at least order_status_<suffix>
                    new_notification_type = f"order_{parts[1]}_{status}_{'_'.join(parts[2:])}"
                else:
                    new_notification_type = f"order_{parts[1]}_{status}"
                
                # Log if we're using a generic notification type (no specific handler)
                if status not in ['created', 'pending', 'confirmed', 'preparing', 'accepted', 
                                'assigned', 'ready_for_pickup', 'picked_up', 'on_the_way', 
                                'delivered', 'completed', 'cancelled', 'verification_needed']:
                    order_id = metadata.get('order_id', 'unknown')
                    user_types = metadata.get('user_types', ['unknown'])
                    user_type = user_types[0] if user_types and len(user_types) > 0 else 'unknown'
                    
                    logger.warning(
                        f"Using generic notification type for status: {original_status!r} (normalized: {status!r}), "
                        f"notification_type: {notification_type!r} -> {new_notification_type!r}, "
                        f"order_id: {order_id!r}, user_type: {user_type!r}"
                    )
                
                return new_notification_type
                
        return notification_type  # Default to the provided type

    def _normalize_status(self, status: str) -> str:
        """
        Normalize status strings to a consistent format (lowercase with underscores).
        Handles common variations and edge cases for all order statuses.
        
        Args:
            status: The status string to normalize
            
        Returns:
            str: Normalized status string in snake_case
        """
        if not status:
            return ''
            
        # Convert to lowercase, strip whitespace, and normalize spaces/underscores
        normalized = str(status).lower().strip()
        normalized = normalized.replace(' ', '_').replace('-', '_')
        
        # Comprehensive status mapping with all variations
        status_mapping = {
            # Order creation and initial statuses
            'created': 'created',
            'new': 'created',
            'pending': 'pending',
            'received': 'pending',
            'confirmed': 'confirmed',
            'accepted': 'accepted',
            
            # Preparation statuses
            'preparing': 'preparing',
            'in_preparation': 'preparing',
            'in_prep': 'preparing',
            'prep': 'preparing',
            'processing': 'preparing',
            
            # Ready for pickup/delivery
            'ready': 'ready_for_pickup',
            'ready_for_pickup': 'ready_for_pickup',
            'ready_for_delivery': 'ready_for_pickup',
            'prepared': 'ready_for_pickup',
            'ready_to_pickup': 'ready_for_pickup',
            'pickup_ready': 'ready_for_pickup',
            
            # Assignment and pickup
            'assigned': 'assigned',
            'assigned_to_driver': 'assigned',
            'driver_assigned': 'assigned',
            'picked_up': 'picked_up',
            'collected': 'picked_up',
            'in_transit': 'on_the_way',
            'on_the_way': 'on_the_way',
            'on_route': 'on_the_way',
            'out_for_delivery': 'on_the_way',
            'delivering': 'on_the_way',
            
            # Delivery and completion
            'delivered': 'completed',
            'completed': 'completed',
            'fulfilled': 'completed',
            'finished': 'completed',
            
            # Verification
            'verification_needed': 'verification_needed',
            'needs_verification': 'verification_needed',
            'awaiting_verification': 'verification_needed',
            'pending_verification': 'verification_needed',
            
            # Cancellation and issues
            'cancelled': 'cancelled',
            'canceled': 'cancelled',
            'rejected': 'cancelled',
            'declined': 'cancelled',
            'failed': 'cancelled',
            'error': 'cancelled',
            
            # Shipping related
            'shipped': 'shipped',
            'dispatched': 'shipped',
            'in_transit': 'shipped',
            'shipping': 'shipped',
            'in_shipping': 'shipped',
            
            # Payment related (for completeness)
            'payment_pending': 'payment_pending',
            'payment_received': 'payment_received',
            'paid': 'payment_received',
            'payment_failed': 'payment_failed',
            'refunded': 'refunded',
            'partially_refunded': 'partially_refunded'
        }
        
        # First try exact match
        normalized_status = status_mapping.get(normalized)
        
        # If no exact match, try partial matching for more flexibility
        if not normalized_status:
            for key, value in status_mapping.items():
                if key in normalized or normalized in key:
                    normalized_status = value
                    break
        
        # If still no match, return the cleaned input
        return normalized_status if normalized_status else normalized

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
        
        Args:
            notification_type: Type of notification to send (e.g., 'order_status_updated')
            metadata: Dictionary containing additional data for the notification
            user_types: List of user types this notification is for
            default_title: Default notification title if no specific title is crafted
            default_body: Default notification body if no specific body is crafted
        
        Returns:
            Tuple containing (title, body) of the notification
        """
        metadata = metadata or {}
        logger.debug(f"Crafting notification - type: {notification_type}, metadata: {metadata}, user_types: {user_types}")
        
        # Default to provided title and body
        title = default_title
        body = default_body
        
        # Safely extract user type
        user_type_str = "user"
        if user_types and len(user_types) > 0:
            user_type_str = user_types[0].lower()
        
        # Handle order status notifications
        if notification_type.startswith(('order_status_', 'order_assigned_')):
            order_id = metadata.get('order_id', 'unknown')
            original_status = metadata.get('status', '')
            # Get and normalize the status
            status = self._normalize_status(original_status)
            
            logger.debug(f"Processing order notification - order_id: {order_id}, original_status: {original_status}, "
                       f"normalized_status: {status}, user_type: {user_type_str}")
            
            # Clean up status for display
            status_display = status.replace('_', ' ').title()
            
            # Map status to more user-friendly messages
            status_messages = {
                'pending': 'is being processed',
                'confirmed': 'has been confirmed',
                'preparing': 'is being prepared',
                'ready_for_pickup': 'is ready for pickup',
                'assigned': 'has been assigned to a rider',
                'picked_up': 'has been picked up',
                'on_the_way': 'is on its way',
                'delivered': 'has been delivered',
                'completed': 'has been completed',
                'cancelled': 'has been cancelled',
                'verification_needed': 'needs verification',
                'accepted': 'has been accepted',
                'created': 'has been created'
            }
            
            # Default status message if not found in the mapping
            status_message = status_messages.get(status, f'is {status_display}')
            
            # Log when we're using a default status message
            if status not in status_messages:
                logger.warning(
                    f"Using default status message for status: {status!r} (original: {original_status!r}), "
                    f"order_id: {order_id!r}, user_type: {user_type_str!r}"
                )
            
            # Handle specific status messages by user type and status
            if status == 'created':
                logger.debug(f"Creating 'created' notification for order {order_id}, user_type: {user_type_str}")
                if user_type_str == 'user':
                    title = "Order Created"
                    body = f"Your order #{order_id} has been successfully created."
                elif user_type_str == 'chef':
                    title = "New Order Received!"
                    body = f"You have a new order #{order_id} to prepare."
                elif user_type_str == 'producer':
                    title = "New Order Received!"
                    body = f"You have a new order #{order_id} to process."
                elif user_type_str == 'transporter':
                    title = "New Delivery Available"
                    body = f"A new order #{order_id} has been created and may need delivery soon."
            
            elif status == 'pending':
                if user_type_str == 'user':
                    title = "Order Processing"
                    body = f"Your order #{order_id} is being processed."
                elif user_type_str == 'chef':
                    title = "Pending Order"
                    body = f"Order #{order_id} is pending and will be ready for preparation soon."
                elif user_type_str == 'producer':
                    title = "Pending Order"
                    body = f"Order #{order_id} is pending and will be ready for processing soon."
                elif user_type_str == 'transporter':
                    title = "Upcoming Delivery"
                    body = f"Order #{order_id} is pending and may need delivery soon."
            
            elif status == 'confirmed':
                if user_type_str == 'user':
                    title = "Order Confirmed"
                    body = f"Your order #{order_id} has been confirmed."
                elif user_type_str == 'chef':
                    title = "Order Confirmed"
                    body = f"Order #{order_id} has been confirmed and is ready for preparation."
                elif user_type_str == 'producer':
                    title = "Order Confirmed"
                    body = f"Order #{order_id} has been confirmed and is ready for processing."
                elif user_type_str == 'transporter':
                    title = "Confirmed Order"
                    body = f"Order #{order_id} has been confirmed and will need delivery soon."
            
            elif status == 'preparing':
                if user_type_str == 'user':
                    title = "Order Being Prepared"
                    body = f"Your order #{order_id} is now being prepared."
                elif user_type_str == 'chef':
                    title = "Order Preparation Started"
                    body = f"You have started preparing order #{order_id}."
                elif user_type_str == 'producer':
                    title = "Order In Progress"
                    body = f"Order #{order_id} is now being prepared by the chef."
                elif user_type_str == 'transporter':
                    title = "Order In Preparation"
                    body = f"Order #{order_id} is being prepared and will need pickup soon."
            
            elif status == 'accepted':
                if user_type_str == 'user':
                    title = "Order Accepted!"
                    body = f"Your order #{order_id} has been accepted."
                elif user_type_str == 'chef':
                    title = "Order Acceptance Confirmed"
                    body = f"You've accepted order #{order_id} for preparation."
                elif user_type_str == 'producer':
                    title = "Order Acceptance Confirmed"
                    body = f"You've accepted order #{order_id} for processing."
                elif user_type_str == 'transporter':
                    title = "Order Accepted by Provider"
                    body = f"Order #{order_id} has been accepted by the provider."
                    
            elif status == 'assigned':
                logger.debug(f"Creating 'assigned' notification for order {order_id}, user_type: {user_type_str}")
                if user_type_str == 'user':
                    title = "Your delivery is on the way!"
                    body = f"Your order #{order_id} has been assigned to a transporter."
                elif user_type_str == 'chef':
                    title = "Order Assigned to Transporter"
                    body = f"Order #{order_id} has been assigned to a transporter for delivery."
                elif user_type_str == 'producer':
                    title = "Order Assigned to Transporter"
                    body = f"Order #{order_id} has been assigned to a transporter for delivery."
                elif user_type_str == 'transporter':
                    title = f"New Delivery Assignment: Order #{order_id}!"
                    body = "You have been assigned a new order for delivery."
                else:
                    logger.warning(f"Unhandled user_type '{user_type_str}' for 'assigned' status in order {order_id}")
                logger.debug(f"Assigned notification - title: {title!r}, body: {body!r}")
                    
            elif status == 'ready_for_pickup':
                if user_type_str == 'user':
                    title = f"Order #{order_id} Ready for Pickup!"
                    body = "Your order is ready for pickup at the designated location."
                elif user_type_str == 'chef':
                    title = f"Order #{order_id} Ready for Pickup Confirmed"
                    body = "You have marked the order as ready for pickup."
                elif user_type_str == 'producer':
                    title = "Order Ready for Pickup"
                    body = f"Order #{order_id} has been prepared and is ready for pickup."
                elif user_type_str == 'transporter':
                    title = "Order Ready for Pickup"
                    body = f"Order #{order_id} is ready to be picked up. Please proceed to the pickup location."
                    
            elif status in ('picked_up', 'picked up'):
                if user_type_str == 'user':
                    title = f"Order #{order_id} Picked Up!"
                    body = "Your order is on its way to you now."
                elif user_type_str == 'chef':
                    title = "Order Picked Up"
                    body = f"Order #{order_id} has been picked up by the transporter."
                elif user_type_str == 'producer':
                    title = "Order Picked Up"
                    body = f"Order #{order_id} has been picked up by the transporter."
                elif user_type_str == 'transporter':
                    title = f"Order #{order_id} Pickup Confirmed"
                    body = "You have marked the order as picked up. Safe travels!"
                    
            elif status in ('on_the_way', 'on the way', 'delivering'):
                if user_type_str == 'user':
                    title = f"Your Order is On the Way!"
                    body = f"Order #{order_id} is on its way to you. Your rider will arrive soon."
                elif user_type_str == 'chef':
                    title = "Order In Transit"
                    body = f"Order #{order_id} is on the way to the customer."
                elif user_type_str == 'producer':
                    title = "Order In Transit"
                    body = f"Order #{order_id} is on the way to the customer."
                elif user_type_str == 'transporter':
                    title = "In Transit"
                    body = f"You marked order #{order_id} as on the way to the customer."
                    
            elif status == 'delivered':
                if user_type_str == 'user':
                    title = "Order Delivered!"
                    body = f"Your order #{order_id} has been delivered. Enjoy!"
                elif user_type_str == 'chef':
                    title = "Order Delivered to Customer"
                    body = f"Order #{order_id} has been successfully delivered to the customer."
                elif user_type_str == 'producer':
                    title = "Order Delivered to Customer"
                    body = f"Order #{order_id} has been successfully delivered to the customer."
                elif user_type_str == 'transporter':
                    title = "Delivery Completed"
                    body = f"You have successfully delivered order #{order_id}."
                    
            elif status in ('shipped', 'dispatched'):
                if user_type_str == 'user':
                    title = f"Order #{order_id} Shipped!"
                    body = "Your order has been shipped and is on its way to you."
                elif user_type_str == 'chef':
                    title = "Order Shipped"
                    body = f"Order #{order_id} has been shipped to the customer."
                elif user_type_str == 'producer':
                    title = "Order Shipped"
                    body = f"Order #{order_id} has been shipped to the customer."
                elif user_type_str == 'transporter':
                    title = "Order Shipped"
                    body = f"Order #{order_id} has been shipped to the customer."
                    
            elif status in ('verification_needed', 'verification needed'):
                if user_type_str == 'user':
                    title = "Your order has arrived!"
                    body = f"Order #{order_id} requires verification. Please check the app."
                elif user_type_str == 'chef':
                    title = "Order Completion Pending Verification"
                    body = f"Order #{order_id} requires verification from customer before being marked complete."
                elif user_type_str == 'producer':
                    title = "Order Completion Pending Verification"
                    body = f"Order #{order_id} requires verification from customer before being marked complete."
                elif user_type_str == 'transporter':
                    title = "Delivery Verification Required"
                    body = f"Order #{order_id} requires verification from customer to complete delivery."
                    
            elif status == 'cancelled':
                if user_type_str == 'user':
                    title = f"Order #{order_id} Cancelled"
                    body = "Your order has been cancelled."
                elif user_type_str == 'chef':
                    title = "Order Cancelled"
                    body = f"Order #{order_id} has been cancelled. No further action is required."
                elif user_type_str == 'producer':
                    title = "Order Cancelled"
                    body = f"Order #{order_id} has been cancelled. No further action is required."
                elif user_type_str == 'transporter':
                    title = "Delivery Cancelled"
                    body = f"Order #{order_id} has been cancelled. No delivery is required."
                    
            elif status == 'completed':
                if user_type_str == 'user':
                    title = f"Order #{order_id} Complete!"
                    body = "Your order has been successfully completed. Thank you for your business!"
                elif user_type_str == 'chef':
                    title = f"Order #{order_id} Complete"
                    body = "The order has been successfully completed and delivered to the customer."
                elif user_type_str == 'producer':
                    title = f"Order #{order_id} Complete"
                    body = "The order has been successfully completed and delivered to the customer."
                elif user_type_str == 'transporter':
                    title = f"Order #{order_id} Complete"
                    body = "The order has been successfully completed and verified by the customer."
                    
            # For any other statuses, use the general message format
            else:
                # Log when falling back to default message
                logger.warning(
                    f"Using default notification message for status: {status!r} (normalized: {status_display!r}), "
                    f"notification_type: {notification_type!r}, order_id: {order_id!r}, "
                    f"user_type: {user_type_str!r}"
                )
                
                title = f"Order {status_display}"
                body = f"Order #{order_id} {status_message}."
                
                # Additional customization for general user types
                if user_type_str == 'user':
                    body = f"Your order #{order_id} {status_message}."
                elif user_type_str == 'chef':
                    body = f"Order #{order_id} from customer {status_message}."
                elif user_type_str == 'producer':
                    body = f"Order #{order_id} from customer {status_message}."
                elif user_type_str == 'transporter':
                    body = f"Delivery order #{order_id} {status_message}."
        
        # Handle broadcast notifications
        elif notification_type == 'broadcast':
            title = metadata.get('broadcast_title', "Important Announcement")
            body = metadata.get('broadcast_message', "Please check the app for an important update.")
            
            # Customize broadcast messages based on user type
            if user_type_str == 'user':
                title = metadata.get('user_broadcast_title', title)
                body = metadata.get('user_broadcast_message', body)
            elif user_type_str == 'chef':
                title = metadata.get('chef_broadcast_title', title)
                body = metadata.get('chef_broadcast_message', body)
            elif user_type_str == 'producer':
                title = metadata.get('producer_broadcast_title', title)
                body = metadata.get('producer_broadcast_message', body)
            elif user_type_str == 'transporter':
                title = metadata.get('transporter_broadcast_title', title)
                body = metadata.get('transporter_broadcast_message', body)
            
        # Handle payment notifications
        elif notification_type.startswith('payment_'):
            payment_status = notification_type.replace('payment_', '')
            amount = metadata.get('amount', 'unknown amount')
            
            if payment_status == 'received':
                if user_type_str == 'user':
                    title = "Payment Received"
                    body = f"We've received your payment of {amount}."
                elif user_type_str in ['chef', 'producer']:
                    title = "Payment Received"
                    body = f"You have received a payment of {amount}."
                elif user_type_str == 'transporter':
                    title = "Payment Received"
                    body = f"You have received a payment of {amount}."
            elif payment_status == 'failed':
                if user_type_str == 'user':
                    title = "Payment Failed"
                    body = f"Your payment of {amount} could not be processed."
                elif user_type_str in ['chef', 'producer']:
                    title = "Payment Failed"
                    body = f"A payment of {amount} failed to process."
                elif user_type_str == 'transporter':
                    title = "Payment Failed"
                    body = f"A payment of {amount} failed to process."
            elif payment_status == 'refunded':
                if user_type_str == 'user':
                    title = "Payment Refunded"
                    body = f"Your payment of {amount} has been refunded."
                elif user_type_str in ['chef', 'producer']:
                    title = "Payment Refunded"
                    body = f"A payment of {amount} has been refunded to the customer."
                elif user_type_str == 'transporter':
                    title = "Payment Refunded"
                    body = f"A payment of {amount} has been refunded to the customer."
            elif payment_status == 'sent':
                if user_type_str == 'user':
                    title = "Payment Sent"
                    body = f"Your payment of {amount} has been sent."
                elif user_type_str in ['chef', 'producer', 'transporter']:
                    title = "Payment Sent"
                    body = f"A payment of {amount} has been sent to your account."
        
        # Handle account notifications
        elif notification_type.startswith('account_'):
            account_action = notification_type.replace('account_', '')
            
            if account_action == 'created':
                if user_type_str == 'user':
                    title = "Welcome to Our Platform!"
                    body = "Your customer account has been successfully created."
                elif user_type_str == 'chef':
                    title = "Welcome to Our Chef Network!"
                    body = "Your chef account has been successfully created."
                elif user_type_str == 'producer':
                    title = "Welcome to Our Producer Network!"
                    body = "Your producer account has been successfully created."
                elif user_type_str == 'transporter':
                    title = "Welcome to Our Delivery Network!"
                    body = "Your transporter account has been successfully created."
            elif account_action == 'verified':
                if user_type_str == 'user':
                    title = "Account Verified"
                    body = "Your customer account has been successfully verified."
                elif user_type_str == 'chef':
                    title = "Chef Account Verified"
                    body = "Your chef account has been successfully verified."
                elif user_type_str == 'producer':
                    title = "Producer Account Verified"
                    body = "Your producer account has been successfully verified."
                elif user_type_str == 'transporter':
                    title = "Transporter Account Verified"
                    body = "Your transporter account has been successfully verified."
            elif account_action == 'password_reset':
                title = "Password Reset"
                body = "Your password has been reset successfully."
            elif account_action == 'update_required':
                if user_type_str == 'user':
                    title = "Account Update Required"
                    body = "Please update your customer account information."
                elif user_type_str == 'chef':
                    title = "Chef Profile Update Required"
                    body = "Please update your chef profile information."
                elif user_type_str == 'producer':
                    title = "Producer Profile Update Required"
                    body = "Please update your producer profile information."
                elif user_type_str == 'transporter':
                    title = "Transporter Profile Update Required"
                    body = "Please update your transporter profile information."
        
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

    async def store_fcm_token(self, user_id: int, token: str, platform: str, user_type: str, app_version: Optional[str] = None):
        """
        Store a new FCM token for a user in the 'fcm_tokens' table.
        Each user_id/user_type combination can have multiple active tokens across different platforms.
        
        Args:
            user_id: The ID of the user
            token: The FCM token to store
            platform: The platform (e.g., 'android', 'ios', 'web')
            user_type: The type of user (e.g., 'user', 'chef', 'producer')
            app_version: Optional app version string (e.g., '1.2.22+28')
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
                            app_version = $3,
                            is_active = TRUE,
                            updated_at = NOW()
                        WHERE user_id = $4 AND token = $5
                        """,
                        user_type, platform, app_version, user_id, token
                    )
                else:
                    # Insert new token
                    await conn.execute(
                        """
                        INSERT INTO fcm_tokens (
                            user_id, user_type, token, platform, app_version,
                            is_active
                        )
                        VALUES (
                            $1, $2, $3, $4, $5,
                            TRUE
                        )
                        """,
                        user_id, user_type, token, platform, app_version
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
