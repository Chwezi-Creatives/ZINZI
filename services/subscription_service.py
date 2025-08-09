from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Union
import asyncpg
from fastapi import HTTPException, status
from pydantic import BaseModel

class SubscriptionStatus:
    ACTIVE = "active"
    CANCELLED = "cancelled"
    EXPIRED = "expired"

class PlanStatusResponse(BaseModel):
    has_active_plan: bool
    current_plan: Optional[Dict[str, Any]] = None
    days_remaining: int = 0
    is_trial: bool = False

class SubscriptionService:

    async def get_subscription_plans(self, conn: asyncpg.Connection) -> List[Dict[str, Any]]:
        """Get all active subscription plans"""
        query = """
        SELECT * FROM subscription_plans 
        WHERE is_active = true AND deleted_at IS NULL
        ORDER BY price_in_cents ASC
        """
        rows = await conn.fetch(query)
        return [dict(row) for row in rows]

    async def get_plan_by_id(self, conn: asyncpg.Connection, plan_id: int) -> Optional[Dict[str, Any]]:
        """Get a specific subscription plan by ID"""
        query = """
        SELECT * FROM subscription_plans 
        WHERE id = $1 AND is_active = true AND deleted_at IS NULL
        """
        row = await conn.fetchrow(query, plan_id)
        return dict(row) if row else None

    async def get_user_subscription(self, conn: asyncpg.Connection, user_id: int) -> Optional[Dict[str, Any]]:
        """Get a user's active subscription"""
        query = """
        SELECT us.*, sp.*, us.id as subscription_id, us.status as subscription_status
        FROM user_subscriptions us
        JOIN subscription_plans sp ON us.plan_id = sp.id
        WHERE us.user_id = $1 
        AND us.status = 'active'
        AND (us.end_date IS NULL OR us.end_date > NOW())
        AND sp.is_active = true
        LIMIT 1
        """
        row = await conn.fetchrow(query, user_id)
        return dict(row) if row else None

    async def create_subscription(
        self, 
        conn: asyncpg.Connection,
        user_id: int, 
        plan_id: int, 
        payment_transaction_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """Create a new subscription for a user"""
        # Check if plan exists
        plan = await self.get_plan_by_id(conn, plan_id)
        if not plan:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Subscription plan not found"
            )

        # Check for existing active subscription
        existing_sub = await self.get_user_subscription(conn, user_id)
        if existing_sub:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User already has an active subscription"
            )

        # Calculate start and end dates
        now = datetime.utcnow()
        end_date = now + timedelta(days=plan['billing_cycle_days'])

        # Create new subscription
        query = """
        INSERT INTO user_subscriptions (
            user_id, plan_id, status, 
            start_date, end_date, payment_transaction_id
        )
        VALUES (
            $1, $2, $3, $4, $5, $6
        )
        RETURNING *
        """
        
        row = await conn.fetchrow(
            query,
            user_id,
            plan_id,
            SubscriptionStatus.ACTIVE,
            now,
            end_date,
            payment_transaction_id
        )
        
        return dict(row) if row else None

    async def cancel_subscription(self, conn: asyncpg.Connection, user_id: int) -> bool:
        """Cancel a user's active subscription"""
        query = """
        UPDATE user_subscriptions
        SET 
            status = $1,
            cancelled_at = NOW(),
            updated_at = NOW()
        WHERE user_id = $2 
        AND status = $3
        AND (end_date IS NULL OR end_date > NOW())
        RETURNING *
        """
        result = await conn.execute(
            query,
            SubscriptionStatus.CANCELLED,
            user_id,
            SubscriptionStatus.ACTIVE
        )
        return bool(await conn.fetchval("SELECT row_count()"))

    async def get_subscription_status(self, conn: asyncpg.Connection, user_id: int) -> Dict[str, Any]:
        """Get the current subscription status for a user"""
        subscription = await self.get_user_subscription(conn, user_id)
        if not subscription:
            return PlanStatusResponse(has_active_plan=False)

        # Calculate days remaining
        days_remaining = 0
        if subscription['end_date']:
            days_remaining = (subscription['end_date'].replace(tzinfo=None) - datetime.utcnow()).days
            days_remaining = max(0, days_remaining)

        return PlanStatusResponse(
            has_active_plan=True,
            current_plan=subscription,
            days_remaining=days_remaining,
            is_trial=False
        )
