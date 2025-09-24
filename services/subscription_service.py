import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, List, Union
import asyncpg
from fastapi import status, HTTPException, Request
from functools import wraps
import time

# Import caching utilities
from utils.cache import cached, invalidate_cache, clear_all_caches, get_cache, set_cache

# Set up logger
logger = logging.getLogger(__name__)
from pydantic import BaseModel
from enum import Enum

class SubscriptionStatus(str, Enum):
    ACTIVE = "active"
    CANCELED = "canceled"
    EXPIRED = "expired"

class BillingCycle(str, Enum):
    MONTHLY = "monthly"
    BI_WEEKLY = "bi-weekly"
    YEARLY = "yearly"

class PlanStatusResponse(BaseModel):
    has_active_plan: bool
    current_plan: Optional[Dict[str, Any]] = None
    days_remaining: int = 0
    is_trial: bool = False

class MealPlanCreate(BaseModel):
    user_id: int
    chefid: int
    subscription_id: int
    name: str
    start_date: datetime
    end_date: datetime
    meals: List[Dict[str, Any]]

class PlanCreate(BaseModel):
    name: str
    description: str
    price: float
    billing_cycle: BillingCycle
    features: List[str]
    is_active: bool = True

class PlanUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    billing_cycle: Optional[BillingCycle] = None
    features: Optional[List[str]] = None
    is_active: Optional[bool] = None

