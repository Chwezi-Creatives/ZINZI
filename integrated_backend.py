
# Cspell:disable

import os
import json
import random
import base64
import time
import uuid
import string
from datetime import datetime, timedelta, date
from typing import Dict, Any, Optional, List, Tuple, Union # Added Union, Tuple
#import mealrecommendation2 currently not implemented
from dotenv import load_dotenv
from async_lru import alru_cache # Import alru_cache for async caching
import bcrypt
# import psycopg2 # Removed synchronous driver
import asyncpg # Added asynchronous driver
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google.auth.exceptions import RefreshError
from email.mime.text import MIMEText
import logging
import paypalrestsdk
import stripe
import requests # Keeping synchronous requests for payment gateways for now
# from flask import Flask, request, jsonify # Removed Flask imports
# from flask_cors import CORS

# --- FastAPI Imports ---
from fastapi import FastAPI, Request, Depends, HTTPException, status, Body, Query, Path
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager # For lifespan manager
from fastapi.responses import ORJSONResponse

# --- Configuration Loading ---
load_dotenv()  # Load environment variables first

# --- Logging Configuration ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

try:
    from utils import lowercase_keys
except ImportError:
    # Define a simple fallback if utils is missing
    def lowercase_keys(d):
        if isinstance(d, dict):
            return {k.lower(): v for k, v in d.items()}
        return d
    logger.warning("utils.lowercase_keys not found, using basic fallback.")

