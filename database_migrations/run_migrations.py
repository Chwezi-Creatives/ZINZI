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

def run_sql_file(sql_file_path):
    """Executes a SQL file and rolls back on error."""
    connection = get_db_connection()
    if not connection:
        return

    try:
        with connection.cursor() as cursor:
            # Read and execute the SQL file
            with open(sql_file_path, 'r') as file:
                sql = file.read()
                cursor.execute(sql)
        
        connection.commit()
        print(f"Successfully executed SQL from {sql_file_path}")

    except Exception as e:
        print(f"Error executing SQL from {sql_file_path}: {e}")
        # Automatically roll back any changes made during the transaction
        connection.rollback()
        print("Changes have been rolled back due to an error.")
        
    finally:
        connection.close()
        print("Database connection closed.")

if __name__ == "__main__":
    sql_file_to_run = 'notifications.sql'
    run_sql_file(sql_file_to_run)