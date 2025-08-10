import asyncpg
import asyncio
import os
from dotenv import load_dotenv

async def get_table_schema():
    load_dotenv()
    
    # Get database connection details from environment variables
    db_url = os.getenv("DATABASE_URL")
    
    # If DATABASE_URL is not set, construct it from individual variables
    if not db_url:
        db_user = os.getenv("DB_USER")
        db_password = os.getenv("DB_PASSWORD")
        db_host = os.getenv("DB_HOST")
        db_name = os.getenv("DB_NAME")
        db_url = f"postgresql://{db_user}:{db_password}@{db_host}/{db_name}"
    
    conn = await asyncpg.connect(db_url)
    
    try:
        # Get table columns and their properties
        query = """
        SELECT 
            column_name, 
            data_type, 
            is_nullable,
            column_default
        FROM information_schema.columns 
        WHERE table_name = 'subscriptions'
        ORDER BY ordinal_position;
        """
        
        rows = await conn.fetch(query)
        
        print("\n=== Subscriptions Table Schema ===")
        print(f"{'Column Name':<25} | {'Data Type':<20} | {'Nullable':<10} | {'Default'}")
        print("-" * 70)
        
        for row in rows:
            print(f"{row['column_name']:<25} | {row['data_type']:<20} | {row['is_nullable']:<10} | {row['column_default']}")
        
        # Check constraints
        print("\n=== Constraints ===")
        constraints = await conn.fetch("""
        SELECT conname, pg_get_constraintdef(oid)
        FROM pg_constraint 
        WHERE conrelid = 'public.subscriptions'::regclass;
        """)
        
        for con in constraints:
            print(f"{con['conname']}: {con['pg_get_constraintdef']}")
        
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.get_event_loop().run_until_complete(get_table_schema())
