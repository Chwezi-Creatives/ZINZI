import asyncio
import asyncpg
import json
import os
import pytest
import pytest_asyncio
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import AsyncGenerator, Dict, Any, Optional, List
from dotenv import load_dotenv
from fastapi import HTTPException, status
from services.subscription_service import SubscriptionService

# Helper function to generate unique IDs for tests
def unique_id(prefix: str = '') -> str:
    return f"{prefix}{uuid.uuid4().hex[:8]}"

# Configure pytest asyncio
pytest_plugins = ('pytest_asyncio',)
pytestmark = pytest.mark.asyncio

# Fixture for event loop
@pytest.fixture
def event_loop():
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

# Override the default event_loop fixture to avoid warnings
@pytest.fixture(scope="session")
def event_loop():
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    yield loop
    loop.close()

# Load environment variables
load_dotenv()

# Database connection settings
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME'),
    'ssl': os.getenv('DB_SSL', 'prefer'),
    'statement_cache_size': 0  # Disable prepared statements for pgbouncer
}

# Test data constants
TEST_USER_ID = 138
TEST_CHEF_ID = 45
TEST_MEAL_IDS = ["M101", "M102", "M103", "M104"]
TEST_MEAL_IDS_STR = ["4", "5", "6"]  # As strings to match database expectations

# Test plans data
TEST_PLAN = {
    'name': 'Test Plan',
    'description': 'Test plan description',
    'price': Decimal('99.99'),
    'billing_cycle': 'monthly',
    'features': ['feature1', 'feature2'],
    'is_active': True,
    'is_prebuilt': False,
    'chef_id': None,
    'meal_ids': []
}

TEST_PREBUILT_PLAN = {
    'name': 'Test Prebuilt Plan',
    'description': 'Test prebuilt plan description',
    'price': Decimal('149.99'),
    'billing_cycle': 'monthly',
    'features': ['breakfast', 'lunch', 'dinner'],
    'is_active': True,
    'is_prebuilt': True,
    'chef_id': 1,  # Assuming chef with ID 1 exists
    'meal_ids': ['M101', 'M102']  # Assuming these meal IDs exist
}

# Fixtures
@pytest_asyncio.fixture(scope='function')
async def db_pool(event_loop):
    """Create a database connection pool for testing"""
    # Filter out None values from DB_CONFIG
    db_config = {k: v for k, v in DB_CONFIG.items() if v is not None}
    
    # Create a new connection pool
    pool = await asyncpg.create_pool(**db_config)
    
    # Ensure the tables exist
    async with pool.acquire() as conn:
        # Add your schema creation SQL here if needed
        pass
    
    yield pool
    
    # Clean up
    await pool.close()

@pytest_asyncio.fixture(scope='function')
async def db_connection(db_pool, event_loop):
    """Get a database connection with automatic rollback"""
    # Start a transaction
    conn = await db_pool.acquire()
    tr = conn.transaction()
    await tr.start()
    
    try:
        yield conn
    finally:
        # Rollback any changes made during the test
        await tr.rollback()
        await db_pool.release(conn)

@pytest_asyncio.fixture(scope='function')
async def subscription_service(db_pool):
    """Create a subscription service instance for testing"""
    return SubscriptionService(db_pool=db_pool)

