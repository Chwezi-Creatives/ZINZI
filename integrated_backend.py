# Cspell:disable
from vercel_adapter import VercelAdapter
import os
import json
import random
import string
from datetime import datetime, timedelta, date
from dotenv import load_dotenv
import bcrypt
import psycopg2  # Database driver
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google.auth.exceptions import RefreshError
from email.mime.text import MIMEText
import base64
import paypalrestsdk
import logging
import stripe
import requests
import time
import uuid
from typing import Dict, Any, Optional, List
from flask import Flask, request, jsonify
import logging
# Assuming utils.py exists with this function, if not, define it or remove the import
try:
    from utils import lowercase_keys
except ImportError:
    # Define a simple fallback if utils is missing
    def lowercase_keys(d):
        if isinstance(d, dict):
            return {k.lower(): v for k, v in d.items()}
        return d
    # logger.warning("utils.lowercase_keys not found, using basic fallback.") # Defined below

from flask_cors import CORS

# --- Configuration Loading ---
load_dotenv()  # Load environment variables first

# --- Logging Configuration ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__) # <<< DEFINED LOGGER HERE

# Now we can safely use logger
try:
    from utils import lowercase_keys # Attempt import again now that logger is defined
except ImportError:
    # Define a simple fallback if utils is missing
    def lowercase_keys(d):
        if isinstance(d, dict):
            return {k.lower(): v for k, v in d.items()}
        return d
    logger.warning("utils.lowercase_keys not found, using basic fallback.")


# --- Database Connection Function ---
def get_db_connection():
    db_host = os.getenv("DB_POOLER_HOST")
    db_port = os.getenv("DB_POOLER_PORT", "6543")
    db_name = os.getenv("DB_NAME", "postgres")
    db_user_base = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    supabase_project_id = os.getenv("SUPABASE_PROJECT_ID")
    db_user = db_user_base
    if db_user_base and supabase_project_id and '.' not in db_user_base:
        db_user = f"{db_user_base}.{supabase_project_id}"
        logger.debug(f"Constructed pooler username: {db_user}")
    elif not db_user_base: logger.warning("DB_USER environment variable not set.")
    missing_vars = [var for var, val in locals().items() if var.startswith('db_') and not val and var != 'db_user_base']
    if not db_user: missing_vars.append("DB_USER (or base + SUPABASE_PROJECT_ID)")
    if missing_vars: error_msg = f"Database POOLED connection details missing: {', '.join(missing_vars)}."; logger.critical(error_msg); return None
    try:
        connection = psycopg2.connect(host=db_host, port=db_port, database=db_name, user=db_user, password=db_password, sslmode='require', connect_timeout=10)
        logger.debug("Database connection via pooler successful!")
        return connection
    except psycopg2.OperationalError as e: logger.error(f"Error connecting to pooler ({db_host}:{db_port}): {e}", exc_info=False); return None
    except psycopg2.Error as e: logger.error(f"Database Error connecting via pooler: {e}", exc_info=True); return None
    except Exception as e: logger.error(f"An unexpected error occurred connecting via pooler: {e}", exc_info=True); return None

# --- Helper Functions ---
def hash_password(password): return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
def generate_random_code(length=6, use_digits=True, use_uppercase=True):
    chars = ""
    if use_digits:
        chars += string.digits
    if use_uppercase:
        chars += string.ascii_uppercase
    if not chars:
        raise ValueError("Character set required.")
    return ''.join(random.choices(chars, k=length))

def check_required_fields(data, required_fields):
    data_keys_lower = {k.lower() for k in data.keys()}
    missing = []
    empty = []
    for field in required_fields:
        field_lower = field.lower()
        if field_lower not in data_keys_lower:
            missing.append(field)
        else:
            original_key = next((k for k in data if k.lower() == field_lower), None)
            value = data.get(original_key)
            if value is None or (isinstance(value, str) and not value.strip()):
                empty.append(field)
    error_messages = []
    if missing:
        error_messages.append(f"Missing fields: {', '.join(missing)}")
    if empty:
        error_messages.append(f"Fields cannot be empty: {', '.join(empty)}")
    if error_messages:
        raise ValueError(". ".join(error_messages))

def serialize_list(data_list):
    return ','.join(map(str, data_list)) if isinstance(data_list, list) else ''

def deserialize_list(data_string):
    if not data_string or not isinstance(data_string, str):
        return []
    return [item.strip() for item in data_string.split(',') if item.strip()]

def deserialize_list_from_json_string(json_string):
    if not json_string or not isinstance(json_string, str):
        return []
    try:
        data_list = json.loads(json_string)
        return data_list if isinstance(data_list, list) else []
    except json.JSONDecodeError:
        logger.warning(f"Could not decode JSON: {json_string}. Fallback: comma split.")
        return [item.strip() for item in json_string.split(',') if item.strip()]

import os
import json
import random
import string
from datetime import datetime, timedelta, date
from dotenv import load_dotenv
import bcrypt
import psycopg2 # Database driver
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google.auth.exceptions import RefreshError
from email.mime.text import MIMEText
import base64
import logging
from typing import Dict, Any, Optional, List

# Assuming logger, get_db_connection, hash_password, generate_random_code,
# lowercase_keys, check_required_fields, deserialize_list are defined and imported correctly.

# --- Base Class for Common DB Operations ---
class BaseRepository:
    def _execute_query(self, sql: str, params: Optional[tuple] = None, fetch_one: bool = False, fetch_all: bool = False, commit: bool = False, returning_id_column: Optional[str] = None) -> Any:
        """Executes SQL query with error handling, connection management, and flexible fetching."""
        conn = None # Initialize connection to None
        results = None
        returned_id = None
        try:
            conn = get_db_connection()
            if not conn:
                # Use a specific, informative error for connection failures
                raise ConnectionError("Failed to get database connection.")

            # Use context manager for cursor to ensure it's closed
            with conn.cursor() as cursor:
                logger.debug(f"Executing SQL: {sql} with params: {params}")
                # Use empty tuple if params is None to avoid TypeError
                cursor.execute(sql, params or ())

                if returning_id_column:
                    fetched = cursor.fetchone()
                    if fetched:
                        returned_id = fetched[0] # Assume ID is the first column
                        logger.debug(f"Returning {returning_id_column}: {returned_id}")
                    # else: returned_id remains None

                elif fetch_one:
                    fetched = cursor.fetchone()
                    # Check if cursor.description is available before creating dict
                    if fetched and cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        results = dict(zip(columns, fetched))
                    # else: results remains None if no row found
                    logger.debug(f"Fetched one: {results}")

                elif fetch_all:
                    # Check description before fetching to handle queries that don't return rows (like some UPDATE/DELETE)
                    if cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
                    else:
                        results = [] # Return empty list if no columns/rows
                    logger.debug(f"Fetched all ({len(results)} rows)")

                # Commit transaction if requested *after* potential fetches
                if commit:
                    conn.commit()
                    logger.debug("Transaction committed.")

            # Return based on what was requested
            if returning_id_column:
                return returned_id
            else:
                return results # Returns dict, list, or None

        except (psycopg2.Error, ConnectionError) as e: # Catch specific expected errors first
            logger.error(f"Database/Connection Error executing SQL: {sql} | Params: {params} | Error: {e}", exc_info=True)
            if conn:
                try:
                    conn.rollback() # Rollback on error
                    logger.debug("Transaction rolled back due to error.")
                except psycopg2.Error as rb_err:
                    logger.error(f"Error during rollback: {rb_err}")
            # Re-raise as a ValueError for consistent API error handling upstream
            raise ValueError(f"Database operation failed: {e}") from e
        except Exception as e: # Catch unexpected errors
             logger.error(f"Unexpected Error during DB operation: {sql} | Params: {params} | Error: {e}", exc_info=True)
             if conn:
                try:
                    conn.rollback()
                    logger.debug("Transaction rolled back due to unexpected error.")
                except psycopg2.Error as rb_err:
                    logger.error(f"Error during rollback: {rb_err}")
             # Re-raise as ValueError
             raise ValueError(f"An unexpected error occurred during database operation: {e}") from e

        finally:
            # Ensure connection is closed if it was successfully opened
            if conn:
                try:
                    conn.close()
                    logger.debug("Database connection closed.")
                except Exception as close_err:
                    # Log error but don't re-raise, as original error (if any) is more important
                    logger.error(f"Error closing database connection: {close_err}")


