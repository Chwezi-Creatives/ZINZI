import asyncio
import asyncpg
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Database connection settings
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME'),
    'ssl': os.getenv('DB_SSL', 'prefer')
}

async def main():
    db_config = {k: v for k, v in DB_CONFIG.items() if v is not None}
    try:
        print("Attempting to connect to the database...")
        conn = await asyncpg.connect(**db_config)
        await conn.close()
        print("✅ Successfully connected to the database!")
    except Exception as e:
        print(f"❌ Failed to connect to the database: {e}")

if __name__ == "__main__":
    asyncio.run(main())