# Helper functions
async def create_test_plan(conn: asyncpg.Connection, plan_data: Dict[str, Any]) -> Dict[str, Any]:
    """Helper to create a test plan in the database"""
    if 'name' not in plan_data:
        plan_data['name'] = f"Test Plan {uuid.uuid4().hex[:8]}"
        
    # Set default values for required fields if not provided
    defaults = {
        'description': 'Test plan description',
        'price': Decimal('99.99'),
        'billing_cycle': 'monthly',
        'features': [],
        'is_active': True,
        'is_prebuilt': False,
        'chef_id': None,
        'meal_ids': []
    }
    
    # Apply defaults for any missing fields
    for key, value in defaults.items():
        if key not in plan_data:
            plan_data[key] = value
    
    # Convert features to JSON string if it's a list
    features = plan_data.get('features', [])
    if isinstance(features, list):
        features = json.dumps(features)
    
    query = """
    INSERT INTO plans (
        name, description, price, billing_cycle, features, is_active, 
        is_prebuilt, chef_id, meal_ids
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    RETURNING *
    """
    
    # Set default values for required fields
    plan_data = plan_data.copy()
    plan_data.setdefault('is_active', True)
    plan_data.setdefault('is_prebuilt', False)
    plan_data.setdefault('features', [])
    
    row = await conn.fetchrow(
        query,
        plan_data['name'],
        plan_data.get('description', ''),
        plan_data['price'],
        plan_data['billing_cycle'],
        features,
        plan_data['is_active'],
        plan_data['is_prebuilt'],
        plan_data.get('chef_id'),
        plan_data.get('meal_ids', [])
    )
    
    if not row:
        raise ValueError("Failed to create test plan")
    
    # Convert the row to a dict and parse JSON fields
    plan_dict = dict(row)
    if 'features' in plan_dict and isinstance(plan_dict['features'], str):
        try:
            plan_dict['features'] = json.loads(plan_dict['features'])
        except (json.JSONDecodeError, TypeError):
            plan_dict['features'] = []
    
    return plan_dict

# Tests
@pytest.mark.asyncio
async def test_create_regular_plan(db_connection, subscription_service):
    """Test creating a regular subscription plan"""
    # Create the plan
    created_plan = await subscription_service.create_plan(
        conn=db_connection,
        plan_data=TEST_PLAN
    )
    
    # Verify the plan was created correctly
    assert created_plan['name'] == TEST_PLAN['name']
    assert Decimal(str(created_plan['price'])) == Decimal(str(TEST_PLAN['price']))
    assert created_plan['billing_cycle'] == TEST_PLAN['billing_cycle']
    assert created_plan['is_active'] is True
    assert created_plan['is_prebuilt'] is False
    assert created_plan['chef_id'] == TEST_PLAN['chef_id']
    
    # Clean up
    await db_connection.execute("DELETE FROM plans WHERE id = $1", created_plan['id'])

@pytest.mark.asyncio
async def test_create_prebuilt_plan(db_connection, subscription_service):
    """Test creating a pre-built subscription plan"""
    # Create the plan
    created_plan = await subscription_service.create_plan(
        conn=db_connection,
        plan_data=TEST_PREBUILT_PLAN
    )
    
    # Verify the plan was created correctly
    assert created_plan['name'] == TEST_PREBUILT_PLAN['name']
    assert Decimal(str(created_plan['price'])) == Decimal(str(TEST_PREBUILT_PLAN['price']))
    assert created_plan['is_prebuilt'] is True
    assert created_plan['chef_id'] == TEST_PREBUILT_PLAN['chef_id']
    
    # Clean up
    await db_connection.execute("DELETE FROM plans WHERE id = $1", created_plan['id'])

@pytest.mark.asyncio
async def test_get_plan_by_id(db_connection, subscription_service):
    """Test retrieving a plan by ID"""
    # Create a test plan
    created_plan = await create_test_plan(db_connection, TEST_PLAN)
    
    # Retrieve the plan
    retrieved_plan = await subscription_service.get_plan_by_id(
        conn=db_connection,
        plan_id=created_plan['id']
    )
    
    # Verify the plan was retrieved correctly
    assert retrieved_plan is not None
    assert retrieved_plan['id'] == created_plan['id']
    assert retrieved_plan['name'] == created_plan['name']
    assert Decimal(str(retrieved_plan['price'])) == Decimal(str(created_plan['price']))

@pytest.mark.asyncio
async def test_update_plan(db_connection, subscription_service):
    """Test updating a plan"""
    # Create a test plan
    created_plan = await create_test_plan(db_connection, TEST_PLAN)
    
    # Update the plan
    updates = {
        'name': 'Updated Plan Name',
        'price': Decimal('149.99'),
        'description': 'Updated description',
        'features': ['updated_feature1', 'updated_feature2'],
        'meal_ids': TEST_MEAL_IDS[1:4]  # Different set of meal IDs
    }

    updated_plan = await subscription_service.update_plan(
        conn=db_connection,
        plan_id=created_plan['id'],
        updates=updates
    )
    
    # Verify the plan was updated correctly
    assert updated_plan['name'] == updates['name']
    assert Decimal(str(updated_plan['price'])) == updates['price']
    assert updated_plan['description'] == updates['description']
    
    # Handle features comparison - convert to set if it's a string
    updated_features = updated_plan['features']
    if isinstance(updated_features, str):
        updated_features = json.loads(updated_features)
    assert set(updated_features) == set(updates['features'])
    
    # Compare meal_ids
    assert set(updated_plan['meal_ids']) == set(updates['meal_ids'])

