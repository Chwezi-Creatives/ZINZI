import asyncpg
import asyncio
import os
from pathlib import Path
from dotenv import load_dotenv

async def apply_migration():
    # Load environment variables
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
    
    # Connect to the database
    conn = await asyncpg.connect(db_url)
    
    try:
        # Start a transaction
        async with conn.transaction():
            print("🔄 Starting migration: Adding payment_transaction_id to subscriptions table")
            
            # Read the migration SQL file
            migration_path = Path(__file__).parent / "database_migrations" / "20250809_add_payment_transaction_id.sql"
            with open(migration_path, 'r') as f:
                migration_sql = f.read()
            
            # Execute the migration
            await conn.execute(migration_sql)
            
            print("✅ Migration applied successfully!")
            
            # Verify the column was added
            columns = await conn.fetch("""
                SELECT column_name, data_type, is_nullable
                FROM information_schema.columns 
                WHERE table_name = 'subscriptions' 
                AND column_name = 'payment_transaction_id';
            """)
            
            if columns:
                col = columns[0]
                print(f"\n✅ Column 'payment_transaction_id' exists in subscriptions table")
                print(f"   - Data Type: {col['data_type']}")
                print(f"   - Nullable: {col['is_nullable']}")
            else:
                print("\n❌ Failed to verify column creation. Please check the database manually.")
                
    except Exception as e:
        print(f"\n❌ Error applying migration: {str(e)}")
        raise
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(apply_migration())
