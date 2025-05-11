# UNUSED FILE: This notifications.py router is not included in the FastAPI app and is not used.
# All notification endpoints are handled directly in integrated_backend.py.
# This file can be ignored or deleted if not needed for reference.

from fastapi import APIRouter, HTTPException, Depends
from typing import List, Optional
from pydantic import BaseModel
from ..services.notification_service import notification_service
from ..dependencies import get_current_user

router = APIRouter()

class FCMToken(BaseModel):
    token: str
    platform: str
    user_type: str = "user"  # Default to 'user' if not specified
    user_id: str = None  # Optional user_id, prefer this if provided

class NotificationSubscription(BaseModel):
    topic: str

class NotificationData(BaseModel):
    title: str
    body: str
    data: dict
    type: str

@router.post("/tokens")
async def register_fcm_token(
    token_data: FCMToken,
    user_id: str = Depends(get_current_user)
):
    """
    Register or update an FCM token for a user.
    
    Args:
        token_data: FCM token data
        user_id: User's UUID
    
    Returns:
        dict: Success message
    """
    final_user_id = token_data.user_id if token_data.user_id else user_id
    success = notification_service.store_fcm_token(
        user_id=final_user_id,
        token=token_data.token,
        platform=token_data.platform,
        user_type=token_data.user_type
    )
    
    if success:
        return {"message": "Token registered successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to register token")

@router.get("/tokens", response_model=List[FCMToken])
async def get_fcm_tokens(
    platform: Optional[str] = None,
    user_type: Optional[str] = None,
    user_id: str = Depends(get_current_user)
):
    """
    Get FCM tokens for a user.
    
    Args:
        platform: Optional platform filter
        user_type: Optional user type filter ('user', 'chef', 'producer', 'transporter')
        user_id: User's UUID
    
    Returns:
        List[FCMToken]: List of FCM tokens
    """
    tokens = notification_service.get_fcm_tokens(user_id, platform, user_type)
    return tokens

@router.delete("/tokens/{token_id}")
async def deactivate_fcm_token(
    token_id: int,
    user_id: str = Depends(get_current_user)
):
    """
    Deactivate an FCM token.
    
    Args:
        token_id: ID of the token to deactivate
        user_id: User's UUID
    
    Returns:
        dict: Success message
    """
    success = notification_service.deactivate_fcm_token(token_id)
    
    if success:
        return {"message": "Token deactivated successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to deactivate token")

@router.post("/subscriptions")
async def subscribe_to_topic(
    subscription: NotificationSubscription,
    user_id: str = Depends(get_current_user)
):
    """
    Subscribe a user to a notification topic.
    
    Args:
        subscription: Topic subscription data
        user_id: User's UUID
    
    Returns:
        dict: Success message
    """
    success = notification_service.subscribe_to_topic(
        user_id=user_id,
        topic=subscription.topic
    )
    
    if success:
        return {"message": "Subscribed to topic successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to subscribe to topic")

@router.delete("/subscriptions/{topic}")
async def unsubscribe_from_topic(
    topic: str,
    user_id: str = Depends(get_current_user)
):
    """
    Unsubscribe a user from a notification topic.
    
    Args:
        topic: Topic name
        user_id: User's UUID
    
    Returns:
        dict: Success message
    """
    success = notification_service.unsubscribe_from_topic(
        user_id=user_id,
        topic=topic
    )
    
    if success:
        return {"message": "Unsubscribed from topic successfully"}
    else:
        raise HTTPException(status_code=500, detail="Failed to unsubscribe from topic")

@router.post("/send")
async def send_notification(
    notification: NotificationData,
    user_id: str = Depends(get_current_user)
):
    """
    Send a notification to a user.
    
    Args:
        notification: Notification data
        user_id: User's UUID
    
    Returns:
        dict: Notification ID
    """
    # Get tokens for the user
    tokens = notification_service.get_fcm_tokens(user_id)
    
    if not tokens:
        raise HTTPException(status_code=400, detail="No active tokens found")
    
    # Log the notification
    notification_id = notification_service.log_notification(
        user_id=user_id,
        token=tokens[0]['token'],  # Use the first active token
        notification_type=notification.type,
        title=notification.title,
        body=notification.body,
        data=notification.data
    )
    
    if not notification_id:
        raise HTTPException(status_code=500, detail="Failed to log notification")
    
    return {"notification_id": notification_id}

@router.get("/history", response_model=List[dict])
async def get_notification_history(
    limit: int = 50,
    user_id: str = Depends(get_current_user)
):
    """
    Get notification history for a user.
    
    Args:
        limit: Maximum number of notifications to return
        user_id: User's UUID
    
    Returns:
        List[dict]: List of notification history items
    """
    return notification_service.get_notification_history(user_id, limit)