# --- Database Connection Pool (asyncpg) ---
db_pool: Optional[asyncpg.Pool] = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the database connection pool lifecycle."""
    global db_pool
    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME", "postgres")
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    missing_vars = [var for var, val in locals().items() if var.startswith('db_') and not val]
    if not db_user: missing_vars.append("DB_USER")
    if missing_vars:
        error_msg = f"Database POOLED connection details missing: {', '.join(missing_vars)}."
        logger.critical(error_msg)
        # Indicate failure but allow app to start (maybe partially)
        db_pool = None # Ensure pool is None
        yield
        return # Exit early

    db_url = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}?ssl=require"
    logger.info(f"Attempting to connect to database: {db_host}:{db_port}/{db_name}")

    try:
        db_pool = await asyncpg.create_pool(
            db_url,
            min_size=1,
            max_size=10, # Example pool size
            timeout=10,
            command_timeout=60
        )
        logger.info("Database connection pool created successfully.")
        yield # Application runs here
    except (asyncpg.exceptions.PostgresError, OSError, Exception) as e:
        logger.critical(f"Failed to create database pool: {e}", exc_info=True)
        db_pool = None # Ensure pool is None on failure
        yield # Allow app startup even if pool fails
    finally:
        if db_pool:
            await db_pool.close()
            logger.info("Database connection pool closed.")

# --- Database Dependency ---
from typing import AsyncGenerator

async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """FastAPI dependency to get a database connection from the pool."""
    if db_pool is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database service is unavailable.")
    async with db_pool.acquire() as connection:
        yield connection

# --- Helper Functions (Unchanged unless they used DB directly) ---
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
    """Checks for required fields, raising HTTPException if missing/empty."""
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
        # Raise HTTPException for API error handling
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=". ".join(error_messages))

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
        # Fallback to comma split if JSON decode fails
        return [item.strip() for item in json_string.split(',') if item.strip()]


# --- Base Class for Common DB Operations (Updated for asyncpg) ---
class BaseRepository:
    async def _execute_query(self, conn: asyncpg.Connection, sql: str, params: Optional[tuple] = None, fetch_one: bool = False, fetch_all: bool = False, commit: bool = False, returning_id_column: Optional[str] = None) -> Any:
        """Executes SQL query asynchronously with asyncpg."""
        results = None
        returned_id = None
        params = params or () # Ensure params is a tuple
        logger.debug(f"Executing SQL: {sql} with params: {params}")

        try:
            # asyncpg handles transactions often via context managers, but explicit check might be needed if commit=True is used outside a transaction block
            # For simplicity, assuming operations are atomic or wrapped in transactions at a higher level if needed.
            # The `commit` flag might become less relevant with asyncpg's transaction handling.

            if returning_id_column:
                # fetchrow returns a Record or None
                row = await conn.fetchrow(sql, *params)
                if row:
                    returned_id = row[0] # Access by index (usually the ID)
                    logger.debug(f"Returning {returning_id_column}: {returned_id}")
            elif fetch_one:
                row = await conn.fetchrow(sql, *params)
                if row:
                    results = dict(row) # Convert Record to dict
                logger.debug(f"Fetched one: {results}")
            elif fetch_all:
                rows = await conn.fetch(sql, *params)
                results = [dict(row) for row in rows] # Convert list of Records to list of dicts
                logger.debug(f"Fetched all ({len(results)} rows)")
            else: # Just execute (INSERT, UPDATE, DELETE without RETURNING)
                await conn.execute(sql, *params)
                logger.debug("Executed statement without fetching.")

            # Note: Commits are typically handled by transaction blocks (`async with conn.transaction():`)
            # The `commit` flag here might need rethinking depending on how transactions are managed in calling methods.
            if commit:
                 logger.warning("Manual commit requested in _execute_query. Ensure this is intended within the transaction context.")
                 # If not in a transaction, this doesn't do much. If in one, it might commit early.

            if returning_id_column:
                return returned_id
            else:
                return results

        except asyncpg.PostgresError as e:
            logger.error(f"Database Error executing SQL: {sql} | Params: {params} | Error: {e}", exc_info=True)
            # Raise HTTPException for FastAPI to handle
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Database operation failed: {e}") from e
        except Exception as e:
            logger.error(f"Unexpected Error during DB operation: {sql} | Params: {params} | Error: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected error occurred during database operation.") from e


# --- Authentication Class (Updated for asyncpg) ---
class AuthenticationAndUsers(BaseRepository):
    async def signup_user(self, conn: asyncpg.Connection, name: str, email: str, password: str, image: Optional[str] = None) -> Dict[str, Any]:
        """Signs up a new user asynchronously."""
        hashed_pw = hash_password(password)
        verification_code = generate_random_code()
        user_id = None

        try:
             # Use a transaction block for atomicity
            async with conn.transaction():
                # 1. Check if email exists
                email_query = "SELECT user_id FROM users WHERE lower(email) = lower($1)"
                existing_email = await conn.fetchval(email_query, email) # fetchval gets single value
                if existing_email:
                    raise ValueError(f"Email '{email}' is already registered.") # Raise ValueError for specific handling

                # 2. Check if name exists
                name_query = "SELECT user_id FROM users WHERE lower(name) = lower($1)"
                existing_name = await conn.fetchval(name_query, name)
                if existing_name:
                    raise ValueError(f"Name '{name}' is already taken.")

                # 3. Insert new user
                if image is not None:
                    insert_query = """
                        INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified, image)
                        VALUES ($1, $2, $3, NOW(), FALSE, $4) RETURNING user_id
                    """
                    user_id = await conn.fetchval(insert_query, name, email, hashed_pw, image)
                else:
                    insert_query = """
                        INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified)
                        VALUES ($1, $2, $3, NOW(), FALSE) RETURNING user_id
                    """
                    user_id = await conn.fetchval(insert_query, name, email, hashed_pw)

                if not user_id:
                     raise asyncpg.PostgresError("User insertion failed to return user_id.") # Use a more specific error

                # 4. Insert/Update verification code (Optional - commented out in original)
                # verification_query = """..."""
                # await conn.execute(verification_query, user_id, verification_code)

            # 5. Send verification email (outside transaction) - Remains synchronous for now
            # self.send_verification_email_gmail(email, verification_code) # If uncommented, this will block

            logger.info(f"User '{name}' (ID: {user_id}) registered successfully.")
            return {"user_id": user_id, "success": True}

        except ValueError as e: # Catch specific validation errors
            logger.warning(f"Signup validation failed for {email}: {e}")
            # Re-raise as HTTPException for the API layer
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
        except (asyncpg.PostgresError) as e: # Catch database errors
            logger.error(f"Database error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An internal error occurred during signup.") from e
        except Exception as e: # Catch unexpected errors
            logger.error(f"Unexpected error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected server error occurred.") from e

    async def verify_user_email(self, conn: asyncpg.Connection, user_id: int, verification_code: str) -> None:
        """Verifies a user's email asynchronously. Raises HTTPException on failure."""
        check_query = "SELECT verification_code FROM email_verifications WHERE user_id = $1 AND verification_code = $2 AND expires_at > NOW()"
        update_query = "UPDATE users SET is_email_verified = TRUE WHERE user_id = $1"
        delete_query = "DELETE FROM email_verifications WHERE user_id = $1 AND verification_code = $2"

        try:
            async with conn.transaction():
                 # 1. Check if the code is valid and not expired
                 code_exists = await conn.fetchval(check_query, user_id, verification_code)
                 if not code_exists:
                     logger.warning(f"Email verification failed for user {user_id}: Invalid or expired code.")
                     raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid or expired verification code')

                 # 2. Update user status and delete verification record
                 await conn.execute(update_query, user_id)
                 await conn.execute(delete_query, user_id, verification_code)

            logger.info(f"Email successfully verified for user ID {user_id}.")
            # No return needed on success, exception indicates failure

        except HTTPException: # Re-raise HTTP exceptions
             raise
        except (asyncpg.PostgresError) as e:
            logger.error(f"Database error during email verification for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An error occurred during email verification.') from e
        except Exception as e:
            logger.error(f"Unexpected error during email verification for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An unexpected server error occurred during verification.') from e

    # send_verification_email_gmail remains synchronous using googleapiclient
    def send_verification_email_gmail(self, to_email: str, verification_code: str):
        """Handles Gmail authentication and sends email (Synchronous)."""
        # NOTE: This part remains synchronous. For a fully async API,
        # you'd need an async email library or run this in a separate thread/process.
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None
        token_file = 'token.json'
        client_secret_file = 'client_secret.json'
        if not os.path.exists(client_secret_file):
            logger.error(f"Gmail client secret file not found: {client_secret_file}")
            raise FileNotFoundError(f"Required file '{client_secret_file}' not found for sending email.")
        if os.path.exists(token_file):
             try: creds = Credentials.from_authorized_user_file(token_file, SCOPES)
             except Exception as e: logger.warning(f"Error loading credentials from {token_file}: {e}. Will attempt re-authentication."); creds = None
        needs_refresh = False; needs_reauth = False
        if creds:
            try:
                is_expired = creds.expiry and creds.expiry < (datetime.utcnow().replace(tzinfo=None) + timedelta(minutes=5))
                if is_expired:
                    needs_refresh = True
                    if creds.refresh_token:
                        logger.info("Refreshing Gmail API access token..."); creds.refresh(Request()); logger.info("Gmail token refreshed successfully."); needs_refresh = False
                    else: logger.warning("Gmail token expired, but no refresh token. Re-auth required."); needs_reauth = True; creds = None
                elif not creds.valid: logger.warning("Gmail token is invalid. Re-auth required."); needs_reauth = True; creds = None
            except RefreshError as e: logger.error(f"Error refreshing Gmail token (requires re-auth): {e}"); needs_reauth = True; creds = None; needs_refresh = False
            except Exception as e: logger.error(f"Unexpected error checking/refreshing Gmail token: {e}"); creds = None; needs_reauth = True; needs_refresh = False
        if not creds or needs_reauth:
            try:
                logger.info("Starting Gmail authentication flow..."); flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES); creds = flow.run_local_server(port=8080); logger.info("Gmail authentication successful.")
            except Exception as e: logger.error(f"Gmail authentication flow failed: {e}"); raise ConnectionError("Failed to obtain Google API credentials through authentication flow.") from e
        if creds:
            try:
                with open(token_file, 'w') as token: token.write(creds.to_json()); logger.debug(f"Gmail credentials saved to {token_file}")
            except IOError as e: logger.error(f"Error saving Gmail token to {token_file}: {e}")
        try:
            service = build('gmail', 'v1', credentials=creds)
            subject = "Your ZINZI Verification Code"; body = f"Your verification code is: {verification_code}\nPlease enter this code in the ZINZI app."; message = MIMEText(body); message['to'] = to_email; message['from'] = 'me'; message['subject'] = subject
            raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
            send_message_body = {'raw': raw_message}
            sent_message = service.users().messages().send(userId="me", body=send_message_body).execute()
            logger.info(f"Verification email sent successfully to {to_email}. Message ID: {sent_message.get('id')}")
        except Exception as e: logger.error(f"Failed to send Gmail verification email to {to_email}: {e}", exc_info=True); raise ConnectionError(f"Failed to send verification email via Gmail: {e}") from e

    async def create_user(self, conn: asyncpg.Connection, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """Wrapper for async signup_user."""
        name = user_data.get('Name')
        email = user_data.get('Email')
        password = user_data.get('Password')
        image = user_data.get('Image')
        if not name or not email or not password:
             missing = [k for k in ['Name', 'Email', 'Password'] if not user_data.get(k)]
             # Raise HTTPException instead of ValueError
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Missing required fields for user creation: {', '.join(missing)}")
        # Await the async signup method
        return await self.signup_user(conn, name, email, password, image)

    async def list_users(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> Optional[Union[List[Dict[str, Any]], Dict[str, Any]]]:
        """Lists users asynchronously."""
        sql = "SELECT user_id, name, email, registration_date, is_email_verified, user_type, last_login, image FROM users"
        params = []
        if user_id is not None:
            sql += " WHERE user_id = $1"
            params.append(user_id)

        # Use await for the async query
        users_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)

        if users_list:
            processed_users = []
            for user_row in users_list: # user_row is already a dict-like Record
                processed_user = dict(user_row) # Convert to standard dict if needed
                for key, value in processed_user.items():
                    if isinstance(value, (datetime, date)):
                        processed_user[key] = value.isoformat()
                processed_users.append(processed_user)
            if user_id is not None:
                return processed_users[0] if processed_users else None
            else:
                return processed_users
        else:
            if user_id is not None:
                logger.warning(f"No user found with ID: {user_id}")
                return None
            else:
                return []

    async def login_user(self, conn: asyncpg.Connection, identifier: str, password: str) -> Dict[str, Any]:
        """Logs in a user asynchronously. Raises HTTPException on failure."""
        sql = "SELECT user_id, hashed_password, user_type, is_email_verified FROM users WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())

        try:
            result = await self._execute_query(conn, sql, params, fetch_one=True)

            if not result:
                logger.warning(f"Login failed: Identifier '{identifier}' not found.")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials or account not found.')

            user_id = result['user_id']
            stored_hashed_password = result['hashed_password']
            user_type = result.get('user_type', 'user')
            is_verified = result.get('is_email_verified', False)

            # bcrypt expects bytes
            stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
            if not isinstance(stored_hashed_pw_bytes, bytes):
                 logger.error(f"Invalid hashed_password type for user {user_id}. Type: {type(stored_hashed_password)}")
                 raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal server error during login processing.')

            if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                # Optional: Check verification
                # if not is_verified:
                #     raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Account not verified. Please check your email.')

                logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
                # Update last_login time (best effort)
                update_sql = "UPDATE users SET last_login = NOW() WHERE user_id = $1"
                try:
                    await self._execute_query(conn, update_sql, (user_id,), commit=False) # No commit needed if part of larger transaction or auto-commit
                except Exception as update_err:
                    logger.error(f"Failed to update last_login for user {user_id}: {update_err}") # Log but don't fail login

                return {'message': 'Login successful', 'data': {'user_id': user_id, 'user_type': user_type, 'verified': is_verified}}
            else:
                logger.warning(f"Login failed: Invalid password for identifier '{identifier}'.")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

        except HTTPException: # Re-raise auth-related HTTP exceptions
             raise
        except (asyncpg.PostgresError) as e:
             logger.error(f"Database error during user login for '{identifier}': {e}")
             raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Login service unavailable.') from e
        except Exception as e:
             logger.error(f"Unexpected error during user login for '{identifier}': {e}", exc_info=True)
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An unexpected server error occurred.') from e

    async def delete_user(self, conn: asyncpg.Connection, user_id: int) -> bool:
        """Deletes a user record asynchronously."""
        logger.warning(f"Attempting to delete user ID: {user_id}")
        sql = "DELETE FROM users WHERE user_id = $1 RETURNING user_id" # Use RETURNING to check effect
        try:
            deleted_id = await conn.fetchval(sql, user_id) # Use fetchval with RETURNING
            if deleted_id == user_id:
                 logger.info(f"Successfully deleted user ID: {user_id}")
                 return True
            else:
                 # This case means the user_id didn't exist
                 logger.warning(f"Attempted to delete non-existent user ID: {user_id}")
                 return False
        except asyncpg.PostgresError as e:
            logger.error(f"Database error deleting user ID {user_id}: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error deleting user ID {user_id}: {e}", exc_info=True)
            return False

    # --- Metrics Methods (async) ---
    async def create_metric(self, conn: asyncpg.Connection, metric_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new user metric record asynchronously."""
        metric_data_lower = lowercase_keys(metric_data)
        # Use check_required_fields which now raises HTTPException
        check_required_fields(metric_data_lower, ['user_id', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse'])
        sql = """
            INSERT INTO user_metrics (user_id, age_range, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, recorded_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW()) RETURNING metric_id
        """
        try:
             params = (
                int(metric_data_lower['user_id']), metric_data_lower.get('age_range'), float(metric_data_lower['weight']),
                float(metric_data_lower['height']), float(metric_data_lower['cholesterol_level']), int(metric_data_lower['sys_bp']),
                int(metric_data_lower['dia_bp']), int(metric_data_lower['pulse'])
             )
        except (ValueError, TypeError) as e:
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid numeric format in metric data: {e}") from e

        metric_id = await self._execute_query(conn, sql, params, returning_id_column='metric_id') # No commit=True needed with fetchval/RETURNING
        if metric_id:
            logger.info(f"Created metric ID: {metric_id} for User: {metric_data_lower['user_id']}")
            return {"metric_id": metric_id}
        else:
             # This shouldn't happen if RETURNING works and insertion is successful
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Metric creation failed unexpectedly.")

    async def update_metric(self, conn: asyncpg.Connection, metric_id: int, updates: Dict[str, Any]):
        """Updates an existing user metric record asynchronously."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []
        params = []
        allowed_fields = ['age_range', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse', 'sex', 'activity_level']
        param_index = 1
        for key, value in updates_lower.items():
             if key in ['metric_id', 'user_id', 'recorded_at']: continue
             if key in allowed_fields:
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1
             else: logger.warning(f"Ignoring unrecognized field '{key}' during metric update.")

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")

        sql = f"UPDATE user_metrics SET {', '.join(set_clauses)} WHERE metric_id = ${param_index}"
        params.append(metric_id) # Add metric_id for WHERE clause
        await self._execute_query(conn, sql, tuple(params)) # No fetch needed
        logger.info(f"Updated metric ID: {metric_id}")

    async def list_metrics(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists metrics asynchronously."""
        sql = "SELECT * FROM user_metrics" # Select all columns for now
        params = []
        if user_id is not None:
             sql += " WHERE user_id = $1 ORDER BY recorded_at DESC"
             params.append(user_id)
        else:
             sql += " ORDER BY recorded_at DESC"

        metrics = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if metrics:
             processed = []
             for item in metrics:
                  p_item = dict(item) # Already dict-like
                  for k, v in p_item.items():
                       if isinstance(v, (datetime, date)): p_item[k] = v.isoformat()
                  processed.append(p_item)
             return processed
        return []

    # --- Metric History Methods (async) ---
    async def create_metric_history(self, conn: asyncpg.Connection, metric_history_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new metric history record asynchronously."""
        data_lower = lowercase_keys(metric_history_data)
        check_required_fields(data_lower, ['user_id', 'weight'])
        sql = "INSERT INTO metrics_history (user_id, weight, logged_at) VALUES ($1, $2, NOW()) RETURNING log_id"
        try:
            params = (int(data_lower['user_id']), float(data_lower['weight']))
        except (ValueError, TypeError) as e:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid numeric format in metric history data: {e}") from e

        log_id = await self._execute_query(conn, sql, params, returning_id_column='log_id')
        if log_id:
             logger.info(f"Created metric history Log ID: {log_id} for User: {data_lower['user_id']}")
             return {"log_id": log_id}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Metric history creation failed unexpectedly.")

    async def update_metric_history(self, conn: asyncpg.Connection, log_id: int, updates: Dict[str, Any]):
        """Updates an existing metric history record asynchronously."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []; params = []; param_index = 1;
        allowed_fields = ['weight']
        for key, value in updates_lower.items():
            if key in ['log_id', 'user_id', 'logged_at']: continue
            if key in allowed_fields:
                 try: weight_f = float(value);
                 except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid weight format for update.")
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(weight_f)
                 param_index += 1
            else: logger.warning(f"Ignoring unrecognized field '{key}' during metric history update.")

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")
        sql = f"UPDATE metrics_history SET {', '.join(set_clauses)} WHERE log_id = ${param_index}"
        params.append(log_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated metric history Log ID: {log_id}")

    async def list_metric_history(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists metric history asynchronously."""
        sql = "SELECT * FROM metrics_history"
        params = []
        if user_id is not None:
             sql += " WHERE user_id = $1 ORDER BY logged_at DESC"
             params.append(user_id)
        else:
             sql += " ORDER BY logged_at DESC"

        history = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if history:
             processed = []
             for item in history:
                  p_item = dict(item)
                  for k, v in p_item.items():
                       if isinstance(v, (datetime, date)): p_item[k] = v.isoformat()
                  processed.append(p_item)
             return processed
        return []

    # --- Preferences Methods (async) ---
    async def create_preference(self, conn: asyncpg.Connection, preference_data: Dict[str, Any]) -> Dict[str, int]:
        """Creates a new user preference record asynchronously."""
        data_lower = lowercase_keys(preference_data)
        check_required_fields(data_lower, ['user_id', 'goals', 'diet_type'])
        sql = """
            INSERT INTO user_preferences (user_id, goals, diet_type, food_restrictions, cuisine_preferences)
            VALUES ($1, $2, $3, $4, $5) RETURNING preference_id
        """
        try:
             params = (
                int(data_lower['user_id']), data_lower['goals'], data_lower['diet_type'],
                # Assuming TEXT columns, pass strings directly (or serialize if needed for TEXT[])
                serialize_list(data_lower.get('food_restrictions', [])),
                serialize_list(data_lower.get('cuisine_preferences', []))
             )
        except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user_id format.")

        preference_id = await self._execute_query(conn, sql, params, returning_id_column='preference_id')
        if preference_id:
            logger.info(f"Created preference ID: {preference_id} for User: {data_lower['user_id']}")
            return {"preference_id": preference_id}
        else:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Preference creation failed unexpectedly.")

    async def update_preference(self, conn: asyncpg.Connection, preference_id: int, updates: Dict[str, Any]):
        """Updates an existing user preference record asynchronously."""
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []; params = []; param_index = 1;
        allowed_fields = ['goals', 'diet_type', 'food_restrictions', 'cuisine_preferences']
        for key, value in updates_lower.items():
             if key in ['preference_id', 'user_id']: continue
             if key in allowed_fields:
                 # Serialize lists if needed
                 if key in ['food_restrictions', 'cuisine_preferences']:
                     value_to_store = serialize_list(value)
                 else:
                     value_to_store = value
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value_to_store)
                 param_index += 1
             else: logger.warning(f"Ignoring unrecognized field '{key}' during preference update.")

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for preference update.")
        sql = f"UPDATE user_preferences SET {', '.join(set_clauses)} WHERE preference_id = ${param_index}"
        params.append(preference_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated preference ID: {preference_id}")

    async def list_preferences(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        """Lists preferences asynchronously."""
        sql = "SELECT * FROM user_preferences"
        params = []
        if user_id is not None:
             sql += " WHERE user_id = $1"
             params.append(user_id)

        preferences = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if preferences:
             processed = []
             for pref_row in preferences:
                  p_pref = dict(pref_row)
                  # Deserialize list-like fields
                  p_pref['food_restrictions'] = deserialize_list(p_pref.get('food_restrictions', ''))
                  p_pref['cuisine_preferences'] = deserialize_list(p_pref.get('cuisine_preferences', ''))
                  processed.append(p_pref)
             return processed
        return []


# --- Chefs Class (Updated for asyncpg) ---
class Chefs(BaseRepository):
    # _validate_stock remains synchronous helper
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
            # Using .get for safer access
            name_val = item.get('Name')
            if not isinstance(name_val, str) or not name_val.strip():
                raise ValueError("Stock item must have a non-empty 'Name' string")
            id_val = item.get(id_field)
            if id_val is not None and not isinstance(id_val, str): # Check ID type if present
                raise ValueError(f"Stock item {id_field} must be a string or null")
            qty_val = item.get('quantity')
            if qty_val is not None: # Check quantity type if present
                try:
                    item['quantity'] = float(qty_val)  # Ensure numeric
                except (ValueError, TypeError):
                    raise ValueError("Stock item quantity must be a number or null")
        return stock_data

    async def create_chef(self, conn: asyncpg.Connection, chef_data: dict):
        chef_data_lower = lowercase_keys(chef_data)
        # Use check_required_fields (raises HTTPException)
        required = ['name', 'password', 'email', 'chef_type', 'phone_number', 'location', 'experience', 'responsetime', 'minnotice', 'teamsize', 'bio', 'image', 'pricing']
        check_required_fields(chef_data_lower, required)

        email = chef_data_lower['email']
        check_sql = "SELECT chefid FROM chefs WHERE lower(email) = lower($1)"
        # Use await and fetchval
        existing_chef = await conn.fetchval(check_sql, email)
        if existing_chef:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Chef email '{email}' already exists.")

        try:
            hashed_password = hash_password(chef_data_lower['password'])
        except Exception as e:
            logger.error(f"Password hashing failed: {e}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Password processing error.")

        # Pricing validation (remains synchronous logic)
        pricing_data = chef_data_lower.get('pricing', {})
        if not isinstance(pricing_data, dict):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid pricing data format.")
        try:
            # Example: Ensure floats where expected
            if 'starting_price' in pricing_data: pricing_data['starting_price'] = float(pricing_data['starting_price']) if pricing_data['starting_price'] is not None else None
            if 'per_month' in pricing_data: pricing_data['per_month'] = float(pricing_data['per_month']) if pricing_data['per_month'] is not None else None
            if 'per_gig' in pricing_data and isinstance(pricing_data.get('per_gig'), dict): pricing_data['per_gig'] = {k: float(v) if v is not None else None for k, v in pricing_data['per_gig'].items()}
            else: pricing_data['per_gig'] = {}
            pricing_param = json.dumps(pricing_data) # Convert final dict to JSON string
        except (ValueError, TypeError, KeyError) as e:
            logger.error(f"Error processing pricing data: {pricing_data}. Error: {e}")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid value in pricing data: {e}")

        # Handle stock and other JSON fields
        try:
            stock_data = self._validate_stock(chef_data_lower.get('stock'), is_chef=True)
            stock_json_str = json.dumps(stock_data)
            equipment_json_str = json.dumps(chef_data_lower.get('equipment', []))
            availability_json_str = json.dumps(chef_data_lower.get('availability', []))
            languages_json_str = json.dumps(chef_data_lower.get('languages', []))
            specialties_json_str = json.dumps(chef_data_lower.get('specialties', []))
            certifications_json_str = json.dumps(chef_data_lower.get('certifications', []))
            samplemenu_json_str = json.dumps(chef_data_lower.get('samplemenu', []))
        except (ValueError, TypeError) as e: # Catch validation or JSON errors
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Error processing list/object data: {e}")


        user_type = chef_data_lower.get('user_type', 'chef')
        is_email_verified = chef_data_lower.get('is_email_verified', False)
        is_active = chef_data_lower.get('is_active', True)
        added_by = chef_data_lower.get('added_by')
        added_by_type = chef_data_lower.get('added_by_type', user_type)

        # Use $ placeholders for asyncpg
        sql = """INSERT INTO chefs (
            name, image, email, hashed_password, is_email_verified, user_type, chef_type, is_active,
            rating, phone_number, experience, serviceradius, responsetime, minnotice, punctuality,
            teamsize, equipment, bio, availability, languages, specialties, certifications,
            registration_date, location, samplemenu, added_by, added_by_type, last_login, pricing, stock
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, NOW(), $23, $24, $25, $26, NOW(), $27, $28)
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

        # Use await and the base class method
        chef_id = await self._execute_query(conn, sql, params, returning_id_column='chefid')

        if chef_id:
            logger.info(f"Successfully created chef ID: {chef_id} for email: {email}")
            return {"Chef_id": chef_id, "user_type": user_type, "message": "Chef created successfully"}
        else:
            # This path indicates an issue if RETURNING was expected to work
            logger.error(f"Chef creation query executed for email {email} but did not return chefid.")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to retrieve chef ID after insertion.")

    async def list_chefs(self, conn: asyncpg.Connection, chef_id=None):
        sql = "SELECT * FROM chefs"
        params = []
        if chef_id is not None:
            try:
                cid = int(chef_id)
                sql += " WHERE chefid = $1"
                params.append(cid)
            except ValueError:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid chef_id format.")

        chefs_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if chefs_list is None: # Should return [] from execute_query on no results
            return []

        processed_chefs = []
        for chef_dict in chefs_list: # chef_dict is already dict-like
            # Create a mutable copy if needed, but Records are generally fine
            processed_chef = dict(chef_dict)
            # Deserialize JSON fields and format dates
            list_fields = ['equipment', 'availability', 'languages', 'specialties', 'certifications', 'samplemenu', 'stock']
            for field in list_fields:
                processed_chef[field] = deserialize_list_from_json_string(processed_chef.get(field))

            # Extract 'price' from 'pricing' JSON if needed
            try:
                pricing_data = json.loads(processed_chef.get('pricing') or '{}') # Load JSON string
                extracted_price = pricing_data.get('starting_price', 0.0)
                processed_chef['price'] = extracted_price if extracted_price is not None else 0.0
            except json.JSONDecodeError:
                 logger.warning(f"Could not decode pricing JSON for chef {processed_chef.get('chefid')}")
                 processed_chef['price'] = 0.0 # Default price on error

            # Format datetime objects
            for key, value in processed_chef.items():
                if isinstance(value, (datetime, date)):
                    processed_chef[key] = value.isoformat()

            processed_chefs.append(processed_chef)

        if chef_id and not processed_chefs:
            logger.warning(f"No chef found ID: {chef_id}")
            # Return empty list for consistency, caller handles 404 if needed
            return []
        return processed_chefs

    async def update_chef(self, conn: asyncpg.Connection, chef_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []
        params = []
        param_index = 1

        # Handle specific JSON fields first
        if 'pricing' in updates_lower:
            pricing_data = updates_lower.pop('pricing')
            if not isinstance(pricing_data, dict):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="'pricing' update must be a valid JSON object.")
            try:
                pricing_json_string = json.dumps(pricing_data)
                set_clauses.append(f"pricing = ${param_index}")
                params.append(pricing_json_string)
                param_index += 1
            except TypeError as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Could not serialize pricing: {e}")

        if 'stock' in updates_lower:
            try:
                # Validate stock data before serialization
                stock_data = self._validate_stock(updates_lower.pop('stock'), is_chef=True)
                stock_json_string = json.dumps(stock_data)
                set_clauses.append(f"stock = ${param_index}")
                params.append(stock_json_string)
                param_index += 1
            except (ValueError, TypeError) as e: # Catch validation or serialization errors
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Could not process stock update: {e}")

        updates_lower.pop('price', None) # Remove 'price' derived field if present

        list_fields = ['equipment', 'availability', 'languages', 'specialties', 'certifications', 'samplemenu']
        allowed_direct_fields = [
            'name', 'image', 'email', 'chef_type', 'is_active', 'rating', 'phone_number', 'experience',
            'serviceradius', 'responsetime', 'minnotice', 'punctuality', 'teamsize', 'bio', 'reviews',
            'location', 'added_by', 'added_by_type', 'last_login'
        ]

        for key, value in updates_lower.items():
            if key == 'chefid': continue # Cannot update primary key

            if key in allowed_direct_fields:
                set_clauses.append(f"{key} = ${param_index}")
                params.append(value)
                param_index += 1
            elif key in list_fields:
                 # Assuming these should be updated with new JSON strings
                 if isinstance(value, list): # If client sends list, serialize it
                     try: value = json.dumps(value)
                     except TypeError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Could not serialize list field '{key}'.")
                 elif not isinstance(value, str): # If not list or string, it's invalid
                     raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Field '{key}' must be a valid JSON list/array or a JSON string for update.")
                 # If it's already a string, assume it's valid JSON
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1
            elif key == 'password':
                if not isinstance(value, str) or not value:
                     raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password update needs non-empty string.")
                hashed_pw = hash_password(value)
                set_clauses.append(f"hashed_password = ${param_index}")
                params.append(hashed_pw)
                param_index += 1
            # else: ignore unrecognized fields

        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")

        # Add updated_at timestamp
        set_clauses.append(f"updated_at = NOW()")

        sql = f"UPDATE chefs SET {', '.join(set_clauses)} WHERE chefid = ${param_index}"
        params.append(chef_id)

        # Execute the update query
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated chef ID: {chef_id}")

    async def login_chef(self, conn: asyncpg.Connection, identifier: str, password: str):
        sql = "SELECT chefid, hashed_password, user_type, is_email_verified FROM chefs WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)

        if not result:
            logger.warning(f"Chef login failed: '{identifier}' not found.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials or account not found.')

        chef_id = result['chefid']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']
        is_verified = result['is_email_verified']

        stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
        if not isinstance(stored_hashed_pw_bytes, bytes):
             logger.error(f"Bad hash type chef {chef_id}")
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal login error.')

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Chef login success '{identifier}', ID: {chef_id}")
            return {'message': 'Login successful', 'data': {'chef_id': chef_id, 'user_type': user_type, 'verified': is_verified}}
        else:
            logger.warning(f"Chef login failed: Invalid password for '{identifier}'.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

    async def delete_chef(self, conn: asyncpg.Connection, chef_id: int):
        logger.warning(f"Attempting to delete chef ID: {chef_id}")
        sql = "DELETE FROM chefs WHERE chefid = $1 RETURNING chefid"
        deleted_id = await conn.fetchval(sql, chef_id)
        if deleted_id == chef_id:
            logger.info(f"Deleted chef ID: {chef_id}")
            return True
        else:
             logger.warning(f"Attempted to delete non-existent chef ID: {chef_id}")
             return False # Or raise 404

    async def update_chef_status(self, conn: asyncpg.Connection, chef_id: int, is_active: bool):
        sql = "UPDATE chefs SET is_active = $1, updated_at = NOW() WHERE chefid = $2"
        await self._execute_query(conn, sql, (is_active, chef_id))
        logger.info(f"Updated chef ID {chef_id} active status to {is_active}")

# --- Producers Class (Updated for asyncpg) ---
class Producers(BaseRepository):
    # _validate_stock is synchronous helper, no changes needed
    def _validate_stock(self, stock_data, is_chef=False):
         if stock_data is None: return []
         if not isinstance(stock_data, list): raise ValueError(f"Stock must be a list, got {type(stock_data)}")
         id_field = 'produce_id' if not is_chef else 'meal_id'
         validated_stock = []
         for i, item in enumerate(stock_data):
             if not isinstance(item, dict): raise ValueError(f"Stock item at index {i} must be a dict, got {type(item)}")
             name_val = item.get('name') if 'name' in item else item.get('Name')
             if not isinstance(name_val, str) or not name_val.strip(): raise ValueError(f"Stock item at index {i} must have a non-empty 'Name' string")
             validated_item = {'Name': name_val.strip(), id_field: item.get(id_field)}
             if validated_item[id_field] is not None and not isinstance(validated_item[id_field], str): raise ValueError(f"Stock item at index {i} {id_field} must be a string or null")
             if 'quantity' in item and item['quantity'] is not None:
                 try:
                     validated_item['quantity'] = float(item['quantity'])
                     if validated_item['quantity'] < 0: raise ValueError(f"Stock item at index {i} quantity must be non-negative")
                 except (ValueError, TypeError): raise ValueError(f"Stock item at index {i} quantity must be a number or null")
             validated_stock.append(validated_item)
         return validated_stock

    async def update_producer(self, conn: asyncpg.Connection, producer_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided")

        set_clauses = []; params = []; param_index = 1;
        allowed = ['name', 'image', 'producer_type', 'is_active', 'rating', 'phone_number', 'location', 'reviews']

        if 'stock' in updates_lower:
            try:
                stock_data = self._validate_stock(updates_lower.pop('stock'), is_chef=False)
                stock_json_string = json.dumps(stock_data)
                set_clauses.append(f"stock = ${param_index}")
                params.append(stock_json_string)
                param_index += 1
            except (ValueError, TypeError) as e:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Could not process stock update: {e}")

        for key, value in updates_lower.items():
            # Skip non-updatable or special-handled fields
            if key in ['producer_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified', 'password']:
                if key == 'password': logger.warning(f"Password update attempt ignored for producer {producer_id} via general update endpoint")
                continue
            elif key in allowed:
                # Perform type validation/conversion if needed
                if key == 'rating' and value is not None:
                    try: value = float(value); assert value >= 0;
                    except (ValueError, TypeError, AssertionError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Rating must be a valid non-negative number")
                if key == 'is_active' and not isinstance(value, bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="is_active must be a boolean")
                set_clauses.append(f"{key} = ${param_index}")
                params.append(value)
                param_index += 1
            # else: ignore unrecognized fields

        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update")

        # Check if producer exists before updating
        check_sql = "SELECT producer_id FROM producers WHERE producer_id = $1"
        if not await conn.fetchval(check_sql, producer_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Producer with ID {producer_id} does not exist")

        set_clauses.append(f"updated_at = NOW()")
        sql = f"UPDATE producers SET {', '.join(set_clauses)} WHERE producer_id = ${param_index}"
        params.append(producer_id)

        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Successfully updated producer ID: {producer_id}")

    async def create_producer(self, conn: asyncpg.Connection, producer_data: dict):
        producer_data_lower = lowercase_keys(producer_data)
        check_required_fields(producer_data_lower, ['name', 'password', 'email'])
        email = producer_data_lower['email']
        check_sql = "SELECT producer_id FROM producers WHERE lower(email) = lower($1)"
        if await conn.fetchval(check_sql, email):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Producer email '{email}' already exists.")

        hashed_password = hash_password(producer_data_lower['password'])
        try:
            stock_data = self._validate_stock(producer_data_lower.get('stock'), is_chef=False)
            stock_json_str = json.dumps(stock_data)
        except (ValueError, TypeError) as e:
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Error processing stock data: {e}")

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
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11, $12, $13, NOW(), $14, $15)
            RETURNING producer_id
        """
        try:
            added_by_id = int(added_by) if added_by is not None else None
        except (ValueError, TypeError): added_by_id = None
        try: rating_f = float(producer_data_lower.get('rating', 0.0) or 0.0)
        except (ValueError, TypeError): rating_f = 0.0

        params = (
            producer_data_lower['name'], producer_data_lower.get('image'), email, hashed_password,
            is_email_verified, user_type, producer_data_lower.get('producer_type', 'Individual'),
            is_active, rating_f, producer_data_lower.get('phone_number'),
            producer_data_lower.get('location'), added_by_id, added_by_type,
            producer_data_lower.get('reviews'), stock_json_str
        )
        producer_id = await self._execute_query(conn, sql, params, returning_id_column='producer_id')
        if producer_id:
            logger.info(f"Successfully created producer ID: {producer_id}")
            return {"producer_id": producer_id, "UserType": user_type}
        else:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Producer creation failed to return ID.")

    async def list_producers(self, conn: asyncpg.Connection, producer_id=None):
        sql = "SELECT * FROM producers"
        params = []
        if producer_id is not None:
            try:
                pid = int(producer_id)
                sql += " WHERE producer_id = $1"
                params.append(pid)
            except ValueError:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid producer_id format provided.")

        producers_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if producers_list is None: return [] # Should be handled by _execute_query

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
            # Let the caller handle the 404 based on the empty list
            return []
        return processed_list

    async def login_producer(self, conn: asyncpg.Connection, identifier: str, password: str):
        sql = "SELECT producer_id, hashed_password, user_type, is_email_verified FROM producers WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)

        if not result:
            logger.warning(f"Producer login failed: '{identifier}' not found.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials or account not found.')

        producer_id = result['producer_id']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']
        is_verified = result['is_email_verified']

        stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
        if not isinstance(stored_hashed_pw_bytes, bytes):
             logger.error(f"Bad hash type producer {producer_id}")
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal login error.')

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Producer login success '{identifier}', ID: {producer_id}")
            return {'message': 'Login successful', 'data': {'producer_id': producer_id, 'user_type': user_type, 'verified': is_verified}}
        else:
            logger.warning(f"Producer login failed: Invalid password for '{identifier}'.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

    async def delete_producer(self, conn: asyncpg.Connection, producer_id: int):
        logger.warning(f"Attempting to delete producer ID: {producer_id}")
        sql = "DELETE FROM producers WHERE producer_id = $1 RETURNING producer_id"
        deleted_id = await conn.fetchval(sql, producer_id)
        if deleted_id == producer_id:
            logger.info(f"Deleted producer ID: {producer_id}")
            return True
        else:
            logger.warning(f"Attempted to delete non-existent producer ID: {producer_id}")
            return False # Or raise 404

    async def update_producer_status(self, conn: asyncpg.Connection, producer_id: int, is_active: bool):
        sql = "UPDATE producers SET is_active = $1, updated_at = NOW() WHERE producer_id = $2"
        await self._execute_query(conn, sql, (is_active, producer_id))
        logger.info(f"Updated producer ID {producer_id} active status to {is_active}")


# --- Transporters Class (Updated for asyncpg) ---
class Transporters(BaseRepository):
    async def create_transporter(self, conn: asyncpg.Connection, transporter_data: dict):
        data_lower = lowercase_keys(transporter_data)
        check_required_fields(data_lower, ['name', 'password', 'email'])
        email = data_lower['email']
        check_sql = "SELECT transporter_id FROM transporters WHERE lower(email) = lower($1)"
        if await conn.fetchval(check_sql, email):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Transporter email '{email}' already exists.")

        hashed_password = hash_password(data_lower['password'])
        user_type = data_lower.get('user_type', 'transporter')
        is_active = data_lower.get('is_active', False)

        sql = """
            INSERT INTO transporters (
                name, email, hashed_password, phone_number, profile_image_url,
                vehicle_type, license_plate, is_active, rating, location,
                registration_date, user_type, reviews
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11, $12)
            RETURNING transporter_id
        """
        params = (
            data_lower['name'], email, hashed_password, data_lower.get('phone_number'),
            data_lower.get('profile_image_url'), data_lower.get('vehicle_type'),
            data_lower.get('license_plate'), is_active, data_lower.get('rating', 0.0),
            data_lower.get('location'), user_type, data_lower.get('reviews')
        )
        transporter_id = await self._execute_query(conn, sql, params, returning_id_column='transporter_id')
        if transporter_id:
            logger.info(f"Created transporter ID: {transporter_id} for email {email}")
            return {"transporter_id": transporter_id, "UserType": user_type, "message": "Transporter created successfully."}
        else:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Transporter creation failed to return ID.")

    async def list_transporters(self, conn: asyncpg.Connection, transporter_id=None):
        sql = "SELECT * FROM transporters"
        params = []
        if transporter_id is not None:
            try: tid = int(transporter_id); sql += " WHERE transporter_id = $1"; params.append(tid)
            except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid transporter_id format.")

        transporters_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if transporters_list is None: return []

        processed_list = []
        for transporter in transporters_list:
            processed_trans = dict(transporter)
            for key, value in processed_trans.items():
                if isinstance(value, (datetime, date)): processed_trans[key] = value.isoformat()
            processed_list.append(processed_trans)

        if transporter_id is not None and not processed_list:
            logger.warning(f"No transporter found ID: {transporter_id}")
            return [] # Caller handles 404
        return processed_list

    async def update_transporter(self, conn: asyncpg.Connection, transporter_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []; params = []; param_index = 1;
        allowed_fields = ['name', 'phone_number', 'profile_image_url', 'vehicle_type', 'license_plate', 'is_active', 'rating', 'location', 'reviews']

        for key, value in updates_lower.items():
            if key in ['transporter_id', 'email', 'registration_date', 'user_type']: continue
            if key == 'password':
                 hashed_pw = hash_password(value)
                 set_clauses.append(f"hashed_password = ${param_index}"); params.append(hashed_pw); param_index += 1;
            elif key in allowed_fields:
                 set_clauses.append(f"{key} = ${param_index}"); params.append(value); param_index += 1;

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")

        set_clauses.append(f"updated_at = NOW()")
        sql = f"UPDATE transporters SET {', '.join(set_clauses)} WHERE transporter_id = ${param_index}"
        params.append(transporter_id)

        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated transporter ID: {transporter_id}")

    async def login_transporter(self, conn: asyncpg.Connection, identifier: str, password: str):
        sql = "SELECT transporter_id, hashed_password, user_type, is_email_verified FROM transporters WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)

        if not result:
            logger.warning(f"Transporter login failed: '{identifier}' not found.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials or account not found.')

        transporter_id = result['transporter_id']
        stored_hashed_password = result['hashed_password']
        user_type = result.get('user_type', 'transporter')
        is_verified = result.get('is_email_verified', True)

        stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
        if not isinstance(stored_hashed_pw_bytes, bytes):
            logger.error(f"Invalid hash type for transporter {transporter_id}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal login error.')

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Transporter login successful for '{identifier}', ID: {transporter_id}")
            # Optional: Update last_login
            update_sql = "UPDATE transporters SET last_login = NOW() WHERE transporter_id = $1"
            try: await self._execute_query(conn, update_sql, (transporter_id,))
            except Exception as update_err: logger.error(f"Failed to update last_login for transporter {transporter_id}: {update_err}")
            return {'message': 'Login successful', 'data': {'transporter_id': transporter_id, 'user_type': user_type, 'verified': is_verified }}
        else:
            logger.warning(f"Transporter login failed: Invalid password for '{identifier}'.")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

    async def delete_transporter(self, conn: asyncpg.Connection, transporter_id: int):
        logger.warning(f"Attempting to delete transporter ID: {transporter_id}")
        sql = "DELETE FROM transporters WHERE transporter_id = $1 RETURNING transporter_id"
        deleted_id = await conn.fetchval(sql, transporter_id)
        if deleted_id == transporter_id:
            logger.info(f"Deleted transporter ID: {transporter_id}")
            return True
        else:
             logger.warning(f"Attempted to delete non-existent transporter ID: {transporter_id}")
             return False # Or raise 404

    async def update_transporter_status(self, conn: asyncpg.Connection, transporter_id: int, is_active: bool):
        if not isinstance(is_active, bool): raise ValueError("'is_active' must be a boolean value.") # Internal validation
        sql = "UPDATE transporters SET is_active = $1, updated_at = NOW() WHERE transporter_id = $2"
        await self._execute_query(conn, sql, (is_active, transporter_id))
        logger.info(f"Updated transporter ID {transporter_id} active status to {is_active}")

# --- Stakeholders Class (Updated for asyncpg) ---
class Stakeholders(BaseRepository):
    async def create_stakeholder(self, conn: asyncpg.Connection, stakeholder_data: dict):
        stakeholder_data_lower = lowercase_keys(stakeholder_data)
        check_required_fields(stakeholder_data_lower, ['name', 'password', 'email', 'full_name'])
        email = stakeholder_data_lower['email']
        check_sql = "SELECT stakeholder_id FROM stakeholders WHERE lower(email) = lower($1)"
        if await conn.fetchval(check_sql, email):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Stakeholder email '{email}' already exists.")

        hashed_password = hash_password(stakeholder_data_lower['password'])
        user_type = stakeholder_data_lower.get('user_type', 'stakeholder')
        is_email_verified = stakeholder_data_lower.get('is_email_verified', False)
        is_active = stakeholder_data_lower.get('is_active', True)
        added_by = stakeholder_data_lower.get('added_by')
        added_by_type = stakeholder_data_lower.get('added_by_type', user_type)

        sql = """
            INSERT INTO stakeholders (
                name, full_name, image, email, hashed_password, is_email_verified,
                user_type, is_active, rating, phone_number, registration_date, location,
                added_by, added_by_type, last_login
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),$11,$12,$13,NOW())
            RETURNING stakeholder_id
        """
        try: added_by_id = int(added_by) if added_by is not None else None
        except (ValueError, TypeError): added_by_id = None

        params = (
            stakeholder_data_lower['name'], stakeholder_data_lower['full_name'], stakeholder_data_lower.get('image'),
            email, hashed_password, is_email_verified, user_type, is_active,
            stakeholder_data_lower.get('rating', 0.0), stakeholder_data_lower.get('phone_number'),
            stakeholder_data_lower.get('location'), added_by_id, added_by_type
        )
        stakeholder_id = await self._execute_query(conn, sql, params, returning_id_column='stakeholder_id')
        if stakeholder_id:
            logger.info(f"Created stakeholder ID: {stakeholder_id}")
            return {"stakeholder_id": stakeholder_id, "UserType": user_type}
        else:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Stakeholder creation failed to return ID.")

    async def list_stakeholders(self, conn: asyncpg.Connection):
        sql = "SELECT * FROM stakeholders"
        results = await self._execute_query(conn, sql, fetch_all=True)
        if results:
            processed = []
            for item in results:
                p_item = dict(item)
                for key, value in p_item.items():
                    if isinstance(value, (datetime, date)): p_item[key] = value.isoformat()
                processed.append(p_item)
            return processed
        return []

    async def get_stakeholder_by_id(self, conn: asyncpg.Connection, stakeholder_id: int):
        sql = "SELECT * FROM stakeholders WHERE stakeholder_id = $1"
        result = await self._execute_query(conn, sql, (stakeholder_id,), fetch_one=True)
        if result:
             p_result = dict(result)
             for key, value in p_result.items():
                 if isinstance(value, (datetime, date)): p_result[key] = value.isoformat()
             return p_result
        return None

    async def update_stakeholder(self, conn: asyncpg.Connection, stakeholder_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")

        set_clauses = []; params = []; param_index = 1;
        allowed = ['name', 'full_name', 'image', 'is_active', 'rating', 'phone_number', 'location']

        for key, value in updates_lower.items():
            if key in ['stakeholder_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified']: continue
            if key == 'password':
                 hashed_pw = hash_password(value)
                 set_clauses.append(f"hashed_password = ${param_index}"); params.append(hashed_pw); param_index += 1;
            elif key in allowed:
                 set_clauses.append(f"{key} = ${param_index}"); params.append(value); param_index += 1;

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")
        set_clauses.append(f"updated_at = NOW()")
        sql = f"UPDATE stakeholders SET {', '.join(set_clauses)} WHERE stakeholder_id = ${param_index}"
        params.append(stakeholder_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated stakeholder ID: {stakeholder_id}")

    async def login_stakeholder(self, conn: asyncpg.Connection, identifier: str, password: str):
        sql = "SELECT stakeholder_id, hashed_password, user_type, is_email_verified FROM stakeholders WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials or account not found.')

        stakeholder_id = result['stakeholder_id']; stored_hashed_password = result['hashed_password']; user_type = result.get('user_type', 'stakeholder'); is_verified = result.get('is_email_verified', False)
        stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
        if not isinstance(stored_hashed_pw_bytes, bytes): raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal login error.')

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
            logger.info(f"Stakeholder login successful for '{identifier}', ID: {stakeholder_id}")
            update_sql = "UPDATE stakeholders SET last_login = NOW() WHERE stakeholder_id = $1"
            try: await self._execute_query(conn, update_sql, (stakeholder_id,))
            except Exception as update_err: logger.error(f"Failed to update last_login for stakeholder {stakeholder_id}: {update_err}")
            return {'message': 'Login successful', 'data': {'stakeholder_id': stakeholder_id, 'user_type': user_type, 'verified': is_verified}}
        else:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

    async def delete_stakeholder(self, conn: asyncpg.Connection, stakeholder_id: int):
        logger.warning(f"Attempting to delete stakeholder ID: {stakeholder_id}")
        sql = "DELETE FROM stakeholders WHERE stakeholder_id = $1 RETURNING stakeholder_id"
        deleted_id = await conn.fetchval(sql, stakeholder_id)
        if deleted_id == stakeholder_id:
            logger.info(f"Deleted stakeholder ID: {stakeholder_id}")
            return True
        else:
            logger.warning(f"Attempted to delete non-existent stakeholder ID: {stakeholder_id}")
            return False # Or raise 404

    async def update_stakeholder_status(self, conn: asyncpg.Connection, stakeholder_id: int, is_active: bool):
         if not isinstance(is_active, bool): raise ValueError("'is_active' must be a boolean value.")
         sql = "UPDATE stakeholders SET is_active = $1, updated_at = NOW() WHERE stakeholder_id = $2"
         await self._execute_query(conn, sql, (is_active, stakeholder_id))
         logger.info(f"Updated stakeholder ID {stakeholder_id} active status to {is_active}")

# --- Herbals Class (Updated for asyncpg) ---
class Herbals(BaseRepository):
    async def create_herbal(self, conn: asyncpg.Connection, herbal_data: dict):
        herbal_data_lower = lowercase_keys(herbal_data)
        check_required_fields(herbal_data_lower, ['herbal_name', 'description', 'unit', 'price'])
        user_type = herbal_data_lower.get('user_type', 'herbal')
        sql = """INSERT INTO herbals (herbal_name, description, unit, price, image_url, date_added, added_by, added_by_type, user_type) VALUES ($1, $2, $3, $4, $5, NOW(), $6, $7, $8) RETURNING herbal_id"""
        try: price_f = float(herbal_data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format for herbal.")
        params = (
            herbal_data_lower['herbal_name'], herbal_data_lower['description'], herbal_data_lower['unit'],
            price_f, herbal_data_lower.get('image_url'), herbal_data_lower.get('added_by'),
            herbal_data_lower.get('added_by_type', user_type), user_type
        )
        herbal_id = await self._execute_query(conn, sql, params, returning_id_column='herbal_id')
        if herbal_id:
            logger.info(f"Created herbal ID: {herbal_id}")
            return {"herbal_id": herbal_id, "UserType": user_type}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Herbal creation failed unexpectedly.")

    async def update_herbal(self, conn: asyncpg.Connection, herbal_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
        set_clauses = []; params = []; param_index = 1;
        allowed = ['herbal_name', 'description', 'unit', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 # Add validation if needed (e.g., price is float)
                 if key == 'price':
                     try: value = float(value)
                     except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format.")
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields for update.")
        sql = f"UPDATE herbals SET {', '.join(set_clauses)} WHERE herbal_id = ${param_index}"
        params.append(herbal_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated herbal ID: {herbal_id}")

    async def list_herbals(self, conn: asyncpg.Connection):
        results = await self._execute_query(conn, "SELECT * FROM herbals", fetch_all=True)
        return results or []

    async def get_herbal_by_id(self, conn: asyncpg.Connection, herbal_id: int):
        sql = "SELECT * FROM herbals WHERE herbal_id = $1"
        return await self._execute_query(conn, sql, (herbal_id,), fetch_one=True)

    async def delete_herbal(self, conn: asyncpg.Connection, herbal_id: int):
        logger.warning(f"Attempting to delete herbal ID: {herbal_id}")
        sql = "DELETE FROM herbals WHERE herbal_id = $1 RETURNING herbal_id"
        deleted_id = await conn.fetchval(sql, herbal_id)
        if deleted_id == herbal_id:
             logger.info(f"Deleted herbal ID: {herbal_id}")
             return True
        else:
             logger.warning(f"Attempted to delete non-existent herbal ID: {herbal_id}")
             return False

# --- Meals Class (Updated for asyncpg) ---
class Meals(BaseRepository):
    async def create_meal(self, conn: asyncpg.Connection, meal_data: dict):
        meal_data_lower = lowercase_keys(meal_data)
        check_required_fields(meal_data_lower, ['meal_name', 'meal_category', 'ingredients'])
        user_type = meal_data_lower.get('user_type', 'meal')
        sql = """INSERT INTO meals (meal_name, meal_category, ingredients, complementary_dishes, recipe, recipe_link, image_link, goal, dietary_preference, allergies, disease_management, cuisine_preferences, skill_level, prep_time, meal_description, date_added, date_last_edited, added_by, added_by_type, user_type) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,NOW(),NOW(),$16,$17,$18) RETURNING meal_id"""
        params = (
            meal_data_lower['meal_name'], meal_data_lower['meal_category'], meal_data_lower['ingredients'],
            meal_data_lower.get('complementary_dishes'), meal_data_lower.get('recipe'), meal_data_lower.get('recipe_link'),
            meal_data_lower.get('image_link'), meal_data_lower.get('goal'), meal_data_lower.get('dietary_preference'),
            meal_data_lower.get('allergies'), meal_data_lower.get('disease_management'), meal_data_lower.get('cuisine_preferences'),
            meal_data_lower.get('skill_level'), meal_data_lower.get('prep_time'), meal_data_lower.get('meal_description'),
            meal_data_lower.get('added_by'), meal_data_lower.get('added_by_type', user_type), user_type
        )
        meal_id = await self._execute_query(conn, sql, params, returning_id_column='meal_id')
        if meal_id:
            logger.info(f"Created meal ID: {meal_id}")
            return {"meal_id": meal_id, "UserType": user_type}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Meal creation failed unexpectedly.")

    async def update_meal(self, conn: asyncpg.Connection, meal_id: str, updates: dict):
        mid = str(meal_id) # Keep as string if meal_id is text
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
        updates_lower['date_last_edited'] = datetime.now() # Automatically update edit time

        set_clauses = []; params = []; param_index = 1;
        allowed_fields = [
            'meal_name', 'meal_category', 'ingredients', 'complementary_dishes', 'recipe', 'recipe_link',
            'image_link', 'goal', 'dietary_preference', 'allergies', 'disease_management', 'cuisine_preferences',
            'skill_level', 'prep_time', 'meal_description', 'date_last_edited'
        ]
        for key, value in updates_lower.items():
            if key in allowed_fields:
                set_clauses.append(f"{key} = ${param_index}")
                params.append(value)
                param_index += 1

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields for meal update.")
        sql = f"UPDATE meals SET {', '.join(set_clauses)} WHERE meal_id = ${param_index}"
        params.append(mid)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated meal ID: {meal_id}")

    async def list_meals(self, conn: asyncpg.Connection):
        sql_query = """
        WITH MealDetails AS (
            SELECT
                m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link, m.goal,
                m.dietary_preference, m.allergies, m.disease_management, m.cuisine_preferences,
                m.skill_level, m.prep_time, m.meal_description
            FROM meals m
        )
        SELECT
            md.*,
            COALESCE((SELECT STRING_AGG(p.produce_name, ', ') FROM meal_ingredients i JOIN produce p ON i.produce_id = p.produce_id WHERE i.meal_id = md.meal_id), '') AS ingredients,
            COALESCE((SELECT STRING_AGG(mc.meal_name, ', ') FROM meal_complementaries mc_link JOIN meals mc ON mc_link.complementary_dish_id = mc.meal_id WHERE mc_link.meal_id = md.meal_id), '') AS complementary_dishes
        FROM MealDetails md;
        """
        results = await self._execute_query(conn, sql_query, fetch_all=True)
        if not results: return []

        meal_recommendations = []
        for row in results:
            meal = dict(row)
            meal_dict = {
                "Meal_id": meal.get("meal_id"), "Meal_name": meal.get("meal_name"), "Meal_category": meal.get("meal_category"),
                "Recipe": meal.get("recipe"), "Recipe_link": meal.get("recipe_link"), "Image_link": meal.get("image_link"),
                "Goal": meal.get("goal"), "Dietary_preference": meal.get("dietary_preference"), "Allergies": meal.get("allergies"),
                "Disease_management": meal.get("disease_management"), "Cuisine_preferences": meal.get("cuisine_preferences"),
                "Skill_level": meal.get("skill_level"), "Prep_time": meal.get("prep_time"), "Meal_description": meal.get("meal_description"),
                "Ingredients": meal.get("ingredients") or "", "Complementary_dishes": meal.get("complementary_dishes") or "",
                "Price": 10_000 # Default price
            }
            meal_recommendations.append(meal_dict)
        return meal_recommendations

    async def get_meal_by_id(self, conn: asyncpg.Connection, meal_id: str):
        # Assuming meal_id is text/varchar
        sql = "SELECT * FROM meals WHERE meal_id = $1"
        return await self._execute_query(conn, sql, (str(meal_id),), fetch_one=True)

    async def delete_meal(self, conn: asyncpg.Connection, meal_id: str):
        logger.warning(f"Attempting to delete meal ID: {meal_id}")
        sql = "DELETE FROM meals WHERE meal_id = $1 RETURNING meal_id"
        deleted_id = await conn.fetchval(sql, str(meal_id))
        if deleted_id == meal_id:
             logger.info(f"Deleted meal ID: {meal_id}")
             return True
        else:
             logger.warning(f"Attempted to delete non-existent meal ID: {meal_id}")
             return False


# --- Produce Class (Updated for asyncpg) ---
class Produce(BaseRepository):
    async def create_produce(self, conn: asyncpg.Connection, produce_data: dict):
        produce_data_lower = lowercase_keys(produce_data)
        check_required_fields(produce_data_lower, ['produce_name', 'unit_grams', 'calories'])
        user_type = produce_data_lower.get('user_type', 'produce')
        sql = """INSERT INTO produce (produce_name, unit_grams, calories, cholesterol, carbohydrates, proteins, fats, fiber, sugars, meal_type, source, nutritional_info, date_added, date_last_edited, added_by, added_by_type, user_type) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,NOW(),NOW(),$13,$14,$15) RETURNING produce_id"""
        try:
             params = (
                produce_data_lower['produce_name'], float(produce_data_lower['unit_grams']), float(produce_data_lower['calories']),
                produce_data_lower.get('cholesterol'), produce_data_lower.get('carbohydrates'), produce_data_lower.get('proteins'),
                produce_data_lower.get('fats'), produce_data_lower.get('fiber'), produce_data_lower.get('sugars'),
                produce_data_lower.get('meal_type'), produce_data_lower.get('source'), produce_data_lower.get('nutritional_info'),
                produce_data_lower.get('added_by'), produce_data_lower.get('added_by_type', user_type), user_type
            )
        except (ValueError, TypeError) as e:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid numeric format in produce data: {e}") from e
        produce_id = await self._execute_query(conn, sql, params, returning_id_column='produce_id')
        if produce_id:
            logger.info(f"Created produce ID: {produce_id}")
            return {"produce_id": produce_id, "UserType": user_type}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Produce creation failed unexpectedly.")

    async def update_produce(self, conn: asyncpg.Connection, produce_id: str, updates: dict):
        pid = str(produce_id) # Keep as string if ID is text
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
        updates_lower['date_last_edited'] = datetime.now()

        set_clauses = []; params = []; param_index = 1;
        allowed = ['produce_name', 'unit_grams', 'calories', 'cholesterol', 'carbohydrates', 'proteins', 'fats', 'fiber', 'sugars', 'meal_type', 'source', 'nutritional_info', 'date_last_edited']
        for key, value in updates_lower.items():
             if key in allowed:
                 # Add validation for numeric types if needed
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1

        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields for produce update.")
        sql = f"UPDATE produce SET {', '.join(set_clauses)} WHERE produce_id = ${param_index}"
        params.append(pid)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated produce ID: {produce_id}")

    async def list_produce(self, conn: asyncpg.Connection):
        results = await self._execute_query(conn, "SELECT * FROM produce", fetch_all=True)
        return results or []

    async def get_produce_by_id(self, conn: asyncpg.Connection, produce_id: int): # Assuming produce_id is int based on usage
        sql = "SELECT * FROM produce WHERE produce_id = $1"
        return await self._execute_query(conn, sql, (produce_id,), fetch_one=True)

    async def delete_produce(self, conn: asyncpg.Connection, produce_id: int): # Assuming int
        logger.warning(f"Attempting to delete produce ID: {produce_id}")
        sql = "DELETE FROM produce WHERE produce_id = $1 RETURNING produce_id"
        deleted_id = await conn.fetchval(sql, produce_id)
        if deleted_id == produce_id:
             logger.info(f"Deleted produce ID: {produce_id}")
             return True
        else:
             logger.warning(f"Attempted to delete non-existent produce ID: {produce_id}")
             return False

# --- Gadgets Class (Updated for asyncpg) ---
class Gadgets(BaseRepository):
    async def create_gadget(self, conn: asyncpg.Connection, gadget_data: dict):
        gadget_data_lower = lowercase_keys(gadget_data)
        check_required_fields(gadget_data_lower, ['gadget_name', 'description', 'price'])
        user_type = gadget_data_lower.get('user_type', 'gadget')
        sql = """INSERT INTO gadgets (gadget_name, description, brand, model, price, image_url, date_added, added_by, added_by_type, user_type) VALUES ($1,$2,$3,$4,$5,$6,NOW(),$7,$8,$9) RETURNING gadget_id"""
        try: price_f = float(gadget_data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format for gadget.")
        params = (
            gadget_data_lower['gadget_name'], gadget_data_lower['description'], gadget_data_lower.get('brand'),
            gadget_data_lower.get('model'), price_f, gadget_data_lower.get('image_url'),
            gadget_data_lower.get('added_by'), gadget_data_lower.get('added_by_type', user_type), user_type
        )
        gadget_id = await self._execute_query(conn, sql, params, returning_id_column='gadget_id')
        if gadget_id:
            logger.info(f"Created gadget ID: {gadget_id}")
            return {"gadget_id": gadget_id, "UserType": user_type}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Gadget creation failed unexpectedly.")

    async def update_gadget(self, conn: asyncpg.Connection, gadget_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
        set_clauses = []; params = []; param_index = 1;
        allowed = ['gadget_name', 'description', 'brand', 'model', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 if key == 'price':
                      try: value = float(value)
                      except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format.")
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields for update.")
        sql = f"UPDATE gadgets SET {', '.join(set_clauses)} WHERE gadget_id = ${param_index}"
        params.append(gadget_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated gadget ID: {gadget_id}")

    async def list_gadgets(self, conn: asyncpg.Connection):
        results = await self._execute_query(conn, "SELECT * FROM gadgets", fetch_all=True)
        return results or []

    async def get_gadget_by_id(self, conn: asyncpg.Connection, gadget_id: int):
        sql = "SELECT * FROM gadgets WHERE gadget_id = $1"
        return await self._execute_query(conn, sql, (gadget_id,), fetch_one=True)

    async def delete_gadget(self, conn: asyncpg.Connection, gadget_id: int):
        logger.warning(f"Attempting to delete gadget ID: {gadget_id}")
        sql = "DELETE FROM gadgets WHERE gadget_id = $1 RETURNING gadget_id"
        deleted_id = await conn.fetchval(sql, gadget_id)
        if deleted_id == gadget_id:
             logger.info(f"Deleted gadget ID: {gadget_id}")
             return True
        else:
             logger.warning(f"Attempted to delete non-existent gadget ID: {gadget_id}")
             return False

# --- Spices Class (Updated for asyncpg) ---
class Spices(BaseRepository):
    async def create_spice(self, conn: asyncpg.Connection, spice_data: dict):
        spice_data_lower = lowercase_keys(spice_data)
        check_required_fields(spice_data_lower, ['spice_name', 'description', 'price'])
        user_type = spice_data_lower.get('user_type', 'spice')
        sql = """INSERT INTO spices (spice_name, description, unit, price, image_url, date_added, added_by, added_by_type, user_type) VALUES ($1,$2,$3,$4,$5,NOW(),$6,$7,$8) RETURNING spice_id"""
        try: price_f = float(spice_data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format for spice.")
        params = (
            spice_data_lower['spice_name'], spice_data_lower['description'], spice_data_lower.get('unit'),
            price_f, spice_data_lower.get('image_url'), spice_data_lower.get('added_by'),
            spice_data_lower.get('added_by_type', user_type), user_type
        )
        spice_id = await self._execute_query(conn, sql, params, returning_id_column='spice_id')
        if spice_id:
            logger.info(f"Created spice ID: {spice_id}")
            return {"spice_id": spice_id, "UserType": user_type}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Spice creation failed unexpectedly.")

    async def update_spice(self, conn: asyncpg.Connection, spice_id: int, updates: dict):
        updates_lower = lowercase_keys(updates)
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
        set_clauses = []; params = []; param_index = 1;
        allowed = ['spice_name', 'description', 'unit', 'price', 'image_url']
        for key, value in updates_lower.items():
             if key in allowed:
                 if key == 'price':
                     try: value = float(value)
                     except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format.")
                 set_clauses.append(f"{key} = ${param_index}")
                 params.append(value)
                 param_index += 1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields for update.")
        sql = f"UPDATE spices SET {', '.join(set_clauses)} WHERE spice_id = ${param_index}"
        params.append(spice_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated spice ID: {spice_id}")

    async def list_spices(self, conn: asyncpg.Connection):
        results = await self._execute_query(conn, "SELECT * FROM spices", fetch_all=True)
        return results or []

    async def get_spice_by_id(self, conn: asyncpg.Connection, spice_id: int):
        sql = "SELECT * FROM spices WHERE spice_id = $1"
        return await self._execute_query(conn, sql, (spice_id,), fetch_one=True)

    async def delete_spice(self, conn: asyncpg.Connection, spice_id: int):
        logger.warning(f"Attempting to delete spice ID: {spice_id}")
        sql = "DELETE FROM spices WHERE spice_id = $1 RETURNING spice_id"
        deleted_id = await conn.fetchval(sql, spice_id)
        if deleted_id == spice_id:
             logger.info(f"Deleted spice ID: {spice_id}")
             return True
        else:
             logger.warning(f"Attempted to delete non-existent spice ID: {spice_id}")
             return False


# --- Orders Class (Updated for asyncpg) ---
class Orders(BaseRepository):
    ALLOWED_ORDER_TYPES = {'meal', 'supplement', 'gig', 'herbal', 'gadget', 'spice', 'produce'}
    ALLOWED_ORDER_STATUSES = {'cancelled', 'assigned', 'delivered', 'shipped', 'preparing', 'confirmed', 'pending', 'accepted', 'dispatched', 'picked up', 'delivering'}
    ALLOWED_PAYMENT_STATUSES = {'failed', 'refunded', 'paid', 'pending', 'completed'}
    ALLOWED_PAYMENT_MODES = {'cash', 'momo', 'mobile money', 'Airtel Card', 'paypal', 'stripe', 'debit card', 'credit card'}

    async def _validate_product_id(self, conn: asyncpg.Connection, product_id: Union[str, int], order_type: str):
        """Validates product_id asynchronously. Raises HTTPException."""
        if not product_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"product_id is required for {order_type} orders.")

        order_type_l = order_type.lower().strip()
        table_map = {
            'meal': ('meals', 'meal_id'), 'supplement': ('supplements', 'supplement_id'),
            'herbal': ('herbals', 'herbal_id'), 'gadget': ('gadgets', 'gadget_id'),
            'spice': ('spices', 'spice_id'), 'produce': ('produce', 'produce_id')
        }

        if order_type_l == 'gig': return # Skip validation for gigs

        if order_type_l not in table_map:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order_type: '{order_type}'.")

        table_name, id_column = table_map[order_type_l]
        # Use SQL injection safe formatting (asyncpg doesn't support dynamic table names in params)
        # Ensure table/column names are safe and validated
        sql = f"SELECT {id_column} FROM {table_name} WHERE {id_column} = $1"

        try:
            # Try fetching with the original type, then string if needed (IDs can be int or text)
            result = await conn.fetchval(sql, product_id)
            if result is None:
                result = await conn.fetchval(sql, str(product_id)) # Try as string

            if result is None:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid product_id: '{product_id}' does not exist for order_type '{order_type}'.")
        except (ValueError, TypeError): # Catch potential issues casting product_id
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid format for product_id: '{product_id}'.")

    async def create_order(self, conn: asyncpg.Connection, user_id: int, order_type: str, order_status: str = "pending", payment_status: str = "pending", payment_mode: str = "cash",
                           delivery_address: Optional[str] = None, notes: Optional[str] = None, total_price: float = 0.0, amount_paid: float = 0.0, quantity: int = 1,
                           product_id: Optional[Union[str, int]] = None, chef_id: Optional[int] = None, producer_id: Optional[int] = None, transporter_id: Optional[int] = None, transaction_id: Optional[str] = None,
                           items: Optional[List[Dict]] = None):
        order_type_l = str(order_type).lower().strip()
        gig_details_json = None
        try:
            if order_type_l == 'gig':
                if not items or not isinstance(items, list) or len(items) == 0:
                    raise ValueError("items parameter with gig_details is required for gig orders.")
                gig_details = items[0].get('gig_details', {})
                if not gig_details or not isinstance(gig_details, dict):
                    raise ValueError("Valid gig_details dictionary is required for gig orders.")
                gig_details_json = json.dumps(gig_details)
            else:
                # Await validation
                await self._validate_product_id(conn, product_id, order_type_l)

            order_status_l = str(order_status).lower().strip()
            payment_status_l = str(payment_status).lower().strip()
            payment_mode_l = str(payment_mode).lower().strip()

            # Validate enums
            if order_type_l not in self.ALLOWED_ORDER_TYPES: raise ValueError(f"Invalid order_type: '{order_type}'.")
            if order_status_l not in self.ALLOWED_ORDER_STATUSES: raise ValueError(f"Invalid order_status: '{order_status}'.")
            if payment_status_l not in self.ALLOWED_PAYMENT_STATUSES: raise ValueError(f"Invalid payment_status: '{payment_status}'.")
            if payment_mode_l != 'airtel card' and payment_mode_l not in self.ALLOWED_PAYMENT_MODES:
                is_airtel_card = str(payment_mode).strip() == 'Airtel Card'
                if not is_airtel_card and payment_mode_l not in self.ALLOWED_PAYMENT_MODES:
                    raise ValueError(f"Invalid payment_mode: '{payment_mode}'.")
                if is_airtel_card: payment_mode_l = 'Airtel Card'

            delivery_address_s = delivery_address or "Not specified"
            notes_s = notes or "No special instructions"
            # Convert numeric types
            price_f = float(total_price); paid_f = float(amount_paid); qty_i = int(quantity); user_id_i = int(user_id)
            # Ensure IDs are correct types (or None)
            prod_id_s = str(product_id) if product_id is not None else None # Product ID might be text
            chef_id_i = int(chef_id) if chef_id is not None else None
            producer_id_i = int(producer_id) if producer_id is not None else None
            transporter_id_i = int(transporter_id) if transporter_id is not None else None

        except (ValueError, TypeError) as e:
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order data format: {e}") from e

        sql = """INSERT INTO orders (user_id, order_type, product_id, chef_id, producer_id, transporter_id, order_date, delivery_address, order_status, total_price, notes, payment_status, payment_mode, amount_paid, transaction_id, quantity, gig_details)
                 VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                 RETURNING order_id"""
        params = (user_id_i, order_type_l, prod_id_s, chef_id_i, producer_id_i, transporter_id_i,
                  delivery_address_s, order_status_l, price_f, notes_s, payment_status_l, payment_mode_l,
                  paid_f, transaction_id, qty_i, gig_details_json)

        order_id = await self._execute_query(conn, sql, params, returning_id_column='order_id')
        if order_id:
            logger.info(f"Order created: {order_id}")
            return {"message": "Order created successfully", "order_id": order_id, "success": True}
        else:
             raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Order creation failed unexpectedly.")

    async def read_orders(self, conn: asyncpg.Connection, order_id=None, chef_id=None, producer_id=None, user_id=None, transporter_id=None):
        # SQL query remains the same structure
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
        param_index = 1
        def _safe_int(val, field_name="ID"):
            if val is None: return None
            try: return int(val)
            except (ValueError, TypeError): raise ValueError(f"Invalid format for {field_name}: '{val}'. Expected an integer.")

        try:
            if order_id is not None: sql += f" AND o.order_id = ${param_index}"; params.append(_safe_int(order_id, "order_id")); param_index += 1
            if chef_id is not None: sql += f" AND o.chef_id = ${param_index}"; params.append(_safe_int(chef_id, "chef_id")); param_index += 1
            if producer_id is not None: sql += f" AND o.producer_id = ${param_index}"; params.append(_safe_int(producer_id, "producer_id")); param_index += 1
            if user_id is not None: sql += f" AND o.user_id = ${param_index}"; params.append(_safe_int(user_id, "user_id")); param_index += 1
            if transporter_id is not None: sql += f" AND o.transporter_id = ${param_index}"; params.append(_safe_int(transporter_id, "transporter_id")); param_index += 1
        except ValueError as e:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

        sql += " ORDER BY o.order_date DESC"

        results = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if results is None: return []

        processed_results = []
        for order in results:
            processed_order = dict(order)
            for key, value in processed_order.items():
                if isinstance(value, (datetime, date)):
                    processed_order[key] = value.isoformat()
                if key == 'gig_details' and value:
                    try: processed_order['gig_details'] = json.loads(value)
                    except (json.JSONDecodeError, TypeError):
                         logger.warning(f"Failed to parse gig_details for order_id {processed_order.get('order_id')}")
                         processed_order['gig_details'] = None # Or keep original string?
            processed_results.append(processed_order)

        logger.info(f"Retrieved {len(processed_results)} orders matching criteria.")
        return processed_results

    async def update_order_status(self, conn: asyncpg.Connection, order_id: int, new_status: str):
        new_status_l = str(new_status).lower().strip()
        if new_status_l not in self.ALLOWED_ORDER_STATUSES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid target order status: {new_status}")

        sql = "UPDATE orders SET order_status = $1, updated_at = NOW() WHERE order_id = $2 RETURNING order_id"
        updated_id = await conn.fetchval(sql, new_status_l, order_id)

        if updated_id == order_id:
            logger.info(f"Updated order ID {order_id} status to {new_status_l}")
            return True
        else:
            # Order ID not found
            logger.warning(f"Attempted to update status for non-existent order ID: {order_id}")
            return False # Or raise 404

    async def delete_order(self, conn: asyncpg.Connection, order_id: int):
        logger.warning(f"Attempting to delete order ID: {order_id}")
        sql = "DELETE FROM orders WHERE order_id = $1 RETURNING order_id"
        deleted_id = await conn.fetchval(sql, order_id)
        if deleted_id == order_id:
            logger.info(f"Deleted order ID: {order_id}")
            return True
        else:
            logger.warning(f"Attempted to delete non-existent order ID: {order_id}")
            return False


# --- Calculation Logic Class (No DB interaction, remains synchronous) ---
class CalculationLogic:
    def calculate_bmi(self, weight, height):
        if not height or height == 0: return 0.0
        try: weight_f = float(weight); height_f = float(height); height_m = height_f / 100.0; return round(weight_f / (height_m ** 2), 1) if height_m != 0 else 0.0
        except (ValueError, TypeError) as e: logger.warning(f"Invalid BMI input: w={weight}, h={height}. Err: {e}"); return 0.0
    def calculate_bmi_category(self, bmi):
        try: bmi_f = float(bmi)
        except (ValueError, TypeError): logger.warning(f"Invalid BMI value: {bmi}"); return 'Unknown'
        if bmi_f < 18.5: return 'Underweight'
        elif 18.5 <= bmi_f < 24.9: return 'Normal weight'
        elif 25 <= bmi_f < 29.9: return 'Overweight'
        else: return 'Obesity'
    def calculate_ideal_weight(self, height, sex):
        try: height_f = float(height)
        except (ValueError, TypeError): logger.warning(f"Invalid height for Ideal Weight: {height}"); return 0.0
        sex_lower = str(sex).strip().lower() if sex else 'unknown'
        ideal_weight_kg = 0.0
        if sex_lower == 'male': ideal_weight_kg = 50 + 0.91 * (height_f - 152)
        elif sex_lower == 'female': ideal_weight_kg = 45.5 + 0.91 * (height_f - 152)
        else: logger.warning(f"Unknown sex '{sex}' for Ideal Weight, using average formula."); ideal_weight_kg = 47.75 + 0.91 * (height_f - 152)
        return round(max(ideal_weight_kg, 0), 1)
    def convert_age_range_to_age(self, age_range):
        if isinstance(age_range, (int, float)): return int(age_range)
        if isinstance(age_range, str):
            try:
                if '-' in age_range: age_min, age_max = map(int, age_range.split('-')); return (age_min + age_max) // 2
                else: return int(age_range)
            except ValueError: logger.warning(f"Error parsing age range string '{age_range}', using default 30."); return 30
        else: logger.warning(f"Invalid age range type '{type(age_range)}', using default 30."); return 30
    def calculate_bmr(self, weight, height, age_range, sex):
        try:
            weight_f=float(weight); height_f=float(height); age=self.convert_age_range_to_age(age_range); sex_lower=str(sex).strip().lower() if sex else 'unknown'
            if sex_lower == 'male': bmr = (10*weight_f) + (6.25*height_f) - (5*age) + 5
            elif sex_lower == 'female': bmr = (10*weight_f) + (6.25*height_f) - (5*age) - 161
            else: logger.warning(f"Unknown sex '{sex}' for BMR, using male formula."); bmr = (10*weight_f) + (6.25*height_f) - (5*age) + 5
            return round(max(bmr, 0))
        except (ValueError, TypeError) as e: logger.warning(f"Invalid input for BMR calc: w={weight}, h={height}, age={age_range}, sex={sex}. Err: {e}"); return 0
    def calculate_daily_calories(self, bmr, activity_level):
        try: bmr_f = float(bmr)
        except (ValueError, TypeError): logger.warning(f"Invalid BMR for TDEE calc: {bmr}"); return 0
        activity_level_lower = str(activity_level).strip().lower().replace(" ", "_") if activity_level else 'sedentary'
        activity_multiplier = {'sedentary': 1.2, 'lightly_active': 1.375, 'moderately_active': 1.55, 'very_active': 1.725, 'extremely_active': 1.9, 'extra_active': 1.9}
        multiplier = activity_multiplier.get(activity_level_lower, 1.2)
        if activity_level_lower not in activity_multiplier: logger.warning(f"Unknown activity level '{activity_level}', using sedentary (1.2).")
        return round(bmr_f * multiplier)

# --- Meal Recommendation Classes (Updated for asyncpg) ---
class BaseMealRecommender:
    def __init__(self, user_id: int):
        if not isinstance(user_id, int): raise TypeError("user_id must be an integer.")
        self.user_id = user_id
        # Instantiate CRUD classes - they don't need DB conn at init time
        self._users_crud = AuthenticationAndUsers()
        self._produce_crud = Produce()
        # Defer fetching data until needed or within an async method
        self.user_preferences: Optional[Dict] = None
        self.user_metrics: Optional[Dict] = None

    async def _load_user_data(self, conn: asyncpg.Connection):
         """Loads user preferences and metrics asynchronously."""
         # Load only if not already loaded
         if self.user_preferences is None:
             self.user_preferences = await self._get_user_preferences(conn)
         if self.user_metrics is None:
             self.user_metrics = await self._get_user_metrics(conn)
         self._validate_user_data() # Validate after loading

    # _validate_user_data remains synchronous helper
    def _validate_user_data(self):
        if not self.user_preferences: logger.warning(f"RecSys({self.__class__.__name__}) No preferences found for User ID: {self.user_id}.")
        if not self.user_metrics: logger.warning(f"RecSys({self.__class__.__name__}) No metrics found for User ID: {self.user_id}.")

    # Remove _execute_query wrapper, use CRUD instances directly
    async def _get_user_preferences(self, conn: asyncpg.Connection) -> Optional[Dict]:
        try:
             prefs_list = await self._users_crud.list_preferences(conn, user_id=self.user_id) # Pass conn
             if not prefs_list: return None
             result = prefs_list[0]
             return {
                "goals": result.get('goals', '').strip().lower() or None,
                "diet_type": result.get('diet_type', '').strip().lower() or None,
                "food_restrictions": deserialize_list(result.get('food_restrictions', '')),
                "cuisine_preferences": deserialize_list(result.get('cuisine_preferences', ''))
             }
        except Exception as e: logger.error(f"Error fetching preferences user {self.user_id}: {e}", exc_info=True); return None

    async def _get_user_metrics(self, conn: asyncpg.Connection) -> Optional[Dict]:
        try:
             metrics_list = await self._users_crud.list_metrics(conn, user_id=self.user_id) # Pass conn
             if not metrics_list: return None
             metrics = metrics_list[0]
             metrics['sex'] = metrics.get('sex', 'male').strip().lower()
             metrics['activity_level'] = metrics.get('activity_level', 'sedentary').strip().lower()
             return metrics
        except Exception as e: logger.error(f"Error fetching metrics user {self.user_id}: {e}", exc_info=True); return None

    async def _fetch_produce_data(self, conn: asyncpg.Connection, produce_names: List[str]) -> Dict[str, Dict]:
        if not produce_names: return {}
        try:
            all_produce = await self._produce_crud.list_produce(conn) # Pass conn
            produce_dict = {}
            if all_produce:
                name_lookup = {str(p['produce_name']).lower(): p for p in all_produce if p and p.get('produce_name')}
                for name_req in produce_names:
                    name_req_lower = name_req.strip().lower()
                    if name_req_lower in name_lookup:
                        p_data = name_lookup[name_req_lower]
                        produce_dict[name_req_lower] = {
                            "calories": float(p_data.get('calories', 0.0) or 0.0), "unit_grams": float(p_data.get('unit_grams', 100.0) or 100.0),
                            "cholesterol": float(p_data.get('cholesterol', 0.0) or 0.0), "carbohydrates": float(p_data.get('carbohydrates', 0.0) or 0.0),
                            "proteins": float(p_data.get('proteins', 0.0) or 0.0), "fats": float(p_data.get('fats', 0.0) or 0.0),
                            "fiber": float(p_data.get('fiber', 0.0) or 0.0), "sugars": float(p_data.get('sugars', 0.0) or 0.0),
                        }
            return produce_dict
        except Exception as e: logger.error(f"Error fetching produce data user {self.user_id}: {e}", exc_info=True); return {}

    # _calculate_meal_nutrition remains synchronous helper
    def _calculate_meal_nutrition(self, ingredients_str: Optional[str], produce_data_cache: Dict[str, Dict]) -> Dict[str, float]:
        nutrition = {"calories": 0.0, "proteins": 0.0, "carbohydrates": 0.0, "fats": 0.0, "fiber": 0.0, "sugars": 0.0, "cholesterol": 0.0, "total_grams": 0.0}
        if not ingredients_str or not isinstance(ingredients_str, str): return nutrition
        ingredient_names = [name.strip().lower() for name in ingredients_str.split(",") if name.strip()]
        for name_lower in ingredient_names:
            data = produce_data_cache.get(name_lower)
            if data:
                try:
                    grams = data.get('unit_grams', 0.0); nutrition["calories"] += float(data.get('calories', 0.0) or 0.0); nutrition["proteins"] += float(data.get('proteins', 0.0) or 0.0); nutrition["carbohydrates"] += float(data.get('carbohydrates', 0.0) or 0.0); nutrition["fats"] += float(data.get('fats', 0.0) or 0.0); nutrition["fiber"] += float(data.get('fiber', 0.0) or 0.0); nutrition["sugars"] += float(data.get('sugars', 0.0) or 0.0); nutrition["cholesterol"] += float(data.get('cholesterol', 0.0) or 0.0); nutrition["total_grams"] += float(grams or 0.0)
                except (TypeError, ValueError) as e: logger.warning(f"RecSys NutriCalc Error ingredient '{name_lower}', User:{self.user_id}. Data: {data}, Err: {e}")
            else: logger.warning(f"RecSys NutriData missing ingredient '{name_lower}', User:{self.user_id}.")
        for key in nutrition: nutrition[key] = round(nutrition[key], 1)
        return nutrition

class MealRecommendation1(BaseMealRecommender):
    async def fetch_all_meals_with_ingredients(self, conn: asyncpg.Connection):
        query = """ ... """ # Same query as before
        try:
             all_meals = await self._execute_query(conn, query, fetch_all=True) # Use base class method
             if not all_meals: return []
             all_ingredient_names = set(name.strip().lower() for meal in all_meals if meal.get('ingredients') for name in str(meal['ingredients']).split(",") if name.strip())
             # Fetch produce data async
             produce_data_cache = await self._fetch_produce_data(conn, list(all_ingredient_names))
             processed_meals = []
             for meal in all_meals:
                  p_meal = dict(meal)
                  # Calculate nutrition synchronously
                  p_meal['calculated_nutrition'] = self._calculate_meal_nutrition(p_meal.get('ingredients'), produce_data_cache)
                  processed_meals.append(p_meal)
             return processed_meals
        except HTTPException: raise # Re-raise HTTP exceptions
        except Exception as e: logger.error(f"RecSys(V1) User {self.user_id}: Error fetching meals: {e}", exc_info=True); return None

    # filter_meals remains synchronous helper
    def filter_meals(self, all_meals):
        if not all_meals: return []
        if not self.user_preferences: logger.warning(f"RecSys(V1) User {self.user_id}: No prefs, returning all."); return all_meals
        prefs = self.user_preferences; filtered = []
        for meal in all_meals:
            meal_diet_str = meal.get('dietary_preference') or ''; meal_diet = [d.strip().lower() for d in str(meal_diet_str).split(',') if d.strip()]
            meal_allergens_str = meal.get('allergies') or ''; meal_allergens = [a.strip().lower() for a in str(meal_allergens_str).split(',') if a.strip()]
            meal_cuisines_str = meal.get('cuisine_preferences') or ''; meal_cuisines = [c.strip().lower() for c in str(meal_cuisines_str).split(',') if c.strip()]
            meal_goal = meal.get('goal') or ''; meal_goal_lower = str(meal_goal).strip().lower() if meal_goal else None
            user_goal = prefs.get('goals'); user_diet = prefs.get('diet_type'); user_restrictions = prefs.get('food_restrictions'); user_cuisines = prefs.get('cuisine_preferences')
            if user_diet and meal_diet and user_diet not in meal_diet: continue
            if user_restrictions and any(res in meal_allergens for res in user_restrictions): continue
            if user_cuisines and meal_cuisines and not any(cp in meal_cuisines for cp in user_cuisines): continue
            if user_goal and meal_goal_lower and user_goal != meal_goal_lower: continue
            filtered.append(meal)
        logger.info(f"RecSys(V1) User {self.user_id}: Filtered {len(all_meals)} -> {len(filtered)}")
        return filtered

    async def recommend_meals(self, conn: asyncpg.Connection):
        try:
             await self._load_user_data(conn) # Load data if not already loaded
             if not self.user_preferences:
                 raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User preferences not found.")

             all_meals = await self.fetch_all_meals_with_ingredients(conn)
             if all_meals is None:
                  raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to retrieve meals from database.")

             recommended_meals = self.filter_meals(all_meals) # Sync filtering
             processed_recs = []
             for meal in recommended_meals:
                  p_meal = dict(meal); p_meal.setdefault('price', 10000)
                  for key, value in p_meal.items():
                       if isinstance(value, (datetime, date)): p_meal[key] = value.isoformat()
                  processed_recs.append(p_meal)

             logger.info(f"RecSys(V1) User {self.user_id}: Generated {len(processed_recs)} recommendations.")
             return {"recommended_meals": processed_recs, "success": True}
        except HTTPException: raise # Re-raise HTTP exceptions
        except Exception as e:
            logger.error(f"RecSys(V1) User {self.user_id}: Unexpected Error: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected error occurred during recommendation.")


# --- GetAllMeals Class (Updated for asyncpg) ---
class GetAllMeals(BaseRepository):
    async def fetch_all_meals(self, conn: asyncpg.Connection):
        logger.debug("Fetching all meals with ingredients and complementaries...")
        sql_query = """ ... """ # Same query as before
        try:
            all_meals_list = await self._execute_query(conn, sql_query, fetch_all=True)
            if all_meals_list is None:
                 logger.error("Database query for all meals returned None.")
                 # Let the API layer return 500 based on HTTPException from _execute_query
                 # Or raise specific exception here if needed
                 raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to retrieve meals data.")

            processed_meals = []
            for meal_row in all_meals_list:
                 meal_dict = dict(meal_row)
                 meal_dict.setdefault('price', 10000)
                 for key, value in meal_dict.items():
                     if isinstance(value, (datetime, date)): meal_dict[key] = value.isoformat()
                 processed_meals.append(meal_dict)

            logger.info(f"Successfully fetched {len(processed_meals)} meals.")
            return {"All_Meals": processed_meals, "success": True}
        except HTTPException: raise # Re-raise HTTP exceptions
        except Exception as e:
            logger.error(f"Unexpected error fetching all meals: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected server error occurred.")


# --- Payment Gateway Functions (Remain Synchronous) ---
# Initial Payment Gateway Configurations
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


# --- FastAPI App Initialization ---
app=FastAPI(
    title="ZINZI",
    description="Robust ZINZI backend.",
    lifespan=lifespan,  # Attach the lifespan context manager
    default_response_class=ORJSONResponse  # Use ORJSONResponse for better performance
)
# --- CORS Middleware ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Be more specific in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Backend Class Instantiations ---
# These can be instantiated globally or managed via Depends if needed later
auth_users = AuthenticationAndUsers()
chefs_crud = Chefs()
herbals_crud = Herbals()
meals_crud = Meals()
produce_crud = Produce()
producers_crud = Producers()
gadgets_crud = Gadgets()
spices_crud = Spices()
stakeholders_crud = Stakeholders()
orders_crud = Orders()
transporters_crud = Transporters()
calc_logic = CalculationLogic() # Doesn't need DB, can be global
meal_fetcher = GetAllMeals() # Needs DB, instantiate per request or pass conn


# --- FastAPI Endpoints ---

import functools # Import functools for caching

@app.get('/rr')
async def welcome():
    """Welcome endpoint."""
    return {'message': 'Welcome to BONOBO.'}

# === USER Endpoints (FastAPI) ===
@app.post('/rr/signup_user', status_code=status.HTTP_201_CREATED)
async def signup_user_endpoint(user_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Signs up a new user."""
    # FastAPI handles JSON parsing into user_data
    try:
        # Check required fields (using dict access with potential KeyError)
        name = user_data['name']
        email = user_data['email']
        password = user_data['password']
        image = user_data.get('image')
        # Await the async method
        user_info = await auth_users.create_user(conn, {'Name': name, 'Email': email, 'Password': password, 'Image': image})
        # No need for .get("success"), exceptions handle failure
        return {'message': 'User registered. Please verify email.', 'user_id': user_info['user_id']}
    except KeyError as ke:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f'Missing field: {ke}')
    # Other exceptions (ValueError, PostgresError, etc.) are caught and raised as HTTPException within create_user

@app.post('/rr/verify_user')
async def verify_user_endpoint(verification_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Verifies a user's email address."""
    try:
        user_id = int(verification_data['user_id'])
        verification_code = verification_data['verification_code']
        if not verification_code: raise ValueError("verification_code cannot be empty")
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid input: user_id (int) and verification_code (str) required.')

    # verify_user_email raises HTTPException on failure
    await auth_users.verify_user_email(conn, user_id, verification_code)
    return {'message': 'Email verification successful'} # Return success message directly


@app.post('/rr/login_user')
async def login_user_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Logs in a user by identifier (name or email) and password."""
    identifier = login_data.get('identifier')
    password = login_data.get('password')
    if not identifier or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier and password required')
    # login_user raises HTTPException on failure
    login_result = await auth_users.login_user(conn, identifier, password)
    return login_result


# === USER Endpoints (FastAPI - Corrected List/Get) ===

# --- Endpoint to list ALL users ---
@app.get('/rr/rusers')
async def list_all_users_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all users."""
    # Call the backend function without a user_id
    data = await auth_users.list_users(conn, user_id=None)
    # list_users should handle potential DB errors and raise HTTPException
    return {'message': 'All users retrieved successfully.', 'data': data or []}

# --- Endpoint to get a SPECIFIC user by ID ---
@app.get('/rr/rusers/{user_id}')
async def get_user_by_id_endpoint(
    user_id: int = Path(..., description="The ID of the user to retrieve", gt=0), # Path param is required, '...' indicates this. Added gt=0 validation.
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific user by ID."""
    # Call the backend function with the specific user_id
    data = await auth_users.list_users(conn, user_id=user_id)
    # list_users should handle potential DB errors and raise HTTPException
    if data is None: # list_users returns None if specific user not found
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    return {'message': 'User retrieved successfully.', 'data': data}


@app.delete('/rr/users/{user_id}', status_code=status.HTTP_200_OK)
async def delete_user_endpoint(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a user by ID."""
    success = await auth_users.delete_user(conn, user_id)
    if success:
        return {'message': f'User {user_id} deleted successfully'}
    else:
        # Assume failure means not found or DB error (which should raise HTTPException)
        # If delete_user returns False only for "not found", raise 404
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'User {user_id} not found or failed to delete.')


# === CHEF Endpoints (FastAPI) ===
@app.post('/rr/signup_chef', status_code=status.HTTP_201_CREATED)
async def create_chef_endpoint(chef_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new chef profile."""
    # create_chef raises HTTPException on failure
    result = await chefs_crud.create_chef(conn, chef_data)
    return result

@app.post('/rr/login/chefs')
async def login_chef_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Logs in a chef by identifier (name or email) and password."""
    identifier = login_data.get('identifier')
    password = login_data.get('password')
    if not identifier or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier and password required')
    # login_chef raises HTTPException on failure
    result = await chefs_crud.login_chef(conn, identifier, password)
    return result

# === CHEF Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/rchefs')
async def list_all_chefs_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all chefs."""
    # list_chefs already handles potential DB errors via _execute_query
    data = await chefs_crud.list_chefs(conn, chef_id=None)
    return {'message': 'Chefs retrieved.', 'data': data} # Returns empty list if none found

@app.get('/rr/rchefs/{chef_id}')
async def get_chef_by_id_endpoint(
    chef_id: int = Path(..., description="The ID of the chef to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific chef by ID."""
    # list_chefs returns a list even when filtered by ID
    data_list = await chefs_crud.list_chefs(conn, chef_id=chef_id)
    if not data_list: # Check if the list is empty
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Chef not found')
    # If found, return the first (and only) element
    return {'message': 'Chef retrieved.', 'data': data_list[0]}

@app.put('/rr/chefs/{chef_id}')
@app.patch('/rr/chefs/{chef_id}')
async def update_chef_endpoint(chef_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a chef's profile."""
    # update_chef raises HTTPException on failure/validation error
    await chefs_crud.update_chef(conn, chef_id, updates)
    # Fetch the updated data to return it
    updated_chef_list = await chefs_crud.list_chefs(conn, chef_id=chef_id)
    if updated_chef_list:
         return {'message': 'Chef updated successfully', 'data': updated_chef_list[0]}
    else:
         # Should not happen if update succeeded unless deleted concurrently
         raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Chef not found after update.')

@app.delete('/rr/chefs/{chef_id}', status_code=status.HTTP_200_OK)
async def delete_chef_endpoint(chef_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a chef by ID."""
    success = await chefs_crud.delete_chef(conn, chef_id)
    if success:
        return {'message': f'Chef {chef_id} deleted successfully'}
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Chef {chef_id} not found or failed to delete.')

@app.patch('/rr/chefs/{chef_id}/status')
async def update_chef_status_endpoint(chef_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates the active status of a chef."""
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Request body must contain a boolean "is_active" field')
    is_active = status_update['is_active']
    # update_chef_status raises HTTPException on DB error
    await chefs_crud.update_chef_status(conn, chef_id, is_active)
    return {'message': f'Chef {chef_id} status updated to {"active" if is_active else "inactive"}'}


# === PRODUCER Endpoints (FastAPI) ===
@app.post('/rr/aproducers', status_code=status.HTTP_201_CREATED)
async def add_producer_endpoint(producer_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new producer profile."""
    # create_producer raises HTTPException on failure
    result = await producers_crud.create_producer(conn, producer_data)
    return result

@app.post('/rr/login/producers')
async def login_producer_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Logs in a producer by identifier (name or email) and password."""
    identifier = login_data.get('identifier')
    password = login_data.get('password')
    if not identifier or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier and password required')
    # login_producer raises HTTPException on failure
    result = await producers_crud.login_producer(conn, identifier, password)
    return result

# === PRODUCER Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/rproducers')
async def list_all_producers_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all producers."""
    data = await producers_crud.list_producers(conn, producer_id=None)
    return {'message': 'Producers retrieved.', 'data': data}

@app.get('/rr/rproducers/{producer_id}')
async def get_producer_by_id_endpoint(
    producer_id: int = Path(..., description="The ID of the producer to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific producer by ID."""
    data_list = await producers_crud.list_producers(conn, producer_id=producer_id)
    if not data_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Producer not found')
    return {'message': 'Producer retrieved.', 'data': data_list[0]}


@app.put('/rr/producers/{producer_id}')
@app.patch('/rr/producers/{producer_id}')
async def update_producer_endpoint(producer_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a producer's profile."""
    # update_producer raises HTTPException on failure
    await producers_crud.update_producer(conn, producer_id, updates)
    updated_producer_list = await producers_crud.list_producers(conn, producer_id=producer_id)
    if updated_producer_list:
        return {'message': 'Producer updated successfully', 'data': updated_producer_list[0]}
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Producer not found after update.')

@app.delete('/rr/producers/{producer_id}', status_code=status.HTTP_200_OK)
async def delete_producer_endpoint(producer_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a producer by ID."""
    success = await producers_crud.delete_producer(conn, producer_id)
    if success:
        return {'message': f'Producer {producer_id} deleted successfully'}
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Producer {producer_id} not found or failed to delete.')

@app.patch('/rr/producers/{producer_id}/status')
async def update_producer_status_endpoint(producer_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates the active status of a producer."""
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Request body must contain a boolean "is_active" field')
    is_active = status_update['is_active']
    await producers_crud.update_producer_status(conn, producer_id, is_active)
    return {'message': f'Producer {producer_id} status updated to {"active" if is_active else "inactive"}'}


# === TRANSPORTER Endpoints (FastAPI) ===
@app.post('/rr/transporters/signup', status_code=status.HTTP_201_CREATED)
async def signup_transporter_endpoint(transporter_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new transporter profile."""
    result = await transporters_crud.create_transporter(conn, transporter_data)
    return result

@app.post('/rr/transporters/login')
async def login_transporter_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Logs in a transporter by identifier (name or email) and password."""
    identifier = login_data.get('identifier')
    password = login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier and password required')
    result = await transporters_crud.login_transporter(conn, identifier, password)
    return result

# === TRANSPORTER Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/transporters')
async def list_all_transporters_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all transporters."""
    data = await transporters_crud.list_transporters(conn, transporter_id=None)
    return {'message': 'Transporters retrieved.', 'data': data}

@app.get('/rr/transporters/{transporter_id}')
async def get_transporter_by_id_endpoint(
    transporter_id: int = Path(..., description="The ID of the transporter to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific transporter by ID."""
    data_list = await transporters_crud.list_transporters(conn, transporter_id=transporter_id)
    if not data_list:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Transporter not found')
    return {'message': 'Transporter retrieved.', 'data': data_list[0]}


@app.put('/rr/transporters/{transporter_id}')
@app.patch('/rr/transporters/{transporter_id}')
async def update_transporter_endpoint(transporter_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a transporter's profile."""
    await transporters_crud.update_transporter(conn, transporter_id, updates)
    updated_profile_list = await transporters_crud.list_transporters(conn, transporter_id=transporter_id)
    if updated_profile_list: return {'message': 'Transporter updated successfully', 'data': updated_profile_list[0]}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Transporter not found after update.')

@app.delete('/rr/transporters/{transporter_id}', status_code=status.HTTP_200_OK)
async def delete_transporter_endpoint(transporter_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a transporter by ID."""
    success = await transporters_crud.delete_transporter(conn, transporter_id)
    if success: return {'message': f'Transporter {transporter_id} deleted successfully'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Transporter {transporter_id} not found or failed to delete.')

@app.patch('/rr/transporters/{transporter_id}/status')
async def update_transporter_status_endpoint(transporter_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates the active status of a transporter."""
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Request body must contain a boolean "is_active" field')
    is_active = status_update['is_active']
    await transporters_crud.update_transporter_status(conn, transporter_id, is_active)
    return {'message': f'Transporter {transporter_id} status updated to {"active" if is_active else "inactive"}'}


# === STAKEHOLDER Endpoints (FastAPI) ===
@app.post('/rr/create_stakeholders', status_code=status.HTTP_201_CREATED)
async def add_stakeholder_endpoint(stakeholder_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new stakeholder profile."""
    result = await stakeholders_crud.create_stakeholder(conn, stakeholder_data)
    return result

@app.post('/rr/login/stakeholders')
async def login_stakeholder_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Logs in a stakeholder by identifier (name or email) and password."""
    identifier = login_data.get('identifier')
    password = login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier and password required')
    result = await stakeholders_crud.login_stakeholder(conn, identifier, password)
    return result

# === STAKEHOLDER Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/rstakeholders')
async def list_all_stakeholders_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all stakeholders."""
    data = await stakeholders_crud.list_stakeholders(conn)
    return {'message': 'Stakeholders retrieved.', 'data': data}

@app.get('/rr/rstakeholders/{stakeholder_id}')
async def get_stakeholder_by_id_endpoint(
    stakeholder_id: int = Path(..., description="The ID of the stakeholder to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific stakeholder by ID."""
    # get_stakeholder_by_id already returns None if not found
    data = await stakeholders_crud.get_stakeholder_by_id(conn, stakeholder_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Stakeholder not found')
    return {'message': 'Stakeholder retrieved.', 'data': data}


@app.put('/rr/stakeholders/{stakeholder_id}')
@app.patch('/rr/stakeholders/{stakeholder_id}')
async def update_stakeholder_endpoint(stakeholder_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a stakeholder's profile."""
    await stakeholders_crud.update_stakeholder(conn, stakeholder_id, updates)
    updated_stakeholder = await stakeholders_crud.get_stakeholder_by_id(conn, stakeholder_id)
    if updated_stakeholder: return {'message': 'Stakeholder updated successfully', 'data': updated_stakeholder}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Stakeholder not found after update.')

@app.delete('/rr/stakeholders/{stakeholder_id}', status_code=status.HTTP_200_OK)
async def delete_stakeholder_endpoint(stakeholder_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a stakeholder by ID."""
    success = await stakeholders_crud.delete_stakeholder(conn, stakeholder_id)
    if success: return {'message': f'Stakeholder {stakeholder_id} deleted successfully'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Stakeholder {stakeholder_id} not found or failed to delete.')

@app.patch('/rr/stakeholders/{stakeholder_id}/status')
async def update_stakeholder_status_endpoint(stakeholder_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates the active status of a stakeholder."""
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Request body must contain a boolean "is_active" field')
    is_active = status_update['is_active']
    await stakeholders_crud.update_stakeholder_status(conn, stakeholder_id, is_active)
    return {'message': f'Stakeholder {stakeholder_id} status updated to {"active" if is_active else "inactive"}'}


# === PRODUCT TYPE Endpoints (FastAPI - Herbals, Meals, Produce, Gadgets, Spices) ===

# --- Herbals ---
@app.post('/rr/aherbals', status_code=status.HTTP_201_CREATED)
async def add_herbal_endpoint(herbal_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Adds a new herbal product."""
    result = await herbals_crud.create_herbal(conn, herbal_data)
    return result

# === HERBAL Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/rherbals')
async def list_all_herbals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all herbal products."""
    data = await herbals_crud.list_herbals(conn)
    return {'message': 'Herbals retrieved.', 'data': data or []} # list_herbals returns [] if none

@app.get('/rr/rherbals/{herbal_id}')
async def get_herbal_by_id_endpoint(
    herbal_id: int = Path(..., description="The ID of the herbal product to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific herbal product by ID."""
    # get_herbal_by_id returns None if not found
    data = await herbals_crud.get_herbal_by_id(conn, herbal_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Herbal not found')
    return {'message': 'Herbal retrieved.', 'data': data}


@app.put('/rr/herbals/{herbal_id}')
@app.patch('/rr/herbals/{herbal_id}')
async def update_herbal_endpoint(herbal_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates an herbal product."""
    await herbals_crud.update_herbal(conn, herbal_id, updates)
    return {'message': 'Herbal updated successfully'} # Optionally fetch and return updated

@app.delete('/rr/herbals/{herbal_id}', status_code=status.HTTP_200_OK)
async def delete_herbal_endpoint(herbal_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes an herbal product."""
    success = await herbals_crud.delete_herbal(conn, herbal_id)
    if success: return {'message': f'Herbal {herbal_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Herbal {herbal_id} not found or failed to delete.')


# --- Meals ---
# === MEAL Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/meals')
@alru_cache(maxsize=1) # Use async-aware cache 
async def list_all_meals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all meals."""
    # list_meals should return a list (potentially empty)
    data = await meals_crud.list_meals(conn)
    return {'message': 'Meals retrieved.', 'data': data or []}

@app.get('/rr/meals/{meal_id}')
async def get_meal_by_id_endpoint(
    meal_id: str = Path(..., description="The ID (string) of the meal to retrieve"), # Assuming meal_id is text
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific meal by ID."""
    # get_meal_by_id returns None if not found
    data = await meals_crud.get_meal_by_id(conn, meal_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Meal not found')
    return {'message': 'Meal retrieved.', 'data': data}


# POST handled by recommendation endpoints? If direct creation needed:
@app.post('/rr/meals', status_code=status.HTTP_201_CREATED)
async def create_meal_endpoint(meal_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     """Creates a new meal."""
     result = await meals_crud.create_meal(conn, meal_data)
     return result

@app.put('/rr/umeals/{meal_id}')
@app.patch('/rr/umeals/{meal_id}')
async def update_meal_endpoint(meal_id: str, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a meal."""
    await meals_crud.update_meal(conn, meal_id, updates)
    return {'message': 'Meal updated successfully'} # Optionally fetch and return

@app.delete('/rr/dmeals/{meal_id}', status_code=status.HTTP_200_OK)
async def delete_meal_endpoint(meal_id: str, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a meal."""
    success = await meals_crud.delete_meal(conn, meal_id)
    if success: return {'message': f'Meal {meal_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Meal {meal_id} not found or failed to delete.')


# --- Produce ---
# Assuming produce_id is int, adjust if text
# === PRODUCE Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/produce')
async def list_all_produce_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all produce items."""
    data = await produce_crud.list_produce(conn)
    return {'message': 'Produce retrieved.', 'data': data or []}

@app.get('/rr/produce/{produce_id}')
async def get_produce_by_id_endpoint(
    # Adjust type hint (int or str) based on your actual produce_id type
    produce_id: int = Path(..., description="The ID of the produce item to retrieve"), # Assuming int here
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific produce item by ID."""
    # get_produce_by_id returns None if not found
    data = await produce_crud.get_produce_by_id(conn, produce_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Produce not found')
    return {'message': 'Produce retrieved.', 'data': data}

@app.post('/rr/produce', status_code=status.HTTP_201_CREATED)
async def create_produce_endpoint(produce_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     """Creates a new produce item."""
     result = await produce_crud.create_produce(conn, produce_data)
     return result

@app.put('/rr/uproduce/{produce_id}')
@app.patch('/rr/uproduce/{produce_id}')
async def update_produce_endpoint(produce_id: str, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a produce item. Note: Path param type might need adjustment if produce_id is int."""
    await produce_crud.update_produce(conn, produce_id, updates)
    return {'message': 'Produce updated successfully'}

@app.delete('/rr/dproduce/{produce_id}', status_code=status.HTTP_200_OK)
async def delete_produce_endpoint(produce_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a produce item."""
    success = await produce_crud.delete_produce(conn, produce_id)
    if success: return {'message': f'Produce {produce_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Produce {produce_id} not found or failed to delete.')


# --- Gadgets ---
# === GADGET Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/gadgets')
async def list_all_gadgets_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all gadgets."""
    data = await gadgets_crud.list_gadgets(conn)
    return {'message': 'Gadgets retrieved.', 'data': data or []}

@app.get('/rr/gadgets/{gadget_id}')
async def get_gadget_by_id_endpoint(
    gadget_id: int = Path(..., description="The ID of the gadget to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific gadget by ID."""
    # get_gadget_by_id returns None if not found
    data = await gadgets_crud.get_gadget_by_id(conn, gadget_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Gadget not found')
    return {'message': 'Gadget retrieved.', 'data': data}


@app.post('/rr/gadgets', status_code=status.HTTP_201_CREATED)
async def create_gadget_endpoint(gadget_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     """Creates a new gadget."""
     result = await gadgets_crud.create_gadget(conn, gadget_data)
     return result

@app.put('/rr/gadgets/{gadget_id}')
@app.patch('/rr/gadgets/{gadget_id}')
async def update_gadget_endpoint(gadget_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a gadget."""
    await gadgets_crud.update_gadget(conn, gadget_id, updates)
    return {'message': 'Gadget updated successfully'}

@app.delete('/rr/gadgets/{gadget_id}', status_code=status.HTTP_200_OK)
async def delete_gadget_endpoint(gadget_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a gadget."""
    success = await gadgets_crud.delete_gadget(conn, gadget_id)
    if success: return {'message': f'Gadget {gadget_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Gadget {gadget_id} not found or failed to delete.')


# --- Spices ---
# === SPICE Endpoints (FastAPI - Corrected List/Get) ===

@app.get('/rr/spices')
async def list_all_spices_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves a list of all spices."""
    data = await spices_crud.list_spices(conn)
    return {'message': 'Spices retrieved.', 'data': data or []}

@app.get('/rr/spices/{spice_id}')
async def get_spice_by_id_endpoint(
    spice_id: int = Path(..., description="The ID of the spice to retrieve", gt=0),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves a specific spice by ID."""
    # get_spice_by_id returns None if not found
    data = await spices_crud.get_spice_by_id(conn, spice_id)
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Spice not found')
    return {'message': 'Spice retrieved.', 'data': data}


@app.post('/rr/spices', status_code=status.HTTP_201_CREATED)
async def create_spice_endpoint(spice_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     """Creates a new spice."""
     result = await spices_crud.create_spice(conn, spice_data)
     return result

@app.put('/rr/spices/{spice_id}')
@app.patch('/rr/spices/{spice_id}')
async def update_spice_endpoint(spice_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates a spice."""
    await spices_crud.update_spice(conn, spice_id, updates)
    return {'message': 'Spice updated successfully'}

@app.delete('/rr/spices/{spice_id}', status_code=status.HTTP_200_OK)
async def delete_spice_endpoint(spice_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a spice."""
    success = await spices_crud.delete_spice(conn, spice_id)
    if success: return {'message': f'Spice {spice_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Spice {spice_id} not found or failed to delete.')


# ... (previous code from the FastAPI conversion) ...

# --- Order Endpoints (FastAPI) ---
@app.post('/rr/Aorders', status_code=status.HTTP_201_CREATED)
async def create_order_endpoint(order_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new order."""
    logger.debug(f"Received order payload: {order_data}")
    try:
        user_id = order_data.get('user_id')
        order_type = order_data.get('order_type')
        product_id = order_data.get('product_id') # Can be int or string
        delivery_address = order_data.get('delivery_address')
        order_status = order_data.get('order_status', 'pending')
        total_price = order_data.get('total_price', 0.0)
        notes = order_data.get('notes')
        payment_status = order_data.get('payment_status', 'pending')
        payment_mode = order_data.get('payment_mode', 'cash')
        amount_paid = order_data.get('amount_paid', 0.0)
        transaction_id = order_data.get('transaction_id')
        quantity = order_data.get('quantity', 1)
        transporter_id = order_data.get('transporter_id')
        items = order_data.get('items') # Keep items

        # --- Continuing from the user's prompt ---
        # Extract IDs from items if present, allowing top-level override
        chef_id = order_data.get('chef_id') # Get default/override from top level
        producer_id = order_data.get('producer_id')

        if isinstance(items, list) and len(items) > 0:
             first_item = items[0]
             # Override IDs/product/quantity if specified in the first item
             chef_id = first_item.get('chef_id', chef_id)
             producer_id = first_item.get('producer_id', producer_id)
             # Also allow product_id and quantity to be overridden by item
             product_id = first_item.get('product_id', product_id)
             quantity = first_item.get('quantity', quantity)
        # --- End of continuation ---

        # Validation: Exactly one of chef_id or producer_id must be set (unless it's a 'gig' maybe?)
        # Adjust this logic based on your specific requirements for different order types
        is_gig = str(order_type).lower().strip() == 'gig'
        if not is_gig: # Apply chef/producer validation only for non-gig orders
            if (chef_id is None and producer_id is None):
                 raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Either chef_id or producer_id must be set for this order type.')
            if (chef_id is not None and producer_id is not None):
                 raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot set both chef_id and producer_id for an order.')

        # Call the async create_order function
        # create_order now raises HTTPException on failure/validation error
        result = await orders_crud.create_order(
            conn=conn,
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
            items=items  # Pass items list
        )

        return result # Return the dict from create_order

    except HTTPException: # Re-raise known validation/DB errors
        raise
    except KeyError as ke:
         raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Missing required field in order data: {ke}")
    except Exception as e:
        logger.error(f"Unexpected error creating order: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal server error during order creation.')


@app.get('/rr/orders')
async def get_orders_endpoint(
    # Use Query for optional query parameters
    order_id: Optional[int] = Query(None),
    chef_id: Optional[int] = Query(None),
    producer_id: Optional[int] = Query(None),
    user_id: Optional[int] = Query(None),
    transporter_id: Optional[int] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Retrieves orders, optionally filtered by various IDs."""
    # read_orders raises HTTPException on ID format errors or DB issues
    data = await orders_crud.read_orders(
        conn=conn,
        order_id=order_id,
        chef_id=chef_id,
        producer_id=producer_id,
        user_id=user_id,
        transporter_id=transporter_id
    )
    return {'message': 'Orders retrieved.', 'data': data}


@app.patch('/rr/orders/{order_id}/status')
async def update_order_status_endpoint(
    order_id: int,
    status_update: dict = Body(...), # Expect {'order_status': 'new_status'}
    conn: asyncpg.Connection = Depends(get_db)
):
    """Updates the status of a specific order."""
    if 'order_status' not in status_update:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Request body must contain "order_status" field')
    new_status = status_update['order_status']

    # update_order_status raises HTTPException on failure (invalid status, DB error)
    success = await orders_crud.update_order_status(conn, order_id, new_status)

    if success:
        return {'message': f'Order {order_id} status updated to {new_status}'}
    else:
        # If update_order_status returns False, it means the order wasn't found
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Order {order_id} not found.')


@app.delete('/rr/orders/{order_id}', status_code=status.HTTP_200_OK)
async def delete_order_endpoint(order_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes an order by ID."""
    success = await orders_crud.delete_order(conn, order_id)
    if success:
        return {'message': f'Order {order_id} deleted successfully'}
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Order {order_id} not found or failed to delete.')


# --- METRICS CRUD (FastAPI) ---
@app.post('/rr/metrics', status_code=status.HTTP_201_CREATED)
async def create_metric_endpoint(metric_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new user metric record."""
    result = await auth_users.create_metric(conn, metric_data)
    return {'message': 'Metric created successfully', 'data': result}

@app.get('/rr/metrics')
async def get_metrics_endpoint(user_id: Optional[int] = Query(None), conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves metrics, optionally filtered by user_id."""
    data = await auth_users.list_metrics(conn, user_id=user_id)
    return {'message': 'Metrics retrieved.', 'data': data}

@app.put('/rr/metrics/{metric_id}')
@app.patch('/rr/metrics/{metric_id}')
async def update_metric_endpoint(metric_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates an existing user metric record."""
    await auth_users.update_metric(conn, metric_id, updates)
    return {'message': 'Metric updated successfully'}

@app.delete('/rr/metrics/{metric_id}', status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def delete_metric_endpoint(metric_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a user metric record (Not Implemented)."""
    # If you implement deletion, change the status code and logic
    # success = await auth_users.delete_metric(conn, metric_id) # Assuming this method exists
    # if success: return {'message': f'Metric {metric_id} deleted'}
    # else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Metric {metric_id} not found.')
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail='Metric deletion not implemented')


# --- PREFERENCES CRUD (FastAPI) ---
@app.post('/rr/preferences', status_code=status.HTTP_201_CREATED)
async def create_preference_endpoint(preference_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Creates a new user preference record."""
    result = await auth_users.create_preference(conn, preference_data)
    return {'message': 'Preference created successfully', 'data': result}

@app.get('/rr/preferences')
async def get_preferences_endpoint(user_id: Optional[int] = Query(None), conn: asyncpg.Connection = Depends(get_db)):
    """Retrieves preferences, optionally filtered by user_id."""
    data = await auth_users.list_preferences(conn, user_id=user_id)
    return {'message': 'Preferences retrieved.', 'data': data}

@app.put('/rr/preferences/{preference_id}')
@app.patch('/rr/preferences/{preference_id}')
async def update_preference_endpoint(preference_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Updates an existing user preference record."""
    await auth_users.update_preference(conn, preference_id, updates)
    return {'message': 'Preference updated successfully'}

@app.delete('/rr/preferences/{preference_id}', status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def delete_preference_endpoint(preference_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Deletes a user preference record (Not Implemented)."""
    # Implement if needed, similar to delete_metric_endpoint
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail='Preference deletion not implemented')


# --- Payment Endpoints (FastAPI - calling synchronous logic) ---
# Note: These endpoints are async, but the underlying payment functions
# (using requests, paypalrestsdk, stripe sdk) are synchronous and will block.
# For full async, these libraries need to be replaced (e.g., httpx).

@app.post('/rr/pay', status_code=status.HTTP_201_CREATED)
async def create_payment_route(payment_data: dict = Body(...)):
    """Creates a PayPal payment."""
    amount = payment_data.get('amount')
    description = payment_data.get('description', "Payment for ZINZI health service")
    if amount is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Amount is required")
    try:
        # Synchronous call
        response = paypalrestsdk.create_payment_paypal(amount, description)
        if not response.get("success"):
             # Raise HTTPException based on the error from the sync function
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=response.get("error", "PayPal payment creation failed"))
        return response
    except ValueError as ve:
         raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
    except Exception as e:
        logger.error(f"Unexpected error creating PayPal payment: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during payment creation.")


@app.get('/rr/execute')
async def execute_payment_route(paymentId: str = Query(...), PayerID: str = Query(...)):
    """Executes a PayPal payment after user approval."""
    try:
        # Synchronous call
        response = paypalrestsdk.execute_payment_paypal(paymentId, PayerID)
        if response.get("status") != "success":
            # Determine appropriate status code based on failure reason
            status_code = status.HTTP_400_BAD_REQUEST # Generic failure
            if "Payment not found" in response.get("error", ""):
                status_code = status.HTTP_404_NOT_FOUND
            raise HTTPException(status_code=status_code, detail=response.get("error", "PayPal payment execution failed"))
        return response
    except Exception as e:
        logger.error(f"Unexpected error executing PayPal payment (ID: {paymentId}): {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during payment execution.")

@app.get('/rr/cancel')
async def handle_payment_cancellation_route():
    """Handles PayPal payment cancellation."""
    try:
        # Synchronous call
        response = paypalrestsdk.handle_payment_cancellation_paypal()
        return response # Typically returns {"status": "cancelled", ...}
    except Exception as e:
        logger.error(f"Unexpected error handling PayPal cancellation: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during cancellation handling.")

@app.post('/rr/create_stripe_payment', status_code=status.HTTP_201_CREATED)
async def create_stripe_payment_route(payment_data: dict = Body(...)):
    """Creates a Stripe Payment Intent."""
    amount = payment_data.get('amount')
    if amount is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Amount is required")
    try:
        # Synchronous call
        response = create_stripe_payment(amount)
        if response.get("status") != "success":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=response.get("error", "Stripe payment creation failed"))
        return response
    except ValueError as ve:
         raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
    except Exception as e:
        logger.error(f"Error creating Stripe payment: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during payment creation.")

@app.post('/rr/confirm_stripe_payment')
async def confirm_stripe_payment_route(confirm_data: dict = Body(...)):
    """Checks the status of a Stripe Payment Intent (confirmation usually client-side)."""
    payment_intent_id = confirm_data.get('paymentIntentId')
    payment_method_id = confirm_data.get('paymentMethodId') # Optional
    if not payment_intent_id: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="paymentIntentId is required")
    try:
        # Synchronous call
        response = execute_stripe_payment(payment_intent_id, payment_method_id)
        # Return the status directly, client interprets it
        return response
    except Exception as e:
        logger.error(f"Error confirming/checking Stripe payment (Intent ID: {payment_intent_id}): {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during payment confirmation.")

@app.post('/rr/cancel_stripe_payment')
async def cancel_stripe_payment_route():
    """Handles Stripe payment cancellation (typically implicit)."""
    try:
        # Synchronous call
        response = handle_stripe_payment_cancellation()
        return response
    except Exception as e:
        logger.error(f"Unexpected error handling Stripe cancellation: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error during cancellation handling.")

@app.post('/rr/request_momo_payment')
async def request_momo_payment_route(momo_data: dict = Body(...)):
    """Requests a MoMo payment from a user."""
    try:
        amount = momo_data['amount'] # Required
        payer_number = momo_data['payer_number'] # Required
        currency = momo_data.get('currency', 'EUR')
        external_id = momo_data.get('external_id', str(uuid.uuid4()))
        payer_message = momo_data.get('payer_message', 'Payment')
        payee_note = momo_data.get('payee_note', 'Payment Request')

        amount_float = float(amount) # Validate inside try

        # Synchronous call
        result = request_momo_payment(amount_float, currency, external_id, payer_number, payer_message, payee_note)

        if result.get("status") == "pending":
            return JSONResponse(content=result, status_code=status.HTTP_202_ACCEPTED)
        else:
            # Failure within the sync function
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=result.get("error", "MoMo payment request failed"))

    except (KeyError, ValueError) as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid input for MoMo payment request: {ve}")
    except Exception as e:
        logger.error(f"Error requesting MoMo payment: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error requesting MoMo payment.")

@app.get('/rr/check_momo_payment_status')
async def check_momo_payment_status_route(transaction_ref: str = Query(...)):
    """Checks the status of a previously initiated MoMo payment."""
    try:
        # Synchronous call
        result = check_momo_payment_status(transaction_ref)

        if result.get("status") == "success":
            return result # Contains payment_status dict
        elif result.get("status") == "not_found":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=result.get("error", "Transaction reference not found."))
        else: # failure
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=result.get("error", "Failed to check MoMo status."))

    except Exception as e:
        logger.error(f"Error checking MoMo status (Ref: {transaction_ref}): {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal server error checking MoMo status.")

# Allow POST/PUT for callbacks as per original
@app.post('/rr/momo_callback')
@app.put('/rr/momo_callback')
async def momo_callback(request: Request): # Use Request to get body directly
    """Handles asynchronous notifications from MoMo."""
    try:
        notification_data = await request.json() # Await reading the body
        logger.info(f"MoMo Callback Received: {notification_data}")

        if not notification_data or not isinstance(notification_data, dict):
            logger.error("Invalid MoMo callback format received.")
            # Return simple 400, avoid detailed error response
            return JSONResponse(content={"error": "Invalid callback format"}, status_code=status.HTTP_400_BAD_REQUEST)

        # TODO: Process the notification_data securely and idempotently
        # (e.g., update order status in DB using transaction_ref)

        # Acknowledge receipt successfully
        return {"message": "Callback received and acknowledged"}

    except json.JSONDecodeError:
         logger.error("Failed to decode MoMo callback JSON.")
         return JSONResponse(content={"error": "Invalid JSON format"}, status_code=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        logger.error(f"Error processing MoMo callback: {e}", exc_info=True)
        # Return generic 500 for internal processing errors
        return JSONResponse(content={"error": "Failed to process callback"}, status_code=status.HTTP_500_INTERNAL_SERVER_ERROR)

# --- Recommendation Endpoints (FastAPI) ---
@app.get("/rr/recommendations/v1/{user_id}")
async def get_recommendations_v1(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Get meal recommendations using basic filtering (V1)."""
    recommender = MealRecommendation1(user_id)
    # recommend_meals raises HTTPException on error/not found
    result = await recommender.recommend_meals(conn)
    return result

@app.get("/rr/recommendations/v2/{user_id}")
async def get_recommendations_v2(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Get meal recommendations using calorie budgeting and scoring (V2)."""
    #return "Not implemented yet"
    # Need to instantiate V2 recommender
    #recommender = MealRecommendation2(user_id)
    # Implement recommend_meals in V2 if not already done, make it async
    # result = await recommender.recommend_meals(conn)
    # return result
    # Placeholder if V2 recommend_meals is not async/implemented
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Recommendation V2 not fully implemented asynchronously.")


@app.get("/rr/allmeals")
async def get_all_meals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """Fetch all meals with processed details."""
    # Instantiate here or use Depends if it becomes complex
    fetcher = GetAllMeals()
    # fetch_all_meals raises HTTPException on failure
    result = await fetcher.fetch_all_meals(conn)
    return result

# --- Configuration Setup (Run before App Definition or in Lifespan) ---
# Configure PayPal
paypal_client_id = os.getenv('PAYPAL_CLIENT_ID')
paypal_client_secret = os.getenv('PAYPAL_CLIENT_SECRET')
paypal_mode = os.getenv('PAYPAL_MODE', 'sandbox')
if paypal_client_id and paypal_client_secret:
    paypalrestsdk.configure_paypal(paypal_mode, paypal_client_id, paypal_client_secret)
else:
    logger.warning("PayPal credentials not found. PayPal payments disabled.")

# Configure Stripe
stripe_secret_key = os.getenv('STRIPE_SECRET_KEY')
if stripe_secret_key:
    stripe.configure_stripe(stripe_secret_key)
else:
    logger.warning("Stripe secret key not found. Stripe payments disabled.")

# Note: MoMo config (API Key, etc.) is read directly from env vars in the functions


# === REMOVED if __name__ == '__main__': block ===
# Run with: uvicorn your_filename:app --reload --host 0.0.0.0 --port 5000