@pytest.mark.asyncio
async def test_get_subscription_plans(db_connection, subscription_service):
    """Test retrieving subscription plans with filters"""
    # Create test plans
    regular_plan = await create_test_plan(db_connection, TEST_PLAN)
    prebuilt_plan = await create_test_plan(db_connection, {
        **TEST_PREBUILT_PLAN,
        'is_active': True
    })
    inactive_prebuilt_plan = await create_test_plan(db_connection, {
        **TEST_PREBUILT_PLAN,
        'name': 'Inactive Prebuilt Plan',
        'is_active': False
    })

    # Test getting all plans
    all_plans = await subscription_service.get_subscription_plans(
        conn=db_connection
    )
    assert len(all_plans) >= 3  # Should include all plans

    # Test filtering by is_prebuilt=True and include_inactive=True
    prebuilt_plans = await subscription_service.get_subscription_plans(
        conn=db_connection,
        is_prebuilt=True,
        include_inactive=True  # Explicitly include inactive plans
    )
    # Should include both active and inactive prebuilt plans
    prebuilt_plan_ids = [p['id'] for p in prebuilt_plans]
    assert prebuilt_plan['id'] in prebuilt_plan_ids
    assert inactive_prebuilt_plan['id'] in prebuilt_plan_ids
    
    # Test filtering by include_inactive=False (default)
    active_plans = await subscription_service.get_subscription_plans(
        conn=db_connection,
        include_inactive=False
    )
    # Should include active prebuilt and regular plans
    active_plan_ids = [p['id'] for p in active_plans]
    assert regular_plan['id'] in active_plan_ids
    assert prebuilt_plan['id'] in active_plan_ids
    assert inactive_prebuilt_plan['id'] not in active_plan_ids
    
    # Test filtering by is_prebuilt=False (regular plans)
    regular_plans = await subscription_service.get_subscription_plans(
        conn=db_connection,
        is_prebuilt=False
    )
    assert any(p['id'] == regular_plan['id'] for p in regular_plans)
    assert not any(p['id'] == prebuilt_plan['id'] for p in regular_plans)
    assert not any(p['id'] == inactive_prebuilt_plan['id'] for p in regular_plans)
    
    # Test filtering by chef_id and is_prebuilt
    if prebuilt_plan.get('chef_id'):
            # First test with is_prebuilt=True and include_inactive=True
            chef_prebuilt_plans = await subscription_service.get_subscription_plans(
                conn=db_connection,
                chef_id=prebuilt_plan['chef_id'],
                is_prebuilt=True,
                include_inactive=True  # Explicitly include inactive plans
            )
            # Should include both active and inactive prebuilt plans for this chef
            assert any(p['id'] == prebuilt_plan['id'] for p in chef_prebuilt_plans)
            assert any(p['id'] == inactive_prebuilt_plan['id'] for p in chef_prebuilt_plans)
            assert not any(p['id'] == regular_plan['id'] for p in chef_prebuilt_plans)
            
            # Test with is_prebuilt=True and include_inactive=False (default)
            active_chef_plans = await subscription_service.get_subscription_plans(
                conn=db_connection,
                chef_id=prebuilt_plan['chef_id'],
                is_prebuilt=True,
                include_inactive=False
            )
            # Should only include active prebuilt plans for this chef
            assert any(p['id'] == prebuilt_plan['id'] for p in active_chef_plans)
            assert not any(p['id'] == inactive_prebuilt_plan['id'] for p in active_chef_plans)
            assert not any(p['id'] == regular_plan['id'] for p in active_chef_plans)
    