# --- Authentication Class (Merged Logic) ---
class AuthenticationAndUsers(BaseRepository):
    def signup_user(self, name: str, email: str, password: str, image: Optional[str] = None) -> Dict[str, Any]:
        """Signs up a new user, hashes password, sends verification email. Optionally stores image link."""
        hashed_pw = hash_password(password)
        verification_code = generate_random_code()
        conn = None # Initialize connection
        user_id = None # Initialize user_id
        try:
            conn = get_db_connection()
            if not conn:
                raise ConnectionError("Signup failed: Database connection could not be established.")

            with conn.cursor() as cursor:
                # 1. Check if email exists
                email_query = "SELECT user_id FROM users WHERE lower(email) = lower(%s)"
                cursor.execute(email_query, (email,))
                if cursor.fetchone():
                    raise ValueError(f"Email '{email}' is already registered.")

                # 2. Check if name exists
                name_query = "SELECT user_id FROM users WHERE lower(name) = lower(%s)"
                cursor.execute(name_query, (name,))
                if cursor.fetchone():
                    raise ValueError(f"Name '{name}' is already taken.")

                # 3. Insert new user (with optional image)
                if image is not None:
                    insert_query = """
                        INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified, image)
                        VALUES (%s, %s, %s, NOW(), FALSE, %s) RETURNING user_id
                    """
                    cursor.execute(insert_query, (name, email, hashed_pw, image))
                else:
                    insert_query = """
                        INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified)
                        VALUES (%s, %s, %s, NOW(), FALSE) RETURNING user_id
                    """
                    cursor.execute(insert_query, (name, email, hashed_pw))
                user_id_result = cursor.fetchone()
                if not user_id_result:
                     # This should ideally not happen with RETURNING if insert was successful
                     raise psycopg2.DatabaseError("User insertion failed to return user_id.")
                user_id = user_id_result[0]

                # 4. Insert/Update verification code
                # Commenting out the email verification step:
                # verification_query = """
                #     INSERT INTO email_verifications (user_id, verification_code, expires_at)
                #     VALUES (%s, %s, NOW() + INTERVAL '15 minutes')
                #     ON CONFLICT (user_id) DO UPDATE
                #     SET verification_code = EXCLUDED.verification_code, expires_at = EXCLUDED.expires_at
                # """
                # cursor.execute(verification_query, (user_id, verification_code))

                # 5. Commit transaction *before* sending email
                conn.commit()

            # 6. Send verification email (only if DB operations succeeded)
            # self.send_verification_email_gmail(email, verification_code)

            logger.info(f"User '{name}' (ID: {user_id}) registered successfully.")
            return {"user_id": user_id, "success": True}

        # Catch specific expected errors first
        except (ValueError, psycopg2.Error, ConnectionError) as e:
            logger.error(f"Error during signup for {email}: {e}", exc_info=True)
            if conn: # Attempt rollback if connection exists
                try: conn.rollback()
                except psycopg2.Error as rb_err: logger.error(f"Rollback error during signup: {rb_err}")
            # Return a more specific error message if possible
            err_msg = str(e) if isinstance(e, (ValueError, ConnectionError)) else "An internal error occurred during signup."
            return {"error": err_msg, "success": False}
        # Catch any other unexpected exceptions
        except Exception as e:
            logger.error(f"Unexpected error during signup for {email}: {e}", exc_info=True)
            if conn:
                try: conn.rollback()
                except psycopg2.Error as rb_err: logger.error(f"Rollback error during signup: {rb_err}")
            return {"error": "An unexpected server error occurred.", "success": False}
        finally:
             # Ensure connection is closed
             if conn:
                 try: conn.close()
                 except Exception as close_err: logger.error(f"Error closing signup connection: {close_err}")

    def verify_user_email(self, user_id: int, verification_code: str) -> tuple[Dict[str, str], int]:
        """Verifies a user's email using the provided code."""
        # Define SQL queries
        check_query = "SELECT verification_code FROM email_verifications WHERE user_id = %s AND verification_code = %s AND expires_at > NOW()"
        update_query = "UPDATE users SET is_email_verified = TRUE WHERE user_id = %s"
        delete_query = "DELETE FROM email_verifications WHERE user_id = %s AND verification_code = %s"
        conn = None # Initialize connection

        try:
            conn = get_db_connection()
            if not conn:
                # Return error if DB connection fails
                return {'message': 'Verification service unavailable at the moment.'}, 503 # Service Unavailable

            with conn.cursor() as cursor:
                 # 1. Check if the code is valid and not expired
                 cursor.execute(check_query, (user_id, verification_code))
                 if not cursor.fetchone():
                     logger.warning(f"Email verification failed for user {user_id}: Invalid or expired code.")
                     return {'message': 'Invalid or expired verification code'}, 400 # Bad Request

                 # 2. Update user status and delete verification record within transaction
                 cursor.execute(update_query, (user_id,))
                 cursor.execute(delete_query, (user_id, verification_code))

                 # 3. Commit the transaction
                 conn.commit()

            logger.info(f"Email successfully verified for user ID {user_id}.")
            return {'message': 'Email verification successful'}, 200 # OK

        # Catch specific database or connection errors
        except (psycopg2.Error, ConnectionError) as e:
            logger.error(f"Error during email verification for user {user_id}: {e}", exc_info=True)
            if conn:
                try: conn.rollback()
                except psycopg2.Error as rb_err: logger.error(f"Rollback error during verification: {rb_err}")
            # Determine status code based on error type
            status_code = 503 if isinstance(e, ConnectionError) else 500 # Internal Server Error
            return {'message': 'An error occurred during email verification.'}, status_code
        # Catch any other unexpected exceptions
        except Exception as e:
            logger.error(f"Unexpected error during email verification for user {user_id}: {e}", exc_info=True)
            if conn:
                try: conn.rollback()
                except psycopg2.Error as rb_err: logger.error(f"Rollback error during verification: {rb_err}")
            return {'message': 'An unexpected server error occurred during verification.'}, 500
        finally:
            # Ensure connection is closed
            if conn:
                 try: conn.close()
                 except Exception as close_err: logger.error(f"Error closing verification connection: {close_err}")

    def send_verification_email_gmail(self, to_email: str, verification_code: str):
        """Handles Gmail authentication and sends a verification email."""
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None
        token_file = 'token.json'
        client_secret_file = 'client_secret.json'

        # Check if client secret file exists
        if not os.path.exists(client_secret_file):
            logger.error(f"Gmail client secret file not found: {client_secret_file}")
            # This is a configuration error, raise FileNotFoundError
            raise FileNotFoundError(f"Required file '{client_secret_file}' not found for sending email.")

        # Load existing credentials if token file exists
        if os.path.exists(token_file):
            try:
                creds = Credentials.from_authorized_user_file(token_file, SCOPES)
            except Exception as e:
                logger.warning(f"Error loading credentials from {token_file}: {e}. Will attempt re-authentication.")
                creds = None # Reset creds if loading fails

        # Check if credentials need refresh or re-authentication
        needs_refresh = False
        needs_reauth = False
        if creds:
            try:
                # Check expiry (use a small buffer like 5 minutes)
                # Ensure comparison handles timezone awareness correctly if needed (utcnow is naive by default)
                is_expired = creds.expiry and creds.expiry < (datetime.utcnow().replace(tzinfo=None) + timedelta(minutes=5))

                if is_expired:
                    needs_refresh = True
                    if creds.refresh_token:
                        logger.info("Refreshing Gmail API access token...")
                        creds.refresh(Request())
                        logger.info("Gmail token refreshed successfully.")
                        needs_refresh = False # Reset flag after success
                    else:
                        # Cannot refresh without a refresh token, needs full re-auth
                        logger.warning("Gmail token expired, but no refresh token available. Re-authentication required.")
                        needs_reauth = True
                        creds = None # Nullify creds to trigger re-auth flow
                elif not creds.valid:
                     # If not expired but invalid (e.g., revoked), needs re-auth
                     logger.warning("Gmail token is invalid. Re-authentication required.")
                     needs_reauth = True
                     creds = None

            except RefreshError as e:
                # Refresh failed (e.g., refresh token expired/revoked)
                logger.error(f"Error refreshing Gmail token (requires re-auth): {e}")
                needs_reauth = True
                creds = None # Force re-authentication
                needs_refresh = False # Reset flag
            except Exception as e:
                # Catch other unexpected errors during check/refresh
                logger.error(f"Unexpected error checking/refreshing Gmail token: {e}")
                creds = None # Assume invalid
                needs_reauth = True
                needs_refresh = False

        # If no valid credentials or re-authentication is needed, run the auth flow
        if not creds or needs_reauth:
            try:
                logger.info("Starting Gmail authentication flow...")
                flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES)
                # Note: run_local_server will block until flow is complete
                creds = flow.run_local_server(port=8080) # Consider using a different port if 8080 is common
                logger.info("Gmail authentication successful.")
            except Exception as e:
                logger.error(f"Gmail authentication flow failed: {e}")
                # Raise a specific error indicating auth failure
                raise ConnectionError("Failed to obtain Google API credentials through authentication flow.") from e

        # Save the obtained/refreshed credentials
        if creds:
            try:
                with open(token_file, 'w') as token:
                    token.write(creds.to_json())
                logger.debug(f"Gmail credentials saved to {token_file}")
            except IOError as e:
                # Log error but don't fail the email sending if creds are valid in memory
                logger.error(f"Error saving Gmail token to {token_file}: {e}")

        # Send the email using the valid credentials
        try:
            # Build the Gmail service client
            service = build('gmail', 'v1', credentials=creds)

            # Create the email message
            subject = "Your ZINZI Verification Code"
            body = f"Your verification code is: {verification_code}\nPlease enter this code in the ZINZI app."
            message = MIMEText(body)
            message['to'] = to_email
            message['from'] = 'me' # 'me' uses the authenticated user's email address
            message['subject'] = subject

            # Encode the message in base64url format
            raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()

            # Send the message
            send_message_body = {'raw': raw_message}
            sent_message = service.users().messages().send(userId="me", body=send_message_body).execute()

            logger.info(f"Verification email sent successfully to {to_email}. Message ID: {sent_message.get('id')}")
        except Exception as e:
            logger.error(f"Failed to send Gmail verification email to {to_email}: {e}", exc_info=True)
            # Raise a specific error that can be caught by the caller (e.g., signup_user)
            raise ConnectionError(f"Failed to send verification email via Gmail: {e}") from e

    def create_user(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Wrapper for signup_user, extracting data from a dictionary. Supports optional Image."""
        # Ensure keys exist before accessing, provide better error if missing
        name = user_data.get('Name')
        email = user_data.get('Email')
        password = user_data.get('Password')
        image = user_data.get('Image')  # Optional
        if not name or not email or not password:
             # Be specific about which fields are missing
             missing = [k for k in ['Name', 'Email', 'Password'] if not user_data.get(k)]
             raise ValueError(f"Missing required fields for user creation: {', '.join(missing)}")
        # Call the main signup logic
        return self.signup_user(name, email, password, image)

    def list_users(self, user_id: Optional[int] = None) -> Optional[List[Dict[str, Any]]]:
        """Lists users, optionally filtering by user_id. Excludes sensitive info."""
        # Select specific columns, excluding hashed_password
        sql = "SELECT user_id, name, email, registration_date, is_email_verified, user_type, last_login, image FROM users"
        params = []
        if user_id is not None:
            try:
                uid = int(user_id)
                sql += " WHERE user_id = %s"
                params.append(uid)
            except ValueError:
                raise ValueError("Invalid user_id format provided.")

        users_list = self._execute_query(sql, params, fetch_all=True)

        # Process results: Convert datetime objects and ensure dicts
        if users_list:
            processed_users = []
            for user_row in users_list:
                processed_user = dict(user_row) # Create a mutable copy
                for key, value in processed_user.items():
                    if isinstance(value, (datetime, date)):
                        processed_user[key] = value.isoformat()
                processed_users.append(processed_user)
            if user_id is not None:
                # Return a single user dict if user_id was provided
                return processed_users[0] if processed_users else None
            else:
                return processed_users # Return list if no user_id filter
        else:
            if user_id is not None:
                logger.warning(f"No user found with ID: {user_id}")
                return None # Return None if specific user not found
            else:
                return [] # Return empty list if no users found globally

    def login_user(self, identifier: str, password: str) -> tuple[Dict[str, Any], int]:
        """Logs in a user using name or email."""
        sql = "SELECT user_id, hashed_password, user_type, is_email_verified FROM users WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)"
        params = (identifier.lower(), identifier.lower())

        try:
            result = self._execute_query(sql, params, fetch_one=True)

            if not result:
                logger.warning(f"Login failed: Identifier '{identifier}' not found.")
                return {'message': 'Invalid credentials or account not found.'}, 401

            user_id = result['user_id']
            stored_hashed_password = result['hashed_password']
            user_type = result.get('user_type', 'user') # Provide default if NULL
            is_verified = result.get('is_email_verified', False) # Default to False if NULL

            # Ensure the stored hash is bytes before comparison
            if isinstance(stored_hashed_password, str):
                stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
            elif isinstance(stored_hashed_password, bytes):
                stored_hashed_pw_bytes = stored_hashed_password
            else:
                # Handle unexpected hash type (e.g., None or other type)
                logger.error(f"Invalid hashed_password type for user {user_id}. Type: {type(stored_hashed_password)}")
                return {'message': 'Internal server error during login processing.'}, 500

            # Check password using bcrypt
            if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                # Optional: Check if email is verified before allowing login
                # if not is_verified:
                #     logger.warning(f"Login attempt for unverified user {user_id} ('{identifier}').")
                #     return {'message': 'Account not verified. Please check your email.', 'user_id': user_id, 'verified': False}, 403 # 403 Forbidden

                logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
                # Update last_login time (best effort, don't fail login if this fails)
                update_sql = "UPDATE users SET last_login = NOW() WHERE user_id = %s"
                try:
                    self._execute_query(update_sql, (user_id,), commit=True)
                except Exception as update_err:
                    # Log error but continue with successful login response
                    logger.error(f"Failed to update last_login for user {user_id}: {update_err}")

                # Return success response
                return {'message': 'Login successful', 'data': {'user_id': user_id, 'user_type': user_type, 'verified': is_verified}}, 200
            else:
                # Password did not match
                logger.warning(f"Login failed: Invalid password for identifier '{identifier}'.")
                return {'message': 'Invalid credentials.'}, 401

        except ValueError as ve: # Catch DB errors from _execute_query
             logger.error(f"Database error during user login for '{identifier}': {ve}")
             return {'message': 'Login service unavailable.'}, 503 # Service Unavailable
        except Exception as e: # Catch unexpected errors
             logger.error(f"Unexpected error during user login for '{identifier}': {e}", exc_info=True)
             return {'message': 'An unexpected server error occurred.'}, 500

    def delete_user(self, user_id: int) -> bool:
        """Deletes a user record. Use with caution!"""
        logger.warning(f"Attempting to delete user ID: {user_id}")
        # Consider dependencies: Orders, Metrics, Preferences might need deletion or handling via CASCADE
        sql = "DELETE FROM users WHERE user_id = %s"
        try:
            # Validate ID format (already int from type hint, but extra check)
            if not isinstance(user_id, int): raise ValueError("Invalid user_id format.")
            # Execute query returns None for DELETE unless RETURNING is used
            self._execute_query(sql, (user_id,), commit=True)
            # If no exception, assume success
            logger.info(f"Successfully deleted user ID: {user_id}")
            return True # Indicate success
        except ValueError as ve: # Catch ID format error or DB error from execute
            logger.error(f"Error deleting user ID {user_id}: {ve}")
            return False # Indicate failure
        except Exception as e: # Catch unexpected errors
            logger.error(f"Unexpected error deleting user ID {user_id}: {e}", exc_info=True)
            return False # Indicate failure

    # --- Metrics Methods ---
    def create_metric(self, metric_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new user metric record."""
        metric_data_lower = lowercase_keys(metric_data)
        required_fields = ['user_id', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse']
        check_required_fields(metric_data_lower, required_fields)
        sql = """
            INSERT INTO user_metrics (
                user_id, age_range, weight, height, cholesterol_level,
                sys_bp, dia_bp, pulse, recorded_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
            RETURNING metric_id
        """
        # Ensure numeric types are correct before passing to DB
        try:
             params = (
                int(metric_data_lower['user_id']),
                metric_data_lower.get('age_range'), # Keep as string or handle conversion if needed
                float(metric_data_lower['weight']),
                float(metric_data_lower['height']),
                float(metric_data_lower['cholesterol_level']),
                int(metric_data_lower['sys_bp']),
                int(metric_data_lower['dia_bp']),
                int(metric_data_lower['pulse'])
             )
        except (ValueError, TypeError) as e:
             raise ValueError(f"Invalid numeric format in metric data: {e}") from e

        metric_id = self._execute_query(sql, params, commit=True, returning_id_column='metric_id')
        if metric_id:
            logger.info(f"Created metric ID: {metric_id} for User: {metric_data_lower['user_id']}")
            return {"metric_id": metric_id}
        else:
             raise ValueError("Metric creation failed to return ID.")

    def update_metric(self, metric_id: int, updates: Dict[str, Any]):
        """Updates an existing user metric record."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        # Basic validation: Ensure metric_id is int-like
        try:
            mid = int(metric_id)
        except ValueError: raise ValueError("Invalid metric_id format.")

        set_clauses = []
        params = []
        # Define fields allowed for update
        allowed_fields = ['age_range', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse', 'sex', 'activity_level'] # Added sex/activity
        for key, value in updates_lower.items():
             # Skip keys that shouldn't be updated
             if key in ['metric_id', 'user_id', 'recorded_at']: continue
             if key in allowed_fields:
                 # Add type validation/conversion if necessary here before appending
                 set_clauses.append(f"{key} = %s")
                 params.append(value)
             else:
                  logger.warning(f"Ignoring unrecognized field '{key}' during metric update.")

        if not set_clauses: raise ValueError("No valid fields provided for update.")

        sql = f"UPDATE user_metrics SET {', '.join(set_clauses)} WHERE metric_id = %s"
        params.append(mid) # Append metric_id for WHERE clause
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated metric ID: {metric_id}")

    def list_metrics(self, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists metrics, optionally filtered by user_id."""
        sql = "SELECT * FROM user_metrics" # Select all columns for now
        params = []
        if user_id is not None:
             try:
                 uid = int(user_id)
                 sql += " WHERE user_id = %s ORDER BY recorded_at DESC" # Order by most recent
                 params.append(uid)
             except ValueError: raise ValueError("Invalid user_id format.")
        else:
             sql += " ORDER BY recorded_at DESC" # Order globally if no user_id

        # Execute query and handle potential None return
        metrics = self._execute_query(sql, params, fetch_all=True)
        # Process datetimes
        if metrics:
             processed = []
             for item in metrics:
                  p_item = dict(item)
                  for k, v in p_item.items():
                       if isinstance(v, (datetime, date)): p_item[k] = v.isoformat()
                  processed.append(p_item)
             return processed
        return [] # Return empty list if None or no results

    # --- Metric History Methods ---
    def create_metric_history(self, metric_history_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new metric history record (e.g., weight log)."""
        metric_history_data_lower = lowercase_keys(metric_history_data)
        # Only require user_id and weight for history log
        check_required_fields(metric_history_data_lower, ['user_id', 'weight'])
        sql = "INSERT INTO metrics_history (user_id, weight, logged_at) VALUES (%s, %s, NOW()) RETURNING log_id"
        try:
            params = (int(metric_history_data_lower['user_id']), float(metric_history_data_lower['weight']))
        except (ValueError, TypeError) as e:
            raise ValueError(f"Invalid numeric format in metric history data: {e}") from e

        log_id = self._execute_query(sql, params, commit=True, returning_id_column='log_id')
        if log_id:
             logger.info(f"Created metric history Log ID: {log_id} for User: {metric_history_data_lower['user_id']}")
             return {"log_id": log_id}
        else:
             raise ValueError("Metric history creation failed to return ID.")

    def update_metric_history(self, log_id: int, updates: Dict[str, Any]):
        """Updates an existing metric history record."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        try:
            lid = int(log_id)
        except ValueError: raise ValueError("Invalid log_id format.")

        set_clauses = []
        params = []
        allowed_fields = ['weight'] # Typically only allow updating the value itself
        for key, value in updates_lower.items():
            # Skip keys that shouldn't be updated
            if key in ['log_id', 'user_id', 'logged_at']: continue
            if key in allowed_fields:
                 # Validate type if needed (e.g., ensure weight is float)
                 try: weight_f = float(value);
                 except (ValueError, TypeError): raise ValueError("Invalid weight format for update.")
                 set_clauses.append(f"{key} = %s")
                 params.append(weight_f)
            else:
                 logger.warning(f"Ignoring unrecognized field '{key}' during metric history update.")

        if not set_clauses: raise ValueError("No valid fields provided for update.")
        sql = f"UPDATE metrics_history SET {', '.join(set_clauses)} WHERE log_id = %s"
        params.append(lid) # Append log_id for WHERE clause
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated metric history Log ID: {log_id}")

    def list_metric_history(self, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists metric history, optionally filtered by user_id, ordered by date."""
        sql = "SELECT * FROM metrics_history"
        params = []
        if user_id is not None:
             try:
                 uid = int(user_id)
                 sql += " WHERE user_id = %s ORDER BY logged_at DESC" # Order by most recent
                 params.append(uid)
             except ValueError: raise ValueError("Invalid user_id format.")
        else:
             sql += " ORDER BY logged_at DESC" # Order globally if no user_id

        history = self._execute_query(sql, params, fetch_all=True)
        # Process datetimes
        if history:
             processed = []
             for item in history:
                  p_item = dict(item)
                  for k, v in p_item.items():
                       if isinstance(v, (datetime, date)): p_item[k] = v.isoformat()
                  processed.append(p_item)
             return processed
        return [] # Return empty list if None or no results

    # --- Preferences Methods ---
    def create_preference(self, preference_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new user preference record."""
        preference_data_lower = lowercase_keys(preference_data)
        check_required_fields(preference_data_lower, ['user_id', 'goals', 'diet_type'])
        sql = """
            INSERT INTO user_preferences (
                user_id, goals, diet_type, food_restrictions, cuisine_preferences
            ) VALUES (%s, %s, %s, %s, %s)
            RETURNING preference_id
        """
        try:
             # Prepare parameters, potentially serializing lists if needed
             # Assuming DB columns are TEXT or similar for list-like fields
             params = (
                int(preference_data_lower['user_id']),
                preference_data_lower['goals'],
                preference_data_lower['diet_type'],
                # Pass lists directly if column type supports it (e.g., TEXT[], JSONB)
                # Or serialize them: serialize_list(preference_data_lower.get('food_restrictions', []))
                preference_data_lower.get('food_restrictions'),
                preference_data_lower.get('cuisine_preferences')
             )
        except ValueError: raise ValueError("Invalid user_id format.")

        preference_id = self._execute_query(sql, params, commit=True, returning_id_column='preference_id')
        if preference_id:
            logger.info(f"Created preference ID: {preference_id} for User: {preference_data_lower['user_id']}")
            return {"preference_id": preference_id}
        else:
            raise ValueError("Preference creation failed to return ID.")

    def update_preference(self, preference_id: int, updates: Dict[str, Any]):
        """Updates an existing user preference record."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        try:
            pid = int(preference_id)
        except ValueError: raise ValueError("Invalid preference_id format.")

        set_clauses = []
        params = []
        # Define allowed fields for update
        allowed_fields = ['goals', 'diet_type', 'food_restrictions', 'cuisine_preferences']
        for key, value in updates_lower.items():
             # Skip keys that shouldn't be updated
             if key in ['preference_id', 'user_id']: continue
             if key in allowed_fields:
                 # Serialize lists if necessary based on DB column type
                 # Example: if key in ['food_restrictions', 'cuisine_preferences']: value = serialize_list(value)
                 set_clauses.append(f"{key} = %s")
                 params.append(value)
             else:
                 logger.warning(f"Ignoring unrecognized field '{key}' during preference update.")

        if not set_clauses: raise ValueError("No valid fields provided for preference update.")
        sql = f"UPDATE user_preferences SET {', '.join(set_clauses)} WHERE preference_id = %s"
        params.append(pid) # Append preference_id for WHERE clause
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated preference ID: {preference_id}")

    def list_preferences(self, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists preferences, optionally filtered by user_id."""
        sql = "SELECT * FROM user_preferences"
        params = []
        if user_id is not None:
             try:
                 uid = int(user_id)
                 sql += " WHERE user_id = %s"
                 params.append(uid)
             except ValueError: raise ValueError("Invalid user_id format.")

        preferences = self._execute_query(sql, params, fetch_all=True)
        # Deserialize list-like fields if they were stored serialized
        if preferences:
             processed = []
             for pref_row in preferences:
                  p_pref = dict(pref_row)
                  # Example deserialization:
                  # p_pref['food_restrictions'] = deserialize_list(p_pref.get('food_restrictions', ''))
                  # p_pref['cuisine_preferences'] = deserialize_list(p_pref.get('cuisine_preferences', ''))
                  processed.append(p_pref)
             return processed
        return [] # Return empty list if None or no results

# --- CRUD Operations Classes ---

# --- Chefs Class ---
class Chefs(BaseRepository):
    def _validate_stock(self, stock_data, is_chef=True):
        """Validate stock data format for chefs or producers."""
        if stock_data is None:
            return []  # Allow null/None to be stored as empty list
        if not isinstance(stock_data, list):
            raise ValueError(f"Stock must be a list, got {type(stock_data)}")
        id_field = 'meal_id' if is_chef else 'produce_id'
        for item in stock_data:
            if not isinstance(item, dict):
                raise ValueError(f"Stock item must be a dict, got {type(item)}")
            if 'Name' not in item or not isinstance(item['Name'], str) or not item['Name'].strip():
                raise ValueError("Stock item must have a non-empty 'Name' string")
            if id_field in item and item[id_field] is not None and not isinstance(item[id_field], str):
                raise ValueError(f"Stock item {id_field} must be a string or null")
            if 'quantity' in item and item['quantity'] is not None:
                try:
                    item['quantity'] = float(item['quantity'])  # Ensure numeric
                except (ValueError, TypeError):
                    raise ValueError("Stock item quantity must be a number or null")
        return stock_data

    def create_chef(self, chef_data):
        chef_data_lower = lowercase_keys(chef_data)
        required = ['name', 'password', 'email', 'chef_type', 'phone_number', 'location', 'experience', 'responsetime', 'minnotice', 'teamsize', 'bio', 'image', 'pricing']
        check_required_fields(chef_data_lower, required)
        email = chef_data_lower['email']
        check_sql = "SELECT chefid FROM chefs WHERE lower(email) = lower(%s)"
        if self._execute_query(check_sql, (email,), fetch_one=True):
            raise ValueError(f"Chef email '{email}' already exists.")
        try:
            hashed_password = hash_password(chef_data_lower['password'])
        except Exception as e:
            logger.error(f"Password hashing failed: {e}")
            raise ValueError("Password processing error.")
        pricing_data = chef_data_lower.get('pricing', {})
        if not isinstance(pricing_data, dict):
            raise ValueError("Invalid pricing data format.")
        try:
            if 'starting_price' in pricing_data:
                pricing_data['starting_price'] = float(pricing_data['starting_price']) if pricing_data['starting_price'] is not None else None
            if 'per_month' in pricing_data:
                pricing_data['per_month'] = float(pricing_data['per_month']) if pricing_data['per_month'] is not None else None
            if 'per_gig' in pricing_data and isinstance(pricing_data.get('per_gig'), dict):
                pricing_data['per_gig'] = {k: float(v) if v is not None else None for k, v in pricing_data['per_gig'].items()}
            else:
                pricing_data['per_gig'] = {}
            pricing_param = json.dumps(pricing_data)
        except (ValueError, TypeError, KeyError) as e:
            logger.error(f"Error processing pricing data: {pricing_data}. Error: {e}")
            raise ValueError(f"Invalid value in pricing data: {e}")
        # Handle stock
        stock_data = self._validate_stock(chef_data_lower.get('stock'), is_chef=True)
        stock_json_str = json.dumps(stock_data)
        equipment_json_str = json.dumps(chef_data_lower.get('equipment', []))
        availability_json_str = json.dumps(chef_data_lower.get('availability', []))
        languages_json_str = json.dumps(chef_data_lower.get('languages', []))
        specialties_json_str = json.dumps(chef_data_lower.get('specialties', []))
        certifications_json_str = json.dumps(chef_data_lower.get('certifications', []))
        samplemenu_json_str = json.dumps(chef_data_lower.get('samplemenu', []))
        user_type = chef_data_lower.get('user_type', 'chef')
        is_email_verified = chef_data_lower.get('is_email_verified', False)
        is_active = chef_data_lower.get('is_active', True)
        added_by = chef_data_lower.get('added_by')
        added_by_type = chef_data_lower.get('added_by_type', user_type)
        sql = """INSERT INTO chefs (
            name, image, email, hashed_password, is_email_verified, user_type, chef_type, is_active,
            rating, phone_number, experience, serviceradius, responsetime, minnotice, punctuality,
            teamsize, equipment, bio, availability, languages, specialties, certifications,
            registration_date, location, samplemenu, added_by, added_by_type, last_login, pricing, stock
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, %s, NOW(), %s, %s)
        RETURNING chefid"""
        params = (
            chef_data_lower['name'], chef_data_lower.get('image'), email, hashed_password,
            is_email_verified, user_type, chef_data_lower.get('chef_type', 'Individual'),
            is_active, chef_data_lower.get('rating', 0.0), chef_data_lower.get('phone_number'),
            chef_data_lower.get('experience'), chef_data_lower.get('serviceradius'),
            chef_data_lower.get('responsetime'), chef_data_lower.get('minnotice'),
            chef_data_lower.get('punctuality', 0.0), chef_data_lower.get('teamsize'),
            equipment_json_str, chef_data_lower.get('bio'), availability_json_str,
            languages_json_str, specialties_json_str, certifications_json_str,
            chef_data_lower.get('location'), samplemenu_json_str, added_by, added_by_type,
            pricing_param, stock_json_str
        )
        assert len(params) == 28, f"Chef create param count mismatch: expected 28, got {len(params)}"
        try:
            chef_id = self._execute_query(sql, params, commit=True, returning_id_column='chefid')
            if chef_id:
                logger.info(f"Successfully created chef ID: {chef_id} for email: {email}")
                return {"Chef_id": chef_id, "user_type": user_type, "message": "Chef created successfully"}
            else:
                logger.error(f"Chef creation query executed for email {email} but did not return chefid.")
                raise ValueError("Failed to retrieve chef ID after insertion.")
        except Exception as e:
            logger.error(f"DB Error chef creation {email}: {e}", exc_info=True)
            logger.debug(f"Failed SQL: {sql}")
            raise ValueError(f"Database operation failed: {e}")

    def list_chefs(self, chef_id=None):
        sql = "SELECT * FROM chefs"
        params = []
        if chef_id is not None:
            try:
                cid = int(chef_id)
                sql += " WHERE chefid = %s"
                params.append(cid)
            except ValueError:
                raise ValueError("Invalid chef_id format.")
        chefs_list = self._execute_query(sql, params, fetch_all=True)
        if chefs_list is None:
            return []
        processed_chefs = []
        for chef_dict in chefs_list:
            chef_dict = dict(chef_dict)
            list_fields = ['equipment', 'availability', 'languages', 'specialties', 'certifications', 'samplemenu', 'stock']
            for field in list_fields:
                chef_dict[field] = deserialize_list_from_json_string(chef_dict.get(field))
            pricing_data = chef_dict.get('pricing') or {}
            extracted_price = pricing_data.get('starting_price', 0.0)
            chef_dict['price'] = extracted_price
            for key, value in chef_dict.items():
                if isinstance(value, (datetime, date)):
                    chef_dict[key] = value.isoformat()
            processed_chefs.append(chef_dict)
        if chef_id and not processed_chefs:
            logger.warning(f"No chef found ID: {chef_id}")
            return []
        return processed_chefs

    def update_chef(self, chef_id, updates):
        updates_lower = lowercase_keys(updates)
        print(updates_lower)
        if not updates_lower:
            raise ValueError("No updates provided.")
        set_clauses = []
        params = []
        if 'pricing' in updates_lower:
            pricing_data = updates_lower.pop('pricing')
            if not isinstance(pricing_data, dict):
                raise ValueError("'pricing' update must be a valid JSON object.")
            try:
                pricing_json_string = json.dumps(pricing_data)
                set_clauses.append("pricing = %s")
                params.append(pricing_json_string)
            except TypeError as e:
                raise ValueError(f"Could not serialize pricing: {e}")
        if 'stock' in updates_lower:
            stock_data = self._validate_stock(updates_lower.pop('stock'), is_chef=True)
            try:
                stock_json_string = json.dumps(stock_data)
                set_clauses.append("stock = %s")
                params.append(stock_json_string)
            except TypeError as e:
                raise ValueError(f"Could not serialize stock: {e}")
        updates_lower.pop('price', None)
        list_fields = ['equipment', 'availability', 'languages', 'specialties', 'certifications', 'samplemenu']
        allowed_direct_fields = [
            'name', 'image', 'email', 'chef_type', 'is_active', 'rating', 'phone_number', 'experience',
            'serviceradius', 'responsetime', 'minnotice', 'punctuality', 'teamsize', 'bio', 'reviews',
            'location', 'added_by', 'added_by_type', 'last_login'
        ]
        for key in updates_lower:
            value = updates_lower[key]
            if key == 'chefid':
                continue
            if key in allowed_direct_fields:
                # Accept both string and numeric values for allowed fields, convert as needed
                if key in ['rating', 'experience', 'serviceradius', 'responsetime', 'minnotice', 'punctuality', 'teamsize'] and isinstance(value, (int, float)):
                    set_clauses.append(f"{key} = %s")
                    params.append(str(value))
                else:
                    set_clauses.append(f"{key} = %s")
                    params.append(value)
            elif key in list_fields:
                if not isinstance(value, str):
                    raise ValueError(f"Field '{key}' must be JSON string for update.")
                set_clauses.append(f"{key} = %s")
                params.append(value)
            elif key == 'password':
                if not isinstance(value, str) or not value:
                    raise ValueError("Password update needs non-empty string.")
                hashed_pw = hash_password(value)
                set_clauses.append("hashed_password = %s")
                params.append(hashed_pw)
        # Debug log for troubleshooting
        logger.debug(f"update_chef: chef_id={chef_id}, updates={updates_lower}, set_clauses={set_clauses}, params={params}")
        if not set_clauses:
            raise ValueError("No valid fields for update.")
        sql = f"UPDATE chefs SET {', '.join(set_clauses)}, updated_at = NOW() WHERE chefid = %s"
        params.append(chef_id)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated chef ID: {chef_id}")

    def login_chef(self, identifier, password):
        sql = "SELECT chefid, hashed_password, user_type, is_email_verified FROM chefs WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)"
        params = (identifier.lower(), identifier.lower())
        result = self._execute_query(sql, params, fetch_one=True)
        if not result:
            logger.warning(f"Chef login failed: '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401
        chef_id = result['chefid']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']
        is_verified = result['is_email_verified']
        if isinstance(stored_hashed_password, str):
            stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
            stored_hashed_pw_bytes = stored_hashed_password
        else:
            logger.error(f"Bad hash type chef {chef_id}")
            return {'message': 'Internal login error.'}, 500
        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Chef login success '{identifier}', ID: {chef_id}")
            return {'message': 'Login successful', 'data': {'chef_id': chef_id, 'user_type': user_type, 'verified': is_verified}}, 200
        else:
            logger.warning(f"Chef login failed: Invalid password for '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401

    def delete_chef(self, chef_id):
        """Deletes a chef record. Use with caution!"""
        logger.warning(f"Attempting to delete chef ID: {chef_id}")
        sql = "DELETE FROM chefs WHERE chefid = %s"
        try:
            self._execute_query(sql, (chef_id,), commit=True)
            logger.info(f"Deleted chef ID: {chef_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete chef ID {chef_id}: {e}", exc_info=True)
            return False

    def update_chef_status(self, chef_id, is_active):
        """Updates only the is_active status of a chef."""
        sql = "UPDATE chefs SET is_active = %s, updated_at = NOW() WHERE chefid = %s"
        self._execute_query(sql, (is_active, chef_id), commit=True)
        logger.info(f"Updated chef ID {chef_id} active status to {is_active}")

# --- Producers Class ---
class Producers(BaseRepository):
    def _validate_stock(self, stock_data, is_chef=False):
        """Validate stock data format for chefs or producers."""
        if stock_data is None:
            return []
        if not isinstance(stock_data, list):
            raise ValueError(f"Stock must be a list, got {type(stock_data)}")
        id_field = 'produce_id' if not is_chef else 'meal_id'
        validated_stock = []
        for i, item in enumerate(stock_data):
            if not isinstance(item, dict):
                raise ValueError(f"Stock item at index {i} must be a dict, got {type(item)}")
            # Accept both 'Name' and 'name' (after lowercasing)
            name_val = item.get('name') if 'name' in item else item.get('Name')
            if not isinstance(name_val, str) or not name_val.strip():
                raise ValueError(f"Stock item at index {i} must have a non-empty 'Name' string")
            validated_item = {
                'Name': name_val.strip(),
                id_field: item.get(id_field)
            }
            if validated_item[id_field] is not None and not isinstance(validated_item[id_field], str):
                raise ValueError(f"Stock item at index {i} {id_field} must be a string or null")
            if 'quantity' in item and item['quantity'] is not None:
                try:
                    validated_item['quantity'] = float(item['quantity'])
                    if validated_item['quantity'] < 0:
                        raise ValueError(f"Stock item at index {i} quantity must be non-negative")
                except (ValueError, TypeError):
                    raise ValueError(f"Stock item at index {i} quantity must be a number or null")
            validated_stock.append(validated_item)
        return validated_stock

    def update_producer(self, producer_id, updates):
        try:
            pid = int(producer_id)
        except ValueError:
            raise ValueError("Invalid producer_id format provided for update")
        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise ValueError("No updates provided")
        set_clauses = []
        params = []
        allowed = ['name', 'image', 'producer_type', 'is_active', 'rating', 'phone_number', 'location', 'reviews']
        if 'stock' in updates_lower:
            stock_data = self._validate_stock(updates_lower.pop('stock'), is_chef=False)
            try:
                stock_json_string = json.dumps(stock_data)
                set_clauses.append("stock = %s")
                params.append(stock_json_string)
            except TypeError as e:
                raise ValueError(f"Could not serialize stock: {e}")
        for key, value in updates_lower.items():
            if key in ['producer_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified']:
                continue
            if key == 'password':
                logger.warning(f"Password update attempt ignored for producer {producer_id} via general update endpoint")
                continue
            elif key in allowed:
                if key == 'rating' and value is not None:
                    try:
                        value = float(value)
                        if value < 0:
                            raise ValueError("Rating cannot be negative")
                    except (ValueError, TypeError):
                        raise ValueError("Rating must be a valid number")
                if key == 'is_active' and not isinstance(value, bool):
                    raise ValueError("is_active must be a boolean")
                set_clauses.append(f"{key} = %s")
                params.append(value)
        if not set_clauses:
            raise ValueError("No valid fields provided for update")
        # Check if producer exists
        check_sql = "SELECT producer_id FROM producers WHERE producer_id = %s"
        if not self._execute_query(check_sql, (pid,), fetch_one=True):
            raise ValueError(f"Producer with ID {pid} does not exist")
        sql = f"UPDATE producers SET {', '.join(set_clauses)}, updated_at = NOW() WHERE producer_id = %s"
        params.append(pid)
        try:
            self._execute_query(sql, tuple(params), commit=True)
            logger.info(f"Successfully updated producer ID: {producer_id}")
        except Exception as e:
            logger.error(f"Database error updating producer {producer_id}: {e}", exc_info=True)
            raise ValueError(f"Failed to update producer: {e}")

    def create_producer(self, producer_data):
        producer_data_lower = lowercase_keys(producer_data)
        check_required_fields(producer_data_lower, ['name', 'password', 'email'])
        email = producer_data_lower['email']
        check_sql = "SELECT producer_id FROM producers WHERE lower(email) = lower(%s)"
        if self._execute_query(check_sql, (email,), fetch_one=True):
            raise ValueError(f"Producer email '{email}' already exists.")
        hashed_password = hash_password(producer_data_lower['password'])
        # Handle stock
        stock_data = self._validate_stock(producer_data_lower.get('stock'), is_chef=False)
        stock_json_str = json.dumps(stock_data)
        user_type = producer_data_lower.get('user_type', 'producer')
        is_email_verified = producer_data_lower.get('is_email_verified', False)
        is_active = producer_data_lower.get('is_active', True)
        added_by = producer_data_lower.get('added_by')
        added_by_type = producer_data_lower.get('added_by_type', user_type)
        sql = """
            INSERT INTO producers (
                name, image, email, hashed_password, is_email_verified, user_type,
                producer_type, is_active, rating, phone_number, registration_date,
                location, added_by, added_by_type, last_login, reviews, stock
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, NOW(), %s, %s)
            RETURNING producer_id
        """
        try:
            added_by_id = int(added_by) if added_by is not None else None
        except (ValueError, TypeError):
            logger.warning(f"Invalid format for 'added_by' ({added_by}), setting to NULL.")
            added_by_id = None
        try:
            rating_f = float(producer_data_lower.get('rating', 0.0) or 0.0)
        except (ValueError, TypeError):
            rating_f = 0.0
        params = (
            producer_data_lower['name'], producer_data_lower.get('image'), email, hashed_password,
            is_email_verified, user_type, producer_data_lower.get('producer_type', 'Individual'),
            is_active, rating_f, producer_data_lower.get('phone_number'),
            producer_data_lower.get('location'), added_by_id, added_by_type,
            producer_data_lower.get('reviews'), stock_json_str
        )
        producer_id = self._execute_query(sql, params, commit=True, returning_id_column='producer_id')
        if producer_id:
            logger.info(f"Successfully created producer ID: {producer_id}")
            return {"producer_id": producer_id, "UserType": user_type}
        else:
            raise ValueError("Producer creation failed to return ID.")

    def list_producers(self, producer_id=None):
        sql = "SELECT * FROM producers"
        params = []
        if producer_id is not None:
            try:
                pid = int(producer_id)
                sql += " WHERE producer_id = %s"
                params.append(pid)
            except ValueError:
                raise ValueError("Invalid producer_id format provided.")
        producers_list = self._execute_query(sql, params, fetch_all=True)
        if producers_list is None:
            return []
        processed_list = []
        for producer_row in producers_list:
            processed_prod = dict(producer_row)
            processed_prod['stock'] = deserialize_list_from_json_string(processed_prod.get('stock'))
            for key, value in processed_prod.items():
                if isinstance(value, (datetime, date)):
                    processed_prod[key] = value.isoformat()
            processed_list.append(processed_prod)
        if producer_id is not None and not processed_list:
            logger.warning(f"No producer found with ID: {producer_id}")
            return []
        return processed_list

    '''def update_producer_version2(self, producer_id, updates):
        try:
            pid = int(producer_id)
        except ValueError:
            raise ValueError("Invalid producer_id format provided for update.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise ValueError("No updates provided.")
        set_clauses = []
        params = []
        allowed = ['name', 'image', 'producer_type', 'is_active', 'rating', 'phone_number', 'location', 'reviews']
        if 'stock' in updates_lower:
            stock_data = self._validate_stock(updates_lower.pop('stock'), is_chef=False)
            try:
                stock_json_string = json.dumps(stock_data)
                set_clauses.append("stock = %s")
                params.append(stock_json_string)
            except TypeError as e:
                raise ValueError(f"Could not serialize stock: {e}")
        for key, value in updates_lower.items():
            if key in ['producer_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified']:
                continue
            if key == 'password':
                logger.warning(f"Password update attempt ignored for producer {producer_id} via general update endpoint.")
                continue
            elif key in allowed:
                set_clauses.append(f"{key} = %s")
                params.append(value)
        if not set_clauses:
            raise ValueError("No valid fields provided for update.")
        sql = f"UPDATE producers SET {', '.join(set_clauses)}, updated_at = NOW() WHERE producer_id = %s"
        params.append(pid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Successfully updated producer ID: {producer_id}")'''

    def login_producer(self, identifier, password):
        sql = "SELECT producer_id, hashed_password, user_type, is_email_verified FROM producers WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)"
        params = (identifier.lower(), identifier.lower())
        result = self._execute_query(sql, params, fetch_one=True)
        if not result:
            logger.warning(f"Producer login failed: '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401
        producer_id = result['producer_id']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']
        is_verified = result['is_email_verified']
        if isinstance(stored_hashed_password, str):
            stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
            stored_hashed_pw_bytes = stored_hashed_password
        else:
            logger.error(f"Bad hash type producer {producer_id}")
            return {'message': 'Internal login error.'}, 500
        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Producer login success '{identifier}', ID: {producer_id}")
            return {'message': 'Login successful', 'data': {'producer_id': producer_id, 'user_type': user_type, 'verified': is_verified}}, 200
        else:
            logger.warning(f"Producer login failed: Invalid password for '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401

    def delete_producer(self, producer_id):
        logger.warning(f"Attempting to delete producer ID: {producer_id}")
        sql = "DELETE FROM producers WHERE producer_id = %s"
        try:
            self._execute_query(sql, (producer_id,), commit=True)
            logger.info(f"Deleted producer ID: {producer_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete producer ID {producer_id}: {e}", exc_info=True)
            return False

    def update_producer_status(self, producer_id, is_active):
        sql = "UPDATE producers SET is_active = %s, updated_at = NOW() WHERE producer_id = %s"
        self._execute_query(sql, (is_active, producer_id), commit=True)
        logger.info(f"Updated producer ID {producer_id} active status to {is_active}")

# +++ TRANSPORTERS CLASS (with Delete method) +++
class Transporters(BaseRepository):
    def create_transporter(self, transporter_data):
        data_lower = lowercase_keys(transporter_data)
        check_required_fields(data_lower, ['name', 'password', 'email']) # Basic required fields
        email = data_lower['email']
        check_sql = "SELECT transporter_id FROM transporters WHERE lower(email) = lower(%s)"

        # Check if email already exists
        if self._execute_query(check_sql, (email,), fetch_one=True):
            raise ValueError(f"Transporter email '{email}' already exists.")

        hashed_password = hash_password(data_lower['password'])
        user_type = data_lower.get('user_type', 'transporter')
        is_active = data_lower.get('is_active', False) # Default to inactive?

        sql = """
            INSERT INTO transporters (
                name, email, hashed_password, phone_number, profile_image_url,
                vehicle_type, license_plate, is_active, rating, location,
                registration_date, user_type, reviews
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s)
            RETURNING transporter_id
        """
        # Ensure parameters match the SQL statement columns
        params = (
            data_lower['name'], email, hashed_password, data_lower.get('phone_number'),
            data_lower.get('profile_image_url'), data_lower.get('vehicle_type'),
            data_lower.get('license_plate'), is_active, data_lower.get('rating', 0.0), # Provide default for rating
            data_lower.get('location'), user_type, data_lower.get('reviews')
        )

        expected_params = 12
        if len(params) != expected_params: # Assertion check
             raise AssertionError(f"Transporter create param count mismatch: expected {expected_params}, got {len(params)}")

        transporter_id = self._execute_query(sql, params, commit=True, returning_id_column='transporter_id')

        if transporter_id:
            logger.info(f"Created transporter ID: {transporter_id} for email {email}")
            return {"transporter_id": transporter_id, "UserType": user_type, "message": "Transporter created successfully."}
        else:
            # This path should ideally not be reached if RETURNING works and DB is ok
            raise ValueError("Transporter creation failed to return ID.")

    def list_transporters(self, transporter_id=None):
        sql = "SELECT * FROM transporters"
        params = []
        if transporter_id is not None:
            try:
                tid = int(transporter_id)
                sql += " WHERE transporter_id = %s"
                params.append(tid)
            except ValueError:
                raise ValueError("Invalid transporter_id format.")

        transporters_list = self._execute_query(sql, params, fetch_all=True)
        if transporters_list is None:
            return [] # Return empty list if query fails or returns None

        # Process list to convert datetime objects
        processed_list = []
        for transporter in transporters_list:
            processed_trans = dict(transporter) # Ensure mutable dictionary
            for key, value in processed_trans.items():
                if isinstance(value, (datetime, date)):
                    processed_trans[key] = value.isoformat()
            processed_list.append(processed_trans)

        # Handle case where specific ID was requested but not found
        if transporter_id is not None and not processed_list:
            logger.warning(f"No transporter found ID: {transporter_id}")
            # Return empty list consistent with list endpoint, or None if preferred
            return []
        return processed_list

    def update_transporter(self, transporter_id, updates):
        try:
            tid = int(transporter_id) # Validate ID format first
        except ValueError:
            raise ValueError("Invalid transporter_id format.")

        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise ValueError("No updates provided.")

        set_clauses = []
        params = []
        allowed_fields = ['name', 'phone_number', 'profile_image_url', 'vehicle_type', 'license_plate', 'is_active', 'rating', 'location', 'reviews']

        for key, value in updates_lower.items():
            # Skip keys that should not be updated directly
            if key in ['transporter_id', 'email', 'registration_date', 'user_type']:
                continue

            if key == 'password':
                hashed_pw = hash_password(value)
                set_clauses.append("hashed_password = %s")
                params.append(hashed_pw)
            elif key in allowed_fields:
                set_clauses.append(f"{key} = %s")
                params.append(value)
            # else: ignore unrecognized fields

        if not set_clauses:
            raise ValueError("No valid fields provided for update.")

        # Assume 'updated_at' column exists and should be set
        sql = f"UPDATE transporters SET {', '.join(set_clauses)}, updated_at = NOW() WHERE transporter_id = %s"
        params.append(tid) # Add the ID for the WHERE clause

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated transporter ID: {transporter_id}")

    def login_transporter(self, identifier, password):
        # Assuming login is by email only based on original SQL
        sql = "SELECT transporter_id, hashed_password, user_type, is_email_verified FROM transporters WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)"
        params = (identifier.lower(), identifier.lower())
        try:
            result = self._execute_query(sql, params, fetch_one=True)
            if not result:
                logger.warning(f"Transporter login failed: '{identifier}' not found.")
                return {'message': 'Invalid credentials or account not found.'}, 401

            transporter_id = result['transporter_id']
            stored_hashed_password = result['hashed_password']
            # Provide defaults for potentially NULL columns
            user_type = result.get('user_type', 'transporter')
            is_verified = result.get('is_email_verified', True) # Defaulting to True - review if this is correct

            # Ensure hash is bytes
            if isinstance(stored_hashed_password, str):
                stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
            elif isinstance(stored_hashed_password, bytes):
                stored_hashed_pw_bytes = stored_hashed_password
            else:
                logger.error(f"Invalid hashed_password type for transporter {transporter_id}. Type: {type(stored_hashed_password)}")
                return {'message': 'Internal login error.'}, 500

            # Check password
            if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                logger.info(f"Transporter login successful for '{identifier}', ID: {transporter_id}")
                # Optional: Update last_login
                update_sql = "UPDATE transporters SET last_login = NOW() WHERE transporter_id = %s"
                try:
                    self._execute_query(update_sql, (transporter_id,), commit=True)
                except Exception as update_err:
                    logger.error(f"Failed to update last_login for transporter {transporter_id}: {update_err}")
                return {'message': 'Login successful', 'data': {'transporter_id': transporter_id, 'user_type': user_type, 'verified': is_verified }}, 200
            else:
                logger.warning(f"Transporter login failed: Invalid password for '{identifier}'.")
                return {'message': 'Invalid credentials.'}, 401
        except ValueError as ve: # Catch DB errors
             logger.error(f"Database error during transporter login for '{identifier}': {ve}")
             return {'message': 'Login service unavailable.'}, 503
        except Exception as e: # Catch unexpected errors
             logger.error(f"Unexpected error during transporter login for '{identifier}': {e}", exc_info=True)
             return {'message': 'An unexpected server error occurred.'}, 500

    def delete_transporter(self, transporter_id):
        logger.warning(f"Attempting to delete transporter ID: {transporter_id}")
        sql = "DELETE FROM transporters WHERE transporter_id = %s"
        try:
            # Validate ID format
            tid = int(transporter_id)
            self._execute_query(sql, (tid,), commit=True)
            logger.info(f"Deleted transporter ID: {transporter_id}")
            return True
        except ValueError as ve: # Catch ID format error or DB error from execute
            logger.error(f"Error deleting transporter ID {transporter_id}: {ve}")
            return False
        except Exception as e: # Catch unexpected errors
            logger.error(f"Failed to delete transporter ID {transporter_id}: {e}", exc_info=True)
            return False

    def update_transporter_status(self, transporter_id, is_active):
        # Validate inputs
        if not isinstance(is_active, bool):
             raise ValueError("'is_active' must be a boolean value.")
        try:
             tid = int(transporter_id)
        except ValueError:
             raise ValueError("Invalid transporter_id format.")

        # Assume updated_at column exists
        sql = "UPDATE transporters SET is_active = %s, updated_at = NOW() WHERE transporter_id = %s"
        try:
            self._execute_query(sql, (is_active, tid), commit=True)
            logger.info(f"Updated transporter ID {transporter_id} active status to {is_active}")
            # No return value needed, exception indicates failure
        except ValueError as ve: # Catch DB errors
             logger.error(f"Database error updating status for transporter {transporter_id}: {ve}")
             raise # Re-raise DB errors to be handled by caller
        except Exception as e:
             logger.error(f"Unexpected error updating status for transporter {transporter_id}: {e}", exc_info=True)
             raise ValueError("Failed to update transporter status due to server error.") from e

# --- Stakeholders ---
class Stakeholders(BaseRepository):
    def create_stakeholder(self, stakeholder_data):
        stakeholder_data_lower = lowercase_keys(stakeholder_data)
        check_required_fields(stakeholder_data_lower, ['name', 'password', 'email', 'full_name'])
        email = stakeholder_data_lower['email']
        check_sql = "SELECT stakeholder_id FROM stakeholders WHERE lower(email) = lower(%s)"

        if self._execute_query(check_sql, (email,), fetch_one=True):
            raise ValueError(f"Stakeholder email '{email}' already exists.")

        hashed_password = hash_password(stakeholder_data_lower['password'])
        user_type = stakeholder_data_lower.get('user_type', 'stakeholder')
        is_email_verified = stakeholder_data_lower.get('is_email_verified', False) # Default to False
        is_active = stakeholder_data_lower.get('is_active', True) # Default to True
        added_by = stakeholder_data_lower.get('added_by') # Allow None, handle potential type errors later
        added_by_type = stakeholder_data_lower.get('added_by_type', user_type) # Default to stakeholder type

        sql = """
            INSERT INTO stakeholders (
                name, full_name, image, email, hashed_password, is_email_verified,
                user_type, is_active, rating, phone_number, registration_date, location,
                added_by, added_by_type, last_login
            ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW(),%s,%s,%s,NOW())
            RETURNING stakeholder_id
        """
        # Safely convert added_by if needed, or ensure DB column allows NULL
        try: added_by_id = int(added_by) if added_by is not None else None
        except (ValueError, TypeError): added_by_id = None # Set to None if conversion fails

        params = (
            stakeholder_data_lower['name'], stakeholder_data_lower['full_name'], stakeholder_data_lower.get('image'),
            email, hashed_password, is_email_verified, user_type, is_active,
            stakeholder_data_lower.get('rating', 0.0), stakeholder_data_lower.get('phone_number'),
            stakeholder_data_lower.get('location'), added_by_id, added_by_type
        )

        stakeholder_id = self._execute_query(sql, params, commit=True, returning_id_column='stakeholder_id')
        if stakeholder_id:
            logger.info(f"Created stakeholder ID: {stakeholder_id}")
            return {"stakeholder_id": stakeholder_id, "UserType": user_type}
        else:
            raise ValueError("Stakeholder creation failed to return ID.")

    def list_stakeholders(self):
        sql = "SELECT * FROM stakeholders"
        results = self._execute_query(sql, fetch_all=True)
        # Process results for datetime conversion
        if results:
            processed = []
            for item in results:
                p_item = dict(item)
                for key, value in p_item.items():
                    if isinstance(value, (datetime, date)): p_item[key] = value.isoformat()
                processed.append(p_item)
            return processed
        return [] # Return empty list if None

    def get_stakeholder_by_id(self, stakeholder_id):
        try: sid = int(stakeholder_id);
        except ValueError: raise ValueError("Invalid stakeholder_id format.")
        sql = "SELECT * FROM stakeholders WHERE stakeholder_id = %s"
        result = self._execute_query(sql, (sid,), fetch_one=True)
        # Process result
        if result:
             p_result = dict(result)
             for key, value in p_result.items():
                 if isinstance(value, (datetime, date)): p_result[key] = value.isoformat()
             return p_result
        return None # Return None if not found

    def update_stakeholder(self, stakeholder_id, updates):
        try: sid = int(stakeholder_id);
        except ValueError: raise ValueError("Invalid stakeholder_id format.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")

        set_clauses = []; params = [];
        allowed = ['name', 'full_name', 'image', 'is_active', 'rating', 'phone_number', 'location']

        for key, value in updates_lower.items():
            # Skip non-updatable fields
            if key in ['stakeholder_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified']:
                 continue
            if key == 'password':
                 hashed_pw = hash_password(value)
                 set_clauses.append("hashed_password = %s")
                 params.append(hashed_pw)
            elif key in allowed:
                 set_clauses.append(f"{key} = %s")
                 params.append(value)

        if not set_clauses: raise ValueError("No valid fields provided for update.")
        # Assume updated_at exists
        sql = f"UPDATE stakeholders SET {', '.join(set_clauses)}, updated_at = NOW() WHERE stakeholder_id = %s"
        params.append(sid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated stakeholder ID: {stakeholder_id}")

    def login_stakeholder(self, identifier, password):
        sql = "SELECT stakeholder_id, hashed_password, user_type, is_email_verified FROM stakeholders WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)"
        params = (identifier.lower(), identifier.lower())
        try:
             result = self._execute_query(sql, params, fetch_one=True)
             if not result: logger.warning(f"Stakeholder login failed: '{identifier}' not found."); return {'message': 'Invalid credentials or account not found.'}, 401

             stakeholder_id = result['stakeholder_id']; stored_hashed_password = result['hashed_password']; user_type = result.get('user_type', 'stakeholder'); is_verified = result.get('is_email_verified', False)

             if isinstance(stored_hashed_password, str): stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
             elif isinstance(stored_hashed_password, bytes): stored_hashed_pw_bytes = stored_hashed_password
             else: logger.error(f"Invalid hash type for stakeholder {stakeholder_id}"); return {'message': 'Internal login error.'}, 500

             if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                 logger.info(f"Stakeholder login successful for '{identifier}', ID: {stakeholder_id}")
                 # Update last_login
                 update_sql = "UPDATE stakeholders SET last_login = NOW() WHERE stakeholder_id = %s"
                 try: self._execute_query(update_sql, (stakeholder_id,), commit=True)
                 except Exception as update_err: logger.error(f"Failed to update last_login for stakeholder {stakeholder_id}: {update_err}")

                 return {'message': 'Login successful', 'data': {'stakeholder_id': stakeholder_id, 'user_type': user_type, 'verified': is_verified}}, 200
             else: logger.warning(f"Stakeholder login failed: Invalid password for '{identifier}'."); return {'message': 'Invalid credentials.'}, 401

        except ValueError as ve: logger.error(f"Database error during stakeholder login for '{identifier}': {ve}"); return {'message': 'Login service unavailable.'}, 503
        except Exception as e: logger.error(f"Unexpected error during stakeholder login for '{identifier}': {e}", exc_info=True); return {'message': 'An unexpected server error occurred.'}, 500

    def delete_stakeholder(self, stakeholder_id):
        logger.warning(f"Attempting to delete stakeholder ID: {stakeholder_id}")
        sql = "DELETE FROM stakeholders WHERE stakeholder_id = %s"
        try:
            sid = int(stakeholder_id) # Validate ID
            self._execute_query(sql, (sid,), commit=True)
            logger.info(f"Deleted stakeholder ID: {stakeholder_id}")
            return True
        except ValueError as ve: # Catches invalid ID and DB errors
            logger.error(f"Error deleting stakeholder ID {stakeholder_id}: {ve}")
            return False
        except Exception as e:
            logger.error(f"Failed to delete stakeholder ID {stakeholder_id}: {e}", exc_info=True)
            return False

    def update_stakeholder_status(self, stakeholder_id, is_active):
         if not isinstance(is_active, bool): raise ValueError("'is_active' must be a boolean value.")
         try: sid = int(stakeholder_id);
         except ValueError: raise ValueError("Invalid stakeholder_id format.")
         # Assume updated_at exists
         sql = "UPDATE stakeholders SET is_active = %s, updated_at = NOW() WHERE stakeholder_id = %s"
         try:
            self._execute_query(sql, (is_active, sid), commit=True)
            logger.info(f"Updated stakeholder ID {stakeholder_id} active status to {is_active}")
         except ValueError as ve: # Catch DB errors
             logger.error(f"Database error updating status for stakeholder {stakeholder_id}: {ve}")
             raise # Re-raise DB errors
         except Exception as e:
             logger.error(f"Unexpected error updating status for stakeholder {stakeholder_id}: {e}", exc_info=True)
             raise ValueError("Failed to update stakeholder status due to server error.") from e


# --- Herbals ---
# (Herbal class code seems relatively clean, kept as provided)
class Herbals(BaseRepository):
    def create_herbal(self, herbal_data):
        herbal_data_lower = lowercase_keys(herbal_data)
        check_required_fields(herbal_data_lower, ['herbal_name', 'description', 'unit', 'price'])
        user_type = herbal_data_lower.get('user_type', 'herbal')
        sql = """INSERT INTO herbals (herbal_name, description, unit, price, image_url, date_added, added_by, added_by_type, user_type) VALUES (%s, %s, %s, %s, %s, NOW(), %s, %s, %s) RETURNING herbal_id"""
        # Ensure price is float
        try: price_f = float(herbal_data_lower['price']);
        except (ValueError, TypeError): raise ValueError("Invalid price format for herbal.")
        params = (
            herbal_data_lower['herbal_name'], herbal_data_lower['description'], herbal_data_lower['unit'],
            price_f, herbal_data_lower.get('image_url'), herbal_data_lower.get('added_by'),
            herbal_data_lower.get('added_by_type', user_type), user_type
        )
        herbal_id = self._execute_query(sql, params, commit=True, returning_id_column='herbal_id')
        logger.info(f"Created herbal ID: {herbal_id}")
        return {"herbal_id": herbal_id, "UserType": user_type}

    def update_herbal(self, herbal_id, updates):
        try: hid = int(herbal_id);
        except ValueError: raise ValueError("Invalid herbal_id format.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = []
        params = []
        allowed = ['herbal_name', 'description', 'unit', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 set_clauses.append(f"{key} = %s")
                 params.append(value)
        if not set_clauses: raise ValueError("No valid fields for update.")
        sql = f"UPDATE herbals SET {', '.join(set_clauses)} WHERE herbal_id = %s"
        params.append(hid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated herbal ID: {herbal_id}")

    def list_herbals(self):
        results = self._execute_query("SELECT * FROM herbals", fetch_all=True)
        return results or []

    def get_herbal_by_id(self, herbal_id):
        try: hid = int(herbal_id);
        except ValueError: raise ValueError("Invalid herbal_id format.")
        sql = "SELECT * FROM herbals WHERE herbal_id = %s"
        return self._execute_query(sql, (hid,), fetch_one=True)

    def delete_herbal(self, herbal_id):
        logger.warning(f"Attempting to delete herbal ID: {herbal_id}")
        sql = "DELETE FROM herbals WHERE herbal_id = %s"
        try:
            hid = int(herbal_id)
            self._execute_query(sql, (hid,), commit=True)
            logger.info(f"Deleted herbal ID: {herbal_id}")
            return True
        except ValueError as ve:
             logger.error(f"Error deleting herbal ID {herbal_id}: {ve}")
             return False
        except Exception as e:
             logger.error(f"Failed to delete herbal ID {herbal_id}: {e}", exc_info=True)
             return False


# --- Meals ---
# (Meals class code seems relatively clean, kept as provided)
class Meals(BaseRepository):
    def create_meal(self, meal_data):
        meal_data_lower = lowercase_keys(meal_data)
        check_required_fields(meal_data_lower, ['meal_name', 'meal_category', 'ingredients'])
        user_type = meal_data_lower.get('user_type', 'meal')
        sql = """INSERT INTO meals (meal_name, meal_category, ingredients, complementary_dishes, recipe, recipe_link, image_link, goal, dietary_preference, allergies, disease_management, cuisine_preferences, skill_level, prep_time, meal_description, date_added, date_last_edited, added_by, added_by_type, user_type) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW(),NOW(),%s,%s,%s) RETURNING meal_id"""
        params = (
            meal_data_lower['meal_name'], meal_data_lower['meal_category'], meal_data_lower['ingredients'],
            meal_data_lower.get('complementary_dishes'), meal_data_lower.get('recipe'), meal_data_lower.get('recipe_link'),
            meal_data_lower.get('image_link'), meal_data_lower.get('goal'), meal_data_lower.get('dietary_preference'),
            meal_data_lower.get('allergies'), meal_data_lower.get('disease_management'), meal_data_lower.get('cuisine_preferences'),
            meal_data_lower.get('skill_level'), meal_data_lower.get('prep_time'), meal_data_lower.get('meal_description'),
            meal_data_lower.get('added_by'), meal_data_lower.get('added_by_type', user_type), user_type
        )
        meal_id = self._execute_query(sql, params, commit=True, returning_id_column='meal_id')
        logger.info(f"Created meal ID: {meal_id}")
        return {"meal_id": meal_id, "UserType": user_type}

    def update_meal(self, meal_id, updates):
        try:
            mid = str(meal_id)
        except ValueError:
            raise ValueError("Invalid meal_id format.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise ValueError("No updates provided.")
        updates_lower['date_last_edited'] = datetime.now()  # Automatically update edit time

        set_clauses = []
        params = []
        allowed_fields = [
            'meal_name', 'meal_category', 'ingredients', 'complementary_dishes', 'recipe', 'recipe_link',
            'image_link', 'goal', 'dietary_preference', 'allergies', 'disease_management', 'cuisine_preferences',
            'skill_level', 'prep_time', 'meal_description', 'date_last_edited'
        ]
        # Accept both string and numeric values for allowed fields, convert as needed
        for key, value in updates_lower.items():
            if key in allowed_fields:
                # Convert numeric values to string if the DB expects string, except for date_last_edited
                if key == 'date_last_edited':
                    set_clauses.append(f"{key} = %s")
                    params.append(value)
                elif key in ['prep_time', 'skill_level'] and isinstance(value, (int, float)):
                    set_clauses.append(f"{key} = %s")
                    params.append(str(value))
                else:
                    set_clauses.append(f"{key} = %s")
                    params.append(value)

        # Debug log for troubleshooting
        logger.debug(f"update_meal: meal_id={mid}, updates={updates_lower}, set_clauses={set_clauses}, params={params}")

        if not set_clauses:
            raise ValueError("No valid fields for meal update.")
        sql = f"UPDATE meals SET {', '.join(set_clauses)} WHERE meal_id = %s"
        params.append(mid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated meal ID: {meal_id}")

    def list_meals(self):
        """
        Fetch all meals from the database and include real ingredient names and complementary dishes.
        """
        sql_query = """
        WITH MealDetails AS (
            SELECT
                m.meal_id,
                m.meal_name,
                m.meal_category,
                m.recipe,
                m.recipe_link,
                m.image_link,
                m.goal,
                m.dietary_preference,
                m.allergies,
                m.disease_management,
                m.cuisine_preferences,
                m.skill_level,
                m.prep_time,
                m.meal_description
            FROM meals m
        )
        SELECT
            md.*,
            COALESCE((SELECT STRING_AGG(p.produce_name, ', ')
             FROM meal_ingredients i
             JOIN produce p ON i.produce_id = p.produce_id
             WHERE i.meal_id = md.meal_id), '') AS ingredients,
            COALESCE((SELECT STRING_AGG(mc.meal_name, ', ')
             FROM meal_complementaries mc_link
             JOIN meals mc ON mc_link.complementary_dish_id = mc.meal_id
             WHERE mc_link.meal_id = md.meal_id), '') AS complementary_dishes
        FROM MealDetails md;
        """
        try:
            results = self._execute_query(sql_query, fetch_all=True)
            if not results:
                return []
            meal_recommendations = []
            for row in results:
                meal = dict(row)
                # Rename keys to match the provided structure (capitalize as needed)
                meal_dict = {
                    "Meal_id": meal.get("meal_id"),
                    "Meal_name": meal.get("meal_name"),
                    "Meal_category": meal.get("meal_category"),
                    "Recipe": meal.get("recipe"),
                    "Recipe_link": meal.get("recipe_link"),
                    "Image_link": meal.get("image_link"),
                    "Goal": meal.get("goal"),
                    "Dietary_preference": meal.get("dietary_preference"),
                    "Allergies": meal.get("allergies"),
                    "Disease_management": meal.get("disease_management"),
                    "Cuisine_preferences": meal.get("cuisine_preferences"),
                    "Skill_level": meal.get("skill_level"),
                    "Prep_time": meal.get("prep_time"),
                    "Meal_description": meal.get("meal_description"),
                    "Ingredients": meal.get("ingredients") if meal.get("ingredients") else "",
                    "Complementary_dishes": meal.get("complementary_dishes") if meal.get("complementary_dishes") else "",
                    "Price": 10_000  # Default price
                }
                meal_recommendations.append(meal_dict)
            return meal_recommendations
        except Exception as e:
            # Optionally log error if logger is available
            # logger.error(f"Error fetching meal recommendations: {e}")
            return []

    def get_meal_by_id(self, meal_id):
        try: mid = str(meal_id);
        except ValueError: raise ValueError("Invalid meal_id format.")
        sql = "SELECT * FROM meals WHERE meal_id = %s" # Simple get
        return self._execute_query(sql, (mid,), fetch_one=True)

    def delete_meal(self, meal_id):
        logger.warning(f"Attempting to delete meal ID: {meal_id}")
        sql = "DELETE FROM meals WHERE meal_id = %s"
        try:
            mid = str(meal_id)
            self._execute_query(sql, (mid,), commit=True)
            logger.info(f"Deleted meal ID: {meal_id}")
            return True
        except ValueError as ve:
            logger.error(f"Error deleting meal ID {meal_id}: {ve}")
            return False
        except Exception as e:
            logger.error(f"Failed to delete meal ID {meal_id}: {e}", exc_info=True)
            return False

# --- Produce ---
# (Produce class code seems relatively clean, kept as provided)
class Produce(BaseRepository):
    def create_produce(self, produce_data):
        produce_data_lower = lowercase_keys(produce_data)
        check_required_fields(produce_data_lower, ['produce_name', 'unit_grams', 'calories'])
        user_type = produce_data_lower.get('user_type', 'produce')
        sql = """INSERT INTO produce (produce_name, unit_grams, calories, cholesterol, carbohydrates, proteins, fats, fiber, sugars, meal_type, source, nutritional_info, date_added, date_last_edited, added_by, added_by_type, user_type) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW(),NOW(),%s,%s,%s) RETURNING produce_id"""
        # Ensure numeric types are correct
        try:
             params = (
                produce_data_lower['produce_name'], float(produce_data_lower['unit_grams']), float(produce_data_lower['calories']),
                produce_data_lower.get('cholesterol'), produce_data_lower.get('carbohydrates'), produce_data_lower.get('proteins'),
                produce_data_lower.get('fats'), produce_data_lower.get('fiber'), produce_data_lower.get('sugars'),
                produce_data_lower.get('meal_type'), produce_data_lower.get('source'), produce_data_lower.get('nutritional_info'),
                produce_data_lower.get('added_by'), produce_data_lower.get('added_by_type', user_type), user_type
            )
        except (ValueError, TypeError) as e:
            raise ValueError(f"Invalid numeric format in produce data: {e}") from e
        produce_id = self._execute_query(sql, params, commit=True, returning_id_column='produce_id')
        logger.info(f"Created produce ID: {produce_id}")
        return {"produce_id": produce_id, "UserType": user_type}

    def update_produce(self, produce_id, updates):
        # Accept string IDs (alphanumeric, e.g., "P166")
        pid = str(produce_id)
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        updates_lower['date_last_edited'] = datetime.now()

        set_clauses = []
        params = []
        allowed = ['produce_name', 'unit_grams', 'calories', 'cholesterol', 'carbohydrates', 'proteins', 'fats', 'fiber', 'sugars', 'meal_type', 'source', 'nutritional_info', 'date_last_edited']
        for key, value in updates_lower.items():
             if key in allowed:
                 set_clauses.append(f"{key} = %s")
                 params.append(value)

        if not set_clauses: raise ValueError("No valid fields for produce update.")
        sql = f"UPDATE produce SET {', '.join(set_clauses)} WHERE produce_id = %s"
        params.append(pid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated produce ID: {produce_id}")

    def list_produce(self):
        results = self._execute_query("SELECT * FROM produce", fetch_all=True)
        return results or []

    def get_produce_by_id(self, produce_id):
        try: pid = int(produce_id);
        except ValueError: raise ValueError("Invalid produce_id format.")
        sql = "SELECT * FROM produce WHERE produce_id = %s"
        return self._execute_query(sql, (pid,), fetch_one=True)

    def delete_produce(self, produce_id):
        logger.warning(f"Attempting to delete produce ID: {produce_id}")
        sql = "DELETE FROM produce WHERE produce_id = %s"
        try:
            pid = int(produce_id)
            self._execute_query(sql, (pid,), commit=True)
            logger.info(f"Deleted produce ID: {produce_id}")
            return True
        except ValueError as ve:
            logger.error(f"Error deleting produce ID {produce_id}: {ve}")
            return False
        except Exception as e:
            logger.error(f"Failed to delete produce ID {produce_id}: {e}", exc_info=True)
            return False

# --- Gadgets ---
# (Gadget class code seems relatively clean, kept as provided)
class Gadgets(BaseRepository):
    def create_gadget(self, gadget_data):
        gadget_data_lower = lowercase_keys(gadget_data)
        check_required_fields(gadget_data_lower, ['gadget_name', 'description', 'price'])
        user_type = gadget_data_lower.get('user_type', 'gadget')
        sql = """INSERT INTO gadgets (gadget_name, description, brand, model, price, image_url, date_added, added_by, added_by_type, user_type) VALUES (%s,%s,%s,%s,%s,%s,NOW(),%s,%s,%s) RETURNING gadget_id"""
        try: price_f = float(gadget_data_lower['price']);
        except (ValueError, TypeError): raise ValueError("Invalid price format for gadget.")
        params = (
            gadget_data_lower['gadget_name'], gadget_data_lower['description'], gadget_data_lower.get('brand'),
            gadget_data_lower.get('model'), price_f, gadget_data_lower.get('image_url'),
            gadget_data_lower.get('added_by'), gadget_data_lower.get('added_by_type', user_type), user_type
        )
        gadget_id = self._execute_query(sql, params, commit=True, returning_id_column='gadget_id')
        logger.info(f"Created gadget ID: {gadget_id}")
        return {"gadget_id": gadget_id, "UserType": user_type}

    def update_gadget(self, gadget_id, updates):
        try: gid = int(gadget_id);
        except ValueError: raise ValueError("Invalid gadget_id format.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = []
        params = []
        allowed = ['gadget_name', 'description', 'brand', 'model', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 set_clauses.append(f"{key} = %s")
                 params.append(value)
        if not set_clauses: raise ValueError("No valid fields for update.")
        sql = f"UPDATE gadgets SET {', '.join(set_clauses)} WHERE gadget_id = %s"
        params.append(gid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated gadget ID: {gadget_id}")

    def list_gadgets(self):
        results = self._execute_query("SELECT * FROM gadgets", fetch_all=True)
        return results or []

    def get_gadget_by_id(self, gadget_id):
        try: gid = int(gadget_id);
        except ValueError: raise ValueError("Invalid gadget_id format.")
        sql = "SELECT * FROM gadgets WHERE gadget_id = %s"
        return self._execute_query(sql, (gid,), fetch_one=True)

    def delete_gadget(self, gadget_id):
        logger.warning(f"Attempting to delete gadget ID: {gadget_id}")
        sql = "DELETE FROM gadgets WHERE gadget_id = %s"
        try:
            gid = int(gadget_id)
            self._execute_query(sql, (gid,), commit=True)
            logger.info(f"Deleted gadget ID: {gadget_id}")
            return True
        except ValueError as ve:
            logger.error(f"Error deleting gadget ID {gadget_id}: {ve}")
            return False
        except Exception as e:
            logger.error(f"Failed to delete gadget ID {gadget_id}: {e}", exc_info=True)
            return False

# --- Spices ---
# (Spice class code seems relatively clean, kept as provided)
class Spices(BaseRepository):
    def create_spice(self, spice_data):
        spice_data_lower = lowercase_keys(spice_data)
        # Original had 'added_by' required, assuming it might be optional
        check_required_fields(spice_data_lower, ['spice_name', 'description', 'price'])
        user_type = spice_data_lower.get('user_type', 'spice')
        sql = """INSERT INTO spices (spice_name, description, unit, price, image_url, date_added, added_by, added_by_type, user_type) VALUES (%s,%s,%s,%s,%s,NOW(),%s,%s,%s) RETURNING spice_id"""
        try: price_f = float(spice_data_lower['price']);
        except (ValueError, TypeError): raise ValueError("Invalid price format for spice.")
        params = (
            spice_data_lower['spice_name'], spice_data_lower['description'], spice_data_lower.get('unit'),
            price_f, spice_data_lower.get('image_url'), spice_data_lower.get('added_by'), # Allow None
            spice_data_lower.get('added_by_type', user_type), user_type
        )
        spice_id = self._execute_query(sql, params, commit=True, returning_id_column='spice_id')
        logger.info(f"Created spice ID: {spice_id}")
        return {"spice_id": spice_id, "UserType": user_type}

    def update_spice(self, spice_id, updates):
        try: sid = int(spice_id);
        except ValueError: raise ValueError("Invalid spice_id format.")
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = []
        params = []
        allowed = ['spice_name', 'description', 'unit', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 set_clauses.append(f"{key} = %s")
                 params.append(value)
        if not set_clauses: raise ValueError("No valid fields for update.")
        sql = f"UPDATE spices SET {', '.join(set_clauses)} WHERE spice_id = %s"
        params.append(sid)
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated spice ID: {spice_id}")

    def list_spices(self):
        results = self._execute_query("SELECT * FROM spices", fetch_all=True)
        return results or []

    def get_spice_by_id(self, spice_id):
        try: sid = int(spice_id);
        except ValueError: raise ValueError("Invalid spice_id format.")
        sql = "SELECT * FROM spices WHERE spice_id = %s"
        return self._execute_query(sql, (sid,), fetch_one=True)

    def delete_spice(self, spice_id):
        logger.warning(f"Attempting to delete spice ID: {spice_id}")
        sql = "DELETE FROM spices WHERE spice_id = %s"
        try:
            sid = int(spice_id)
            self._execute_query(sql, (sid,), commit=True)
            logger.info(f"Deleted spice ID: {spice_id}")
            return True
        except ValueError as ve:
            logger.error(f"Error deleting spice ID {spice_id}: {ve}")
            return False
        except Exception as e:
            logger.error(f"Failed to delete spice ID {spice_id}: {e}", exc_info=True)
            return False




import json
from datetime import datetime, date
import logging

logger = logging.getLogger(__name__)

# Assuming BaseRepository is defined elsewhere
import json
from datetime import datetime, date
import logging

logger = logging.getLogger(__name__)

class Orders(BaseRepository):
    ALLOWED_ORDER_TYPES = {'meal', 'supplement', 'gig', 'herbal', 'gadget', 'spice', 'produce'}
    ALLOWED_ORDER_STATUSES = {'cancelled', 'assigned', 'delivered', 'shipped', 'preparing', 'confirmed', 'pending', 'accepted', 'dispatched', 'picked up', 'delivering'}
    ALLOWED_PAYMENT_STATUSES = {'failed', 'refunded', 'paid', 'pending', 'completed'}
    ALLOWED_PAYMENT_MODES = {'cash', 'momo', 'mobile money', 'Airtel Card', 'paypal', 'stripe', 'debit card', 'credit card'}

    def _validate_product_id(self, product_id, order_type):
        """Validates that the product_id exists in the appropriate table based on order_type."""
        # if not product_id:
        #     raise ValueError(f"product_id is required for {order_type} orders.")
        
        # order_type_l = order_type.lower().strip()
        # if order_type_l == 'meal':
        #     sql = "SELECT meal_id FROM meals WHERE meal_id = %s"
        # elif order_type_l == 'supplement':
        #     sql = "SELECT supplement_id FROM supplements WHERE supplement_id = %s"
        # elif order_type_l == 'herbal':
        #     sql = "SELECT herbal_id FROM herbals WHERE herbal_id = %s"
        # elif order_type_l == 'gadget':
        #     sql = "SELECT gadget_id FROM gadgets WHERE gadget_id = %s"
        # elif order_type_l == 'spice':
        #     sql = "SELECT spice_id FROM spices WHERE spice_id = %s"
        # elif order_type_l == 'produce':
        #     sql = "SELECT produce_id FROM produce WHERE produce_id = %s"
        # elif order_type_l == 'gig':
        #     # Skip validation for gigs since there's no separate gigs table
        #     return
        # else:
        #     raise ValueError(f"Invalid order_type: '{order_type}'.")

        # try:
        #     product_id_int = int(product_id)
        #     result = self._execute_query(sql, (product_id_int,), fetch_all=False)
        # except (ValueError, TypeError):
        #     result = self._execute_query(sql, (str(product_id),), fetch_all=False)
        # if not result:
        #     raise ValueError(f"Invalid product_id: '{product_id}' does not exist for order_type '{order_type}'.")
        if not product_id:
            raise ValueError(f"product_id is required for {order_type} orders.")
        


    def create_order(self, user_id, order_type, order_status="pending", payment_status="pending", payment_mode="cash",
                     delivery_address=None, notes=None, total_price=0.0, amount_paid=0.0, quantity=1,
                     product_id=None, chef_id=None, producer_id=None, transporter_id=None, transaction_id=None, 
                     items=None):  # Accepting items parameter

        order_type_l = str(order_type).lower().strip()

        # Validate gig_details for gig orders
        gig_details_json = None
        if order_type_l == 'gig':
            if not items or not isinstance(items, list) or len(items) == 0:
                raise ValueError("items parameter with gig_details is required for gig orders.")
            gig_details = items[0].get('gig_details', {})
            if not gig_details or not isinstance(gig_details, dict):
                raise ValueError("Valid gig_details dictionary is required for gig orders.")
            try:
                gig_details_json = json.dumps(gig_details)  # Convert gig_details to JSON
            except (TypeError, ValueError) as e:
                raise ValueError(f"Invalid gig_details format: {e}")
        else:
            # Validate product_id for non-gig orders
            self._validate_product_id(product_id, order_type)

        order_status_l = str(order_status).lower().strip()
        payment_status_l = str(payment_status).lower().strip()
        payment_mode_l = str(payment_mode).lower().strip()

        if not user_id:
            raise ValueError("user_id is required.")
        if not order_type_l:
            raise ValueError("order_type is required.")
        if order_type_l not in self.ALLOWED_ORDER_TYPES:
            raise ValueError(f"Invalid order_type: '{order_type}'. Allowed: {self.ALLOWED_ORDER_TYPES}")
        if order_status_l not in self.ALLOWED_ORDER_STATUSES:
            raise ValueError(f"Invalid order_status: '{order_status}'. Allowed: {self.ALLOWED_ORDER_STATUSES}")
        if payment_status_l not in self.ALLOWED_PAYMENT_STATUSES:
            raise ValueError(f"Invalid payment_status: '{payment_status}'. Allowed: {self.ALLOWED_PAYMENT_STATUSES}")
        if payment_mode_l != 'airtel card' and payment_mode_l not in self.ALLOWED_PAYMENT_MODES:
            is_airtel_card = str(payment_mode).strip() == 'Airtel Card'
            if not is_airtel_card and payment_mode_l not in self.ALLOWED_PAYMENT_MODES:
                raise ValueError(f"Invalid payment_mode: '{payment_mode}'. Allowed: {self.ALLOWED_PAYMENT_MODES}")
            if is_airtel_card:
                payment_mode_l = 'Airtel Card'
        
        delivery_address_s = delivery_address or "Not specified"
        notes_s = notes or "No special instructions"

        try:
            price_f = float(total_price)
            paid_f = float(amount_paid)
            qty_i = int(quantity)
            user_id_i = int(user_id)
        except (ValueError, TypeError) as e:
            raise ValueError(f"Invalid numeric value for order field: {e}") from e

        prod_id_s = str(product_id) if product_id is not None else None
        try:
            chef_id_i = int(chef_id) if chef_id is not None else None
        except (ValueError, TypeError):
            raise ValueError("Invalid chef_id format.")
        try:
            producer_id_i = int(producer_id) if producer_id is not None else None
        except (ValueError, TypeError):
            raise ValueError("Invalid producer_id format.")
        try:
            transporter_id_i = int(transporter_id) if transporter_id is not None else None
        except (ValueError, TypeError):
            raise ValueError("Invalid transporter_id format.")

        sql = """INSERT INTO orders (user_id, order_type, product_id, chef_id, producer_id, transporter_id, order_date, delivery_address, order_status, total_price, notes, payment_status, payment_mode, amount_paid, transaction_id, quantity, gig_details) 
                 VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) 
                 RETURNING order_id"""

        params = (user_id_i, order_type_l, prod_id_s, chef_id_i, producer_id_i, transporter_id_i,
                  delivery_address_s, order_status_l, price_f, notes_s, payment_status_l, payment_mode_l,
                  paid_f, transaction_id, qty_i, gig_details_json)

        try:
            order_id = self._execute_query(sql, params, commit=True, returning_id_column='order_id')
            if order_id:
                logger.info(f"Order created: {order_id}")
                return {"message": "Order created successfully", "order_id": order_id, "success": True}
            else:
                raise ValueError("Order creation failed: Did not return order_id.")
        except ValueError as ve:
            logger.error(f"Error creating order: {ve}", exc_info=False)
            return {"message": str(ve), "order_id": None, "success": False}
        except Exception as e:
            logger.error(f"Unexpected error creating order: {e}", exc_info=True)
            err_msg = "Server error occurred while creating the order."
            return {"message": err_msg, "order_id": None, "success": False}

    def read_orders(self, order_id=None, chef_id=None, producer_id=None, user_id=None, transporter_id=None):
        sql = """
            WITH MealDetails AS (
                SELECT
                    m.meal_id,
                    m.meal_name,
                    COALESCE(STRING_AGG(DISTINCT p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
                FROM meals m
                LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
                LEFT JOIN produce p ON mi.produce_id = p.produce_id
                GROUP BY m.meal_id, m.meal_name
            ),
            SupplementDetails AS (
                SELECT
                    supplement_id,
                    supplement_name AS product_name
                FROM supplements
            ),
            HerbalDetails AS (
                SELECT
                    herbal_id,
                    herbal_name AS product_name
                FROM herbals
            ),
            GadgetDetails AS (
                SELECT
                    gadget_id,
                    gadget_name AS product_name
                FROM gadgets
            ),
            SpiceDetails AS (
                SELECT
                    spice_id,
                    spice_name AS product_name
                FROM spices
            ),
            ProduceDetails AS (
                SELECT
                    produce_id,
                    produce_name AS product_name
                FROM produce
            )
            SELECT
                o.order_id, o.user_id, o.order_type, o.product_id, o.chef_id, o.producer_id, o.transporter_id,
                o.order_date, o.delivery_address, o.order_status, o.total_price, o.notes,
                o.payment_status, o.payment_mode, o.amount_paid, o.transaction_id, o.quantity,
                md.meal_name,
                md.ingredients,
                producer.name AS producer_name,
                producer.location AS producer_address,
                chef.name AS chef_name,
                transporter.name AS transporter_name,
                o.gig_details,
                COALESCE(
                    CASE WHEN o.order_type = 'meal' THEN md.meal_name END,
                    CASE WHEN o.order_type = 'supplement' THEN supd.product_name END,
                    CASE WHEN o.order_type = 'herbal' THEN hd.product_name END,
                    CASE WHEN o.order_type = 'gadget' THEN gd.product_name END,
                    CASE WHEN o.order_type = 'spice' THEN sd.product_name END,
                    CASE WHEN o.order_type = 'produce' THEN prod.product_name END,
                    'Unknown'
                ) AS product_name
            FROM orders o
            LEFT JOIN MealDetails md ON o.product_id::varchar = md.meal_id::varchar AND o.order_type = 'meal'
            LEFT JOIN SupplementDetails supd ON o.product_id::varchar = supd.supplement_id::varchar AND o.order_type = 'supplement'
            LEFT JOIN HerbalDetails hd ON o.product_id::varchar = hd.herbal_id::varchar AND o.order_type = 'herbal'
            LEFT JOIN GadgetDetails gd ON o.product_id::varchar = gd.gadget_id::varchar AND o.order_type = 'gadget'
            LEFT JOIN SpiceDetails sd ON o.product_id::varchar = sd.spice_id::varchar AND o.order_type = 'spice'
            LEFT JOIN ProduceDetails prod ON o.product_id::varchar = prod.produce_id::varchar AND o.order_type = 'produce'
            LEFT JOIN producers producer ON o.producer_id = producer.producer_id
            LEFT JOIN chefs chef ON o.chef_id = chef.chefid
            LEFT JOIN transporters transporter ON o.transporter_id = transporter.transporter_id
            WHERE 1=1
        """
        params = []

        def _safe_int(val, field_name="ID"):
            if val is None: return None
            try: return int(val)
            except (ValueError, TypeError): raise ValueError(f"Invalid format for {field_name}: '{val}'. Expected an integer.")

        try:
            if order_id is not None: sql += " AND o.order_id = %s"; params.append(_safe_int(order_id, "order_id"))
            if chef_id is not None: sql += " AND o.chef_id = %s"; params.append(_safe_int(chef_id, "chef_id"))
            if producer_id is not None: sql += " AND o.producer_id = %s"; params.append(_safe_int(producer_id, "producer_id"))
            if user_id is not None: sql += " AND o.user_id = %s"; params.append(_safe_int(user_id, "user_id"))
            if transporter_id is not None: sql += " AND o.transporter_id = %s"; params.append(_safe_int(transporter_id, "transporter_id"))
        except ValueError as e:
            logger.error(f"Error reading orders due to invalid ID format: {e}")
            raise

        sql += " ORDER BY o.order_date DESC"

        results = self._execute_query(sql, tuple(params), fetch_all=True)
        if results is None: return []

        # Process datetime objects and JSONB fields
        processed_results = []
        for order in results:
            processed_order = dict(order)
            for key, value in processed_order.items():
                if isinstance(value, (datetime, date)):
                    processed_order[key] = value.isoformat()
                if key == 'gig_details' and value:
                    try:
                        processed_order['gig_details'] = json.loads(value)
                    except (json.JSONDecodeError, TypeError):
                        logger.warning(f"Failed to parse gig_details for order_id {processed_order.get('order_id')}")
                        processed_order['gig_details'] = None
            processed_results.append(processed_order)

        logger.info(f"Retrieved {len(processed_results)} orders matching criteria.")
        return processed_results

    def update_order_status(self, order_id, new_status):
        """Updates the status of a specific order."""
        new_status_l = str(new_status).lower()
        if new_status_l not in self.ALLOWED_ORDER_STATUSES:
            raise ValueError(f"Invalid target order status: {new_status}")
        sql = "UPDATE orders SET order_status = %s, updated_at = NOW() WHERE order_id = %s"
        try:
            self._execute_query(sql, (new_status_l, order_id), commit=True)
            logger.info(f"Updated order ID {order_id} status to {new_status_l}")
            return True
        except Exception as e:
            logger.error(f"Failed to update status for order ID {order_id}: {e}", exc_info=True)
            return False

    def delete_order(self, order_id):
        """Deletes an order record. Usually not recommended, prefer cancelling."""
        logger.warning(f"Attempting to delete order ID: {order_id}")
        sql = "DELETE FROM orders WHERE order_id = %s"
        try:
            self._execute_query(sql, (order_id,), commit=True)
            logger.info(f"Deleted order ID: {order_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete order ID {order_id}: {e}", exc_info=True)
            return False
        
# --- Calculation Logic Class ---
class CalculationLogic:
    def calculate_bmi(self, weight, height):
        # Check for valid height first to avoid division by zero
        if not height or height == 0:
            return 0.0
        try:
            # Ensure inputs are numeric
            weight_f = float(weight)
            height_f = float(height)
            height_in_meters = height_f / 100.0
            # Calculate BMI, avoiding division by zero if height was 0 (redundant check but safe)
            if height_in_meters == 0:
                return 0.0
            return round(weight_f / (height_in_meters ** 2), 1)
        except (ValueError, TypeError) as e:
            logger.warning(f"Invalid input for BMI calc: weight={weight}, height={height}. Error: {e}")
            return 0.0

    def calculate_bmi_category(self, bmi):
        try:
            bmi_f = float(bmi) # Ensure bmi is float
        except (ValueError, TypeError):
            logger.warning(f"Invalid BMI value: {bmi}")
            return 'Unknown' # Handle invalid BMI input
        if bmi_f < 18.5:
            return 'Underweight'
        elif 18.5 <= bmi_f < 24.9:
            return 'Normal weight'
        elif 25 <= bmi_f < 29.9:
            return 'Overweight'
        else: # Covers bmi_f >= 30
            return 'Obesity'

    def calculate_ideal_weight(self, height, sex):
        try:
            height_f = float(height) # Ensure height is float
        except (ValueError, TypeError):
            logger.warning(f"Invalid height for Ideal Weight: {height}")
            return 0.0 # Return 0 on invalid height input

        sex_lower = str(sex).strip().lower() if sex else 'unknown'
        ideal_weight_kg = 0.0 # Initialize

        # Use simplified formula from original code, with proper conditional structure
        if sex_lower == 'male':
             ideal_weight_kg = 50 + 0.91 * (height_f - 152)
        elif sex_lower == 'female':
             ideal_weight_kg = 45.5 + 0.91 * (height_f - 152)
        else:
             # Original default was 47.75 + 0.91 * (height - 152) which is an average-like start
             logger.warning(f"Unknown sex '{sex}' for Ideal Weight, using average/default formula.")
             ideal_weight_kg = 47.75 + 0.91 * (height_f - 152)

        return round(max(ideal_weight_kg, 0), 1) # Ensure non-negative and round

    def convert_age_range_to_age(self, age_range):
        # Handle integer/float directly
        if isinstance(age_range, (int, float)):
            return int(age_range)
        # Handle string ranges
        if isinstance(age_range, str):
            try:
                if '-' in age_range:
                    age_min, age_max = map(int, age_range.split('-'))
                    return (age_min + age_max) // 2 # Return midpoint
                else:
                    return int(age_range) # Try converting single string number
            except ValueError:
                # Catch conversion errors from map(int, ...) or int()
                logger.warning(f"Error parsing age range string '{age_range}', using default 30.")
                return 30 # Default age on parsing error
        else:
            # Invalid type, log warning and use default
            logger.warning(f"Invalid age range type '{type(age_range)}', using default 30.")
            return 30 # Default age for other types

    def calculate_bmr(self, weight, height, age_range, sex):
        try:
            weight_f = float(weight)
            height_f = float(height)
            age = self.convert_age_range_to_age(age_range) # Use helper
            sex_lower = str(sex).strip().lower() if sex else 'unknown'

            # Using Mifflin-St Jeor Equation (or similar structure)
            if sex_lower == 'male':
                bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) + 5
            elif sex_lower == 'female':
                bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) - 161
            else:
                 logger.warning(f"Unknown sex '{sex}' for BMR, using general/male formula.")
                 bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) + 5 # Default to male formula

            return round(max(bmr, 0)) # Ensure non-negative
        except (ValueError, TypeError) as e:
             logger.warning(f"Invalid input for BMR calc: w={weight}, h={height}, age={age_range}, sex={sex}. Error: {e}")
             return 0 # Return 0 on invalid input

    def calculate_daily_calories(self, bmr, activity_level):
        try:
            bmr_f = float(bmr) # Ensure bmr is float
        except (ValueError, TypeError):
            logger.warning(f"Invalid BMR for TDEE calc: {bmr}")
            return 0

        activity_level_lower = str(activity_level).strip().lower().replace(" ", "_") if activity_level else 'sedentary'

        # Standard Activity Multipliers
        activity_multiplier = {
            'sedentary': 1.2, 'lightly_active': 1.375, 'moderately_active': 1.55,
            'very_active': 1.725, 'extremely_active': 1.9, 'extra_active': 1.9, # These might be duplicates or represent slightly different levels
        }
        multiplier = activity_multiplier.get(activity_level_lower, 1.2) # Default to sedentary
        if activity_level_lower not in activity_multiplier:
             logger.warning(f"Unknown activity level '{activity_level}', using sedentary multiplier (1.2).")

        return round(bmr_f * multiplier)

# --- Meal Recommendation Classes ---
class BaseMealRecommender:
    def __init__(self, user_id: int):
        if not isinstance(user_id, int): raise TypeError("user_id must be an integer.")
        self.user_id = user_id
        self._users_crud = AuthenticationAndUsers() # Instantiate necessary repositories
        self._produce_crud = Produce()
        self.user_preferences = self._get_user_preferences() # Fetch data on initialization
        self.user_metrics = self._get_user_metrics()
        self._validate_user_data() # Validate fetched data

    def _get_db_connection(self):
        return get_db_connection() # Use the global function

    def _validate_user_data(self):
        if not self.user_preferences:
            logger.warning(f"RecSys({self.__class__.__name__}) No preferences found for User ID: {self.user_id}.")
        if not self.user_metrics:
            logger.warning(f"RecSys({self.__class__.__name__}) No metrics found for User ID: {self.user_id}.")

    def _execute_query(self, query: str, params: tuple = (), fetch_one: bool = False, fetch_all: bool = False) -> Optional[Any]:
        repo = BaseRepository() # Use a temporary BaseRepository instance
        try:
            # Use named arguments for clarity
            return repo._execute_query(query, params=params, fetch_one=fetch_one, fetch_all=fetch_all)
        except ValueError as e:
            # Handle potential ConnectionError re-raised as ValueError
            if "Failed to get database connection" in str(e):
                raise ConnectionError(str(e)) from e
            raise # Re-raise other ValueErrors

    def _get_user_preferences(self) -> Optional[Dict]:
        try:
             prefs_list = self._users_crud.list_preferences(user_id=self.user_id)
             if not prefs_list: return None
             result = prefs_list[0] # Assume only one preference record per user
             # Clean and normalize preference data
             return {
                "goals": result.get('goals', '').strip().lower() or None,
                "diet_type": result.get('diet_type', '').strip().lower() or None,
                "food_restrictions": deserialize_list(result.get('food_restrictions', '')), # Deserialize lists
                "cuisine_preferences": deserialize_list(result.get('cuisine_preferences', '')) # Deserialize lists
             }
        except Exception as e: # Catch errors during fetching or processing
             logger.error(f"Error fetching preferences for user {self.user_id}: {e}", exc_info=True)
             return None

    def _get_user_metrics(self) -> Optional[Dict]:
        try:
             metrics_list = self._users_crud.list_metrics(user_id=self.user_id)
             if not metrics_list: return None
             metrics = metrics_list[0] # Assume latest or single metrics record
             # Normalize relevant fields
             metrics['sex'] = metrics.get('sex', 'male').strip().lower() # Default sex if missing
             metrics['activity_level'] = metrics.get('activity_level', 'sedentary').strip().lower() # Default activity
             # Potentially convert numeric fields here if they come as strings
             return metrics
        except Exception as e: # Catch errors during fetching or processing
             logger.error(f"Error fetching metrics for user {self.user_id}: {e}", exc_info=True)
             return None

    def _fetch_produce_data(self, produce_names: List[str]) -> Dict[str, Dict]:
        if not produce_names: return {}
        try:
            all_produce = self._produce_crud.list_produce()
            produce_dict = {}
            if all_produce:
                # Create a lookup dictionary with lowercase names
                name_lookup = {}
                for p in all_produce:
                    if p and 'produce_name' in p and p['produce_name']: # Check if produce_name exists and is not empty/None
                        name_lookup[str(p['produce_name']).lower()] = p # Convert key to string and lower
                    else:
                        logger.warning(f"RecSys Produce data missing 'produce_name' or is invalid: {p}")

                for name_req in produce_names:
                    name_req_lower = name_req.strip().lower()
                    if name_req_lower in name_lookup:
                        p_data = name_lookup[name_req_lower]
                        # Extract and default nutritional values safely, ensuring float conversion
                        produce_dict[name_req_lower] = {
                            "calories": float(p_data.get('calories', 0.0) or 0.0),
                            "unit_grams": float(p_data.get('unit_grams', 100.0) or 100.0), # Default 100g
                            "cholesterol": float(p_data.get('cholesterol', 0.0) or 0.0),
                            "carbohydrates": float(p_data.get('carbohydrates', 0.0) or 0.0),
                            "proteins": float(p_data.get('proteins', 0.0) or 0.0),
                            "fats": float(p_data.get('fats', 0.0) or 0.0),
                            "fiber": float(p_data.get('fiber', 0.0) or 0.0),
                            "sugars": float(p_data.get('sugars', 0.0) or 0.0),
                        }
            return produce_dict
        except Exception as e:
            logger.error(f"Error fetching produce data for user {self.user_id}: {e}", exc_info=True)
            return {} # Return empty on error

    def _calculate_meal_nutrition(self, ingredients_str: Optional[str], produce_data_cache: Dict[str, Dict]) -> Dict[str, float]:
        # Initialize nutrition dictionary
        nutrition = {"calories": 0.0, "proteins": 0.0, "carbohydrates": 0.0, "fats": 0.0, "fiber": 0.0, "sugars": 0.0, "cholesterol": 0.0, "total_grams": 0.0}
        if not ingredients_str or not isinstance(ingredients_str, str):
            return nutrition # Return zeros if no ingredients string

        # Split ingredients string and process each
        ingredient_names = [name.strip().lower() for name in ingredients_str.split(",") if name.strip()]

        for name_lower in ingredient_names:
            data = produce_data_cache.get(name_lower)
            if data:
                try:
                    # Safely access keys and default to 0.0 if missing or invalid
                    grams = data.get('unit_grams', 0.0) # Default grams to 0 if missing/invalid
                    nutrition["calories"] += float(data.get('calories', 0.0) or 0.0)
                    nutrition["proteins"] += float(data.get('proteins', 0.0) or 0.0)
                    nutrition["carbohydrates"] += float(data.get('carbohydrates', 0.0) or 0.0)
                    nutrition["fats"] += float(data.get('fats', 0.0) or 0.0)
                    nutrition["fiber"] += float(data.get('fiber', 0.0) or 0.0)
                    nutrition["sugars"] += float(data.get('sugars', 0.0) or 0.0)
                    nutrition["cholesterol"] += float(data.get('cholesterol', 0.0) or 0.0)
                    nutrition["total_grams"] += float(grams or 0.0) # Ensure grams is float

                except (TypeError, ValueError) as e:
                    logger.warning(f"RecSys NutriCalc Error for ingredient '{name_lower}', User:{self.user_id}. Data: {data}, Error: {e}")
            else:
                logger.warning(f"RecSys NutriData missing for ingredient '{name_lower}', User:{self.user_id}.")

        # Round final values
        for key in nutrition:
            nutrition[key] = round(nutrition[key], 1)
        return nutrition

class MealRecommendation1(BaseMealRecommender):
    # V1 focuses on basic preference filtering

    def fetch_all_meals_with_ingredients(self):
        # Fetches meals and attempts to get ingredients as a comma-separated string
        query = """
            SELECT m.*, COALESCE(STRING_AGG(p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
            FROM meals m
            LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
            LEFT JOIN produce p ON mi.produce_id = p.produce_id
            GROUP BY m.meal_id -- Group by all columns from meals.* required by SQL standard
                   , m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link, m.goal, m.dietary_preference, m.allergies, m.disease_management, m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description, m.date_added, m.date_last_edited, m.added_by, m.added_by_type, m.user_type
        """
        try:
             all_meals = self._execute_query(query, fetch_all=True)
             if not all_meals: return []

             # Fetch produce data needed for nutrition calculation (even if V1 doesn't use it heavily)
             all_ingredient_names = set()
             for meal in all_meals:
                 ingredients_str = meal.get('ingredients')
                 if ingredients_str:
                     # Ensure string conversion before splitting and processing
                     all_ingredient_names.update(name.strip().lower() for name in str(ingredients_str).split(",") if name.strip())

             self.produce_data_cache = self._fetch_produce_data(list(all_ingredient_names))

             # Calculate nutrition for each meal and store it
             processed_meals = []
             for meal in all_meals:
                  p_meal = dict(meal) # Ensure mutable
                  p_meal['calculated_nutrition'] = self._calculate_meal_nutrition(p_meal.get('ingredients'), self.produce_data_cache)
                  processed_meals.append(p_meal)
             return processed_meals

        except Exception as e:
            logger.error(f"RecSys(V1) User {self.user_id}: Error fetching meals: {e}", exc_info=True)
            return None # Indicate failure

    def filter_meals(self, all_meals):
        if not all_meals: return []
        if not self.user_preferences:
             logger.warning(f"RecSys(V1) User {self.user_id}: No preferences, returning all fetched meals.")
             return all_meals # Return all if no preferences

        prefs = self.user_preferences
        filtered = []
        for meal in all_meals:
            # Normalize meal data safely, handling potential None or non-string values
            meal_diet_str = meal.get('dietary_preference') or ''
            meal_diet = [d.strip().lower() for d in str(meal_diet_str).split(',') if d.strip()]

            meal_allergens_str = meal.get('allergies') or ''
            meal_allergens = [a.strip().lower() for a in str(meal_allergens_str).split(',') if a.strip()]

            meal_cuisines_str = meal.get('cuisine_preferences') or ''
            meal_cuisines = [c.strip().lower() for c in str(meal_cuisines_str).split(',') if c.strip()]

            meal_goal = meal.get('goal') or ''
            meal_goal_lower = str(meal_goal).strip().lower() if meal_goal else None

            user_goal = prefs.get('goals')
            user_diet = prefs.get('diet_type')
            user_restrictions = prefs.get('food_restrictions')
            user_cuisines = prefs.get('cuisine_preferences')

            # Apply filters
            if user_diet and meal_diet and user_diet not in meal_diet: continue
            if user_restrictions and any(res in meal_allergens for res in user_restrictions): continue
            # Only filter by cuisine if user has preferences AND meal has cuisines specified
            if user_cuisines and meal_cuisines and not any(cp in meal_cuisines for cp in user_cuisines): continue
            if user_goal and meal_goal_lower and user_goal != meal_goal_lower: continue

            # Add meal to filtered list if it passed all filters
            filtered.append(meal)

        logger.info(f"RecSys(V1) User {self.user_id}: Filtered {len(all_meals)} -> {len(filtered)}")
        return filtered

    def recommend_meals(self):
        if not self.user_preferences:
            return {"error": "User preferences not found.", "success": False}
        try:
            all_meals = self.fetch_all_meals_with_ingredients()
            if all_meals is None: # Check for fetch failure
                 return {"error": "Failed to retrieve meals from database.", "success": False}

            recommended_meals = self.filter_meals(all_meals)

            # Add default price and format datetime
            processed_recs = []
            for meal in recommended_meals:
                 p_meal = dict(meal) # Ensure mutable
                 p_meal.setdefault('price', 10000) # Add default price if missing
                 for key, value in p_meal.items():
                      if isinstance(value, (datetime, date)): p_meal[key] = value.isoformat()
                 processed_recs.append(p_meal)

            logger.info(f"RecSys(V1) User {self.user_id}: Generated {len(processed_recs)} recommendations.")
            return {"recommended_meals": processed_recs, "success": True}

        except ConnectionError as e:
            logger.error(f"RecSys(V1) User {self.user_id}: Connection Error: {e}")
            return {"error": "Database connection error.", "success": False}
        except ValueError as e: # Catch specific ValueErrors if any
            logger.error(f"RecSys(V1) User {self.user_id}: Value Error: {e}")
            return {"error": str(e), "success": False}
        except Exception as e:
            logger.error(f"RecSys(V1) User {self.user_id}: Unexpected Error: {e}", exc_info=True)
            return {"error": "An unexpected error occurred during recommendation.", "success": False}

class MealRecommendation2(BaseMealRecommender):
    # V2 includes calorie budgeting and scoring

    def __init__(self, user_id: int):
        super().__init__(user_id) # Calls Base init (fetches prefs/metrics)
        self.calc_logic = CalculationLogic()
        self.daily_calorie_budget = self._calculate_daily_calorie_budget() # Calculate budget after fetching data
        logger.info(f"RecSys(V2) User {self.user_id}: Initialized with Calorie Budget: {self.daily_calorie_budget}")

    def _calculate_daily_calorie_budget(self) -> float:
        if not self.user_metrics:
            logger.warning(f"RecSys(V2) User {self.user_id}: Metrics missing for budget calculation. Using default 2000 kcal.")
            return 2000.0

        # Get metrics data, default to None if missing
        weight = self.user_metrics.get('weight')
        height = self.user_metrics.get('height')
        age_range = self.user_metrics.get('age_range')
        sex = self.user_metrics.get('sex')
        activity_level = self.user_metrics.get('activity_level', 'sedentary') # Default activity level
        bmr = self.user_metrics.get('bmr') # Check if BMR is already stored
        daily_calories = self.user_metrics.get('daily_calories') # Check if TDEE is already stored

        tdee = 0.0 # Initialize TDEE

        # Use stored TDEE if valid and present
        if daily_calories is not None:
            try:
                tdee = float(daily_calories)
                logger.debug(f"RecSys(V2) User {self.user_id}: Using stored TDEE: {tdee}")
            except (ValueError, TypeError):
                logger.warning(f"RecSys(V2) User {self.user_id}: Invalid stored TDEE value: {daily_calories}. Recalculating.")
                daily_calories = None # Invalidate if not floatable

        # If TDEE wasn't used/valid, calculate BMR and TDEE
        if tdee <= 0:
            if bmr is None: # If BMR not stored/invalid, calculate it
                try:
                    bmr = self.calc_logic.calculate_bmr(weight, height, age_range, sex)
                    logger.debug(f"RecSys(V2) User {self.user_id}: Calculated BMR: {bmr}")
                except Exception as e:
                    logger.error(f"RecSys(V2) User {self.user_id}: Error calculating BMR: {e}")
                    bmr = 0 # Set BMR to 0 on error

            elif isinstance(bmr, (int, float)) and bmr > 0: # If stored BMR is valid
                pass # Use stored BMR
            else:
                 logger.warning(f"RecSys(V2) User {self.user_id}: Invalid stored BMR value: {bmr}. Recalculating BMR.")
                 # Recalculate BMR if invalid format or <= 0
                 try:
                    bmr = self.calc_logic.calculate_bmr(weight, height, age_range, sex)
                    logger.debug(f"RecSys(V2) User {self.user_id}: Recalculated BMR: {bmr}")
                 except Exception as e:
                    logger.error(f"RecSys(V2) User {self.user_id}: Error recalculating BMR: {e}")
                    bmr = 0

            # Calculate TDEE from BMR (if BMR is valid)
            if bmr is not None and bmr > 0: # Explicitly check if bmr is valid
                try:
                    tdee = self.calc_logic.calculate_daily_calories(bmr, activity_level)
                    logger.debug(f"RecSys(V2) User {self.user_id}: Calculated TDEE from BMR: {tdee}")
                except Exception as e:
                    logger.error(f"RecSys(V2) User {self.user_id}: Error calculating TDEE from BMR: {e}")
                    tdee = 0
            else:
                logger.warning(f"RecSys(V2) User {self.user_id}: Cannot calculate TDEE due to invalid BMR.")
                tdee = 2000.0 # Fallback TDEE if BMR is 0

        # Apply goal adjustment
        goal = self.user_preferences.get('goals') if self.user_preferences else None
        adjustment = 0
        if goal == "weight loss": adjustment = -500
        elif goal == "muscle gain": adjustment = 300
        # Add other goal adjustments here

        final_budget = max(1200, tdee + adjustment) # Ensure minimum budget
        logger.info(f"RecSys(V2) User {self.user_id}: Goal='{goal}', TDEE={tdee}, Adjustment={adjustment}, Final Budget={final_budget}")
        return round(final_budget, 1)

    def fetch_all_meals_with_nutrition(self) -> List[Dict]:
        # Fetches meals, ingredients, and calculates nutrition for each
        query = """
            SELECT m.*, COALESCE(STRING_AGG(p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
            FROM meals m
            LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
            LEFT JOIN produce p ON mi.produce_id = p.produce_id
            GROUP BY m.meal_id -- Group by all columns from meals.*
                   , m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link, m.goal, m.dietary_preference, m.allergies, m.disease_management, m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description, m.date_added, m.date_last_edited, m.added_by, m.added_by_type, m.user_type
        """
        try:
             all_meals = self._execute_query(query, fetch_all=True)
             if not all_meals: return []

             # Fetch produce data efficiently
             all_ingredient_names = set()
             for meal in all_meals:
                 ingredients_str = meal.get('ingredients')
                 if ingredients_str:
                     # Ensure string conversion before splitting and processing
                     all_ingredient_names.update(name.strip().lower() for name in str(ingredients_str).split(",") if name.strip())

             # Use instance variable for cache if preferred, otherwise local is fine
             produce_data_cache = self._fetch_produce_data(list(all_ingredient_names))

             # Calculate and add nutrition info to each meal
             processed_meals = []
             for meal in all_meals:
                 p_meal = dict(meal) # Work with a copy
                 p_meal['nutritional_info'] = self._calculate_meal_nutrition(p_meal.get('ingredients'), produce_data_cache)
                 processed_meals.append(p_meal)

             return processed_meals
        except Exception as e:
            logger.error(f"RecSys(V2) User {self.user_id}: Error fetching meals with nutrition: {e}", exc_info=True)
            return [] # Return empty list on error

    def _calculate_calorie_density(self, meal: Dict) -> float:
        # Calculates calories per gram
        try:
            calories = float(meal.get('nutritional_info', {}).get('calories', 0.0) or 0.0) # Ensure float
            total_grams = float(meal.get('nutritional_info', {}).get('total_grams', 0.0) or 0.0) # Ensure float
            return round(calories / total_grams, 2) if total_grams > 0 else 0.0
        except (ValueError, TypeError) as e:
            logger.warning(f"Invalid nutritional data for calorie density: {meal.get('meal_name', 'Unknown Meal')}. Error: {e}")
            return 0.0

    def _calculate_serving_size(self, meal: Dict) -> float:
        # Calculates recommended serving size in grams based on calorie budget per meal
        target_calories_per_meal = self.daily_calorie_budget / 3.0 # Assuming 3 meals
        if target_calories_per_meal <= 0: return 0.0

        try:
            nutr_info = meal.get('nutritional_info', {})
            total_grams = float(nutr_info.get('total_grams', 0.0) or 0.0)
            total_calories = float(nutr_info.get('calories', 0.0) or 0.0)

            if total_grams <= 0 or total_calories <= 0:
                 logger.warning(f"RecSys(V2) User {self.user_id}: Cannot calculate serving size for '{meal.get('meal_name', 'Unknown Meal')}' due to zero grams/calories. Defaulting to 100g.")
                 return 100.0

            calories_per_gram = total_calories / total_grams
            if calories_per_gram <= 0: # Avoid division by zero
                 logger.warning(f"RecSys(V2) User {self.user_id}: Zero calories per gram for '{meal.get('meal_name', 'Unknown Meal')}', defaulting to 100g serving.")
                 return 100.0

            serving_size_grams = target_calories_per_meal / calories_per_gram
            # Return a minimum serving size
            return round(max(50, serving_size_grams), 1)
        except (ValueError, TypeError) as e:
            logger.warning(f"RecSys(V2) User {self.user_id}: Error calculating serving size for '{meal.get('meal_name', 'Unknown Meal')}': {e}. Defaulting to 100g.")
            return 100.0

    def filter_and_score_meals(self, all_meals: List[Dict]) -> List[Dict]:
        if not all_meals: return []
        if not self.user_preferences: return all_meals # Return all if no prefs

        prefs = self.user_preferences
        filtered_meals = []
        for meal in all_meals:
            # Use defensive programming with get and default values
            meal_diet_str = meal.get('dietary_preference') or ''
            meal_diet = [d.strip().lower() for d in str(meal_diet_str).split(',') if d.strip()]

            meal_allergens_str = meal.get('allergies') or ''
            meal_allergens = [a.strip().lower() for a in str(meal_allergens_str).split(',') if a.strip()]

            meal_cuisines_str = meal.get('cuisine_preferences') or ''
            meal_cuisines = [c.strip().lower() for c in str(meal_cuisines_str).split(',') if c.strip()]

            # --- Apply Basic Filters ---
            if prefs.get('diet_type') and meal_diet and prefs['diet_type'] not in meal_diet: continue
            if prefs.get('food_restrictions') and any(res in meal_allergens for res in prefs['food_restrictions']): continue

            # --- Calculate Serving Size & Nutrition per Serving ---
            serving_size_g = self._calculate_serving_size(meal)
            meal['recommended_serving_g'] = serving_size_g

            nutrition_per_serving = {}
            nutr_info = meal.get('nutritional_info', {})
            total_grams = float(nutr_info.get('total_grams', 0.0) or 0.0)

            if total_grams > 0:
                factor = serving_size_g / total_grams
                for key, val in nutr_info.items():
                    if key != 'total_grams':
                        try: nutrition_per_serving[key] = round(float(val) * factor, 1);
                        except (ValueError, TypeError): nutrition_per_serving[key] = 0.0 # Default on error
            meal['nutrition_per_serving'] = nutrition_per_serving

            # --- Scoring (Example: Cuisine Match) ---
            cuisine_match_score = 0
            if prefs.get('cuisine_preferences') and meal_cuisines:
                if any(cp in meal_cuisines for cp in prefs['cuisine_preferences']):
                    cuisine_match_score = 1 # Simple binary score for now

            # Assign total score
            meal['score'] = cuisine_match_score

            # Add meal to filtered list if it passed filters
            filtered_meals.append(meal)

        # Sort by score (descending)
        filtered_meals.sort(key=lambda x: x.get('score', 0), reverse=True)
        logger.info(f"RecSys(V2) User {self.user_id}: Filtered and scored {len(all_meals)} -> {len(filtered_meals)}")
        return filtered_meals

    def recommend_meals(self) -> Dict:
        if not self.user_preferences or not self.user_metrics:
            missing = []
            if not self.user_preferences: missing.append("preferences")
            if not self.user_metrics: missing.append("metrics")
            error_msg = "User " + (", ".join(missing)) + " data not found."
            logger.warning(f"RecSys(V2) User {self.user_id}: Cannot recommend. {error_msg}")
            return {"error": error_msg, "success": False}

        try:
            all_meals = self.fetch_all_meals_with_nutrition()
            if all_meals is None: # Indicates fetch failure
                return {"error": "Failed to retrieve meals from database.", "success": False}

            recommended_meals = self.filter_and_score_meals(all_meals)

            # Add default price and format datetime
            processed_recs = []
            for meal in recommended_meals:
                p_meal = dict(meal) # Ensure mutable
                p_meal.setdefault('price', 10000) # Add default price if missing
                for key, value in p_meal.items():
                     if isinstance(value, (datetime, date)):
                         p_meal[key] = value.isoformat()
                processed_recs.append(p_meal)

            logger.info(f"RecSys(V2) User {self.user_id}: Generated {len(processed_recs)} recommendations.")
            return {"recommended_meals": processed_recs, "success": True}

        except ConnectionError as e:
            logger.error(f"RecSys(V2) User {self.user_id}: Connection Error: {e}")
            return {"error": "Database connection error.", "success": False}
        except ValueError as e:
            logger.error(f"RecSys(V2) User {self.user_id}: Value Error: {e}")
            return {"error": str(e), "success": False}
        except Exception as e:
            logger.error(f"RecSys(V2) User {self.user_id}: Unexpected Error: {e}", exc_info=True)
            return {"error": "An unexpected error occurred during recommendation.", "success": False}
        
import logging
from datetime import datetime, date
# Assuming BaseRepository and its _execute_query method are defined elsewhere
# Assuming logger is configured globally

class GetAllMeals(BaseRepository):
    # Follow Python naming conventions (snake_case for methods)
    def fetch_all_meals(self):
        logger.debug("Fetching all meals with ingredients and complementaries...")
        try:
            # Using CTEs for better readability and potential performance
            sql_query = """
                WITH MealIngredients AS (
                    SELECT
                        mi.meal_id,
                        COALESCE(STRING_AGG(DISTINCT p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
                    FROM meal_ingredients mi
                    JOIN produce p ON mi.produce_id = p.produce_id
                    GROUP BY mi.meal_id
                ),
                MealComplementaries AS (
                     SELECT
                         mcl.meal_id,
                         COALESCE(STRING_AGG(DISTINCT mc.meal_name, ', ' ORDER BY mc.meal_name), '') AS complementary_dishes
                     FROM meal_complementaries mcl
                     JOIN meals mc ON mcl.complementary_dish_id = mc.meal_id
                     GROUP BY mcl.meal_id
                )
                SELECT
                    m.*, -- Select all columns from the meals table
                    mi.ingredients,
                    mc.complementary_dishes
                FROM meals m
                LEFT JOIN MealIngredients mi ON m.meal_id = mi.meal_id
                LEFT JOIN MealComplementaries mc ON m.meal_id = mc.meal_id;
            """
            # Execute the query using the inherited method
            all_meals_list = self._execute_query(sql_query, fetch_all=True)

            # Handle None return from query execution (indicates an error occurred)
            if all_meals_list is None:
                logger.error("Database query for all meals returned None.")
                return {"error": "Failed to retrieve meals data.", "success": False}

            # Process the results: add default price, format dates
            processed_meals = []
            for meal_row in all_meals_list:
                 # Ensure we are working with a mutable dictionary
                 meal_dict = dict(meal_row)
                 # Set default price if 'price' key doesn't exist or is None
                 meal_dict.setdefault('price', 10000)
                 # Format datetime objects to ISO 8601 strings
                 for key, value in meal_dict.items():
                     if isinstance(value, (datetime, date)):
                         meal_dict[key] = value.isoformat()
                 processed_meals.append(meal_dict)

            logger.info(f"Successfully fetched {len(processed_meals)} meals.")
            # Return the processed list in the desired structure
            return {"All_Meals": processed_meals, "success": True}

        except ValueError as ve:
            # Catch specific database/connection errors re-raised by _execute_query
            logger.error(f"Database error fetching all meals: {ve}", exc_info=False) # Less noise maybe
            # Return consistent error structure
            return {"error": f"Database error: {ve}", "success": False}
        except Exception as e:
            # Catch any other unexpected errors
            logger.error(f"Unexpected error fetching all meals: {e}", exc_info=True)
            return {"error": "An unexpected server error occurred.", "success": False}
        
import os
import json
import base64
import time
import uuid
import logging
from typing import Dict, Any, Optional

# Assuming necessary imports like requests, paypalrestsdk, stripe are present
# Assuming logger is configured globally

# --- Payment Methods (Corrected Syntax & Structure) ---

def configure_paypal(mode: str, client_id: str, client_secret: str):
    """Configures the PayPal SDK."""
    if not client_id or not client_secret:
        logger.error("PayPal client_id and client_secret are required for configuration.")
        # Optionally raise an error or handle appropriately
        return
    try:
        paypalrestsdk.configure({
            'mode': mode,
            'client_id': client_id,
            'client_secret': client_secret
        })
        logger.info(f"PayPal SDK configured successfully for mode: {mode}")
    except Exception as e:
        logger.error(f"Failed to configure PayPal SDK: {e}", exc_info=True)
        # Decide if this should halt the application or just log

def create_payment_paypal(amount: float, description: str, currency: str = "USD") -> Dict[str, Any]:
    """Creates a PayPal payment and returns the approval URL."""
    try:
        # Validate and format amount
        amount_f = float(amount)
        if amount_f <= 0:
            raise ValueError("Payment amount must be positive.")
        formatted_amount = "{:.2f}".format(amount_f)

        # Ensure API_BASE_URL ends without a slash for clean joins
        api_base_url = os.getenv('API_BASE_URL', 'http://localhost:5000').rstrip('/')
        return_url = f"{api_base_url}/rr/execute"
        cancel_url = f"{api_base_url}/rr/cancel"

        payment_details = {
            "intent": "sale",
            "payer": {"payment_method": "paypal"},
            "transactions": [{
                "amount": {"total": formatted_amount, "currency": currency.upper()}, # Use uppercase currency
                "description": description or "ZINZI Health Service Payment" # Ensure description is not None
            }],
            "redirect_urls": {
                "return_url": return_url,
                "cancel_url": cancel_url
            }
        }

        payment = paypalrestsdk.Payment(payment_details)

        if payment.create():
            # Safely extract approval URL
            approval_url = next((link.href for link in payment.links if link.rel == "approval_url"), None)
            if approval_url:
                logger.info(f"PayPal payment created (ID: {payment.id}). Approval URL generated.")
                return {"approval_url": approval_url, "payment_id": payment.id, "success": True}
            else:
                logger.error(f"PayPal payment created (ID: {payment.id}) but no approval URL found.")
                return {"error": "Payment creation succeeded but failed to get approval URL.", "success": False}
        else:
            # Log detailed error if available
            err_details = payment.error if hasattr(payment, 'error') and payment.error else "Unknown error"
            logger.error(f"PayPal payment creation failed: {err_details}")
            # Extract message safely
            err_msg = err_details.get('message', 'Unknown PayPal error') if isinstance(err_details, dict) else str(err_details)
            return {"error": f"PayPal Error: {err_msg}", "success": False}

    except paypalrestsdk.exceptions.PayPalRESTfulException as pe:
        logger.error(f"PayPal API Error during payment creation: {pe}")
        return {"error": f"PayPal API Error: {pe}", "success": False}
    except ValueError as ve: # Catch amount validation error
        logger.error(f"Invalid amount or value for PayPal payment: {ve}")
        return {"error": str(ve), "success": False}
    except Exception as e:
        logger.error(f"Unexpected error creating PayPal payment: {e}", exc_info=True)
        return {"error": "An unexpected server error occurred.", "success": False}


def execute_payment_paypal(payment_id: str, payer_id: str) -> Dict[str, Any]:
    """Executes a PayPal payment after user approval."""
    if not payment_id or not payer_id:
         return {"status": "failure", "error": "payment_id and payer_id are required."}
    try:
        payment = paypalrestsdk.Payment.find(payment_id)
        if payment.execute({"payer_id": payer_id}):
            logger.info(f"PayPal payment execution successful (ID: {payment_id}), State: {payment.state}")
            # Return structured success response
            return {"status": "success", "payment": payment.to_dict()}
        else:
            err_details = payment.error if hasattr(payment, 'error') and payment.error else "Unknown execution error"
            logger.error(f"PayPal payment execution failed (ID: {payment_id}): {err_details}")
            err_msg = err_details.get('message', 'Unknown PayPal error') if isinstance(err_details, dict) else str(err_details)
            # Return structured failure response
            return {"status": "failure", "error": err_msg}
    except paypalrestsdk.exceptions.ResourceNotFound:
        logger.error(f"PayPal payment execution failed: Payment ID '{payment_id}' not found.")
        return {"status": "failure", "error": "Payment not found."}
    except paypalrestsdk.exceptions.PayPalRESTfulException as pe:
        logger.error(f"PayPal API Error during payment execution (ID: {payment_id}): {pe}")
        return {"status": "failure", "error": f"PayPal API Error: {pe}"}
    except Exception as e:
        logger.error(f"Unexpected error executing PayPal payment (ID: {payment_id}): {e}", exc_info=True)
        return {"status": "failure", "error": "An unexpected server error occurred."}


def handle_payment_cancellation_paypal() -> Dict[str, Any]:
    """Handles the scenario where a user cancels the PayPal payment."""
    logger.info("PayPal payment was cancelled by the user.")
    return {"status": "cancelled", "message": "Payment was cancelled by the user."}


def configure_stripe(secret_key: str):
    """Configures the Stripe API key."""
    if not secret_key:
        logger.warning("Stripe Secret Key is missing. Stripe payments will not be available.")
        return # Explicitly return if key is missing
    try:
        stripe.api_key = secret_key
        logger.info("Stripe API key configured successfully.")
    except Exception as e:
        logger.error(f"Failed to configure Stripe: {e}", exc_info=True)


def create_stripe_payment(amount: float, description: str = "Payment for ZINZI Health Service", currency: str = "usd") -> Dict[str, Any]:
    """Creates a Stripe Payment Intent."""
    if not stripe.api_key: # Check if Stripe was configured
         return {"status": "failure", "error": "Stripe is not configured on the server."}
    try:
        # Validate and convert amount to cents
        amount_f = float(amount)
        if amount_f <= 0:
             raise ValueError("Payment amount must be positive.")
        amount_cents = int(round(amount_f * 100))

        # Create Payment Intent
        payment_intent = stripe.PaymentIntent.create(
            amount=amount_cents,
            currency=currency.lower(), # Use lowercase currency
            description=description
            # Consider adding 'automatic_payment_methods': {'enabled': True} for simpler integration
        )
        logger.info(f"Stripe PaymentIntent created successfully (ID: {payment_intent.id})")
        # Return essential details for client-side confirmation
        return {
            "status": "success",
            "client_secret": payment_intent.client_secret,
            "intent_id": payment_intent.id
        }
    except stripe.error.StripeError as e:
        logger.error(f"Stripe API error during PaymentIntent creation: {e}")
        return {"status": "failure", "error": str(e)}
    except ValueError as ve:
         logger.error(f"Invalid amount for Stripe payment: {ve}")
         return {"status": "failure", "error": str(ve)}
    except Exception as e:
        logger.error(f"Unexpected error creating Stripe PaymentIntent: {e}", exc_info=True)
        return {"status": "failure", "error": "An unexpected server error occurred."}


def execute_stripe_payment(payment_intent_id: str, payment_method_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Checks the status of a Stripe Payment Intent.
    Confirmation typically happens client-side. Use this to verify status post-confirmation.
    """
    if not stripe.api_key:
         return {"status": "failure", "error": "Stripe is not configured on the server."}
    if not payment_intent_id:
        return {"status": "failure", "error": "Payment Intent ID is required."}

    try:
        # Retrieve the Payment Intent to check its latest status
        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        status = intent.status
        logger.info(f"Checking status for Stripe PI {payment_intent_id}: Current status is {status}")

        # Handle different statuses appropriately
        if status == 'succeeded':
            logger.info(f"Stripe PaymentIntent {payment_intent_id} has succeeded.")
            return {"status": "success", "payment": intent.to_dict()}
        elif status in ('requires_action', 'requires_confirmation'):
            # These statuses usually require client-side action
            logger.warning(f"Stripe PI {payment_intent_id} requires client action (Status: {status}).")
            return {"status": status, "client_secret": intent.client_secret, "message": f"Payment requires client action ({status})."}
        elif status == 'processing':
            logger.info(f"Stripe PI {payment_intent_id} is processing.")
            return {"status": "processing", "message": "Payment is processing."}
        elif status == 'canceled':
            logger.warning(f"Stripe PI {payment_intent_id} was canceled.")
            return {"status": "failure", "message": "Payment was canceled."}
        elif status == 'requires_payment_method':
             logger.warning(f"Stripe PI {payment_intent_id} failed: Requires payment method.");
             return {"status": "failure", "message": "Payment failed: Requires payment method."}
        else: # Includes 'failed' and any other unexpected statuses
            logger.error(f"Stripe PaymentIntent {payment_intent_id} failed or has unexpected status: {status}.")
            return {"status": "failure", "message": f"Payment status: {status}"}

    except stripe.error.StripeError as e:
        logger.error(f"Stripe API error retrieving PaymentIntent {payment_intent_id}: {e}")
        return {"status": "failure", "error": str(e)}
    except Exception as e:
        logger.error(f"Unexpected error checking Stripe PI {payment_intent_id}: {e}", exc_info=True)
        return {"status": "failure", "error": "An unexpected server error occurred."}


def handle_stripe_payment_cancellation() -> Dict[str, Any]:
    """Handles the scenario where a Stripe payment is cancelled or abandoned."""
    logger.info("Stripe payment flow likely cancelled or abandoned by user.")
    return {"status": "cancelled", "message": "Payment was not completed."}


# --- MoMo Global Variables and Functions ---
MOMO_API_KEY = os.getenv("MOMO_API_KEY")
MOMO_SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")
MOMO_API_USER_ID = os.getenv("MOMO_API_USER_ID")
# Ensure base URL doesn't have trailing slash
MOMO_BASE_URL = os.getenv("MOMO_BASE_URL", "https://sandbox.momodeveloper.mtn.com").rstrip('/')
MOMO_TARGET_ENV = os.getenv("MOMO_TARGET_ENV", "sandbox")
MOMO_CALLBACK_URL = os.getenv("MOMO_CALLBACK_URL", 'chwezicreatives.com') # Verify this URL is correct and reachable

# Global state for token and headers (Consider managing state differently in production)
momo_headers: Dict[str, str] = {} # Type hint
momo_access_token: str = ""
momo_token_expires_at: int = 0 # Use int for timestamp comparison

def get_momo_api_user_key(user_id: str, subscription_key: str) -> Optional[str]:
    """
    Generates a MoMo API Key for a given user ID.
    Note: This is usually done once via the MoMo developer portal.
    """
    if not user_id or not subscription_key:
        logger.error("MoMo API User ID and Subscription Key are required to generate an API key.")
        return None

    url = f"{MOMO_BASE_URL}/v1_0/apiuser/{user_id}/apikey"
    headers = {"Ocp-Apim-Subscription-Key": subscription_key}
    logger.info(f"Requesting MoMo API Key for user {user_id}...")

    try:
        response = requests.post(url, headers=headers, timeout=10) # Added timeout
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
        key_info = response.json()
        api_key = key_info.get("apiKey")
        if api_key:
            logger.info(f"Successfully generated MoMo API Key for user {user_id}.")
            return api_key
        else:
            logger.error(f"MoMo API Key generation failed for user {user_id}. Response: {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        logger.error(f"Network or MoMo API error during API Key generation for user {user_id}: {e}", exc_info=True)
        return None
    except json.JSONDecodeError:
        logger.error(f"Failed to decode JSON response during MoMo API Key generation for user {user_id}. Response: {response.text}")
        return None
    except Exception as e:
         logger.error(f"Unexpected error during MoMo API Key generation for user {user_id}: {e}", exc_info=True)
         return None

def get_momo_access_token() -> bool:
    """Obtains a MoMo API access token."""
    global momo_access_token, momo_token_expires_at, momo_headers

    # Check if essential config is present
    if not MOMO_API_USER_ID or not MOMO_SUBSCRIPTION_KEY:
        logger.critical("MoMo API User ID or Subscription Key is not configured.")
        return False
    api_key = MOMO_API_KEY # Use the key from env vars directly
    if not api_key:
        logger.critical("MoMo API Key is not configured.")
        return False

    url = f"{MOMO_BASE_URL}/collection/token/"
    # Basic Authentication: base64(APIUserID:APIKey)
    auth_str = f"{MOMO_API_USER_ID}:{api_key}"
    auth_b64 = base64.b64encode(auth_str.encode()).decode()
    headers = {
        "Authorization": f"Basic {auth_b64}",
        "Ocp-Apim-Subscription-Key": MOMO_SUBSCRIPTION_KEY
    }

    try:
        logger.info("Requesting new MoMo Access Token...")
        response = requests.post(url, headers=headers, timeout=15)
        response.raise_for_status() # Check for HTTP errors

        token_info = response.json()
        new_token = token_info.get("access_token")
        expires_in = token_info.get("expires_in", 3500) # Default ~1 hour

        if not new_token:
            logger.error(f"MoMo access token missing in response: {token_info}")
            return False

        momo_access_token = new_token
        # Set expiry time slightly before actual expiry
        momo_token_expires_at = int(time.time()) + expires_in - 60 # Use int for timestamp
        # Update global headers for subsequent requests
        momo_headers = {
            "Authorization": f"Bearer {momo_access_token}",
            "X-Reference-Id": str(uuid.uuid4()), # Generate a new one each time token is fetched
            "X-Target-Environment": MOMO_TARGET_ENV,
            "Ocp-Apim-Subscription-Key": MOMO_SUBSCRIPTION_KEY,
            "Content-Type": "application/json"
            # Add other required headers if needed
        }
        logger.info("Successfully obtained MoMo Access Token.")
        return True

    except requests.exceptions.RequestException as e:
        logger.error(f"Network or MoMo API error during token request: {e}", exc_info=True)
        return False
    except json.JSONDecodeError:
         logger.error(f"Failed to decode JSON response during MoMo token request. Response: {response.text}")
         return False
    except Exception as e:
        logger.error(f"Unexpected error obtaining MoMo Access Token: {e}", exc_info=True)
        return False

def ensure_momo_token() -> bool:
    """Checks if the current MoMo token is valid, refreshes if needed."""
    # Check if token is expired or missing
    if time.time() >= momo_token_expires_at or not momo_access_token:
        logger.info("MoMo access token expired or missing. Attempting refresh...")
        return get_momo_access_token()
    # Token is still valid
    return True

def request_momo_payment(amount: float, currency: str, external_id: str, payer_number: str, payer_message: str, payee_note: str) -> Dict[str, Any]:
    """Requests a MoMo payment from a user."""
    if not ensure_momo_token():
        return {"status": "failure", "error": "Failed to authenticate with MoMo API."}

    url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay"
    transaction_uuid = str(uuid.uuid4()) # Unique reference for this specific API request

    # Use the current global headers, but override X-Reference-Id for this specific transaction
    current_headers = {**momo_headers, "X-Reference-Id": transaction_uuid}

    # Construct payload, ensuring amount is string and required fields are present
    try:
        payload = {
            "amount": str(float(amount)), # Convert to float first, then string
            "currency": currency.lower(), # Use lowercase currency code
            "externalId": str(external_id), # Ensure string
            "payer": {
                "partyIdType": "MSISDN",
                "partyId": str(payer_number) # Ensure string
            },
            "payerMessage": str(payer_message),
            "payeeNote": str(payee_note)
            # Add callback URL if required by your MoMo setup
            # "callbackUrl": MOMO_CALLBACK_URL
        }
    except (ValueError, TypeError) as e:
        logger.error(f"Invalid data type for MoMo payment request payload: {e}")
        return {"status": "failure", "error": "Invalid data format for payment request."}

    try:
        logger.info(f"Requesting MoMo Payment: ExternalID={external_id}, TxRef={transaction_uuid}, Amount={amount}, Payer={payer_number}")
        response = requests.post(url, json=payload, headers=current_headers, timeout=30) # Timeout allows for user action

        # MoMo uses 202 Accepted for successful initiation
        if response.status_code == 202:
            logger.info(f"MoMo Payment Request Accepted. TxRef={transaction_uuid}. Awaiting confirmation from {payer_number}.")
            # The transaction_ref is the UUID we generated and sent in headers
            return {"status": "pending", "transaction_ref": transaction_uuid, "message": "Awaiting user confirmation."}
        else:
            # Attempt to parse error response
            error_details = response.text
            try:
                error_details = response.json()
            except json.JSONDecodeError:
                pass # Keep as text if not JSON
            logger.error(f"MoMo Payment Request Failed. Status: {response.status_code}, TxRef: {transaction_uuid}, Error: {error_details}")
            return {"status": "failure", "error": error_details}

    except requests.exceptions.Timeout:
        logger.error(f"MoMo Payment Request Timed Out. TxRef: {transaction_uuid}.")
        return {"status": "failure", "error": "Request timed out."}
    except requests.exceptions.RequestException as e:
        logger.error(f"Network or MoMo API Error during Payment Request. TxRef: {transaction_uuid}. Error: {e}", exc_info=True)
        return {"status": "failure", "error": f"Network/API Error: {e}"}
    except Exception as e:
        logger.error(f"Unexpected Error during MoMo Payment Request. TxRef: {transaction_uuid}. Error: {e}", exc_info=True)
        return {"status": "failure", "error": "An unexpected server error occurred."}


def check_momo_payment_status(transaction_ref: str) -> Dict[str, Any]:
    """Checks the status of a previously initiated MoMo payment request."""
    if not ensure_momo_token():
        return {"status": "failure", "error": "Failed to authenticate with MoMo API."}
    if not transaction_ref:
        return {"status": "failure", "error": "Transaction reference is required."}

    url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay/{transaction_ref}"
    # Use current global headers (includes auth, target env, sub key)
    current_headers = momo_headers

    try:
        logger.info(f"Checking MoMo Payment Status for TxRef: {transaction_ref}")
        response = requests.get(url, headers=current_headers, timeout=15) # Timeout for status check
        response.raise_for_status() # Raise HTTPError for bad responses

        status_data = response.json()
        current_status = status_data.get('status', 'UNKNOWN').upper()
        logger.info(f"MoMo Status Check OK for TxRef: {transaction_ref}. Status: {current_status}")
        # Return the full status data from MoMo
        return {"status": "success", "payment_status": status_data}

    except requests.exceptions.HTTPError as e:
        # Handle specific HTTP errors like 404 Not Found
        if e.response.status_code == 404:
            logger.warning(f"MoMo transaction reference '{transaction_ref}' not found (404).")
            return {"status": "not_found", "error": "Transaction reference not found."}
        else:
            # Handle other HTTP errors
            error_details = e.response.text
            try: error_details = e.response.json();
            except json.JSONDecodeError: pass
            logger.error(f"MoMo Status Check HTTP Error. TxRef: {transaction_ref}, Status: {e.response.status_code}, Error: {error_details}")
            return {"status": "failure", "error": error_details}
    except requests.exceptions.Timeout:
        logger.error(f"MoMo Status Check Timed Out. TxRef: {transaction_ref}.")
        return {"status": "failure", "error": "Status check request timed out."}
    except requests.exceptions.RequestException as e:
        logger.error(f"MoMo Status Check Network Error. TxRef: {transaction_ref}. Error: {e}", exc_info=True)
        return {"status": "failure", "error": f"Network/API Error: {e}"}
    except json.JSONDecodeError:
        logger.error(f"Failed to decode JSON response during MoMo status check. TxRef: {transaction_ref}. Response: {response.text}")
        return {"status": "failure", "error": "Invalid response format from MoMo API."}
    except Exception as e:
        logger.error(f"MoMo Status Check Unexpected Error. TxRef: {transaction_ref}. Error: {e}", exc_info=True)
        return {"status": "failure", "error": "An unexpected server error occurred."}

# --- Flask App Initialization ---
app = Flask(__name__)
CORS(app) # Enable CORS for all routes

# --- Backend Class Instantiations ---
auth_users = AuthenticationAndUsers()
chefs_crud = Chefs()
herbals_crud = Herbals()
meals_crud = Meals()
produce_crud = Produce()
producers_crud = Producers()
gadgets_crud = Gadgets()
# --- METRICS CRUD ---
@app.route('/rr/metrics', methods=['POST'])
def create_metric_endpoint():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400
    try:
        result = auth_users.create_metric(data)
        return jsonify({'message': 'Metric created successfully', 'data': result}), 201
    except Exception as e:
        logger.error(f'Error creating metric: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/metrics', methods=['GET'])
def get_metrics_endpoint():
    user_id = request.args.get('user_id')
    try:
        data = auth_users.list_metrics(user_id=user_id)
        return jsonify({'message': 'Metrics retrieved.', 'data': data}), 200
    except Exception as e:
        logger.error(f'Error fetching metrics: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/metrics/<int:metric_id>', methods=['PUT', 'PATCH'])
def update_metric_endpoint(metric_id):
    updates = request.get_json()
    if not updates:
        return jsonify({'error': 'Request body required'}), 400
    try:
        auth_users.update_metric(metric_id, updates)
        return jsonify({'message': 'Metric updated successfully'}), 200
    except Exception as e:
        logger.error(f'Error updating metric {metric_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/metrics/<int:metric_id>', methods=['DELETE'])
def delete_metric_endpoint(metric_id):
    try:
        # No explicit delete_metric method, so use update to set as deleted or remove if implemented
        # If not implemented, return 501 Not Implemented
        return jsonify({'error': 'Metric deletion not implemented'}), 501
    except Exception as e:
        logger.error(f'Error deleting metric {metric_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

# --- PREFERENCES CRUD ---
@app.route('/rr/preferences', methods=['POST'])
def create_preference_endpoint():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Request body required'}), 400
    try:
        result = auth_users.create_preference(data)
        return jsonify({'message': 'Preference created successfully', 'data': result}), 201
    except Exception as e:
        logger.error(f'Error creating preference: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/preferences', methods=['GET'])
def get_preferences_endpoint():
    user_id = request.args.get('user_id')
    try:
        data = auth_users.list_preferences(user_id=user_id)
        return jsonify({'message': 'Preferences retrieved.', 'data': data}), 200
    except Exception as e:
        logger.error(f'Error fetching preferences: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/preferences/<int:preference_id>', methods=['PUT', 'PATCH'])
def update_preference_endpoint(preference_id):
    updates = request.get_json()
    if not updates:
        return jsonify({'error': 'Request body required'}), 400
    try:
        auth_users.update_preference(preference_id, updates)
        return jsonify({'message': 'Preference updated successfully'}), 200
    except Exception as e:
        logger.error(f'Error updating preference {preference_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/preferences/<int:preference_id>', methods=['DELETE'])
def delete_preference_endpoint(preference_id):
    try:
        # No explicit delete_preference method, so use update to set as deleted or remove if implemented
        # If not implemented, return 501 Not Implemented
        return jsonify({'error': 'Preference deletion not implemented'}), 501
    except Exception as e:
        logger.error(f'Error deleting preference {preference_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

# --- ORDERS UPDATE/DELETE ---
@app.route('/rr/orders/<int:order_id>', methods=['PUT', 'PATCH'])
def update_order_endpoint(order_id):
    updates = request.get_json()
    if not updates or 'order_status' not in updates:
        return jsonify({'error': 'Request body must contain "order_status" field'}), 400
    new_status = updates['order_status']
    try:
        success = orders_crud.update_order_status(order_id, new_status)
        if success:
            return jsonify({'message': f'Order {order_id} status updated to {new_status}'}), 200
        else:
            return jsonify({'error': f'Failed to update status for order {order_id}'}), 500
    except Exception as e:
        logger.error(f"Error updating order status {order_id}: {e}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/orders/<int:order_id>', methods=['DELETE'])
def delete_order_endpoint(order_id):
    try:
        success = orders_crud.delete_order(order_id)
        if success:
            return jsonify({'message': f'Order {order_id} deleted successfully'}), 200
        else:
            return jsonify({'error': f'Failed to delete order {order_id}'}), 500
    except Exception as e:
        logger.error(f"Error deleting order {order_id}: {e}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

spices_crud = Spices()
stakeholders_crud = Stakeholders()
orders_crud = Orders()
transporters_crud = Transporters()
@app.route('/rr/orders', methods=['GET'])
def get_orders_endpoint():
    # Accept optional query parameters
    order_id = request.args.get('order_id')
    chef_id = request.args.get('chef_id')
    producer_id = request.args.get('producer_id')
    user_id = request.args.get('user_id')
    transporter_id = request.args.get('transporter_id')
    try:
        data = orders_crud.read_orders(
            order_id=order_id,
            chef_id=chef_id,
            producer_id=producer_id,
            user_id=user_id,
            transporter_id=transporter_id
        )
        return jsonify({'message': 'Orders retrieved.', 'data': data}), 200
    except ValueError as ve:
        logger.error(f'Error fetching orders: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error fetching orders: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

calc_logic = CalculationLogic()
meal_fetcher = GetAllMeals()

# --- Flask API Endpoints ---

@app.route('/rr')
def welcome():
    return 'Welcome to ZINZI Bonobo API.'

# === USER Endpoints ===
@app.route('/rr/signup_user', methods=['POST'])
def signup_user():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body required'}), 400
    try:
        name = data['name']
        email = data['email']
        password = data['password']
        image = data.get('image')  # Optional, may be None
        user_info = auth_users.create_user({'Name': name, 'Email': email, 'Password': password, 'Image': image})
        if user_info.get("success"):
            return jsonify({'message': 'User registered. Please verify email.', 'user_id': user_info['user_id']}), 201
        else:
            return jsonify({'error': user_info.get('error', 'Signup failed')}), 400
    except KeyError as ke:
        return jsonify({'error': f'Missing field: {ke}'}), 400
    except ValueError as ve:
        return jsonify({'error': str(ve)}), 400 # Catch specific validation errors
    except Exception as e:
        logger.error(f"Signup internal error: {e}", exc_info=True)
        return jsonify({'error': "Internal registration error."}), 500

@app.route('/rr/verify_user', methods=['POST'])
def verify_user():
    data = request.json;
    if not data or 'user_id' not in data or 'verification_code' not in data: return jsonify({'error': 'user_id and verification_code required'}), 400
    try: user_id = int(data['user_id']); verification_code = data['verification_code']
    except (ValueError, TypeError): return jsonify({'error': 'Invalid user_id or verification_code format'}), 400
    try: response, status_code = auth_users.verify_user_email(user_id, verification_code); return jsonify(response), status_code
    except Exception as e: logger.error(f'Internal verify error: {e}', exc_info=True); return jsonify({'message': 'Internal server error'}), 500

@app.route('/rr/login_user', methods=['POST'])
def login_user():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body required'}), 400
    identifier = data.get('identifier'); password = data.get('password')
    if not identifier or not password: return jsonify({'error': 'Identifier and password required'}), 400
    try:
        result, status_code = auth_users.login_user(identifier, password)
        if status_code == 200: return jsonify(result), status_code
        else: logger.warning(f'User login failed for {identifier}: {result.get("message", "Unknown reason")} ({status_code})'); return jsonify({'error': result.get('message', 'Login failed')}), status_code
    except ValueError as ve: logger.error(f"Login DB error: {ve}"); return jsonify({'error': "Login failed due to server issue."}), 500
    except Exception as e: logger.error(f"Login internal error: {e}", exc_info=True); return jsonify({'error': "Internal login error."}), 500

@app.route('/rr/rusers', methods=['GET'])
@app.route('/rr/rusers/<user_id>', methods=['GET'])
def get_users_endpoint(user_id=None):
    try:
        data = auth_users.list_users(user_id=user_id) # Returns list or None
        if user_id and data is None: return jsonify({'error': 'User not found'}), 404
        return jsonify({'message': 'Users retrieved successfully.', 'data': data or []}), 200
    except ValueError as ve: logger.error(f'Error fetching users: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error fetching users: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/users/<int:user_id>', methods=['DELETE'])
def delete_user_endpoint(user_id):
    try:
        success = auth_users.delete_user(user_id)
        if success: return jsonify({'message': f'User {user_id} deleted successfully'}), 200
        else: return jsonify({'error': f'Failed to delete user {user_id}'}), 500
    except ValueError as ve: logger.error(f"Error deleting user {user_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting user {user_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500


# === CHEF Endpoints ===
@app.route('/rr/signup_chef', methods=['POST'])
def create_chef_endpoint():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body missing'}), 400
    try: result = chefs_crud.create_chef(data); return jsonify(result), 201
    except ValueError as ve: logger.warning(f'Chef signup validation error: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error creating chef: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/login/chefs', methods=['POST'])
def login_chef():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body required'}), 400
    identifier = data.get('identifier'); password = data.get('password')
    if not identifier or not password: return jsonify({'error': 'Identifier and password required'}), 400
    try:
        result, status_code = chefs_crud.login_chef(identifier, password)
        if status_code == 200: return jsonify(result), status_code
        else: logger.warning(f'Chef login failed for {identifier}: {result.get("message", "Unknown reason")} ({status_code})'); return jsonify({'error': result.get('message', 'Login failed')}), status_code
    except ValueError as ve: logger.error(f"Chef login DB/Validation error: {ve}"); return jsonify({'error': 'Invalid credentials or account not found.'}), 401 if 'Invalid credentials' in str(ve) or 'not found' in str(ve) else (jsonify({'error': "Login failed due to server issue."}), 500)
    except Exception as e: logger.error(f"Chef login internal error: {e}", exc_info=True); return jsonify({'error': "Internal login error."}), 500

@app.route('/rr/rchefs', methods=['GET'])
@app.route('/rr/rchefs/<chef_id>', methods=['GET'])
def list_chefs_endpoint(chef_id=None):
    # Support both /rr/rchefs/<chef_id> and /rr/rchefs?chef_id=...
    chef_id = chef_id or request.args.get('chef_id') or request.args.get('chefid')
    try:
        data = chefs_crud.list_chefs(chef_id=chef_id)
        if chef_id:
            if data and len(data) > 0:
                return jsonify({'message': 'Chef retrieved.', 'data': data[0]}), 200
            else:
                return jsonify({'error': 'Chef not found'}), 404
        return jsonify({'message': 'Chefs retrieved.', 'data': data}), 200
    except ValueError as ve:
        logger.error(f'Error fetching chefs: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error fetching chefs: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/chefs/<int:chef_id>', methods=['PUT', 'PATCH'])
def update_chef_endpoint(chef_id):
    updates = request.get_json();
    
    if not updates: return jsonify({'error': 'Request body missing'}), 400
    try:
        chefs_crud.update_chef(chef_id, updates)
        updated_chef = chefs_crud.list_chefs(chef_id=chef_id)
        return jsonify({'message': 'Chef updated successfully', 'data': updated_chef[0] if updated_chef else None}), 200
    except ValueError as ve: logger.warning(f'Chef update validation error {chef_id}: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating chef {chef_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/chefs/<int:chef_id>', methods=['DELETE'])
def delete_chef_endpoint(chef_id):
    try:
        success = chefs_crud.delete_chef(chef_id)
        if success: return jsonify({'message': f'Chef {chef_id} deleted successfully'}), 200
        else: return jsonify({'error': f'Failed to delete chef {chef_id}'}), 500
    except ValueError as ve: logger.error(f"Error deleting chef {chef_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting chef {chef_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/chefs/<int:chef_id>/status', methods=['PATCH'])
def update_chef_status_endpoint(chef_id):
    data = request.get_json()
    if not data or 'is_active' not in data or not isinstance(data['is_active'], bool):
        return jsonify({'error': 'Request body must contain a boolean "is_active" field'}), 400
    is_active = data['is_active']
    try:
        chefs_crud.update_chef_status(chef_id, is_active)
        return jsonify({'message': f'Chef {chef_id} status updated to {"active" if is_active else "inactive"}'}), 200
    except ValueError as ve: logger.error(f"Error updating chef status {chef_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error updating chef status {chef_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500


# === PRODUCER Endpoints ===
@app.route('/rr/aproducers', methods=['POST'])
def add_producer_endpoint():
    data = request.json;
    if not data: return jsonify({'error': 'Request body required'}), 400
    try: created_producer = producers_crud.create_producer(data); return jsonify(created_producer), 201
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error adding producer: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/login/producers', methods=['POST'])
def login_producer():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body required'}), 400
    identifier = data.get('identifier'); password = data.get('password')
    if not identifier or not password: return jsonify({'error': 'Identifier and password required'}), 400
    try:
        result, status_code = producers_crud.login_producer(identifier, password)
        if status_code == 200: return jsonify(result), status_code
        else: logger.warning(f'Producer login failed for {identifier}: {result.get("message", "Unknown reason")} ({status_code})'); return jsonify({'error': result.get('message', 'Login failed')}), status_code
    except ValueError as ve: logger.error(f"Producer login DB/Validation error: {ve}"); return jsonify({'error': 'Invalid credentials or account not found.'}), 401 if 'Invalid credentials' in str(ve) or 'not found' in str(ve) else (jsonify({'error': "Login failed due to server issue."}), 500)
    except Exception as e: logger.error(f"Producer login internal error: {e}", exc_info=True); return jsonify({'error': "Internal login error."}), 500

@app.route('/rr/rproducers', methods=['GET'])
@app.route('/rr/rproducers/<producer_id>', methods=['GET'])
def get_producers_endpoint(producer_id=None):
    # Support both /rr/rproducers/<producer_id> and /rr/rproducers?producer_id=...
    producer_id = producer_id or request.args.get('producer_id')
    try:
        data = producers_crud.list_producers(producer_id=producer_id)
        if producer_id and not data:
            return jsonify({'error': 'Producer not found'}), 404
        return jsonify({'message': 'Producers retrieved.', 'data': data}), 200
    except ValueError as ve:
        logger.error(f'Error fetching producers: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error fetching producers: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/producers/<int:producer_id>', methods=['PUT', 'PATCH'])
def update_producer_endpoint(producer_id):
    updates = request.get_json()
    if not updates: return jsonify({'error': 'Request body missing'}), 400
    try:
        producers_crud.update_producer(producer_id, updates)
        updated_producer = producers_crud.list_producers(producer_id=producer_id)
        return jsonify({'message': 'Producer updated successfully', 'data': updated_producer[0] if updated_producer else None}), 200
    except ValueError as ve: logger.warning(f'Producer update validation error {producer_id}: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating producer {producer_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/producers/<int:producer_id>', methods=['DELETE'])
def delete_producer_endpoint(producer_id):
    try:
        success = producers_crud.delete_producer(producer_id)
        if success: return jsonify({'message': f'Producer {producer_id} deleted successfully'}), 200
        else: return jsonify({'error': f'Failed to delete producer {producer_id}'}), 500
    except ValueError as ve: logger.error(f"Error deleting producer {producer_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting producer {producer_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/producers/<int:producer_id>/status', methods=['PATCH'])
def update_producer_status_endpoint(producer_id):
    data = request.get_json()
    if not data or 'is_active' not in data or not isinstance(data['is_active'], bool):
        return jsonify({'error': 'Request body must contain a boolean "is_active" field'}), 400
    is_active = data['is_active']
    try:
        producers_crud.update_producer_status(producer_id, is_active)
        return jsonify({'message': f'Producer {producer_id} status updated to {"active" if is_active else "inactive"}'}), 200
    except ValueError as ve: logger.error(f"Error updating producer status {producer_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error updating producer status {producer_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500


# === TRANSPORTER Endpoints (Corrected & Complete) ===
@app.route('/rr/transporters/signup', methods=['POST'])
def signup_transporter_endpoint():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body missing'}), 400
    try: result = transporters_crud.create_transporter(data); print(result);return jsonify(result), 201
    except ValueError as ve: logger.warning(f'Transporter signup validation error: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error creating transporter: {e}', exc_info=True); return jsonify({'error': 'Internal server error during signup'}), 500

@app.route('/rr/transporters/login', methods=['POST'])
def login_transporter_endpoint():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body missing'}), 400
    identifier = data.get('identifier'); password = data.get('password')
    if not identifier or not password: return jsonify({'error': 'Identifier and password required'}), 400
    try:
        result, status_code = transporters_crud.login_transporter(identifier, password)
        print(result)
        return jsonify(result), status_code
    except ValueError as ve: logger.error(f"Transporter login DB/Validation error: {ve}"); return jsonify({'error': 'Invalid credentials or account not found.'}), 401 if 'Invalid credentials' in str(ve) or 'not found' in str(ve) else (jsonify({'error': "Login failed due to server issue."}), 500)
    except Exception as e: logger.error(f"Transporter login internal error: {e}", exc_info=True); return jsonify({'error': "Internal login error."}), 500

@app.route('/rr/transporters', methods=['GET'])
@app.route('/rr/transporters/<transporter_id>', methods=['GET'])
def get_transporters_endpoint(transporter_id=None):
    # Support both /rr/transporters/<transporter_id> and /rr/transporters?transporter_id=...
    transporter_id = transporter_id or request.args.get('transporter_id')
    try:
        data = transporters_crud.list_transporters(transporter_id=transporter_id)
        # If transporter_id is specified, return only the first match (or 404 if not found)
        if transporter_id:
            if data and len(data) > 0:
                return jsonify({'message': 'Transporter retrieved.', 'data': data[0]}), 200
            else:
                return jsonify({'error': 'Transporter not found'}), 404
        return jsonify({'message': 'Transporters retrieved.', 'data': data}), 200
    except ValueError as ve:
        logger.error(f'Error fetching transporters: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error fetching transporters: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/transporters/<int:transporter_id>', methods=['PUT', 'PATCH'])
def update_transporter_endpoint(transporter_id):
    updates = request.get_json();
    if not updates: return jsonify({'error': 'Request body missing'}), 400
    try:
        transporters_crud.update_transporter(transporter_id, updates)
        updated_profile = transporters_crud.list_transporters(transporter_id=transporter_id)
        return jsonify({'message': 'Transporter updated successfully', 'data': updated_profile[0] if updated_profile else None}), 200
    except ValueError as ve: logger.warning(f'Transporter update validation error {transporter_id}: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating transporter {transporter_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/transporters/<int:transporter_id>', methods=['DELETE'])
def delete_transporter_endpoint(transporter_id):
    try:
        success = transporters_crud.delete_transporter(transporter_id)
        if success: return jsonify({'message': f'Transporter {transporter_id} deleted successfully'}), 200
        else: return jsonify({'error': f'Failed to delete transporter {transporter_id}'}), 500
    except ValueError as ve: logger.error(f"Error deleting transporter {transporter_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting transporter {transporter_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/transporters/<int:transporter_id>/status', methods=['PATCH'])
@app.route('/rr/transporters/status', methods=['PATCH'])
def update_transporter_status_endpoint(transporter_id=None):
    # Support both /rr/transporters/<int:transporter_id>/status and /rr/transporters/status?transporter_id=...
    transporter_id = transporter_id or request.args.get('transporter_id')
    data = request.get_json()
    if not transporter_id:
        return jsonify({'error': 'transporter_id is required'}), 400
    if not data or 'is_active' not in data or not isinstance(data['is_active'], bool):
        return jsonify({'error': 'Request body must contain a boolean "is_active" field'}), 400
    is_active = data['is_active']
    try:
        transporters_crud.update_transporter_status(transporter_id, is_active)
        return jsonify({'message': f'Transporter {transporter_id} status updated to {"active" if is_active else "inactive"}'}), 200
    except ValueError as ve:
        logger.error(f"Error updating transporter status {transporter_id}: {ve}")
        return jsonify({'error': str(ve)}), 500
    except Exception as e:
        logger.error(f"Unexpected error updating transporter status {transporter_id}: {e}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500


# === STAKEHOLDER Endpoints ===
@app.route('/rr/create_stakeholders', methods=['POST'])
def add_stakeholder_endpoint():
    data = request.json;
    if not data: return jsonify({'error': 'Request body required'}), 400
    try: created_stakeholder = stakeholders_crud.create_stakeholder(data); return jsonify(created_stakeholder), 201
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error adding stakeholder: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/login/stakeholders', methods=['POST'])
def login_stakeholder():
    data = request.get_json();
    if not data: return jsonify({'error': 'Request body required'}), 400
    identifier = data.get('identifier'); password = data.get('password')
    if not identifier or not password: return jsonify({'error': 'Identifier and password required'}), 400
    try:
        result, status_code = stakeholders_crud.login_stakeholder(identifier, password)
        if status_code == 200: return jsonify(result), status_code
        else: logger.warning(f'Stakeholder login failed for {identifier}: {result.get("message", "Unknown reason")} ({status_code})'); return jsonify({'error': result.get('message', 'Login failed')}), status_code
    except ValueError as ve: logger.error(f"Stakeholder login DB/Validation error: {ve}"); return jsonify({'error': 'Invalid credentials or account not found.'}), 401 if 'Invalid credentials' in str(ve) or 'not found' in str(ve) else (jsonify({'error': "Login failed due to server issue."}), 500)
    except Exception as e: logger.error(f"Stakeholder login internal error: {e}", exc_info=True); return jsonify({'error': "Internal login error."}), 500

@app.route('/rr/rstakeholders', methods=['GET'])
@app.route('/rr/rstakeholders/<int:stakeholder_id>', methods=['GET'])
def get_stakeholders_endpoint(stakeholder_id=None):
    try:
        if stakeholder_id:
            data = stakeholders_crud.get_stakeholder_by_id(stakeholder_id)
            if data is None: return jsonify({'error': 'Stakeholder not found'}), 404
            for key, value in data.items():
                if isinstance(value, (datetime, date)): data[key] = value.isoformat()
            return jsonify({'message': 'Stakeholder retrieved.', 'data': data}), 200
        else:
            data = stakeholders_crud.list_stakeholders()
            return jsonify({'message': 'Stakeholders retrieved.', 'data': data}), 200
    except ValueError as ve: logger.error(f'Error fetching stakeholders: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error fetching stakeholders: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/stakeholders/<int:stakeholder_id>', methods=['PUT', 'PATCH'])
def update_stakeholder_endpoint(stakeholder_id):
    updates = request.get_json()
    if not updates: return jsonify({'error': 'Request body missing'}), 400
    try:
        stakeholders_crud.update_stakeholder(stakeholder_id, updates)
        updated_stakeholder = stakeholders_crud.get_stakeholder_by_id(stakeholder_id)
        if updated_stakeholder:
             for key, value in updated_stakeholder.items():
                 if isinstance(value, (datetime, date)): updated_stakeholder[key] = value.isoformat()
        return jsonify({'message': 'Stakeholder updated successfully', 'data': updated_stakeholder}), 200
    except ValueError as ve: logger.warning(f'Stakeholder update validation error {stakeholder_id}: {ve}'); return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating stakeholder {stakeholder_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/stakeholders/<int:stakeholder_id>', methods=['DELETE'])
def delete_stakeholder_endpoint(stakeholder_id):
    try:
        success = stakeholders_crud.delete_stakeholder(stakeholder_id)
        if success: return jsonify({'message': f'Stakeholder {stakeholder_id} deleted successfully'}), 200
        else: return jsonify({'error': f'Failed to delete stakeholder {stakeholder_id}'}), 500
    except ValueError as ve: logger.error(f"Error deleting stakeholder {stakeholder_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting stakeholder {stakeholder_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

@app.route('/rr/stakeholders/<int:stakeholder_id>/status', methods=['PATCH'])
def update_stakeholder_status_endpoint(stakeholder_id):
    data = request.get_json()
    if not data or 'is_active' not in data or not isinstance(data['is_active'], bool):
        return jsonify({'error': 'Request body must contain a boolean "is_active" field'}), 400
    is_active = data['is_active']
    try:
        stakeholders_crud.update_stakeholder_status(stakeholder_id, is_active)
        return jsonify({'message': f'Stakeholder {stakeholder_id} status updated to {"active" if is_active else "inactive"}'}), 200
    except ValueError as ve: logger.error(f"Error updating stakeholder status {stakeholder_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error updating stakeholder status {stakeholder_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500


# === PRODUCT TYPE Endpoints (Herbals, Meals, Produce, Gadgets, Spices) ===

# --- Herbals ---
@app.route('/rr/aherbals', methods=['POST'])
def add_herbal_endpoint():
    data = request.json;
    if not data: return jsonify({'error': 'Request body required'}), 400
    try: created_herbal = herbals_crud.create_herbal(data); return jsonify(created_herbal), 201
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error adding herbal: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/rherbals', methods=['GET'])
@app.route('/rr/rherbals/<int:herbal_id>', methods=['GET'])
def get_herbals_endpoint(herbal_id=None):
    try:
        if herbal_id: data = herbals_crud.get_herbal_by_id(herbal_id)
        else: data = herbals_crud.list_herbals()
        if herbal_id and data is None: return jsonify({'error': 'Herbal not found'}), 404
        return jsonify({'message': 'Herbals retrieved.', 'data': data or []}), 200
    except ValueError as ve: logger.error(f'Error fetching herbals: {ve}'); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f'Error fetching herbals: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/herbals/<int:herbal_id>', methods=['PUT','PATCH'])
def update_herbal_endpoint(herbal_id):
    updates = request.json;
    if not updates: return jsonify({'error': 'Request body required'}), 400
    try: herbals_crud.update_herbal(herbal_id, updates); return jsonify({'message': 'Herbal updated successfully'}), 200
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating herbal {herbal_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/herbals/<int:herbal_id>', methods=['DELETE'])
def delete_herbal_endpoint(herbal_id):
    try: success = herbals_crud.delete_herbal(herbal_id); return jsonify({'message': f'Herbal {herbal_id} deleted'}), 200 if success else (jsonify({'error': f'Failed to delete herbal {herbal_id}'}), 500)
    except ValueError as ve: logger.error(f"Error deleting herbal {herbal_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting herbal {herbal_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

# --- Meals ---
# GET handled by /rr/meals
@app.route('/rr/meals', methods=['GET'])
@app.route('/rr/meals/<meal_id>', methods=['GET'])
def get_meal_endpoint(meal_id=None):
    try:
        if meal_id is not None:
            data = meals_crud.get_meal_by_id(meal_id)
            if data:
                return jsonify({'message': 'Meal retrieved.', 'data': data}), 200
            else:
                return jsonify({'error': 'Meal not found'}), 404
        else:
            data = meals_crud.list_meals()
            return jsonify({'message': 'Meals retrieved.', 'data': data or []}), 200
    except ValueError as ve:
        logger.error(f'Error fetching meal {meal_id}: {ve}')
        return jsonify({'error': str(ve)}), 500
    except Exception as e:
        logger.error(f'Error fetching meal {meal_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/umeals/<meal_id>', methods=['PUT', 'PATCH'])
def update_meal_endpostr(meal_id):
    updates = request.json;
    if not updates: return jsonify({'error': 'Request body required'}), 400
    try: meals_crud.update_meal(meal_id, updates); return jsonify({'message': 'Meal updated successfully'}), 200
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating meal {meal_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/dmeals/<meal_id>', methods=['DELETE'])
def delete_meal_endpostr(meal_id):
    try: success = meals_crud.delete_meal(meal_id); return jsonify({'message': f'Meal {meal_id} deleted'}), 200 if success else (jsonify({'error': f'Failed to delete meal {meal_id}'}), 500)
    except ValueError as ve: logger.error(f"Error deleting meal {meal_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting meal {meal_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

# --- Produce ---
# GET/POST handled by /rr/produce
@app.route('/rr/produce', methods=['GET'])
@app.route('/rr/produce/<produce_id>', methods=['GET'])
def get_produce_by_id_endpoint(produce_id=None):
    try:
        if produce_id is not None:
            data = produce_crud.get_produce_by_id(produce_id)
            if data:
                return jsonify({'message': 'Produce retrieved.', 'data': data}), 200
            else:
                return jsonify({'error': 'Produce not found'}), 404
        else:
            data = produce_crud.list_produce()
            return jsonify({'message': 'Produce retrieved.', 'data': data or []}), 200
    except ValueError as ve:
        logger.error(f'Error fetching produce {produce_id}: {ve}')
        return jsonify({'error': str(ve)}), 500
    except Exception as e:
        logger.error(f'Error fetching produce {produce_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/uproduce/<produce_id>', methods=['PUT','PATCH'])
@app.route('/rr/uproduce', methods=['PUT','PATCH'])
def update_produce_endpoint(produce_id=None):
    # Support both /rr/uproduce/<produce_id> and /rr/uproduce?produce_id=...
    produce_id = produce_id or request.args.get('produce_id')
    updates = request.json
    if not updates:
        return jsonify({'error': 'Request body required'}), 400
    if not produce_id:
        return jsonify({'error': 'produce_id is required'}), 400
    try:
        produce_crud.update_produce(produce_id, updates)
        return jsonify({'message': 'Produce updated successfully'}), 200
    except ValueError as ve:
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error updating produce {produce_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/uproduce/<produce_id>', methods=['DELETE'])
def delete_produce_endpoint(produce_id):
    try: success = produce_crud.delete_produce(produce_id); return jsonify({'message': f'Produce {produce_id} deleted'}), 200 if success else (jsonify({'error': f'Failed to delete produce {produce_id}'}), 500)
    except ValueError as ve: logger.error(f"Error deleting produce {produce_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting produce {produce_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

# --- Gadgets ---
# GET/POST handled by /rr/gadgets
@app.route('/rr/gadgets', methods=['GET'])
@app.route('/rr/gadgets/<int:gadget_id>', methods=['GET'])
def get_gadget_by_id_endpoint(gadget_id=None):
    try:
        if gadget_id is not None:
            data = gadgets_crud.get_gadget_by_id(gadget_id)
            if data:
                return jsonify({'message': 'Gadget retrieved.', 'data': data}), 200
            else:
                return jsonify({'error': 'Gadget not found'}), 404
        else:
            data = gadgets_crud.list_gadgets()
            return jsonify({'message': 'Gadgets retrieved.', 'data': data or []}), 200
    except ValueError as ve:
        logger.error(f'Error fetching gadget {gadget_id}: {ve}')
        return jsonify({'error': str(ve)}), 500
    except Exception as e:
        logger.error(f'Error fetching gadget {gadget_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/gadgets/<int:gadget_id>', methods=['PUT','PATCH'])
def update_gadget_endpoint(gadget_id):
    updates = request.json;
    if not updates: return jsonify({'error': 'Request body required'}), 400
    try: gadgets_crud.update_gadget(gadget_id, updates); return jsonify({'message': 'Gadget updated successfully'}), 200
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating gadget {gadget_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/gadgets/<int:gadget_id>', methods=['DELETE'])
def delete_gadget_endpoint(gadget_id):
    try: success = gadgets_crud.delete_gadget(gadget_id); return jsonify({'message': f'Gadget {gadget_id} deleted'}), 200 if success else (jsonify({'error': f'Failed to delete gadget {gadget_id}'}), 500)
    except ValueError as ve: logger.error(f"Error deleting gadget {gadget_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting gadget {gadget_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500

# --- Spices ---
# GET/POST handled by /rr/spices and /rr/rspices
@app.route('/rr/spices', methods=['GET'])
@app.route('/rr/spices/<int:spice_id>', methods=['GET'])
def get_spice_by_id_endpoint(spice_id=None):
    try:
        if spice_id is not None:
            data = spices_crud.get_spice_by_id(spice_id)
            if data:
                return jsonify({'message': 'Spice retrieved.', 'data': data}), 200
            else:
                return jsonify({'error': 'Spice not found'}), 404
        else:
            data = spices_crud.list_spices()
            return jsonify({'message': 'Spices retrieved.', 'data': data or []}), 200
    except ValueError as ve:
        logger.error(f'Error fetching spice {spice_id}: {ve}')
        return jsonify({'error': str(ve)}), 500
    except Exception as e:
        logger.error(f'Error fetching spice {spice_id}: {e}', exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/spices/<int:spice_id>', methods=['PUT', 'PATCH'])
def update_spice_endpoint(spice_id):
    updates = request.json;
    if not updates: return jsonify({'error': 'Request body required'}), 400
    try: spices_crud.update_spice(spice_id, updates); return jsonify({'message': 'Spice updated successfully'}), 200
    except ValueError as ve: return jsonify({'error': str(ve)}), 400
    except Exception as e: logger.error(f'Error updating spice {spice_id}: {e}', exc_info=True); return jsonify({'error': 'Internal server error'}), 500
@app.route('/rr/spices/<int:spice_id>', methods=['DELETE'])
def delete_spice_endpoint(spice_id):
    try: success = spices_crud.delete_spice(spice_id); return jsonify({'message': f'Spice {spice_id} deleted'}), 200 if success else (jsonify({'error': f'Failed to delete spice {spice_id}'}), 500)
    except ValueError as ve: logger.error(f"Error deleting spice {spice_id}: {ve}"); return jsonify({'error': str(ve)}), 500
    except Exception as e: logger.error(f"Unexpected error deleting spice {spice_id}: {e}", exc_info=True); return jsonify({'error': 'Internal server error'}), 500


# --- Order Status Update Endpoint ---
@app.route('/rr/orders/<int:order_id>/status', methods=['PATCH'])
def update_order_status_endpoint(order_id):
    data = request.get_json()
    if not data or 'order_status' not in data:
        return jsonify({'error': 'Request body must contain "order_status" field'}), 400
    new_status = data['order_status']
    # Optional: Add role checking here based on authenticated user if needed
    try:
        success = orders_crud.update_order_status(order_id, new_status)
        if success:
            return jsonify({'message': f'Order {order_id} status updated to {new_status}'}), 200
        else:
            return jsonify({'error': f'Failed to update status for order {order_id}'}), 500
    except ValueError as ve: # Catch invalid status or DB errors
        logger.error(f"Error updating order status {order_id}: {ve}")
        return jsonify({'error': str(ve)}), 400 if 'Invalid target order status' in str(ve) else 500
    except Exception as e:
        logger.error(f"Unexpected error updating order status {order_id}: {e}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

#create order endpoint
@app.route('/rr/Aorders', methods=['POST'])
def create_order_endpoint():
    data = request.get_json()
    logger.debug(f"Received payload: {data}")
    if not data:
        return jsonify({'error': 'Request body required'}), 400

    try:
        user_id = data.get('user_id')
        order_type = data.get('order_type')
        product_id = data.get('product_id')
        delivery_address = data.get('delivery_address')
        order_status = data.get('order_status', 'Pending')
        total_price = data.get('total_price', 0.0)
        notes = data.get('notes')
        payment_status = data.get('payment_status', 'Pending')
        payment_mode = data.get('payment_mode', 'cash')
        amount_paid = data.get('amount_paid', 0.0)
        transaction_id = data.get('transaction_id')
        quantity = data.get('quantity', 1)
        transporter_id = data.get('transporter_id')
        items = data.get('items')  # Keep items for passing to create_order

        # Extract chef_id and producer_id from items[0] if present, else from top-level
        chef_id = None
        producer_id = None
        if isinstance(items, list) and len(items) > 0:
            first_item = items[0]
            chef_id = first_item.get('chef_id')
            producer_id = first_item.get('producer_id')
            # Also allow product_id and quantity to be overridden by item
            product_id = first_item.get('product_id', product_id)
            quantity = first_item.get('quantity', quantity)
        else:
            chef_id = data.get('chef_id')
            producer_id = data.get('producer_id')

        # Validation: at least one of chef_id or producer_id must be set, but not both
        if (chef_id is None and producer_id is None) or (chef_id and producer_id):
            return jsonify({'error': 'Exactly one of chef_id or producer_id must be set for an order.'}), 400

        # Call the create_order function
        result = orders_crud.create_order(
            user_id=user_id,
            order_type=order_type,
            product_id=product_id,
            chef_id=chef_id,
            producer_id=producer_id,
            delivery_address=delivery_address,
            order_status=order_status,
            total_price=total_price,
            notes=notes,
            payment_status=payment_status,
            payment_mode=payment_mode,
            amount_paid=amount_paid,
            transaction_id=transaction_id,
            quantity=quantity,
            transporter_id=transporter_id,
            items=items  # Pass items to create_order
        )

        # Return the result from the function
        if result.get("success"):
            return jsonify(result), 201
        else:
            return jsonify(result), 400

    except ValueError as ve:
        logger.error(f"Order creation validation error: {ve}")
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f"Unexpected error creating order: {e}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500

# --- Payment Endpoints (Unchanged) ---
# --- Payment Endpoints (Corrected Syntax) ---
#import uuid # Ensure uuid is imported if not already done globally
#from flask import jsonify, request # Ensure these are imported
#import logging # Ensure logger is imported and configured

# Assuming logger is configured globally, e.g.:
# logging.basicConfig(level=logging.INFO)
# logger = logging.getLogger(__name__)
# Assuming payment functions (create_payment_paypal, etc.) are defined elsewhere

@app.route('/rr/pay', methods=['POST'])
def create_payment_route():
    # Use request.get_json() for better error handling and content-type checking
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    amount = data.get('amount')
    description = data.get('description', "Payment for ZINZI health service") # Default description

    if amount is None: # Check specifically for None, 0 might be valid?
        return jsonify({"error": "Amount is required"}), 400

    try:
        # Assuming create_payment_paypal handles potential float conversion errors
        response = create_payment_paypal(amount, description)
        # Determine status code based on the success flag from the payment function
        status_code = 201 if response.get("success") else 400 # Use 201 for successful creation
        return jsonify(response), status_code
    except ValueError as ve: # Catch potential validation errors from payment function
         logger.error(f"Value error creating PayPal payment: {ve}")
         return jsonify({"error": str(ve)}), 400
    except Exception as e: # Catch unexpected errors
        logger.error(f"Unexpected error creating PayPal payment: {e}", exc_info=True)
        return jsonify({"error": "Internal server error during payment creation."}), 500


@app.route('/rr/execute', methods=['GET'])
def execute_payment_route():
    # Get parameters from URL query string
    payment_id = request.args.get('paymentId')
    payer_id = request.args.get('PayerID')

    if not payment_id or not payer_id:
        return jsonify({"error": "paymentId and PayerID are required query parameters"}), 400

    try:
        response = execute_payment_paypal(payment_id, payer_id)
        # Determine status code based on the 'status' field in the response dict
        status_code = 200 if response.get("status") == "success" else 400 # Consider other failure statuses?
        return jsonify(response), status_code
    except Exception as e: # Catch unexpected errors
        logger.error(f"Unexpected error executing PayPal payment (ID: {payment_id}): {e}", exc_info=True)
        return jsonify({"error": "Internal server error during payment execution."}), 500

@app.route('/rr/cancel', methods=['GET'])
def handle_payment_cancellation_route():
    # This route is typically where PayPal redirects if the user cancels
    try:
        response = handle_payment_cancellation_paypal()
        # Assuming the handler always returns a valid response structure
        return jsonify(response), 200 # OK status even for cancellation
    except Exception as e: # Catch unexpected errors in the handler
        logger.error(f"Unexpected error handling PayPal cancellation: {e}", exc_info=True)
        return jsonify({"error": "Internal server error during cancellation handling."}), 500

@app.route('/rr/create_stripe_payment', methods=['POST'])
def create_stripe_payment_route():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    amount = data.get('amount')
    if amount is None: # Check specifically for None
        return jsonify({"error": "Amount is required"}), 400

    try:
        # Assuming create_stripe_payment handles potential float conversion errors
        response = create_stripe_payment(amount) # Add description/currency if needed
        status_code = 201 if response.get("status") == "success" else 400
        return jsonify(response), status_code # No semicolon needed
    except ValueError as ve:
         logger.error(f"Value error creating Stripe payment: {ve}")
         return jsonify({"error": str(ve)}), 400
    except Exception as e:
        logger.error(f"Error creating Stripe payment: {e}", exc_info=True)
        return jsonify({"error": "Internal server error during payment creation."}), 500

@app.route('/rr/confirm_stripe_payment', methods=['POST'])
def confirm_stripe_payment():
    # Note: Stripe confirmation is often handled client-side with client_secret.
    # This endpoint might be for server-side checks or specific flows.
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    payment_intent_id = data.get('paymentIntentId')
    payment_method_id = data.get('paymentMethodId') # Optional depending on flow

    if not payment_intent_id:
        return jsonify({"error": "paymentIntentId is required"}), 400

    try:
        response = execute_stripe_payment(payment_intent_id, payment_method_id)
        # Status check needs careful handling based on Stripe's possible statuses
        if response.get("status") == "success":
            status_code = 200
        elif response.get("status") in ["requires_action", "requires_confirmation", "processing"]:
            status_code = 202 # Accepted, but more action needed/pending
        else: # failure or other
            status_code = 400
        return jsonify(response), status_code # No semicolon needed
    except Exception as e:
        logger.error(f"Error confirming/checking Stripe payment (Intent ID: {payment_intent_id}): {e}", exc_info=True)
        return jsonify({"error": "Internal server error during payment confirmation."}), 500

@app.route('/rr/cancel_stripe_payment', methods=['POST'])
def cancel_stripe_payment():
    # This might be called if the client explicitly cancels, or handle implicitly
    try:
        response = handle_stripe_payment_cancellation()
        return jsonify(response), 200 # OK status for cancellation acknowledgement
    except Exception as e:
        logger.error(f"Unexpected error handling Stripe cancellation: {e}", exc_info=True)
        return jsonify({"error": "Internal server error during cancellation handling."}), 500


@app.route('/rr/request_momo_payment', methods=['POST'])
def request_momo_payment_route():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body required"}), 400

    try:
        amount = data.get('amount')
        currency = data.get('currency', 'EUR') # Default currency
        # Generate external_id if not provided by client
        external_id = data.get('external_id', str(uuid.uuid4()))
        payer_number = data.get('payer_number')
        payer_message = data.get('payer_message', 'Payment') # Default message
        payee_note = data.get('payee_note', 'Payment Request') # Default note

        # Check required fields
        if amount is None or payer_number is None: # Check for None explicitly
            return jsonify({"error": "Amount and payer_number are required"}), 400

        # Convert amount to float *inside* the try block
        amount_float = float(amount)

        result = request_momo_payment(
            amount_float, currency, external_id, payer_number, payer_message, payee_note
        )

        # Determine status code based on result
        if result.get("status") == "pending":
            status_code = 202 # Accepted
        elif result.get("status") == "failure":
            status_code = 400 # Bad Request or other failure
        else:
            status_code = 500 # Default to server error if status is unexpected

        return jsonify(result), status_code # No semicolon needed

    except ValueError as ve: # Catch specific conversion/validation errors
        logger.error(f"Invalid input for MoMo payment request: {ve}")
        return jsonify({"error": f"Invalid input: {ve}"}), 400 # No semicolon needed
    except Exception as e:
        logger.error(f"Error requesting MoMo payment: {e}", exc_info=True)
        return jsonify({"error": "Internal server error requesting MoMo payment."}), 500 # No semicolon needed

@app.route('/rr/check_momo_payment_status', methods=['GET'])
def check_momo_payment_status_route():
    transaction_ref = request.args.get('transaction_ref')
    if not transaction_ref:
        return jsonify({"error": "transaction_ref query parameter is required"}), 400

    try:
        result = check_momo_payment_status(transaction_ref)

        # Determine status code based on result
        if result.get("status") == "success":
            status_code = 200 # OK, status found
        elif result.get("status") == "not_found":
            status_code = 404 # Not Found
        elif result.get("status") == "failure":
            status_code = 400 # Indicate failure (e.g., API error)
        else:
            status_code = 500 # Unexpected status

        return jsonify(result), status_code # No semicolon needed
    except Exception as e:
        logger.error(f"Error checking MoMo status (Ref: {transaction_ref}): {e}", exc_info=True)
        return jsonify({"error": "Internal server error checking MoMo status."}), 500 # No semicolon needed

@app.route('/rr/momo_callback', methods=['POST', 'PUT'])
def momo_callback():
    # This endpoint receives asynchronous notifications from MoMo
    try:
        notification_data = request.get_json()
        # Always log received callbacks for debugging
        logger.info(f"MoMo Callback Received: {notification_data}")

        if not notification_data or not isinstance(notification_data, dict):
            logger.error("Invalid MoMo callback format received.")
            return jsonify({"error": "Invalid callback format"}), 400 # No semicolon needed

        # TODO: Implement logic to securely process the notification_data
        # - Verify the source if possible (e.g., IP check, signature validation if offered)
        # - Extract relevant info (transaction ID, status, etc.)
        # - Update your internal order/payment status based on the notification
        # - Handle potential duplicate callbacks idempotently

        # Acknowledge receipt
        return jsonify({"message": "Callback received and acknowledged"}), 200 # No semicolon needed

    except Exception as e:
        logger.error(f"Error processing MoMo callback: {e}", exc_info=True)
        # Avoid returning detailed errors in callback responses if possible
        return jsonify({"error": "Failed to process callback"}), 500 # No semicolon needed

# --- Main Execution ---
if __name__ == '__main__':
    host = os.getenv('FLASK_HOST', '0.0.0.0')
    port = int(os.getenv('FLASK_PORT', 5000))
    debug_mode = os.getenv('FLASK_DEBUG', 'False').lower() in ['true', '1', 't']

    # Initial Payment Gateway Configurations
    paypal_client_id = os.getenv('PAYPAL_CLIENT_ID'); paypal_client_secret = os.getenv('PAYPAL_CLIENT_SECRET'); paypal_mode = os.getenv('PAYPAL_MODE', 'sandbox')
    if paypal_client_id and paypal_client_secret: configure_paypal(paypal_mode, paypal_client_id, paypal_client_secret)
    stripe_secret_key = os.getenv('STRIPE_SECRET_KEY')
    if stripe_secret_key: configure_stripe(stripe_secret_key)

    #app.run(debug=debug_mode, host=host, port=port)
    handler = VercelAdapter(app)


    ''' fix python 3 syntax errors in the following lines of the integrated_backend.py file : lines 84-88, 117-477, 545-642,  and finally line 1132-1148  without introducing further syntax errors for pylance to compleain. make sure no features are lost '''
