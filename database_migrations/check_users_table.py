import psycopg2
import os
from dotenv import load_dotenv

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

def check_users_table():
    """Check if users table exists and its structure."""
    connection = get_db_connection()
    if not connection:
        return

    try:
        with connection.cursor() as cursor:
            # Check if users table exists
            cursor.execute("""
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                    AND table_name = 'users'
                )
            """)
            exists = cursor.fetchone()[0]
            
            if exists:
                print("Users table exists. Checking structure...")
                
                # Get users table structure
                cursor.execute("""
                    SELECT column_name, data_type
                    FROM information_schema.columns
                    WHERE table_name = 'users'
                    AND column_name = 'id'
                """)
                result = cursor.fetchone()
                
                if result:
                    print(f"Users table has id column of type: {result[1]}")
                else:
                    print("Users table exists but doesn't have an id column")
            else:
                print("Users table does not exist")
                
    except Exception as e:
        print(f"Error checking users table: {e}")
    finally:
        connection.close()

if __name__ == "__main__":
    check_users_table()
