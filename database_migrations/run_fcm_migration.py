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
        print("Error: Database connection details missing.")
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

def run_fcm_migration():
    """Run the FCM tokens migration."""
    connection = get_db_connection()
    if not connection:
        return False

    try:
        with connection.cursor() as cursor:
            # Read and execute the SQL file
            with open('20250731031800_add_app_version_to_fcm_tokens.sql', 'r') as file:
                sql = file.read()
                cursor.execute(sql)
        
        connection.commit()
        print("FCM migration completed successfully!")
        return True
    except Exception as e:
        print(f"Error running FCM migration: {e}")
        connection.rollback()
        return False
    finally:
        if connection:
            connection.close()

if __name__ == "__main__":
    success = run_fcm_migration()
    if not success:
        print("FCM migration failed. Please check the error message above.")
        exit(1)
