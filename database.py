# database.py - Using Supabase PgBouncer (NO client-side pool needed)

import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

def get_db_connection():
    """Establishes a connection using Supabase's pooled endpoint."""

    # Ensure these env vars point to the PgBouncer settings (port 6543 usually)
    db_host = os.getenv("DB_POOLER_HOST") # e.g., aws-0-us-west-1.pooler.supabase.com
    db_port = os.getenv("DB_POOLER_PORT", "6543") # <-- Use the pooler port
    db_name = os.getenv("DB_NAME", "postgres")
    db_user = os.getenv("DB_USER", "postgres.your_project_id") # <-- Pooler often needs project ID in username
    db_password = os.getenv("DB_PASSWORD")

    if not all([db_host, db_port, db_name, db_user, db_password]):
        print("Error: Database POOLED connection details missing.")
        print("Please set DB_POOLER_HOST, DB_POOLER_PORT, DB_NAME, DB_USER, and DB_PASSWORD environment variables.")
        return None

    try:
        # Connect directly, PgBouncer handles the pooling server-side
        connection = psycopg2.connect(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password,
            sslmode='require'
        )
        # print("Database connection via pooler successful!")
        return connection
    except psycopg2.OperationalError as e:
        print(f"Error connecting to the database pooler: {e}")
        # Add specific troubleshooting for pooler connection if needed
        return None
    except psycopg2.Error as e:
        print(f"Database Error via pooler: {e}")
        return None
    except Exception as e:
        print(f"An unexpected error occurred connecting via pooler: {e}")
        return None

# --- How calling code would use it ---
# import database as db
#
# connection = None
# try:
#     connection = db.get_db_connection() # Still gets a single connection object
#     if connection:
#         cursor = connection.cursor()
#         cursor.execute("SELECT version();")
#         print(cursor.fetchone())
#         cursor.close()
#         connection.commit()
# finally:
#     if connection:
#         connection.close() # CRITICAL: Still need to close the connection object
#                            # This signals PgBouncer it can be reused.