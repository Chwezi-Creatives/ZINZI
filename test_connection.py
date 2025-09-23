import asyncio
import asyncpg
import os
from dotenv import load_dotenv

async def test_connection():
    # Load environment variables
    load_dotenv()
    
    # Database connection settings
    db_config = {
        'host': os.getenv('DB_HOST', 'localhost'),
        'port': os.getenv('DB_PORT', '5432'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME'),
        'ssl': os.getenv('DB_SSL', 'prefer'),
        'statement_cache_size': 0
    }
    
    # Filter out None values
    db_config = {k: v for k, v in db_config.items() if v is not None}
    
    try:
        # Try to connect to the database
        conn = await asyncpg.connect(**db_config)
        print("Successfully connected to the database!")
        
        # Test a simple query
        version = await conn.fetchval('SELECT version()')
        print(f"Database version: {version}")
        
        # Check if users table exists
        table_exists = await conn.fetchval(
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users')"
        )
        print(f"Users table exists: {table_exists}")
        
        await conn.close()
        
    except Exception as e:
        print(f"Error connecting to the database: {e}")
        # Print the actual connection string (without password) for debugging
        safe_config = db_config.copy()
        if 'password' in safe_config:
            safe_config['password'] = '***'
        print(f"Connection config: {safe_config}")

if __name__ == "__main__":
    asyncio.run(test_connection())