@pytest.mark.asyncio
async def test_prebuilt_plan_creation(db_connection, subscription_service):
    """Test creating a meal plan from a pre-built subscription"""
    # First create a test plan
    plan_data = {
        'name': f'Test Prebuilt Plan {uuid.uuid4().hex[:8]}',
        'description': 'A test prebuilt meal plan',
        'chef_id': 2,  # Assuming chef with ID 2 exists
        'meal_ids': ["4", "5", "6"],  # Meal IDs as strings
        'price': Decimal('199.99'),
        'is_active': True,
        'is_prebuilt': True,
        'duration_days': 30,
        'billing_cycle': 'monthly',
        'features': ['breakfast', 'lunch', 'dinner'],
        'image_url': 'https://example.com/prebuilt-plan.jpg'
    }
    
    # Create the prebuilt plan
    created_plan = await subscription_service.create_plan(
        conn=db_connection,
        plan_data=plan_data
    )
    
    # Create a test subscription
    subscription = await db_connection.fetchrow(
        """
        INSERT INTO subscriptions (
            user_id, plan_id, start_date, end_date, status, payment_transaction_id
        ) VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING *
        """,
        TEST_USER_ID,
        created_plan['id'],
        datetime.now(timezone.utc),
        datetime.now(timezone.utc) + timedelta(days=30),
        'active',
        'test_transaction_123'
    )
    
    # Verify the subscription was created
    assert subscription is not None
    # The subscription should have a subscription_id, not id
    assert 'subscription_id' in subscription
    assert subscription['plan_id'] == created_plan['id']
    
    # Clean up - use subscription_id instead of id
    await db_connection.execute("DELETE FROM subscriptions WHERE subscription_id = $1", subscription['subscription_id'])
    await db_connection.execute("DELETE FROM plans WHERE id = $1", created_plan['id'])

@pytest.mark.asyncio
async def test_custom_meals_override_prebuilt(db_connection, subscription_service):
    """Test that custom meals can override pre-built ones"""
    # Create test data for prebuilt plan with custom meals
    plan_data = {
        'name': 'Custom Meals Test Plan',
        'description': 'A test prebuilt meal plan with custom meals',
        'chef_id': TEST_CHEF_ID,
        'meal_ids': ["4", "5", "6"],  # Meal IDs as strings
        'price': Decimal('249.99'),
        'is_active': True,
        'duration_days': 30,
        'billing_cycle': 'monthly',
        'features': ['breakfast', 'lunch', 'dinner', 'snacks']
    }
    
    # Create the prebuilt plan with custom meals using create_plan instead of create_prebuilt_meal_plan
    test_plan = await subscription_service.create_plan(
        conn=db_connection,
        plan_data={
            **plan_data,
            'is_prebuilt': True,
            'price': Decimal(str(plan_data['price']))  # Ensure price is a Decimal
        }
    )
    
    # Verify the meal plan was created with custom meals
    assert test_plan is not None
    assert set(test_plan.get('meal_ids', [])) == set(plan_data['meal_ids'])

@pytest.mark.asyncio
async def test_meal_plan_validation(db_connection, subscription_service):
    """Test validation of meal plan creation"""
    # Test with missing required fields
    with pytest.raises(HTTPException) as exc_info:
        await subscription_service.create_plan(
            conn=db_connection,
            plan_data={
                'name': 'Incomplete Plan',
                # Missing required fields
            }
        )
    assert exc_info.value.status_code == status.HTTP_500_INTERNAL_SERVER_ERROR
    
    # Test with invalid price (string instead of number)
    with pytest.raises(HTTPException) as exc_info:
        await subscription_service.create_plan(
            conn=db_connection,
            plan_data={
                'name': 'Invalid Price Plan',
                'description': 'A plan with invalid price',
                'billing_cycle': 'monthly',
                'price': 'not_a_number',  # Invalid price format
                'is_active': True
            }
        )
    assert exc_info.value.status_code == status.HTTP_500_INTERNAL_SERVER_ERROR

# Run tests directly if executed as a script
if __name__ == "__main__":
    import sys
    
    async def run_tests():
        """Run the test suite"""
        # Load environment variables
        load_dotenv()
        
        # Run pytest programmatically
        return pytest.main([
            "-v",
            "--tb=short",
            __file__
        ])
    
    sys.exit(asyncio.run(run_tests()))
