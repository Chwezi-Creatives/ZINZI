import json
import logging
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Union, Tuple, AsyncGenerator
import asyncpg
from fastapi import HTTPException, status

# Set up logger
logger = logging.getLogger(__name__)
from pydantic import BaseModel
from enum import Enum, auto

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
    meals: List[Dict[str, Any]]  # List of dicts with meal_id and quantity

class MealPlanResponse(BaseModel):
    id: int
    user_id: int
    chefid: int
    subscription_id: int
    name: str
    start_date: datetime
    end_date: datetime
    created_at: datetime
    meals: List[Dict[str, Any]] = []

class PlanCreate(BaseModel):
    """Pydantic model for creating a new plan"""
    name: str
    description: str
    price: float
    billing_cycle: BillingCycle
    features: List[str]
    is_active: bool = True

class PlanUpdate(BaseModel):
    """Pydantic model for updating a plan"""
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    billing_cycle: Optional[BillingCycle] = None
    features: Optional[List[str]] = None
    is_active: Optional[bool] = None

class SubscriptionService:
    
    async def ensure_indexes_exist(self, conn: asyncpg.Connection) -> None:
        """
        Ensure all required indexes for optimal performance exist
        """
        index_queries = [
            """
            CREATE INDEX IF NOT EXISTS idx_meal_plans_meal_plan_id 
            ON meal_plans(meal_plan_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_meal_plans_user_id 
            ON meal_plans(user_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_meal_plans_chefid 
            ON meal_plans(chefid)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_meal_plan_meals_plan_meal 
            ON meal_plan_meals(meal_plan_id, meal_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_meal_plan_meals_meal 
            ON meal_plan_meals(meal_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_meals_meal_id 
            ON meals(meal_id)
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_subscriptions_user_status 
            ON subscriptions(user_id, status)
            """
        ]
        
        for query in index_queries:
            try:
                await conn.execute(query)
            except Exception as e:
                print(f"Error creating index: {str(e)}")

    async def get_subscription_plans(self, conn: asyncpg.Connection, include_inactive: bool = False) -> List[Dict[str, Any]]:
        """
        Get all available subscription plans
        
        Args:
            conn: Database connection
            include_inactive: Whether to include inactive plans
            
        Returns:
            List of subscription plans
        """
        print(f"🔍 [PLAN SERVICE] Fetching {'all' if include_inactive else 'active'} subscription plans")
        query = """
        SELECT id, name, description, price, billing_cycle, features, is_active, created_at, updated_at
        FROM plans
        """
        params = []
        if not include_inactive:
            query += " WHERE is_active = $1"
            params.append(True)
            
        query += " ORDER BY price ASC"
        
        try:
            rows = await conn.fetch(query, *params)
            print(f"✅ [PLAN SERVICE] Successfully retrieved {len(rows)} plans")
            
            # Convert rows to dict and ensure price is float
            result = []
            for row in rows:
                plan_dict = dict(row)
                # Convert price to float if it's a string
                if isinstance(plan_dict.get('price'), str):
                    try:
                        plan_dict['price'] = float(plan_dict['price'])
                    except (ValueError, TypeError):
                        plan_dict['price'] = 0.0
                result.append(plan_dict)
                
            return result
        except Exception as e:
            print(f"❌ [PLAN SERVICE] Failed to fetch plans: {str(e)}")
            raise

    async def get_plan_by_id(self, conn: asyncpg.Connection, plan_id: int) -> Optional[Dict[str, Any]]:
        """
        Get a specific subscription plan by ID
        
        Args:
            conn: Database connection
            plan_id: ID of the plan to retrieve
            
        Returns:
            Plan details or None if not found
        """
        print(f"🔍 [PLAN SERVICE] Fetching plan with ID: {plan_id}")
        query = """
        SELECT id, name, description, price, billing_cycle, features, is_active, created_at, updated_at
        FROM plans 
        WHERE id = $1
        """
        try:
            row = await conn.fetchrow(query, plan_id)
            if row:
                plan_data = dict(row)
                # Ensure price is float
                if isinstance(plan_data.get('price'), str):
                    try:
                        plan_data['price'] = float(plan_data['price'])
                    except (ValueError, TypeError):
                        plan_data['price'] = 0.0
                
                print(f"✅ [PLAN SERVICE] Found plan: {plan_data.get('name')} (ID: {plan_id})")
                print(f"   - Active: {plan_data.get('is_active')}, Price: {plan_data.get('price')}, Billing: {plan_data.get('billing_cycle')}")
                return plan_data
            else:
                print(f"⚠️ [PLAN SERVICE] Plan not found with ID: {plan_id}")
                return None
        except Exception as e:
            print(f"❌ [PLAN SERVICE] Error fetching plan {plan_id}: {str(e)}")
            raise
        
    async def create_plan(self, conn: asyncpg.Connection, plan_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a new subscription plan
        
        Args:
            conn: Database connection
            plan_data: Dictionary containing plan details
            
        Returns:
            Created plan details
            
        Raises:
            HTTPException: If plan creation fails
        """
        print("\n📝 [PLAN SERVICE] Starting plan creation")
        print(f"📋 Plan data received: {json.dumps(plan_data, indent=2, default=str)}")
        
        query = """
        INSERT INTO plans (name, description, price, billing_cycle, features, is_active)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, name, description, price, billing_cycle, features, is_active,
                  created_at, updated_at
        """
        try:
            # Get the billing cycle value, handling both enum and string cases
            billing_cycle = (
                plan_data["billing_cycle"].value 
                if hasattr(plan_data["billing_cycle"], "value") 
                else plan_data["billing_cycle"]
            )
            
            # Get features list, defaulting to empty list if not provided
            features = plan_data.get("features", [])
            features_json = json.dumps(features)  # Convert list to JSON string
            
            print(f"🔧 [PLAN SERVICE] Processed data:")
            print(f"   - Name: {plan_data.get('name')}")
            print(f"   - Price: {plan_data.get('price')}")
            print(f"   - Billing Cycle: {billing_cycle}")
            print(f"   - Features ({len(features)}): {features}")
            print(f"   - Active: {plan_data.get('is_active', True)}")
            
            # Execute the query with explicit JSONB conversion
            print("💾 [PLAN SERVICE] Saving plan to database...")
            row = await conn.fetchrow(
                query,
                plan_data["name"],
                plan_data.get("description", ""),
                plan_data["price"],
                billing_cycle,
                features_json,  # Use the JSON string directly
                plan_data.get("is_active", True)
            )
            
            if row:
                created_plan = dict(row)
                print(f"✅ [PLAN SERVICE] Successfully created plan: {created_plan.get('name')} (ID: {created_plan.get('id')})")
                return created_plan
            else:
                print("❌ [PLAN SERVICE] Failed to create plan: No data returned from database")
                return None
        except asyncpg.UniqueViolationError:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="A plan with this name already exists"
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to create plan: {str(e)}"
            )
            
    async def update_plan(
        self, 
        conn: asyncpg.Connection, 
        plan_id: int, 
        updates: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """
        Update an existing subscription plan
        
        Args:
            conn: Database connection
            plan_id: ID of the plan to update
            updates: Dictionary containing fields to update
            
        Returns:
            Updated plan details or None if not found
        """
        print(f"\n✏️ [PLAN SERVICE] Starting update for plan ID: {plan_id}")
        print(f"📋 Update data received: {json.dumps(updates, indent=2, default=str)}")
        
        # Get existing plan to ensure it exists
        existing = await self.get_plan_by_id(conn, plan_id)
        if not existing:
            print(f"❌ [PLAN SERVICE] Update failed: Plan ID {plan_id} not found")
            return None
            
        print(f"🔍 [PLAN SERVICE] Current plan data: {json.dumps(existing, indent=2, default=str)}")
        
        # Build dynamic update query
        set_clauses = []
        params = []
        param_count = 1
        
        fields = {
            "name": "name",
            "description": "description",
            "price": "price",
            "billing_cycle": "billing_cycle",
            "features": "features",
            "is_active": "is_active",
        }
        
        print("🔄 [PLAN SERVICE] Processing updates:")
        for field, db_field in fields.items():
            if field in updates:
                value = updates[field]
                original_value = existing.get(field)
                
                if field == 'billing_cycle' and hasattr(value, 'value'):
                    value = value.value
                elif field == 'features':
                    value = json.dumps(value)  # Convert list to JSON string
                    print(f"   - Updating features: {len(updates['features'])} items")
                
                print(f"   - {field}: {original_value} → {value}")
                set_clauses.append(f"{db_field} = ${param_count}")
                params.append(value)
                param_count += 1
        
        if not set_clauses:
            print("ℹ️ [PLAN SERVICE] No valid fields to update")
            return existing
            
        # Add updated_at timestamp
        set_clauses.append("updated_at = NOW()")
        
        query = f"""
        UPDATE plans
        SET {', '.join(set_clauses)}
        WHERE id = ${param_count}
        RETURNING id, name, description, price, billing_cycle, features, is_active,
                  created_at, updated_at
        """
        params.append(plan_id)
        
        try:
            print("💾 [PLAN SERVICE] Saving updated plan to database...")
            row = await conn.fetchrow(query, *params)
            
            if row:
                updated_plan = dict(row)
                print(f"✅ [PLAN SERVICE] Successfully updated plan: {updated_plan.get('name')} (ID: {plan_id})")
                return updated_plan
            else:
                print(f"❌ [PLAN SERVICE] Update failed for plan ID {plan_id}: No data returned")
                return None
                
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to update plan: {str(e)}"
            )
            
    async def delete_plan(self, conn: asyncpg.Connection, plan_id: int) -> bool:
        """
        Delete a subscription plan
        
        Args:
            conn: Database connection
            plan_id: ID of the plan to delete
            
        Returns:
            bool: True if the plan was deleted, False if not found
        """
        print(f"\n🗑️ [PLAN SERVICE] Attempting to delete plan ID: {plan_id}")
        
        # First get the plan details for logging
        existing = await self.get_plan_by_id(conn, plan_id)
        if not existing:
            print(f"⚠️ [PLAN SERVICE] Delete failed: Plan ID {plan_id} not found")
            return False
        if result > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete plan with active subscriptions"
            )
            
        # Soft delete by marking as inactive
        query = """
        UPDATE plans
        SET is_active = FALSE, updated_at = NOW()
        WHERE id = $1
        RETURNING id
        """
        result = await conn.execute(query, plan_id)
        return result != "DELETE 0"

    async def get_user_subscription(self, conn: asyncpg.Connection, user_id: int) -> Optional[Dict[str, Any]]:
        """Get a user's active subscription"""
        query = """
        SELECT s.*, p.name as plan_name, p.price, p.billing_cycle
        FROM subscriptions s
        JOIN plans p ON s.plan_id = p.id
        WHERE s.user_id = $1 
        AND s.status = 'active'
        AND (s.end_date > NOW())
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
        """
        Create a new subscription for a user
        
        Args:
            conn: Database connection
            user_id: ID of the user subscribing
            plan_id: ID of the plan to subscribe to
            payment_transaction_id: Optional payment transaction ID
            
        Returns:
            Dict containing the created subscription
            
        Raises:
            HTTPException: If plan not found or user already has an active subscription
        """
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

        # Calculate start and end dates based on billing cycle
        now = datetime.utcnow()
        if plan['billing_cycle'] == BillingCycle.MONTHLY:
            end_date = now + timedelta(days=30)
        elif plan['billing_cycle'] == BillingCycle.BI_WEEKLY:
            end_date = now + timedelta(days=14)
        else:  # YEARLY
            end_date = now + timedelta(days=365)

        # Create new subscription
        query = """
        INSERT INTO subscriptions (
            user_id, plan_id, start_date, end_date, status
        )
        VALUES ($1, $2, $3, $4, $5)
        RETURNING *
        """
        
        row = await conn.fetchrow(
            query,
            user_id,
            plan_id,
            now,
            end_date,
            SubscriptionStatus.ACTIVE.value
        )
        
        return dict(row) if row else None

    async def cancel_subscription(self, conn: asyncpg.Connection, user_id: int) -> bool:
        """
        Cancel a user's active subscription
        
        Args:
            conn: Database connection
            user_id: ID of the user whose subscription to cancel
            
        Returns:
            bool: True if subscription was cancelled, False if no active subscription found
        """
        query = """
        UPDATE subscriptions
        SET status = $1
        WHERE user_id = $2 
        AND status = $3
        AND end_date > NOW()
        RETURNING subscription_id
        """
        result = await conn.execute(
            query,
            SubscriptionStatus.CANCELED.value,
            user_id,
            SubscriptionStatus.ACTIVE.value
        )
        return bool(await conn.fetchval("SELECT row_count"))

    async def get_subscription_status(self, conn: asyncpg.Connection, user_id: int) -> Dict[str, Any]:
        """
        Get the current subscription status for a user
        
        Args:
            conn: Database connection
            user_id: ID of the user to check status for
            
        Returns:
            Dict containing subscription status information
        """
        subscription = await self.get_user_subscription(conn, user_id)
        if not subscription:
            return PlanStatusResponse(has_active_plan=False).dict()

        # Calculate days remaining
        days_remaining = 0
        if subscription['end_date']:
            end_date = subscription['end_date'].replace(tzinfo=None) if hasattr(subscription['end_date'], 'replace') else subscription['end_date']
            days_remaining = (end_date - datetime.utcnow()).days
            days_remaining = max(0, days_remaining)

        # Prepare response
        response = PlanStatusResponse(
            has_active_plan=True,
            current_plan={
                'id': subscription['subscription_id'],  # Using subscription_id as id for backward compatibility
                'subscription_id': subscription['subscription_id'],
                'plan_id': subscription['plan_id'],
                'plan_name': subscription.get('plan_name'),
                'price': subscription.get('price'),
                'billing_cycle': subscription.get('billing_cycle'),
                'start_date': subscription['start_date'],
                'end_date': subscription['end_date'],
                'status': subscription['status']
            },
            days_remaining=days_remaining,
            is_trial=False
        )
        
        return response.dict()

    async def create_meal_plan(
        self,
        conn: asyncpg.Connection,
        meal_plan_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Create a new meal plan with associated meals
        
        Args:
            conn: Database connection
            meal_plan_data: Dictionary containing meal plan data
                - user_id: int
                - chefid: int
                - subscription_id: int
                - name: str
                - start_date: datetime
                - end_date: datetime
                - meals: List[Dict[meal_id: str, quantity: int]]
                
        Returns:
            Dict containing the created meal plan with associated meals
            
        Raises:
            HTTPException: If validation fails or database error occurs
        """
        import time
        start_time = time.time()
        logger.info("Starting meal plan creation...")
        # Validate input data
        try:
            meal_plan = MealPlanCreate(**meal_plan_data)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid meal plan data: {str(e)}"
            )
            
        # Check if subscription exists and belongs to user
        sub_query = """
        SELECT 1 FROM subscriptions 
        WHERE subscription_id = $1 AND user_id = $2 AND status = 'active'
        """
        sub_exists = await conn.fetchval(sub_query, meal_plan.subscription_id, meal_plan.user_id)
        if not sub_exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Active subscription not found"
            )
            
        # Check if chef exists
        chef_query = "SELECT 1 FROM chefs WHERE chefid = $1"
        chef_exists = await conn.fetchval(chef_query, meal_plan.chefid)
        if not chef_exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Chef not found"
            )
            
        # Start transaction
        async with conn.transaction():
            # Create the meal plan
            query = """
            INSERT INTO meal_plans (user_id, chefid, subscription_id, name, start_date, end_date)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING meal_plan_id, user_id, chefid, subscription_id, name, start_date, end_date, created_at
            """
            
            try:
                db_start_time = time.time()
                meal_plan_result = await conn.fetchrow(
                    query,
                    meal_plan.user_id,
                    meal_plan.chefid,
                    meal_plan.subscription_id,
                    meal_plan.name,
                    meal_plan.start_date,
                    meal_plan.end_date
                )
                db_duration = (time.time() - db_start_time) * 1000  # Convert to milliseconds
                logger.info(f"Meal plan created in {db_duration:.2f}ms - ID: {meal_plan_result['meal_plan_id']}")
                
                # Add meals to the meal plan
                if meal_plan.meals:
                    add_meals_start = time.time()
                    await self._add_meals_to_plan(conn, meal_plan_result['meal_plan_id'], meal_plan.meals)
                    add_meals_duration = (time.time() - add_meals_start) * 1000
                    logger.info(f"Added {len(meal_plan.meals)} meals to plan in {add_meals_duration:.2f}ms")
                
                # Get the full meal plan with meals
                get_plan_start = time.time()
                result = await self.get_meal_plan(conn, meal_plan_result['meal_plan_id'])
                get_plan_duration = (time.time() - get_plan_start) * 1000
                
                total_duration = (time.time() - start_time) * 1000
                logger.info(
                    f"Meal plan creation completed in {total_duration:.2f}ms | "
                    f"Meals: {len(meal_plan.meals)} | "
                    f"DB: {db_duration:.2f}ms | "
                    f"Get Plan: {get_plan_duration:.2f}ms"
                )
                return result
                
            except Exception as e:
                logger.error(f"Error creating meal plan: {e}", exc_info=True)
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Failed to create meal plan"
                )
    
    async def _add_meals_to_plan(
        self,
        conn: asyncpg.Connection,
        meal_plan_id: int,
        meals: List[Dict[str, Any]]
    ) -> None:
        """
        Add meals to a meal plan with performance logging.
        
        Note: Meal existence validation is handled by the database foreign key constraint
        (fk_meal_plan_meals_meals). Do NOT add explicit meal existence checks as they
        would degrade performance. The database will raise a ForeignKeyViolationError
        if any meal doesn't exist.
        
        Args:
            conn: Database connection
            meal_plan_id: ID of the meal plan
            meals: List of meal dictionaries with meal_id and quantity
            
        Raises:
            HTTPException: If any meal is not found or other database error occurs
        """
        import time
        start_time = time.time()
        
        if not meals:
            logger.info("No meals to add, skipping...")
            return
            
        # Prepare arrays for bulk insert
        meal_ids = [meal['meal_id'] for meal in meals]
        quantities = [meal.get('quantity', 1) for meal in meals]
        
        # Log meal IDs being processed (first 5 for brevity)
        sample_meals = ", ".join(meal_ids[:5])
        if len(meal_ids) > 5:
            sample_meals += f" and {len(meal_ids) - 5} more"
        logger.info(f"Adding {len(meal_ids)} meals to plan {meal_plan_id}: {sample_meals}")
        
        # Single query with unnest for bulk insert/update
        # Note: The database's foreign key constraint (fk_meal_plan_meals_meals)
        # will automatically validate that all meal_ids exist in the meals table
        query = """
        INSERT INTO meal_plan_meals (meal_plan_id, meal_id, quantity)
        SELECT $1, m.meal_id, m.quantity
        FROM unnest($2::varchar[], $3::int[]) AS m(meal_id, quantity)
        ON CONFLICT (meal_plan_id, meal_id) 
        DO UPDATE SET quantity = EXCLUDED.quantity
        """
        
        # Execute the bulk insert/update
        try:
            db_start = time.time()
            await conn.execute(query, meal_plan_id, meal_ids, quantities)
            db_duration = (time.time() - db_start) * 1000
            total_duration = (time.time() - start_time) * 1000
            
            logger.info(
                f"Successfully processed {len(meal_ids)} meals for plan {meal_plan_id} | "
                f"Total time: {total_duration:.2f}ms | "
                f"DB operation: {db_duration:.2f}ms"
            )
            
        except asyncpg.ForeignKeyViolationError as e:
            logger.error(f"Failed to add meals - invalid meal ID: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="One or more specified meals do not exist"
            )
            
        except Exception as e:
            logger.error(f"Error adding meals to plan {meal_plan_id}: {str(e)}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to add meals to plan: {str(e)}"
            )
    
    async def get_meal_plan(
        self,
        conn: asyncpg.Connection,
        meal_plan_id: int
    ) -> Dict[str, Any]:
        """
        Get a meal plan by ID with associated meals using a single optimized query
        
        Args:
            conn: Database connection
            meal_plan_id: ID of the meal plan to retrieve
            
        Returns:
            Dictionary containing the meal plan with associated meals
            
        Raises:
            HTTPException: If meal plan not found
        """
        # Single query to get meal plan with associated meals
        query = """
        WITH meal_plan_data AS (
            SELECT 
                mp.*,
                u.name as user_name,
                u.phone_number as user_phone,
                (
                    SELECT json_agg(
                        json_build_object(
                            'meal_id', m.meal_id,
                            'name', m.meal_name,
                            'image_url', m.image_link,
                            'quantity', mpm.quantity
                        )
                    )
                    FROM meal_plan_meals mpm
                    JOIN meals m ON mpm.meal_id = m.meal_id
                    WHERE mpm.meal_plan_id = mp.meal_plan_id
                ) as meals
            FROM meal_plans mp
            JOIN users u ON mp.user_id = u.user_id
            WHERE mp.meal_plan_id = $1
            GROUP BY mp.meal_plan_id, u.user_id
        )
        SELECT 
            m.*,
            COALESCE(m.meals, '[]'::json) as meals
        FROM meal_plan_data m
        """
        
        meal_plan = await conn.fetchrow(query, meal_plan_id)
        
        if not meal_plan:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Meal plan not found"
            )
        
        # Convert to dict and handle the JSON meals
        response = dict(meal_plan)
        # The meals are already in the correct format from the query
        return response
        
    async def get_chef_meal_plans(
        self,
        conn: asyncpg.Connection,
        chef_id: int
    ) -> List[Dict[str, Any]]:
        """
        Get all meal plans assigned to a chef
        
        Args:
            conn: Database connection
            chef_id: ID of the chef
            
        Returns:
            List of meal plans with associated meals and user information
        """
        # Get meal plans for chef
        query = """
        SELECT 
            mp.meal_plan_id as id,
            mp.name as plan_name,
            mp.start_date,
            mp.end_date,
            mp.created_at,
            u.user_id,
            u.name as user_name,
            u.phone as user_phone,
            u.email as user_email,
            jsonb_agg(
                jsonb_build_object(
                    'meal_id', m.meal_id,
                    'name', m.name,
                    'image_url', m.image_url,
                    'quantity', mpm.quantity
                )
            ) as meals
        FROM meal_plans mp
        JOIN users u ON mp.user_id = u.user_id
        LEFT JOIN meal_plan_meals mpm ON mp.meal_plan_id = mpm.meal_plan_id
        LEFT JOIN meals m ON mpm.meal_id = m.meal_id
        WHERE mp.chefid = $1
        GROUP BY mp.meal_plan_id, u.user_id, u.name, u.phone, u.email
        ORDER BY mp.start_date DESC, mp.created_at DESC
        """
        
        rows = await conn.fetch(query, chef_id)
        
        # Process results
        result = []
        for row in rows:
            plan = dict(row)
            # Convert JSONB to Python list
            plan['meals'] = row['meals'] or []
            result.append(plan)
            
        return result
        
    async def get_user_meal_plans(
        self,
        conn: asyncpg.Connection,
        user_id: int
    ) -> List[Dict[str, Any]]:
        """
        Get all meal plans for a user
        
        Args:
            conn: Database connection
            user_id: ID of the user
            
        Returns:
            List of the user's meal plans with associated meals and chef information
        """
        # Get user's meal plans
        query = """
        SELECT 
            mp.meal_plan_id as id,
            mp.name as plan_name,
            mp.start_date,
            mp.end_date,
            mp.created_at,
            c.chefid,
            c.first_name as chef_name,
            c.profile_picture_url as chef_image,
            jsonb_agg(
                jsonb_build_object(
                    'meal_id', m.meal_id,
                    'name', m.name,
                    'image_url', m.image_url,
                    'quantity', mpm.quantity
                )
            ) as meals
        FROM meal_plans mp
        JOIN chefs c ON mp.chefid = c.chefid
        LEFT JOIN meal_plan_meals mpm ON mp.meal_plan_id = mpm.meal_plan_id
        LEFT JOIN meals m ON mpm.meal_id = m.meal_id
        WHERE mp.user_id = $1
        GROUP BY mp.meal_plan_id, c.chefid, c.first_name, c.profile_picture_url
        ORDER BY mp.start_date DESC, mp.created_at DESC
        """
        
        rows = await conn.fetch(query, user_id)
        
        # Process results
        result = []
        for row in rows:
            plan = dict(row)
            # Convert JSONB to Python list
            plan['meals'] = row['meals'] or []
            result.append(plan)
            
        return result
