import asyncio
import asyncpg
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

async def check_schema():
    # Database connection settings
    db_config = {
        'host': os.getenv('DB_HOST', 'localhost'),
        'port': os.getenv('DB_PORT', '5432'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME'),
        'ssl': os.getenv('DB_SSL', 'prefer')
    }
    
    # Filter out None values
    db_config = {k: v for k, v in db_config.items() if v is not None}
    
    # Connect to the database
    conn = await asyncpg.connect(**db_config)
    
    try:
        # Get the list of tables
        tables = await conn.fetch("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            ORDER BY table_name;
        """)
        
        print("\n=== Database Tables ===")
        for table in tables:
            print(f"\nTable: {table['table_name']}")
            print("-" * 50)
            
            # Get column information
            columns = await conn.fetch("""
                SELECT column_name, data_type, is_nullable, column_default
                FROM information_schema.columns
                WHERE table_name = $1
                ORDER BY ordinal_position;
            """, table['table_name'])
            
            for col in columns:
                print(f"{col['column_name']}: {col['data_type']} "
                      f"{'NULL' if col['is_nullable'] == 'YES' else 'NOT NULL'} "
                      f"{f'DEFAULT {col['column_default']}' if col['column_default'] else ''}")
            
            # Get primary key information
            pks = await conn.fetch("""
                SELECT kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_name = $1 AND tc.constraint_type = 'PRIMARY KEY';
            """, table['table_name'])
            
            if pks:
                print("\nPrimary Key(s):", ", ".join(pk['column_name'] for pk in pks))
            
            # Get foreign key information
            fks = await conn.fetch("""
                SELECT
                    kcu.column_name,
                    ccu.table_name AS foreign_table_name,
                    ccu.column_name AS foreign_column_name
                FROM information_schema.table_constraints AS tc
                JOIN information_schema.key_column_usage AS kcu
                    ON tc.constraint_name = kcu.constraint_name
                JOIN information_schema.constraint_column_usage AS ccu
                    ON ccu.constraint_name = tc.constraint_name
                WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name = $1;
            """, table['table_name'])
            
            if fks:
                print("\nForeign Keys:")
                for fk in fks:
                    print(f"  {fk['column_name']} -> {fk['foreign_table_name']}({fk['foreign_column_name']})")
            
            print("\n" + "=" * 80 + "\n")
    
    finally:
        await conn.close()

if __name__ == "__main__":
    asyncio.run(check_schema())