class SubscriptionService:
    def __init__(self, db_pool: asyncpg.Pool):
        self.db_pool = db_pool
        self._cache = {}
        logger.info("SubscriptionService initialized with database pool and in-memory cache")

    async def _check_rate_limit(
        self,
        key: str,
        limit: int = 5,
        window: int = 60
    ) -> Dict[str, Any]:
        current_time = time.time()
        window_start = current_time - window
        rate_limit_key = f"rate_limit:{key}"
        timestamps = self._cache.get(rate_limit_key, [])
        timestamps = [ts for ts in timestamps if ts > window_start]
        
        if len(timestamps) >= limit:
            return {
                'allowed': False,
                'remaining': 0,
                'retry_after': int(timestamps[0] + window - current_time)
            }
        
        timestamps.append(current_time)
        self._cache[rate_limit_key] = timestamps
        
        return {
            'allowed': True,
            'remaining': max(0, limit - len(timestamps)),
            'retry_after': 0
        }

    def _invalidate_user_cache(self, user_id: int) -> None:
        cache_keys = [
            f"user_subscription:{user_id}",
            f"user_plans:{user_id}",
            f"user_meal_plans:{user_id}"
        ]
        for key in cache_keys:
            if key in self._cache:
                del self._cache[key]
                logger.debug(f"Invalidated cache for key: {key}")
        if 'clear_all_caches' in globals() and callable(clear_all_caches):
            clear_all_caches()

    async def ensure_indexes_exist(self, conn: asyncpg.Connection) -> None:
        index_queries = [
            "CREATE INDEX IF NOT EXISTS idx_meal_plans_user_id ON meal_plans(user_id)",
            "CREATE INDEX IF NOT EXISTS idx_meal_plans_chefid ON meal_plans(chefid)",
            "CREATE INDEX IF NOT EXISTS idx_meal_plan_meals_plan_meal ON meal_plan_meals(meal_plan_id, meal_id)",
            "CREATE INDEX IF NOT EXISTS idx_subscriptions_user_status ON subscriptions(user_id, status)"
        ]
        for query in index_queries:
            try:
                await conn.execute(query)
            except Exception as e:
                logger.error(f"Error creating index: {str(e)}")

    @cached(ttl=300)
    async def get_plans(
        self,
        conn: asyncpg.Connection,
        is_active: Optional[bool] = True,
        is_prebuilt: Optional[bool] = None,
        is_featured: Optional[bool] = None,
        chef_id: Optional[int] = None,
        meal_ids: Optional[List[str]] = None,
        require_all_meals: bool = False,
        limit: int = 100,
        offset: int = 0
    ) -> List[Dict[str, Any]]:
        """
        Unified method to get all plans with optional filtering.
        Handles both normal and prebuilt plans.
        """
        cache_key = f"plans:active:{is_active}:prebuilt:{is_prebuilt}:featured:{is_featured}:chef:{chef_id}:meals:{meal_ids}:all:{require_all_meals}:limit:{limit}:offset:{offset}"
        cached = get_cache(cache_key)
        if cached is not None:
            logger.info(f"Using cached plans for key: {cache_key}")
            return cached

        query = """
        SELECT
            plan_id, name, description, price, billing_cycle, features,
            is_active, is_prebuilt, is_featured, chef, meals,
            created_at, updated_at
        FROM plans
        WHERE 1=1
        """
        params = []

        if is_active is not None:
            query += f" AND is_active = ${len(params) + 1}"
            params.append(is_active)
        if is_prebuilt is not None:
            query += f" AND is_prebuilt = ${len(params) + 1}"
            params.append(is_prebuilt)
        if is_featured is not None:
            query += f" AND is_featured = ${len(params) + 1}"
            params.append(is_featured)
        if chef_id is not None:
            query += f" AND (chef->>'chefid')::int = ${len(params) + 1}"
            params.append(chef_id)

        if meal_ids:
            # This query ensures that all elements in meal_ids are present in the 'meals' JSONB array.
            if require_all_meals:
                 query += f" AND is_prebuilt = true AND (SELECT count(DISTINCT m->>'meal_id') FROM jsonb_array_elements(meals) m WHERE m->>'meal_id' = ANY(${len(params) + 1}::text[])) = {len(meal_ids)}"
                 params.append(meal_ids)
            else:
                 query += f" AND is_prebuilt = true AND EXISTS (SELECT 1 FROM jsonb_array_elements(meals) m WHERE m->>'meal_id' = ANY(${len(params) + 1}::text[]))"
                 params.append(meal_ids)


        query += f" ORDER BY created_at DESC LIMIT ${len(params) + 1} OFFSET ${len(params) + 2}"
        params.extend([limit, offset])

        try:
            rows = await conn.fetch(query, *params)
            plans = []
            for row in rows:
                plan = dict(row)
                if 'price' in plan and plan['price'] is not None:
                    plan['price'] = float(plan['price'])
                for field in ['features', 'chef', 'meals']:
                    if field in plan and isinstance(plan[field], str):
                        try:
                            plan[field] = json.loads(plan[field])
                        except (json.JSONDecodeError, TypeError):
                            plan[field] = [] if field in ['features', 'meals'] else None
                plans.append(plan)
            
            logger.info(f"Found {len(plans)} plans matching criteria")
            set_cache(cache_key, plans, ttl=300)
            return plans
        except Exception as e:
            logger.error(f"Error fetching plans: {str(e)}")
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to fetch plans")

    async def get_plan_by_id(self, conn: asyncpg.Connection, plan_id: int) -> Optional[Dict[str, Any]]:
        try:
            query = "SELECT * FROM plans WHERE plan_id = $1"
            plan = await conn.fetchrow(query, plan_id)
            if plan:
                plan_data = dict(plan)
                plan_data['price'] = float(plan_data.get('price', 0.0))
                logger.info(f"Found plan: {plan_data.get('name')} (ID: {plan_id})")
                return plan_data
            logger.warning(f"Plan not found with ID: {plan_id}")
            return None
        except Exception as e:
            logger.error(f"Error fetching plan {plan_id}: {str(e)}")
            raise

    async def create_plan(self, conn: asyncpg.Connection, plan_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new plan (normal or prebuilt).
        """
        logger.info(f"[PLAN SERVICE] Starting plan creation with data: {plan_data}")
        required_fields = ['name', 'price', 'billing_cycle']
        if any(field not in plan_data for field in required_fields):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing required fields")

        is_prebuilt = plan_data.get('is_prebuilt', False)
        if is_prebuilt:
            if 'chef' not in plan_data or not plan_data['chef']:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "chef is required for prebuilt plans")
            if 'meals' not in plan_data or not plan_data['meals']:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "meals are required for prebuilt plans")

        query = """
        INSERT INTO plans (
            name, description, price, billing_cycle, features, is_active, 
            is_prebuilt, is_featured, chef, meals
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *
        """
        try:
            billing_cycle = plan_data["billing_cycle"].value if hasattr(plan_data["billing_cycle"], "value") else plan_data["billing_cycle"]
            features_json = json.dumps(plan_data.get("features", []))
            chef_json = json.dumps(plan_data.get("chef")) if plan_data.get("chef") else None
            meals_json = json.dumps(plan_data.get("meals", []))

            row = await conn.fetchrow(
                query,
                plan_data["name"], plan_data.get("description", ""), plan_data["price"],
                billing_cycle, features_json, plan_data.get("is_active", True),
                is_prebuilt, plan_data.get("is_featured", False),
                chef_json, meals_json
            )

            if row:
                created_plan = dict(row)
                logger.info(f"Successfully created plan: {created_plan.get('name')} (ID: {created_plan.get('plan_id')})")
                invalidate_cache("all_plans")
                return created_plan
            else:
                raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to create plan")
        except asyncpg.UniqueViolationError:
            raise HTTPException(status.HTTP_409_CONFLICT, "A plan with this name already exists")
        except Exception as e:
            logger.error(f"Failed to create plan: {str(e)}", exc_info=True)
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, f"Failed to create plan: {e}")

    async def update_plan(
        self, conn: asyncpg.Connection, plan_id: int, updates: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Update an existing plan (normal or prebuilt).
        """
        logger.info(f"[PLAN SERVICE] Starting update for plan ID: {plan_id}")
        existing = await self.get_plan_by_id(conn, plan_id)
        if not existing:
            return None

        is_prebuilt = updates.get('is_prebuilt', existing.get('is_prebuilt', False))
        if is_prebuilt:
            if 'chef' in updates and not updates['chef']:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "chef cannot be empty for prebuilt plans")
            if 'meals' in updates and not updates['meals']:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "meals cannot be empty for prebuilt plans")

        set_clauses, params = [], []
        param_count = 1
        for field, value in updates.items():
            db_field = field
            if field in ['features', 'chef', 'meals']:
                value = json.dumps(value)
            set_clauses.append(f"{db_field} = ${param_count}")
            params.append(value)
            param_count += 1
        
        if not set_clauses:
            return existing
        
        set_clauses.append("updated_at = NOW()")
        query = f"UPDATE plans SET {', '.join(set_clauses)} WHERE plan_id = ${param_count} RETURNING *"
        params.append(plan_id)

        try:
            row = await conn.fetchrow(query, *params)
            if row:
                updated_plan = dict(row)
                logger.info(f"Successfully updated plan ID: {plan_id}")
                invalidate_cache(f"plan:{plan_id}")
                invalidate_cache("all_plans")
                return updated_plan
            return None
        except Exception as e:
            logger.error(f"Error updating plan {plan_id}: {str(e)}")
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to update plan")

    async def delete_plan(self, conn: asyncpg.Connection, plan_id: int) -> Dict[str, Any]:
        """
        Soft delete a plan by marking it as inactive (for normal and prebuilt plans).
        """
        logger.info(f"[PLAN SERVICE] Attempting to soft delete plan ID: {plan_id}")
        existing = await self.get_plan_by_id(conn, plan_id)
        if not existing:
            raise HTTPException(status.HTTP_404_NOT_FOUND, f"Plan ID {plan_id} not found")

        # Validation logic specifically for prebuilt plans before deletion
        if existing.get('is_prebuilt', False):
            logger.info("Validating prebuilt plan deletion...")
            active_count = await conn.fetchval("SELECT COUNT(*) FROM subscriptions WHERE plan_id = $1 AND status = 'active'", plan_id)
            if active_count > 0:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Cannot delete plan with {active_count} active subscriptions")
            
            # This checks meal_plans associated with subscriptions tied to the plan_id
            active_meal_plans = await conn.fetchval("""
                SELECT COUNT(*) FROM meal_plans mp
                JOIN subscriptions s ON mp.subscription_id = s.subscription_id
                WHERE s.plan_id = $1 AND mp.end_date >= CURRENT_DATE
            """, plan_id)
            if active_meal_plans > 0:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Cannot delete plan with {active_meal_plans} active meal plans")

        query = "UPDATE plans SET is_active = FALSE, updated_at = NOW() WHERE plan_id = $1 RETURNING plan_id, name, is_active"
        try:
            deleted_plan = await conn.fetchrow(query, plan_id)
            if not deleted_plan:
                raise HTTPException(status.HTTP_404_NOT_FOUND, f"Plan ID {plan_id} not found during deletion attempt")
            
            logger.info(f"Successfully soft-deleted plan ID: {plan_id}")
            invalidate_cache(f"plan:{plan_id}")
            invalidate_cache("all_plans")
            return dict(deleted_plan)
        except Exception as e:
            logger.error(f"Error deleting plan {plan_id}: {str(e)}")
            if isinstance(e, HTTPException):
                raise
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to delete plan")

    async def get_user_subscription(self, conn: asyncpg.Connection, user_id: int) -> Optional[Dict[str, Any]]:
        query = """
        SELECT s.*, p.name as plan_name, p.price, p.billing_cycle
        FROM subscriptions s JOIN plans p ON s.plan_id = p.plan_id
        WHERE s.user_id = $1 AND s.status = 'active' AND s.end_date > NOW()
        ORDER BY s.end_date DESC LIMIT 1
        """
        row = await conn.fetchrow(query, user_id)
        return dict(row) if row else None

    async def get_all_subscriptions(
        self, conn: asyncpg.Connection, status_filter: Optional[str] = None,
        user_id: Optional[int] = None, limit: int = 100, offset: int = 0
    ) -> Dict[str, Any]:
        where_clauses, params = [], []
        if status_filter:
            where_clauses.append(f"s.status = ${len(params) + 1}")
            params.append(status_filter)
        if user_id is not None:
            where_clauses.append(f"s.user_id = ${len(params) + 1}")
            params.append(user_id)
        where_clause = " AND ".join(where_clauses) if where_clauses else "1=1"

        count_query = f"SELECT COUNT(*) FROM subscriptions s WHERE {where_clause}"
        total_count = await conn.fetchval(count_query, *params)

        query = f"""
        SELECT s.*, p.name as plan_name, p.price, p.billing_cycle, u.name as user_name, u.email as user_email
        FROM subscriptions s JOIN plans p ON s.plan_id = p.plan_id JOIN users u ON s.user_id = u.user_id
        WHERE {where_clause} ORDER BY s.end_date DESC LIMIT ${len(params) + 1} OFFSET ${len(params) + 2}
        """
        rows = await conn.fetch(query, *params, limit, offset)
        return {
            'subscriptions': [dict(row) for row in rows], 'total_count': total_count,
            'limit': limit, 'offset': offset
        }

    async def create_subscription(
        self, conn: asyncpg.Connection, user_id: int, plan_id: int, 
        payment_transaction_id: Optional[str] = None, request: Optional[Request] = None, phone_number: Optional[str] = None
    ) -> Dict[str, Any]:
        if request:
            rate_limit = await self._check_rate_limit(f"sub_create:{request.client.host}:{user_id}")
            if not rate_limit['allowed']:
                raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many subscription attempts.", headers={"Retry-After": str(rate_limit['retry_after'])})

        plan = await self.get_plan_by_id(conn, plan_id)
        if not plan:
            raise HTTPException(status.HTTP_404_NOT_FOUND, f"Plan with ID {plan_id} not found")
        
        is_prebuilt = plan.get('is_prebuilt', False)
        if not is_prebuilt:
            if await self.get_user_subscription(conn, user_id):
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "User already has an active subscription")

        start_date = datetime.now(timezone.utc)
        days = {'monthly': 30, 'yearly': 365, 'bi-weekly': 14}.get(plan['billing_cycle'], 14)
        end_date = start_date + timedelta(days=days)
        
        query = """
        INSERT INTO subscriptions (
            user_id, plan_id, start_date, end_date, status, payment_transaction_id, is_prebuilt, phone_number
        ) VALUES ($1, $2, $3, $4, 'active', $5, $6, $7) RETURNING *
        """
        try:
            self._invalidate_user_cache(user_id)
            async with conn.transaction():
                result = await conn.fetchrow(query, user_id, plan_id, start_date, end_date, payment_transaction_id, is_prebuilt, phone_number)
                if not result:
                    raise Exception("Failed to create subscription")
                
                subscription = dict(result)
                logger.info(f"Created subscription {subscription.get('subscription_id')} for user {user_id}")
                return subscription
        except Exception as e:
            logger.error(f"Error creating subscription: {e}", exc_info=True)
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Error processing subscription")

    async def update_subscription_status(
        self, conn: asyncpg.Connection, subscription_id: int, status: str
    ) -> Dict[str, Any]:
        normalized_status = 'canceled' if status.lower() in ['cancelled', 'canceled'] else status.lower()
        if normalized_status not in [s.value for s in SubscriptionStatus]:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid status")

        async with conn.transaction():
            sub = await conn.fetchrow("SELECT * FROM subscriptions WHERE subscription_id = $1 FOR UPDATE", subscription_id)
            if not sub:
                raise HTTPException(status.HTTP_404_NOT_FOUND, "Subscription not found")

            updated = await conn.fetchrow("UPDATE subscriptions SET status = $1, updated_at = NOW() WHERE subscription_id = $2 RETURNING *", normalized_status, subscription_id)
        
        self._invalidate_user_cache(sub['user_id'])
        plan = await self.get_plan_by_id(conn, updated['plan_id'])
        response = dict(updated)
        response['plan_name'] = plan.get('name') if plan else 'N/A'
        return response

    async def get_user_subscription_status(self, conn: asyncpg.Connection, user_id: int) -> Dict[str, Any]:
        subscription = await self.get_user_subscription(conn, user_id)
        if not subscription:
            return PlanStatusResponse(has_active_plan=False).dict()

        end_date = subscription['end_date']
        if end_date.tzinfo is None:
            end_date = end_date.replace(tzinfo=timezone.utc)
        days_remaining = max(0, (end_date - datetime.now(timezone.utc)).days)

        return PlanStatusResponse(
            has_active_plan=True,
            current_plan={**subscription},
            days_remaining=days_remaining,
            is_trial=False 
        ).dict()

    async def create_meal_plan(self, conn: asyncpg.Connection, meal_plan_data: Dict[str, Any]) -> Dict[str, Any]:
        try:
            meal_plan = MealPlanCreate(**meal_plan_data)
        except Exception as e:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Invalid data: {e}")

        sub_query = """
        SELECT p.is_prebuilt, p.meals as plan_meals, p.chef as plan_chef
        FROM subscriptions s JOIN plans p ON s.plan_id = p.plan_id
        WHERE s.subscription_id = $1 AND s.user_id = $2 AND s.status = 'active'
        """
        sub_details = await conn.fetchrow(sub_query, meal_plan.subscription_id, meal_plan.user_id)
        if not sub_details:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Active subscription not found")

        if sub_details['is_prebuilt']:
            plan_chef_id = json.loads(sub_details['plan_chef']).get('chefid') if isinstance(sub_details['plan_chef'], str) else sub_details['plan_chef'].get('chefid')
            if meal_plan.chefid != plan_chef_id:
                raise HTTPException(status.HTTP_400_BAD_REQUEST, "Chef mismatch for pre-built plan")
            if not meal_plan.meals: # If no meals provided, use from plan
                meal_plan.meals = json.loads(sub_details['plan_meals']) if isinstance(sub_details['plan_meals'], str) else sub_details['plan_meals']

        async with conn.transaction():
            query = """
            INSERT INTO meal_plans (user_id, chefid, subscription_id, name, start_date, end_date)
            VALUES ($1, $2, $3, $4, $5, $6) RETURNING meal_plan_id
            """
            meal_plan_id = await conn.fetchval(
                query, meal_plan.user_id, meal_plan.chefid, meal_plan.subscription_id,
                meal_plan.name, meal_plan.start_date, meal_plan.end_date
            )
            await self._add_meals_to_meal_plan(conn, meal_plan_id, meal_plan.meals)
            return await self.get_meal_plan_by_id(conn, meal_plan_id)

    async def _add_meals_to_meal_plan(self, conn: asyncpg.Connection, meal_plan_id: int, meals: List[Dict[str, Any]]):
        if not meals: return
        query = """
        INSERT INTO meal_plan_meals (meal_plan_id, meal_id, quantity)
        SELECT $1, m.meal_id, m.quantity FROM unnest($2::text[], $3::int[]) AS m(meal_id, quantity)
        ON CONFLICT (meal_plan_id, meal_id) DO UPDATE SET quantity = EXCLUDED.quantity
        """
        try:
            meal_ids = [m['meal_id'] for m in meals]
            quantities = [m.get('quantity', 1) for m in meals]
            await conn.execute(query, meal_plan_id, meal_ids, quantities)
        except asyncpg.ForeignKeyViolationError:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "One or more meals not found")
        except Exception as e:
            logger.error(f"Error adding meals to plan {meal_plan_id}: {e}", exc_info=True)
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to add meals")

    async def get_meal_plan_by_id(self, conn: asyncpg.Connection, meal_plan_id: int) -> Dict[str, Any]:
        query = """
        SELECT mp.*, u.name as user_name,
               COALESCE(json_agg(json_build_object('meal_id', m.meal_id, 'name', m.meal_name, 'quantity', mpm.quantity))
                        FILTER (WHERE m.meal_id IS NOT NULL), '[]'::json) as meals
        FROM meal_plans mp
        JOIN users u ON mp.user_id = u.user_id
        LEFT JOIN meal_plan_meals mpm ON mp.meal_plan_id = mpm.meal_plan_id
        LEFT JOIN meals m ON mpm.meal_id = m.meal_id
        WHERE mp.meal_plan_id = $1
        GROUP BY mp.meal_plan_id, u.user_id
        """
        plan = await conn.fetchrow(query, meal_plan_id)
        if not plan:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Meal plan not found")
        return dict(plan)

    async def get_meal_plans_by_chef_id(self, conn: asyncpg.Connection, chef_id: int) -> List[Dict[str, Any]]:
        query = """
        SELECT mp.*, u.name as user_name, u.email as user_email,
               COALESCE(json_agg(json_build_object('meal_id', m.meal_id, 'name', m.meal_name, 'quantity', mpm.quantity))
                        FILTER (WHERE m.meal_id IS NOT NULL), '[]'::json) as meals
        FROM meal_plans mp
        JOIN users u ON mp.user_id = u.user_id
        LEFT JOIN meal_plan_meals mpm ON mp.meal_plan_id = mpm.meal_plan_id
        LEFT JOIN meals m ON mpm.meal_id = m.meal_id
        WHERE mp.chefid = $1
        GROUP BY mp.meal_plan_id, u.user_id
        ORDER BY mp.start_date DESC
        """
        return [dict(row) for row in await conn.fetch(query, chef_id)]

    async def get_meal_plans_by_user_id(self, conn: asyncpg.Connection, user_id: int) -> List[Dict[str, Any]]:
        query = """
        SELECT mp.*, c.name as chef_name,
               COALESCE(json_agg(json_build_object('meal_id', m.meal_id, 'name', m.meal_name, 'quantity', mpm.quantity))
                        FILTER (WHERE m.meal_id IS NOT NULL), '[]'::json) as meals
        FROM meal_plans mp
        LEFT JOIN chefs c ON mp.chefid = c.chefid
        LEFT JOIN meal_plan_meals mpm ON mp.meal_plan_id = mpm.meal_plan_id
        LEFT JOIN meals m ON mpm.meal_id = m.meal_id
        WHERE mp.user_id = $1
        GROUP BY mp.meal_plan_id, c.chefid
        ORDER BY mp.start_date DESC
        """
        try:
            return [dict(row) for row in await conn.fetch(query, user_id)]
        except Exception as e:
            logger.error(f"Error fetching meal plans for user {user_id}: {e}")
            raise