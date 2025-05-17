# run_migration_fix.py - Script to apply the user_type column migration

import os
import sys
from dotenv import load_dotenv
import psycopg2

load_dotenv()

def get_db_connection():
    """Establishes a connection using Supabase's pooled endpoint."""
    db_host = os.getenv("DB_POOLER_HOST")
    db_port = os.getenv("DB_POOLER_PORT", "6543")
    db_name = os.getenv("DB_NAME", "postgres")
    db_user = os.getenv("DB_USER", "postgres.your_project_id")
    db_password = os.getenv("DB_PASSWORD")

    if not all([db_host, db_port, db_name, db_user, db_password]):
        print("Error: Database POOLED connection details missing.")
        print("Please set DB_POOLER_HOST, DB_POOLER_PORT, DB_NAME, DB_USER, and DB_PASSWORD environment variables.")
        return None

    try:
        connection = psycopg2.connect(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password,
            sslmode='require'
        )
        return connection
    except psycopg2.Error as e:
        print(f"Database Error: {e}")
        return None

def apply_user_id_migration():
    """Apply the migration to change user_id from UUID to integer in fcm_tokens table."""
    connection = get_db_connection()
    if not connection:
        print("Failed to connect to database. Migration aborted.")
        return False

    try:
        with connection.cursor() as cursor:
            # Execute the user_id type change migration
            # Use absolute path to the migration file
            migration_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'database_migrations', '20250515_change_user_id_to_integer.sql')
            with open(migration_path, 'r') as file:
                sql = file.read()
                cursor.execute(sql)
                print("Changed user_id column type from UUID to integer in fcm_tokens table")
        
        connection.commit()
        print("Migration completed successfully!")
        return True
    except Exception as e:
        print(f"Error applying migration: {e}")
        connection.rollback()
        return False
    finally:
        connection.close()

if __name__ == "__main__":
    print("Starting migration to change user_id from UUID to integer in fcm_tokens table...")
    success = apply_user_id_migration()
    if success:
        print("✅ Migration completed successfully. The FCM token registration now uses integer user IDs instead of UUIDs.")
        sys.exit(0)
    else:
        print("❌ Migration failed. Please check the error messages above.")
        sys.exit(1)