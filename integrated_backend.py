#cspell:disable
# --- AuthenticationAndUsers Class (Updated for asyncpg pool) ---
import os
import json
import random
import base64
import time
import uuid
import string
from datetime import datetime, timedelta, date
from typing import Dict, Any, Optional, List, Tuple, Union, AsyncGenerator # Added Union, Tuple, AsyncGenerator
from dotenv import load_dotenv
from async_lru import alru_cache # Import alru_cache for async caching
import bcrypt
import asyncpg # Added asynchronous driver
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google.auth.exceptions import RefreshError
from email.mime.text import MIMEText
from firebase_admin import messaging
import logging
import paypalrestsdk # Keep sync for now
import stripe # Keep sync for now
import requests # Keep sync for now

# --- FastAPI Imports ---
from services.fcm_service import FirebaseMessagingService
from fastapi import FastAPI, Request, Depends, HTTPException, status, Body, Query, Path
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware import Middleware
from fastapi.staticfiles import StaticFiles # Import StaticFiles
from contextlib import asynccontextmanager # For lifespan manager
from fastapi.responses import ORJSONResponse, FileResponse # Use ORJSON, Import FileResponse
import json
import asyncio
from typing import Dict, Any, Optional, List

# Import notification service
from services.notification_service import NotificationService

# Import meal recommendation algorithm
from meal_algorithm4 import MealRecommendation4

# --- Configuration Loading ---
load_dotenv()

# --- Logging Configuration ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# --- Utility Function ---
try:
    from utils import lowercase_keys
except ImportError:
    def lowercase_keys(d):
        if isinstance(d, dict):
            return {k.lower(): v for k, v in d.items()}
        return d
    logger.warning("utils.lowercase_keys not found, using basic fallback.")

# --- Database Connection Pool (asyncpg) ---
# Global variable to hold the pool, managed by lifespan
db_pool: Optional[asyncpg.Pool] = None

# Function to preload meal data to avoid slow first request
async def preload_meal_data():
    """Preload meal data into cache to improve first request performance."""
    try:
        logger.info("Preloading meal data into cache...")
        # Import here to avoid circular imports
        from meal_algorithm4 import MealRecommendation4
        
        # Create a default instance to populate the shared cache
        default_recommender = MealRecommendation4(1)  # Use a default user ID
        
        # Trigger data loading into the shared cache
        meals = default_recommender.fetch_all_meals()
        logger.info(f"Successfully preloaded {len(meals)} meals into cache")
        return True
    except Exception as e:
        logger.error(f"Error preloading meal data: {e}")
        return False

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the database connection pool lifecycle."""
    global db_pool  # Declare as global within the function
    logger.info("Application startup: Initializing database pool...")
    
    # Get database configuration
    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME", "zinzi")
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    
    # Check for missing required variables
    missing_vars = []
    if not db_host: missing_vars.append("DB_HOST")
    if not db_name: missing_vars.append("DB_NAME")
    if not db_user: missing_vars.append("DB_USER")
    if not db_password: missing_vars.append("DB_PASSWORD")
    
    if missing_vars:
        error_msg = f"Database pool creation failed: Missing required environment variables: {', '.join(missing_vars)}."
        logger.critical(error_msg)
        db_pool = None # Ensure pool is None
        # Allow app to start but endpoints using DB will fail
        yield
        logger.info("Application shutdown: No database pool to close.")
        return # Exit early

    # Use ssl=require for Render/cloud databases, adjust if needed
    db_url = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}?ssl=require"
    logger.info(f"Database DSN constructed: postgresql://{db_user}:*****@{db_host}:{db_port}/{db_name}?ssl=require")

    try:
        # Initialize database pool
        # Already declared as global at the start of the function
        db_pool = await asyncpg.create_pool(
            dsn=db_url,
            min_size=int(os.getenv("DB_POOL_MIN_SIZE", "2")), # Configurable min size
            max_size=int(os.getenv("DB_POOL_MAX_SIZE", "10")),# Configurable max size
            timeout=30, # Connection acquisition timeout
            command_timeout=60, # Default timeout for commands
            statement_cache_size=0 # Uncomment ONLY if needed for pgbouncer transaction/statement mode
        )
        logger.info(f"Database connection pool created successfully (Min: {db_pool.get_min_size()}, Max: {db_pool.get_max_size()}).")        
        
        # Preload meal data to avoid slow first request
        await preload_meal_data()
        
        # Initialize services on-demand
        app.state.notification_service = None
        app.state.fcm_service = None
        
        yield # Application runs here
    except (asyncpg.exceptions.PostgresError, OSError, Exception) as e:
        logger.critical(f"FATAL: Failed to create database pool: {e}", exc_info=True)
        db_pool = None # Ensure pool is None on failure
        yield # Allow app startup even if pool fails, but DB access will fail
    finally:
        # Cleanup during shutdown
        if db_pool is not None:
            try:
                await db_pool.close()
                logger.info("Database pool closed")
            except Exception as e:
                logger.error(f"Error closing database pool: {e}")
            finally:
                db_pool = None
        
        # Clear app state
        app.state.notification_service = None
        app.state.fcm_service = None
        logger.info("Application shutdown: Database connection pool closed.")

# Use the lifespan manager
app = FastAPI(
    title="ZINZI",
    middleware=[
        Middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    ],
    description="Robust ZINZI backend.",
    lifespan=lifespan,
    default_response_class=ORJSONResponse
)

# Service accessor functions
def get_notification_service() -> NotificationService:
    """Get or initialize the notification service."""
    if not app.state.notification_service:
        app.state.notification_service = NotificationService(db_pool)
    return app.state.notification_service

def get_fcm_service() -> FirebaseMessagingService:
    """Get or initialize the FCM service."""
    if not app.state.fcm_service:
        app.state.fcm_service = FirebaseMessagingService(db_pool)
    return app.state.fcm_service

@app.get("/health")
async def health_check():
    return {"status": "ok"}

# --- Request Path Logger Middleware ---
@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Incoming request: {request.method} {request.url.path}")
    response = await call_next(request)
    return response

# Mount static files directory
app.mount("/static", StaticFiles(directory="static"), name="static")

# --- CORS Middleware ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Adjust in production (e.g., ["https://yourfrontend.com"])
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Database Dependency ---
async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """FastAPI dependency to get a database connection from the pool."""
    if db_pool is None:
        logger.error("Attempted to acquire DB connection, but pool is not available.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database service is currently unavailable. Please try again later."
        )
    # Acquire connection from pool; automatically released when block exits
    async with db_pool.acquire() as connection:
        # Set the session timezone to Africa/Kampala
        await connection.execute("SET TIMEZONE = 'Africa/Kampala'");
        # Optional: Set transaction isolation level or other session settings here if needed
        # await connection.execute("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")
        yield connection

# --- Helper Functions (Mostly Unchanged) ---
def hash_password(password): return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
def generate_random_code(length=6, use_digits=True, use_uppercase=True):
    # ... (implementation unchanged)
    chars = ""
    if use_digits: chars += string.digits
    if use_uppercase: chars += string.ascii_uppercase
    if not chars: raise ValueError("Character set required.")
    return ''.join(random.choices(chars, k=length))

def check_required_fields(data, required_fields):
    # ... (implementation unchanged, still raises HTTPException)
    data_keys_lower = {k.lower() for k in data.keys()}
    missing, empty = [], []
    for field in required_fields:
        field_lower = field.lower()
        if field_lower not in data_keys_lower: missing.append(field)
        else:
            original_key = next((k for k in data if k.lower() == field_lower), None)
            value = data.get(original_key)
            if value is None or (isinstance(value, str) and not value.strip()): empty.append(field)
    error_messages = []
    if missing: error_messages.append(f"Missing fields: {', '.join(missing)}")
    if empty: error_messages.append(f"Fields cannot be empty: {', '.join(empty)}")
    if error_messages: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=". ".join(error_messages))

def serialize_list(data_list):
    # ... (implementation unchanged)
    return ','.join(map(str, data_list)) if isinstance(data_list, list) else ''

def deserialize_list(data_string):
    # ... (implementation unchanged)
    if not data_string or not isinstance(data_string, str): return []
    return [item.strip() for item in data_string.split(',') if item.strip()]

def deserialize_list_from_json_string(json_string):
    # ... (implementation unchanged)
    if not json_string or not isinstance(json_string, str): return []
    try:
        data_list = json.loads(json_string)
        return data_list if isinstance(data_list, list) else []
    except json.JSONDecodeError:
        logger.warning(f"Could not decode JSON: {json_string}. Fallback: comma split.")
        return [item.strip() for item in json_string.split(',') if item.strip()]


# --- Consolidated BaseRepository (Takes connection as argument) ---
class BaseRepository:
    # REMOVED DB Connection initialization her
    # Methods now take 'conn' as the first argument

    async def _execute_query(self, conn: asyncpg.Connection, sql: str, params: Optional[tuple] = None, fetch_one: bool = False, fetch_val=False, fetch_all: bool = False, returning_id_column: Optional[str] = None) -> Any:
        """Executes SQL query asynchronously using the provided asyncpg connection."""
        results = None
        returned_id = None
        params = params or ()
        log_params = tuple(str(p) if isinstance(p, bytes) else p for p in params) # Avoid logging raw bytes
        logger.debug(f"Executing SQL: {sql} | Params: {log_params}")

        try:
            # Use fetchval for RETURNING ID for simplicity and efficiency
            if returning_id_column:
                # fetchval returns the first column of the first row, or None
                returned_id = await conn.fetchval(sql, *params)
                if returned_id is not None:
                     logger.debug(f"Returning {returning_id_column}: {returned_id}")
                else:
                     logger.warning(f"Query with RETURNING {returning_id_column} did not return a value. SQL: {sql}")
            elif fetch_one:
                row = await conn.fetchrow(sql, *params)
                results = dict(row) if row else None # Convert Record to dict if found
                logger.debug(f"Fetched one row: {'Found' if results else 'Not Found'}")
            elif fetch_all:
                rows = await conn.fetch(sql, *params)
                results = [dict(row) for row in rows] # Convert list of Records to list of dicts
                logger.debug(f"Fetched {len(results)} rows.")
            else:  # Just execute (INSERT, UPDATE, DELETE without RETURNING needed by caller)
                status_str = await conn.execute(sql, *params)
                logger.debug(f"Executed statement. Status: {status_str}")
                results = status_str # Return status for execute

            # Return based on what was requested
            if returning_id_column:
                return returned_id
            else:
                return results

        except asyncpg.PostgresError as e:
            logger.error(f"Database Error: {e} | SQL: {sql} | Params: {log_params}", exc_info=True)
            # Map specific errors if needed (e.g., unique constraint -> 409 Conflict)
            if isinstance(e, asyncpg.exceptions.UniqueViolationError):
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Database constraint violation: {e.detail or e.message}") from e
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Database operation failed: {e}") from e
        except Exception as e:
            logger.error(f"Unexpected Error during DB operation: {e} | SQL: {sql} | Params: {log_params}", exc_info=True)



# --- AuthenticationAndUsers Class (Updated for asyncpg pool) ---
class AuthenticationAndUsers(BaseRepository):
    async def get_combined_metrics(self, conn: asyncpg.Connection, user_id: int, limit: int = 10):
        """
        Get combined metrics data for a user, joining multiple tables.
        
        Args:
            conn: Database connection
            user_id: User ID to fetch metrics for
            limit: Maximum number of history records to return
            
        Returns:
            Dict containing combined metrics data
        """
        try:
            # Validate input
            if not isinstance(user_id, int) or user_id <= 0:
                raise ValueError("user_id must be a positive integer")
            if not isinstance(limit, int) or limit <= 0:
                raise ValueError("limit must be a positive integer")

            # Get latest user preferences
            prefs_query = """
                SELECT goals FROM user_preferences 
                WHERE user_id = $1
                LIMIT 1
            """
            prefs = await conn.fetchrow(prefs_query, user_id)
            
            # Get latest user metrics
            metrics_query = """
                SELECT weight, ideal_weight, daily_calories, activity_level, bmi, bmi_category 
                FROM user_metrics 
                WHERE user_id = $1
                ORDER BY recorded_at DESC
                LIMIT 1
            """
            metrics = await conn.fetchrow(metrics_query, user_id)
            
            # Get calorie history
            calories_query = """
                SELECT calories::jsonb, logged_at 
                FROM calories_history 
                WHERE user_id = $1
                ORDER BY logged_at DESC
                LIMIT $2
            """
            calories_history = await conn.fetch(calories_query, user_id, limit)
            
            # Get weight history
            weight_query = """
                SELECT weight, logged_at 
                FROM metrics_history 
                WHERE user_id = $1
                ORDER BY logged_at DESC
                LIMIT $2
            """
            weight_history = await conn.fetch(weight_query, user_id, limit)

            # Process preferences safely
            preferences = {}
            if prefs and prefs.get("goals"):
                goals_value = prefs["goals"]
                # Handle different types of goals data
                if isinstance(goals_value, dict):
                    preferences = goals_value
                elif isinstance(goals_value, str):
                    try:
                        # Try to parse JSON if it's a string
                        import json
                        preferences = json.loads(goals_value)
                        if not isinstance(preferences, dict):
                            preferences = {"goal": preferences}
                    except (json.JSONDecodeError, TypeError):
                        # If parsing fails, store as simple goal value
                        preferences = {"goal": goals_value}
                else:
                    # For other types, store as goal value
                    preferences = {"goal": str(goals_value)}

            # Process calories history safely
            processed_calories_history = []
            for record in calories_history or []:
                try:
                    calories_data = record["calories"]
                    if calories_data is None:
                        calories_dict = {}
                    elif isinstance(calories_data, dict):
                        calories_dict = calories_data
                    elif isinstance(calories_data, str):
                        try:
                            import json
                            calories_dict = json.loads(calories_data)
                            if not isinstance(calories_dict, dict):
                                calories_dict = {"value": calories_dict}
                        except (json.JSONDecodeError, TypeError):
                            calories_dict = {"value": calories_data}
                    else:
                        calories_dict = {"value": calories_data}
                    
                    processed_calories_history.append({
                        "calories": calories_dict,
                        "logged_at": record["logged_at"].isoformat() if record["logged_at"] else None
                    })
                except Exception as e:
                    logger.warning(f"Error processing calories record for user {user_id}: {str(e)}")
                    processed_calories_history.append({
                        "calories": {},
                        "logged_at": record["logged_at"].isoformat() if record.get("logged_at") else None
                    })

            # Process and combine results
            result = {
                "user_id": user_id,
                "preferences": preferences,
                "metrics": {
                    "weight": metrics.get("weight") if metrics else None,
                    "ideal_weight": metrics.get("ideal_weight") if metrics else None,
                    "daily_calories": metrics.get("daily_calories") if metrics else None,
                    "activity_level": metrics.get("activity_level") if metrics else None,
                    "bmi": metrics.get("bmi") if metrics else None,
                    "bmi_category": metrics.get("bmi_category") if metrics else None
                },
                "calories_history": processed_calories_history,
                "weight_history": [
                    {
                        "weight": record["weight"] if record["weight"] else None,
                        "logged_at": record["logged_at"].isoformat() if record["logged_at"] else None
                    }
                    for record in weight_history or []
                ],
                "last_updated": datetime.now().isoformat()
            }

            # Clean up None values from metrics
            result["metrics"] = {k: v for k, v in result["metrics"].items() if v is not None}
            
            return result
        except ValueError as ve:
            logger.error(f"Validation error for user {user_id}: {str(ve)}")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
        except Exception as e:
            logger.error(f"Error fetching combined metrics for user {user_id}: {str(e)}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while fetching metrics")
    # Existing methods...
    # Methods now accept 'conn' from Depends(get_db)
    async def signup_user(self, conn: asyncpg.Connection, name: str, email: str, password: str, image: Optional[str] = None) -> Dict[str, Any]:
        # ... (implementation unchanged, but uses the passed 'conn') ...
        hashed_pw = hash_password(password)
        verification_code = generate_random_code()
        user_id = None
        try:
            async with conn.transaction(): # Use transaction
                email_query = "SELECT user_id FROM users WHERE lower(email) = lower($1)"
                existing_email = await conn.fetchval(email_query, email)
                if existing_email: raise ValueError(f"Email '{email}' is already registered.")
                name_query = "SELECT user_id FROM users WHERE lower(name) = lower($1)"
                existing_name = await conn.fetchval(name_query, name)
                if existing_name: raise ValueError(f"Name '{name}' is already taken.")
                if image is not None:
                    insert_query = "INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified, image) VALUES ($1, $2, $3, NOW(), FALSE, $4) RETURNING user_id"
                    user_id = await conn.fetchval(insert_query, name, email, hashed_pw, image)
                else:
                    insert_query = "INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified) VALUES ($1, $2, $3, NOW(), FALSE) RETURNING user_id"
                    user_id = await conn.fetchval(insert_query, name, email, hashed_pw)
                if not user_id: raise asyncpg.PostgresError("User insertion failed to return user_id.")
            # self.send_verification_email_gmail(email, verification_code) # Sync call
            logger.info(f"User '{name}' (ID: {user_id}) registered successfully.")
            return {"user_id": user_id, "success": True}
        except ValueError as e:
            logger.warning(f"Signup validation failed for {email}: {e}")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
        except asyncpg.exceptions.UniqueViolationError as e:
             logger.warning(f"Signup failed due to unique constraint for {email}: {e.detail}")
             # Determine if it was email or name based on the error detail if possible
             detail = "Email or Name already exists."
             if 'email' in str(e.detail).lower() or 'users_email_key' in str(e.constraint_name): detail = f"Email '{email}' is already registered."
             elif 'name' in str(e.detail).lower() or 'users_name_key' in str(e.constraint_name): detail = f"Name '{name}' is already taken."
             raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail) from e
        except asyncpg.PostgresError as e:
            logger.error(f"Database error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An internal error occurred during signup.") from e
        except Exception as e:
            logger.error(f"Unexpected error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected server error occurred.") from e

    async def verify_user_email(self, conn: asyncpg.Connection, user_id: int, verification_code: str) -> None:
        # ... (implementation unchanged, uses passed 'conn') ...
        check_query = "SELECT verification_code FROM email_verifications WHERE user_id = $1 AND verification_code = $2 AND expires_at > NOW()"
        update_query = "UPDATE users SET is_email_verified = TRUE WHERE user_id = $1"
        delete_query = "DELETE FROM email_verifications WHERE user_id = $1 AND verification_code = $2"
        try:
            async with conn.transaction():
                 code_exists = await conn.fetchval(check_query, user_id, verification_code)
                 if not code_exists:
                     logger.warning(f"Email verification failed for user {user_id}: Invalid or expired code.")
                     raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid or expired verification code')
                 await conn.execute(update_query, user_id)
                 await conn.execute(delete_query, user_id, verification_code)
            logger.info(f"Email successfully verified for user ID {user_id}.")
        except HTTPException: raise
        except (asyncpg.PostgresError) as e:
            logger.error(f"Database error during email verification for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An error occurred during email verification.') from e
        except Exception as e:
            logger.error(f"Unexpected error during email verification for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An unexpected server error occurred during verification.') from e

    # send_verification_email_gmail remains synchronous
    def send_verification_email_gmail(self, to_email: str, verification_code: str):
        # ... (implementation unchanged) ...
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None; token_file = 'token.json'; client_secret_file = 'client_secret.json'
        if not os.path.exists(client_secret_file): logger.error(f"Gmail client secret file not found: {client_secret_file}"); raise FileNotFoundError(f"Required file '{client_secret_file}' not found.")
        if os.path.exists(token_file):
             try: creds = Credentials.from_authorized_user_file(token_file, SCOPES)
             except Exception as e: logger.warning(f"Error loading credentials from {token_file}: {e}. Will attempt re-auth."); creds = None
        needs_reauth = False
        if creds:
            try:
                if creds.expiry and creds.expiry < (datetime.utcnow().replace(tzinfo=None) + timedelta(minutes=5)):
                    if creds.refresh_token: logger.info("Refreshing Gmail API access token..."); creds.refresh(Request()); logger.info("Gmail token refreshed.")
                    else: logger.warning("Gmail token expired, no refresh token."); needs_reauth = True; creds = None
                elif not creds.valid: logger.warning("Gmail token invalid."); needs_reauth = True; creds = None
            except RefreshError as e: logger.error(f"Error refreshing Gmail token: {e}"); needs_reauth = True; creds = None
            except Exception as e: logger.error(f"Error checking Gmail token: {e}"); creds = None; needs_reauth = True
        if not creds or needs_reauth:
            try:
                logger.info("Starting Gmail auth flow..."); flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES); creds = flow.run_local_server(port=8080); logger.info("Gmail auth successful.")
                with open(token_file, 'w') as token: token.write(creds.to_json()); logger.debug(f"Gmail credentials saved to {token_file}")
            except Exception as e: logger.error(f"Gmail authentication flow failed: {e}"); raise ConnectionError("Failed Google auth flow.") from e
        try:
            service = build('gmail', 'v1', credentials=creds)
            subject = "Your ZINZI Verification Code"; body = f"Your verification code is: {verification_code}\nPlease enter this code in the ZINZI app."; message = MIMEText(body); message['to'] = to_email; message['from'] = 'me'; message['subject'] = subject
            raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode(); send_message_body = {'raw': raw_message}
            sent_message = service.users().messages().send(userId="me", body=send_message_body).execute()
            logger.info(f"Verification email sent to {to_email}. Message ID: {sent_message.get('id')}")
        except Exception as e: logger.error(f"Failed to send Gmail verification email to {to_email}: {e}", exc_info=True); raise ConnectionError(f"Failed Gmail send: {e}") from e

    async def create_user(self, conn: asyncpg.Connection, user_data: Dict[str, Any]) -> Dict[str, Any]:
        # ... (implementation unchanged, calls signup_user with conn) ...
        name = user_data.get('Name'); email = user_data.get('Email'); password = user_data.get('Password'); image = user_data.get('Image')
        if not name or not email or not password:
             missing = [k for k in ['Name', 'Email', 'Password'] if not user_data.get(k)]
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Missing required fields: {', '.join(missing)}")
        return await self.signup_user(conn, name, email, password, image) # Pass conn

    async def list_users(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> Optional[Union[List[Dict[str, Any]], Dict[str, Any]]]:
        # ... (implementation uses _execute_query with conn) ...
        sql = "SELECT user_id, name, email, registration_date, location, phone_number, is_email_verified, user_type, last_login, image FROM users"
        params = []
        if user_id is not None:
            sql += " WHERE user_id = $1"
            params.append(user_id)
        sql += " ORDER BY user_id" # Added default order

        users_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True) # Use _execute_query

        if users_list:
            processed_users = []
            for user_row in users_list:
                processed_user = dict(user_row) # Already dict from _execute_query if fetch_all
                for key, value in processed_user.items():
                    if isinstance(value, (datetime, date)): processed_user[key] = value.isoformat()
                processed_users.append(processed_user)
            if user_id is not None: return processed_users[0] if processed_users else None
            else: return processed_users
        else:
            if user_id is not None: logger.warning(f"No user found with ID: {user_id}"); return None
            else: return []

    async def login_user(self, conn: asyncpg.Connection, identifier: str, password: str) -> Dict[str, Any]:
        # ... (implementation uses _execute_query with conn) ...
        sql = "SELECT user_id, hashed_password, user_type, is_email_verified FROM users WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        try:
            result = await self._execute_query(conn, sql, params, fetch_one=True)
            if not result:
                logger.warning(f"Login failed: Identifier '{identifier}' not found.")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name or account not found.')
            user_id = result['user_id']; stored_hashed_password = result['hashed_password']; user_type = result.get('user_type', 'user'); is_verified = result.get('is_email_verified', False)
            stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
            if not isinstance(stored_hashed_pw_bytes, bytes):
                 logger.error(f"Invalid hashed_password type for user {user_id}. Type: {type(stored_hashed_password)}")
                 raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal server error during login.')
            if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
                update_sql = "UPDATE users SET last_login = NOW() WHERE user_id = $1"
                try: await self._execute_query(conn, update_sql, (user_id,)) # Use _execute_query
                except Exception as update_err: logger.error(f"Failed to update last_login for user {user_id}: {update_err}")
                return {'message': 'Login successful', 'data': {'user_id': user_id, 'user_type': user_type, 'verified': is_verified}}
            else:
                logger.warning(f"Login failed: Invalid password for identifier '{identifier}'.")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        except HTTPException: raise
        except asyncpg.PostgresError as e: logger.error(f"DB error login '{identifier}': {e}"); raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Login unavailable.') from e
        except Exception as e: logger.error(f"Unexpected error login '{identifier}': {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Unexpected login error.') from e

    async def delete_user(self, conn: asyncpg.Connection, user_id: int) -> bool:
        # ... (implementation uses _execute_query with conn) ...
        logger.warning(f"Attempting to delete user ID: {user_id}")
        sql = "DELETE FROM users WHERE user_id = $1 RETURNING user_id"
        try:
            deleted_id = await self._execute_query(conn, sql, (user_id,), returning_id_column='user_id') # Use _execute_query
            if deleted_id == user_id: logger.info(f"Successfully deleted user ID: {user_id}"); return True
            else: logger.warning(f"Attempted delete non-existent user ID: {user_id}"); return False # Not found
        except HTTPException: raise # Let DB errors propagate
        except Exception as e: logger.error(f"Unexpected error deleting user {user_id}: {e}", exc_info=True); return False

    # --- Metrics Methods (async, use passed conn) ---
    async def create_metric(self, conn: asyncpg.Connection, metric_data: Dict[str, Any]) -> Dict[str, int]:
        # ... (implementation uses _execute_query with conn) ...
        metric_data_lower = lowercase_keys(metric_data)
        check_required_fields(metric_data_lower, ['user_id', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse'])
        sql = "INSERT INTO user_metrics (user_id, age_range, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, recorded_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW()) RETURNING metric_id"
        try: params = (int(metric_data_lower['user_id']), metric_data_lower.get('age_range'), float(metric_data_lower['weight']), float(metric_data_lower['height']), float(metric_data_lower['cholesterol_level']), int(metric_data_lower['sys_bp']), int(metric_data_lower['dia_bp']), int(metric_data_lower['pulse']))
        except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid metric format: {e}") from e
        metric_id = await self._execute_query(conn, sql, params, returning_id_column='metric_id')
        if metric_id: logger.info(f"Created metric ID: {metric_id}"); return {"metric_id": metric_id}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Metric creation failed.")

    async def update_metric(self, conn: asyncpg.Connection, user_id: int, updates: Dict[str, Any]):
        # Update independent fields for latest metric row for this user
        updates_lower = lowercase_keys(updates)
        set_clauses = []
        params = []
        idx = 1
        allowed = ['age_range','weight','height','bmi','ideal_weight','daily_calories','cholesterol_level','sys_bp','dia_bp','pulse','sex','activity_level']
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        # Strictly map and validate update keys
        unknown_keys = [k for k in updates_lower if k not in allowed]
        if unknown_keys:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Unknown or misspelled fields: {', '.join(unknown_keys)}. Allowed fields: {', '.join(allowed)}.")
        # Define expected types for each field
        field_types = {
            'age_range': str,
            'weight': float,
            'height': float,
            'bmi': float,
            'ideal weight': float,
            'daily calories': float,
            'cholesterol_level': float,
            'sys_bp': float,
            'dia_bp': float,
            'pulse': float,
            'sex': str,
            'activity_level': str,
        }
        # Log the update payload and types for debugging
        logger.info(f"update_metric: updates_lower={updates_lower}")
        for k, v in updates_lower.items():
            logger.info(f"Field '{k}': value={v} (type={type(v)})")
        for k in allowed:
            if k in updates_lower:
                set_clauses.append(f"{k}=${idx}")
                v = updates_lower[k]
                # Strict validation for string fields
                if k in ['age_range', 'sex', 'activity_level']:
                    if v is not None and not isinstance(v, str):
                        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Field '{k}' must be a string, got {type(v).__name__}: {v}")
                # Cast to correct type if not None
                if v is not None and k in field_types:
                    try:
                        v = field_types[k](v)
                    except Exception:
                        # Fallback: leave as is if casting fails
                        pass
                params.append(v)
                idx += 1
        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        # Patch all user_metrics rows for this user_id (no ordering, no subquery)
        sql = f"UPDATE user_metrics SET {', '.join(set_clauses)} WHERE user_id = ${idx}"
        params.append(user_id)
        await self._execute_query(conn, sql, tuple(params))
        logger.info(f"Updated metrics for user_id: {user_id}")

        # Fetch any (first) metric row for this user_id to get dependent fields
        metric_row = await conn.fetchrow(
            "SELECT weight, height, age_range, sex, activity_level FROM user_metrics WHERE user_id = $1 LIMIT 1",
            user_id
        )
        if not metric_row:
            logger.warning(f"Metric row not found for dependent update for user_id: {user_id}")
            return
        weight = metric_row['weight']
        height = metric_row['height']
        age_range = metric_row['age_range']
        sex = metric_row['sex']
        activity_level = metric_row['activity_level']

        # Compute dependent values using CalculationLogic
        calc = CalculationLogic()
        bmi = calc.calculate_bmi(weight, height)
        bmr = calc.calculate_bmr(weight, height, age_range, sex)
        ideal_weight = calc.calculate_ideal_weight(height, sex)
        daily_calories = calc.calculate_daily_calories(bmr, activity_level)
        bmi_category = calc.calculate_bmi_category(bmi)

        # Patch all user_metrics rows for this user_id with dependent fields
        dep_sql = """
            UPDATE user_metrics SET 
                bmi = $1,
                bmr = $2,
                ideal_weight = $3,
                daily_calories = $4,
                bmi_category = $5
            WHERE user_id = $6
        """
        # Ensure correct types for asyncpg (floats for numbers, str for category)
        # Cast dependent fields to correct types based on DB schema
        # Numerical: bmi, bmr, ideal_weight, daily_calories; Text: bmi_category
        await conn.execute(
            dep_sql,
            float(bmi) if bmi is not None else None,
            float(bmr) if bmr is not None else None,
            str(ideal_weight) if ideal_weight is not None else None,  # ensure string
            float(daily_calories) if daily_calories is not None else None,
            str(bmi_category) if bmi_category is not None else None,
            user_id
        )
        logger.info(f"Recomputed dependent fields for user_id: {user_id} (all metric rows)")

        # Always insert a new entry in metrics_history whenever weight is updated
        if 'weight' in updates_lower:
            try:
                # Use the new weight value from the update, not the possibly unchanged value from the DB
                weight_f = float(updates_lower['weight'])
                await conn.execute(
                    "INSERT INTO metrics_history (user_id, weight, logged_at) VALUES ($1, $2, NOW())",
                    user_id, weight_f
                )
                logger.info(f"Logged new weight {weight_f} for user {user_id} in metrics_history (logged_at).")
            except Exception as e:
                logger.warning(f"Failed to log weight in metrics_history: {e}")

    async def list_metrics(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        # ... (implementation uses _execute_query with conn) ...
        sql="SELECT * FROM user_metrics"; params=[]
        if user_id is not None: sql+=" WHERE user_id = $1 ORDER BY recorded_at DESC"; params.append(user_id)
        else: sql+=" ORDER BY recorded_at DESC"
        metrics = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if metrics:
             processed = [];
             for item in metrics: p_item = dict(item); [p_item.update({k:v.isoformat()}) for k,v in p_item.items() if isinstance(v, (datetime, date))]; processed.append(p_item)
             return processed
        return []

    # --- Metric History Methods (async, use passed conn) ---
    async def create_metric_history(self, conn: asyncpg.Connection, metric_history_data: Dict[str, Any]) -> Dict[str, int]:
        # ... (implementation uses _execute_query with conn) ...
        data_lower=lowercase_keys(metric_history_data); check_required_fields(data_lower, ['user_id', 'weight'])
        sql="INSERT INTO metrics_history (user_id, weight, logged_at) VALUES ($1, $2, NOW()) RETURNING log_id"
        try: params=(int(data_lower['user_id']), float(data_lower['weight']))
        except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid metric history format: {e}") from e
        log_id = await self._execute_query(conn, sql, params, returning_id_column='log_id')
        if log_id: logger.info(f"Created metric history ID: {log_id}"); return {"log_id": log_id}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Metric history creation failed.")

    async def update_metric_history(self, conn: asyncpg.Connection, log_id: int, updates: Dict[str, Any]):
        # ... (implementation uses _execute_query with conn) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1; allowed=['weight']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
             if k in allowed:
                  try: weight_f = float(v)
                  except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid weight format.")
                  set_clauses.append(f"{k}=${idx}"); params.append(weight_f); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE metrics_history SET {','.join(set_clauses)} WHERE log_id=${idx}"; params.append(log_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated metric history ID: {log_id}")

    async def list_metric_history(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        # ... (implementation uses _execute_query with conn) ...
        sql="SELECT * FROM metrics_history"; params=[]
        if user_id is not None: sql+=" WHERE user_id = $1 ORDER BY logged_at DESC"; params.append(user_id)
        else: sql+=" ORDER BY logged_at DESC"
        history = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if history:
             processed = [];
             for item in history: p_item = dict(item); [p_item.update({k:v.isoformat()}) for k,v in p_item.items() if isinstance(v, (datetime, date))]; processed.append(p_item)
             return processed
        return []

    # --- Preferences Methods (async, use passed conn) ---
    async def create_preference(self, conn: asyncpg.Connection, preference_data: Dict[str, Any]) -> Dict[str, int]:
        # ... (implementation uses _execute_query with conn) ...
        data_lower=lowercase_keys(preference_data); check_required_fields(data_lower, ['user_id', 'goals', 'diet_type'])
        sql="INSERT INTO user_preferences (user_id, goals, diet_type, food_restrictions, cuisine_preferences) VALUES ($1, $2, $3, $4, $5) RETURNING preference_id"
        try: params=(int(data_lower['user_id']), data_lower['goals'], data_lower['diet_type'], serialize_list(data_lower.get('food_restrictions', [])), serialize_list(data_lower.get('cuisine_preferences', [])))
        except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user_id format.")
        preference_id = await self._execute_query(conn, sql, params, returning_id_column='preference_id')
        if preference_id: logger.info(f"Created preference ID: {preference_id}"); return {"preference_id": preference_id}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Preference creation failed.")

    async def update_preference(self, conn: asyncpg.Connection, preference_id: int, updates: Dict[str, Any]):
        # ... (implementation uses _execute_query with conn) ...
        updates_lower = lowercase_keys(updates)
        set_clauses = []
        params = []
        idx = 1
        allowed = ['goals', 'diet_type', 'food_restrictions', 'cuisine_preferences']
        
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
            
        for k, v in updates_lower.items():
            if k in allowed:
                # Handle all preference fields as comma-separated strings
                if v is None or (isinstance(v, list) and not v):
                    # Set to NULL if empty list or None
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(None)
                elif isinstance(v, list):
                    # Convert list to comma-separated string, handle empty list case
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(','.join(str(item) for item in v) if v else None)
                else:
                    # If it's already a string, use as is
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(str(v) if v is not None else None)
                idx += 1
        
        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields to update.")
            
        sql = f"""
            UPDATE user_preferences 
            SET {', '.join(set_clauses)}
            WHERE preference_id = ${idx}
            RETURNING *
        """
        params.append(preference_id)
        
        try:
            result = await self._execute_query(conn, sql, tuple(params), fetch_one=True)
            if result:
                # Convert all preference fields from comma-separated strings to lists
                for field in ['goals', 'diet_type', 'food_restrictions', 'cuisine_preferences']:
                    if field in result and result[field]:
                        result[field] = result[field].split(',')
                    else:
                        result[field] = []
            logger.info(f"Successfully updated preference ID: {preference_id}")
            return result
        except Exception as e:
            logger.error(f"Error updating preference ID {preference_id}: {str(e)}")
            raise

    async def update_user(self, conn: asyncpg.Connection, user_id: int, updates: Dict[str, Any]) -> bool:
        """Updates user data in the users table."""
        updates_lower = lowercase_keys(updates)
        set_clauses = []
        params = []
        idx = 1
        # Define allowed fields for update based on create_user and list_users
        allowed = ['name', 'email', 'location', 'phone_number' , 'password', 'is_email_verified', 'user_type', 'image']

        if not updates_lower:
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")

        for k, v in updates_lower.items():
            if k in allowed:
                # Special handling for password
                if k == 'password':
                    hashed_pw = hash_password(v)
                    set_clauses.append(f"hashed_password=${idx}")
                    params.append(hashed_pw)
                else:
                    set_clauses.append(f"{k}=${idx}")
                    params.append(v)
                idx += 1

        if not set_clauses:
             raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields provided for update.")

        sql = f"UPDATE users SET {','.join(set_clauses)} WHERE user_id=${idx} RETURNING user_id"
        params.append(user_id)

        # Use _execute_query to run the update and check if a row was affected
        # fetchval with RETURNING user_id will return the user_id if the update affected a row
        updated_user_id = await self._execute_query(conn, sql, tuple(params), returning_id_column='user_id')

        if updated_user_id == user_id:
            logger.info(f"Successfully updated user ID: {user_id}")
            return True
        else:
            logger.warning(f"Attempted to update non-existent user ID: {user_id}")
            return False # User not found or update didn't affect any rows

    async def list_preferences(self, conn: asyncpg.Connection, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
        # ... (implementation uses _execute_query with conn) ...
        sql="SELECT * FROM user_preferences"; params=[]
        if user_id is not None: sql+=" WHERE user_id = $1"; params.append(user_id)
        preferences = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if preferences:
             processed = [];
             for row in preferences: p_pref=dict(row); p_pref['food_restrictions']=deserialize_list(p_pref.get('food_restrictions','')); p_pref['cuisine_preferences']=deserialize_list(p_pref.get('cuisine_preferences','')); processed.append(p_pref)
             return processed
async def list_calorie_history(self, conn: asyncpg.Connection, user_id: int) -> List[Dict[str, Any]]:
        """Lists calorie history entries for a given user ID."""
        logger.info(f"Fetching calorie history for user ID: {user_id}")
        sql = "SELECT calories, last_updated FROM calories_history WHERE user_id = $1 ORDER BY last_updated DESC"
        params = (user_id,)
        try:
            history = await self._execute_query(conn, sql, params, fetch_all=True)
            processed_history = []
            for entry in history:
                p_entry = dict(entry)
                if isinstance(p_entry.get('last_updated'), (datetime, date)):
                    p_entry['last_updated'] = p_entry['last_updated'].isoformat()
                processed_history.append(p_entry)
            logger.info(f"Fetched {len(processed_history)} calorie history entries for user ID: {user_id}")
            return processed_history
        except Exception as e:
            logger.error(f"Error fetching calorie history for user {user_id}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Error fetching calorie history.")
        return []

# --- Other Classes (Chefs, Producers, etc. Updated for asyncpg pool) ---
# Repeat the pattern for ALL classes that interact with the database:
# 1. Remove __init__ if it only dealt with DB connection.
# 2. Add 'conn: asyncpg.Connection' as the first argument to all methods performing DB operations.
# 3. Call self._execute_query(conn, ...) within those methods.

class Chefs(BaseRepository):
    # _validate_stock remains synchronous helper
    def _validate_stock(self, stock_data, is_chef=True):
        # ... (implementation unchanged) ...
        if stock_data is None: return []
        if not isinstance(stock_data, list): raise ValueError(f"Stock must be a list, got {type(stock_data)}")
        id_field = 'meal_id' if is_chef else 'produce_id'
        for item in stock_data:
            if not isinstance(item, dict): raise ValueError(f"Stock item must be a dict, got {type(item)}")
            name_val = item.get('Name')
            if not isinstance(name_val, str) or not name_val.strip(): raise ValueError("Stock item Name required")
            id_val = item.get(id_field);
            if id_val is not None and not isinstance(id_val, str): raise ValueError(f"{id_field} must be string or null")
            qty_val = item.get('quantity')
            if qty_val is not None:
                try: item['quantity'] = float(qty_val)
                except (ValueError, TypeError): raise ValueError("Stock quantity must be number or null")
        return stock_data

    async def create_chef(self, conn: asyncpg.Connection, chef_data: dict):
        # ... (uses conn for fetchval and _execute_query) ...
        chef_data_lower = lowercase_keys(chef_data)
        required = ['name', 'password', 'email', 'chef_type', 'phone_number', 'location', 'experience', 'responsetime', 'minnotice', 'teamsize', 'bio', 'image', 'pricing']
        check_required_fields(chef_data_lower, required)
        email = chef_data_lower['email']
        check_sql = "SELECT chefid FROM chefs WHERE lower(email) = lower($1)"
        existing_chef = await conn.fetchval(check_sql, email) # Use conn directly
        if existing_chef: raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Chef email '{email}' already exists.")
        try: hashed_password = hash_password(chef_data_lower['password'])
        except Exception as e: logger.error(f"Password hash failed: {e}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Password processing error.")
        pricing_data = chef_data_lower.get('pricing', {});
        if not isinstance(pricing_data, dict): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid pricing format.")
        try: # Validate pricing structure
            if 'starting_price' in pricing_data: pricing_data['starting_price'] = float(pricing_data['starting_price']) if pricing_data['starting_price'] is not None else None
            if 'per_month' in pricing_data: pricing_data['per_month'] = float(pricing_data['per_month']) if pricing_data['per_month'] is not None else None
            if 'per_gig' in pricing_data and isinstance(pricing_data.get('per_gig'), dict): pricing_data['per_gig'] = {k: float(v) if v is not None else None for k, v in pricing_data['per_gig'].items()}
            else: pricing_data['per_gig'] = {}
            pricing_param = json.dumps(pricing_data)
        except (ValueError, TypeError, KeyError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid pricing data: {e}")
        try: # Validate and serialize other JSON fields
            stock_data = self._validate_stock(chef_data_lower.get('stock'), is_chef=True); stock_json_str = json.dumps(stock_data)
            equipment_json_str = json.dumps(chef_data_lower.get('equipment', [])); availability_json_str = json.dumps(chef_data_lower.get('availability', [])); languages_json_str = json.dumps(chef_data_lower.get('languages', [])); specialties_json_str = json.dumps(chef_data_lower.get('specialties', [])); certifications_json_str = json.dumps(chef_data_lower.get('certifications', [])); samplemenu_json_str = json.dumps(chef_data_lower.get('samplemenu', []))
        except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Error processing JSON data: {e}")

        user_type = chef_data_lower.get('user_type', 'chef'); is_email_verified = chef_data_lower.get('is_email_verified', False); is_active = chef_data_lower.get('is_active', True); added_by = chef_data_lower.get('added_by'); added_by_type = chef_data_lower.get('added_by_type', user_type)
        sql = """INSERT INTO chefs (name, image, email, hashed_password, is_email_verified, user_type, chef_type, is_active, rating, phone_number, experience, serviceradius, responsetime, minnotice, punctuality, teamsize, equipment, bio, availability, languages, specialties, certifications, registration_date, location, samplemenu, added_by, added_by_type, last_login, pricing, stock) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, NOW(), $23, $24, $25, $26, NOW(), $27, $28) RETURNING chefid"""
        params = (chef_data_lower['name'], chef_data_lower.get('image'), email, hashed_password, is_email_verified, user_type, chef_data_lower.get('chef_type', 'Individual'), is_active, chef_data_lower.get('rating', 0.0), chef_data_lower.get('phone_number'), chef_data_lower.get('experience'), chef_data_lower.get('serviceradius'), chef_data_lower.get('responsetime'), chef_data_lower.get('minnotice'), chef_data_lower.get('punctuality', 0.0), chef_data_lower.get('teamsize'), equipment_json_str, chef_data_lower.get('bio'), availability_json_str, languages_json_str, specialties_json_str, certifications_json_str, chef_data_lower.get('location'), samplemenu_json_str, added_by, added_by_type, pricing_param, stock_json_str)
        chef_id = await self._execute_query(conn, sql, params, returning_id_column='chefid')
        if chef_id: logger.info(f"Created chef ID: {chef_id}"); return {"Chef_id": chef_id, "user_type": user_type, "message": "Chef created"}
        else: logger.error(f"Chef creation failed for {email}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Chef creation failed.")

    async def list_chefs(self, conn: asyncpg.Connection, chef_id=None):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM chefs"; params = []
        if chef_id is not None:
            try: cid = int(chef_id); sql += " WHERE chefid = $1"; params.append(cid)
            except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid chef_id.")
        chefs_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if chefs_list is None: return []
        processed_chefs = []
        for chef_dict in chefs_list:
            processed_chef = dict(chef_dict); list_fields = ['equipment','availability','languages','specialties','certifications','samplemenu','stock']
            for field in list_fields: processed_chef[field] = deserialize_list_from_json_string(processed_chef.get(field))
            try: pricing_data=json.loads(processed_chef.get('pricing') or '{}'); extracted_price=pricing_data.get('starting_price',0.0); processed_chef['price']=extracted_price if extracted_price is not None else 0.0
            except json.JSONDecodeError: logger.warning(f"Bad pricing JSON chef {processed_chef.get('chefid')}"); processed_chef['price']=0.0
            [processed_chef.update({k:v.isoformat()}) for k,v in processed_chef.items() if isinstance(v, (datetime, date))]; processed_chefs.append(processed_chef)
        if chef_id and not processed_chefs: logger.warning(f"Chef not found ID: {chef_id}"); return []
        return processed_chefs

    async def update_chef(self, conn: asyncpg.Connection, chef_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower = lowercase_keys(updates); set_clauses = []; params = []; idx = 1;
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        if 'pricing' in updates_lower:
            pricing_data = updates_lower.pop('pricing')
            if not isinstance(pricing_data, dict): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="pricing update invalid.")
            try: pricing_json = json.dumps(pricing_data); set_clauses.append(f"pricing=${idx}"); params.append(pricing_json); idx += 1
            except TypeError as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Pricing serialize fail: {e}")
        if 'stock' in updates_lower:
            try: stock_data=self._validate_stock(updates_lower.pop('stock'),True); stock_json=json.dumps(stock_data); set_clauses.append(f"stock=${idx}"); params.append(stock_json); idx+=1
            except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Stock update process fail: {e}")
        updates_lower.pop('price', None) # Remove derived field
        list_fields=['equipment','availability','languages','specialties','certifications','samplemenu']; allowed_direct=['name','image','email','chef_type','is_active','rating','phone_number','experience','serviceradius','responsetime','minnotice','punctuality','teamsize','bio','reviews','location','added_by','added_by_type','last_login']
        for k,v in updates_lower.items():
            if k == 'chefid': continue
            if k in allowed_direct: set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
            elif k in list_fields:
                 if isinstance(v, list):
                     try: v = json.dumps(v)
                     except TypeError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Serialize fail field '{k}'.")
                 elif not isinstance(v, str): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Field '{k}' must be list or JSON string.")
                 set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
            elif k == 'password':
                 if not isinstance(v, str) or not v: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password update needs non-empty string.")
                 hashed_pw=hash_password(v); set_clauses.append(f"hashed_password=${idx}"); params.append(hashed_pw); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        set_clauses.append(f"updated_at=NOW()")
        sql = f"UPDATE chefs SET {','.join(set_clauses)} WHERE chefid = ${idx}"; params.append(chef_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated chef ID: {chef_id}")

    async def login_chef(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT chefid, hashed_password, user_type, is_email_verified FROM chefs WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: logger.warning(f"Chef login fail: '{identifier}'"); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        chef_id = result['chefid']; stored_hash = result['hashed_password']; user_type = result['user_type']; is_verified = result['is_email_verified']
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash type chef {chef_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
            logger.info(f"Chef login success '{identifier}', ID: {chef_id}")
            # Optional: Update last_login
            # update_sql = "UPDATE chefs SET last_login = NOW() WHERE chefid = $1"
            # try: await self._execute_query(conn, update_sql, (chef_id,))
            # except Exception as update_err: logger.error(f"Failed last_login update chef {chef_id}: {update_err}")
            return {'message': 'Login successful', 'data': {'chef_id': chef_id, 'user_type': user_type, 'verified': is_verified}}
        else: logger.warning(f"Chef login fail pwd: '{identifier}'."); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')

    async def delete_chef(self, conn: asyncpg.Connection, chef_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete chef ID: {chef_id}")
        sql = "DELETE FROM chefs WHERE chefid = $1 RETURNING chefid"
        deleted_id = await self._execute_query(conn, sql, (chef_id,), returning_id_column='chefid')
        if deleted_id == chef_id: logger.info(f"Deleted chef ID: {chef_id}"); return True
        else: logger.warning(f"Attempt delete non-existent chef ID: {chef_id}"); return False

    async def update_chef_status(self, conn: asyncpg.Connection, chef_id: int, is_active: bool):
        # ... (uses conn for _execute_query) ...
        if not isinstance(is_active, bool): raise ValueError("is_active must be bool")
        sql = "UPDATE chefs SET is_active = $1, updated_at = NOW() WHERE chefid = $2"
        await self._execute_query(conn, sql, (is_active, chef_id)); logger.info(f"Updated chef {chef_id} status: {is_active}")

# --- Producers Class ---
class Producers(BaseRepository):
    # _validate_stock is synchronous helper
    def _validate_stock(self, stock_data, is_chef=False):
        # ... (implementation unchanged) ...
         if stock_data is None: return []
         if not isinstance(stock_data, list): raise ValueError(f"Stock must be list, got {type(stock_data)}")
         id_field = 'produce_id' if not is_chef else 'meal_id'; validated_stock = []
         for i, item in enumerate(stock_data):
             if not isinstance(item, dict): raise ValueError(f"Stock item {i} must be dict")
             name_val = item.get('name') if 'name' in item else item.get('Name')
             if not isinstance(name_val, str) or not name_val.strip(): raise ValueError(f"Stock item {i} needs Name")
             validated_item = {'Name': name_val.strip(), id_field: item.get(id_field)}
             if validated_item[id_field] is not None and not isinstance(validated_item[id_field], str): raise ValueError(f"Stock item {i} {id_field} must be string or null")
             if 'quantity' in item and item['quantity'] is not None:
                 try: validated_item['quantity'] = float(item['quantity']); assert validated_item['quantity']>=0
                 except (ValueError, TypeError, AssertionError): raise ValueError(f"Stock item {i} quantity invalid")
             validated_stock.append(validated_item)
         return validated_stock

    async def update_producer(self, conn: asyncpg.Connection, producer_id: int, updates: dict):
        # ... (uses conn for fetchval and _execute_query) ...
        updates_lower = lowercase_keys(updates); set_clauses = []; params = []; idx = 1;
        allowed = ['name','image','producer_type','is_active','rating','phone_number','location','reviews']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        if 'stock' in updates_lower:
            try: stock_data=self._validate_stock(updates_lower.pop('stock'),False); stock_json=json.dumps(stock_data); set_clauses.append(f"stock=${idx}"); params.append(stock_json); idx+=1
            except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Stock update fail: {e}")
        for k,v in updates_lower.items():
            if k in ['producer_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified', 'password']: continue
            if k in allowed:
                if k=='rating' and v is not None:
                    try: v=float(v); assert v>=0
                    except: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Rating invalid.")
                if k=='is_active' and not isinstance(v, bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="is_active invalid.")
                set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        check_sql = "SELECT producer_id FROM producers WHERE producer_id = $1"
        if not await conn.fetchval(check_sql, producer_id): raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Producer {producer_id} not found.")
        set_clauses.append(f"updated_at=NOW()")
        sql = f"UPDATE producers SET {','.join(set_clauses)} WHERE producer_id = ${idx}"; params.append(producer_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated producer ID: {producer_id}")

    async def create_producer(self, conn: asyncpg.Connection, producer_data: dict):
        # ... (uses conn for fetchval and _execute_query) ...
        producer_data_lower=lowercase_keys(producer_data); check_required_fields(producer_data_lower,['name','password','email'])
        email=producer_data_lower['email']; check_sql="SELECT producer_id FROM producers WHERE lower(email)=lower($1)"
        if await conn.fetchval(check_sql, email): raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Producer email '{email}' exists.")
        hashed_password=hash_password(producer_data_lower['password'])
        try: stock_data=self._validate_stock(producer_data_lower.get('stock'),False); stock_json=json.dumps(stock_data)
        except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Stock data error: {e}")
        user_type=producer_data_lower.get('user_type','producer'); is_email_verified=producer_data_lower.get('is_email_verified',False); is_active=producer_data_lower.get('is_active',True); added_by=producer_data_lower.get('added_by'); added_by_type=producer_data_lower.get('added_by_type', user_type)
        sql="INSERT INTO producers (name, image, email, hashed_password, is_email_verified, user_type, producer_type, is_active, rating, phone_number, registration_date, location, added_by, added_by_type, last_login, reviews, stock) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11, $12, $13, NOW(), $14, $15) RETURNING producer_id"
        try: added_by_id=int(added_by) if added_by is not None else None; rating_f=float(producer_data_lower.get('rating',0.0) or 0.0)
        except: added_by_id=None; rating_f=0.0
        params=(producer_data_lower['name'], producer_data_lower.get('image'), email, hashed_password, is_email_verified, user_type, producer_data_lower.get('producer_type','Individual'), is_active, rating_f, producer_data_lower.get('phone_number'), producer_data_lower.get('location'), added_by_id, added_by_type, producer_data_lower.get('reviews'), stock_json)
        producer_id=await self._execute_query(conn, sql, params, returning_id_column='producer_id')
        if producer_id: logger.info(f"Created producer ID: {producer_id}"); return {"producer_id": producer_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Producer creation failed.")

    async def list_producers(self, conn: asyncpg.Connection, producer_id=None):
        # ... (uses conn for _execute_query) ...
        sql="SELECT * FROM producers"; params=[]
        if producer_id is not None:
            try: pid=int(producer_id); sql+=" WHERE producer_id = $1"; params.append(pid)
            except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid producer_id.")
        producers_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if producers_list is None: return []
        processed = [];
        for row in producers_list: p_prod=dict(row); p_prod['stock']=deserialize_list_from_json_string(p_prod.get('stock')); [p_prod.update({k:v.isoformat()}) for k,v in p_prod.items() if isinstance(v, (datetime, date))]; processed.append(p_prod)
        if producer_id is not None and not processed: logger.warning(f"Producer not found ID: {producer_id}"); return []
        return processed

    async def login_producer(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT producer_id, hashed_password, user_type, is_email_verified FROM producers WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: logger.warning(f"Producer login fail: '{identifier}'"); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        producer_id=result['producer_id']; stored_hash=result['hashed_password']; user_type=result['user_type']; is_verified=result['is_email_verified']
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash producer {producer_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
             logger.info(f"Producer login success '{identifier}', ID: {producer_id}")
             # Optional: update last_login
             return {'message':'Login successful', 'data':{'producer_id':producer_id, 'user_type':user_type, 'verified':is_verified}}
        else: logger.warning(f"Producer login fail pwd: '{identifier}'."); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')

    async def delete_producer(self, conn: asyncpg.Connection, producer_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete producer ID: {producer_id}")
        sql = "DELETE FROM producers WHERE producer_id = $1 RETURNING producer_id"
        deleted_id = await self._execute_query(conn, sql, (producer_id,), returning_id_column='producer_id')
        if deleted_id == producer_id: logger.info(f"Deleted producer ID: {producer_id}"); return True
        else: logger.warning(f"Attempt delete non-existent producer ID: {producer_id}"); return False

    async def update_producer_status(self, conn: asyncpg.Connection, producer_id: int, is_active: bool):
        # ... (uses conn for _execute_query) ...
        if not isinstance(is_active, bool): raise ValueError("is_active must be bool")
        sql = "UPDATE producers SET is_active = $1, updated_at = NOW() WHERE producer_id = $2"
        await self._execute_query(conn, sql, (is_active, producer_id)); logger.info(f"Updated producer {producer_id} status: {is_active}")

# --- Transporters Class ---
class Transporters(BaseRepository):
    async def create_transporter(self, conn: asyncpg.Connection, transporter_data: dict):
        # ... (uses conn for fetchval and _execute_query) ...
        data_lower=lowercase_keys(transporter_data); check_required_fields(data_lower,['name','password','email'])
        email=data_lower['email']; check_sql="SELECT transporter_id FROM transporters WHERE lower(email)=lower($1)"
        if await conn.fetchval(check_sql, email): raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Transporter email '{email}' exists.")
        hashed_password=hash_password(data_lower['password']); user_type=data_lower.get('user_type','transporter'); is_active=data_lower.get('is_active',False)
        sql="INSERT INTO transporters (name, email, hashed_password, phone_number, profile_image_url, vehicle_type, license_plate, is_active, rating, location, registration_date, user_type, reviews) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11, $12) RETURNING transporter_id"
        params=(data_lower['name'], email, hashed_password, data_lower.get('phone_number'), data_lower.get('profile_image_url'), data_lower.get('vehicle_type'), data_lower.get('license_plate'), is_active, data_lower.get('rating',0.0), data_lower.get('location'), user_type, data_lower.get('reviews'))
        transporter_id=await self._execute_query(conn, sql, params, returning_id_column='transporter_id')
        if transporter_id: logger.info(f"Created transporter ID: {transporter_id}"); return {"transporter_id": transporter_id, "UserType": user_type, "message":"Transporter created"}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Transporter creation failed.")

    async def list_transporters(self, conn: asyncpg.Connection, transporter_id=None):
        # ... (uses conn for _execute_query) ...
        sql="SELECT * FROM transporters"; params=[]
        if transporter_id is not None:
            try: tid=int(transporter_id); sql+=" WHERE transporter_id = $1"; params.append(tid)
            except ValueError: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid transporter_id.")
        transporters_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if transporters_list is None: return []
        processed = [];
        for t in transporters_list: p_trans=dict(t); [p_trans.update({k:v.isoformat()}) for k,v in p_trans.items() if isinstance(v, (datetime, date))]; processed.append(p_trans)
        if transporter_id is not None and not processed: logger.warning(f"Transporter not found ID: {transporter_id}"); return []
        return processed

    async def update_transporter(self, conn: asyncpg.Connection, transporter_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1;
        allowed=['name','phone_number','profile_image_url','vehicle_type','license_plate','is_active','rating','location','reviews']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
            if k in ['transporter_id', 'email', 'registration_date', 'user_type']: continue
            if k == 'password': hashed_pw=hash_password(v); set_clauses.append(f"hashed_password=${idx}"); params.append(hashed_pw); idx+=1
            elif k in allowed: set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        set_clauses.append(f"updated_at=NOW()")
        sql=f"UPDATE transporters SET {','.join(set_clauses)} WHERE transporter_id=${idx}"; params.append(transporter_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated transporter ID: {transporter_id}")

    async def login_transporter(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql="SELECT transporter_id, hashed_password, user_type, is_email_verified FROM transporters WHERE lower(name)=lower($1) OR lower(email)=lower($2)"
        params=(identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: logger.warning(f"Transporter login fail: '{identifier}'"); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        transporter_id=result['transporter_id']; stored_hash=result['hashed_password']; user_type=result.get('user_type','transporter'); is_verified=result.get('is_email_verified',True) # Assume verified if column missing
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash transporter {transporter_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
            logger.info(f"Transporter login success '{identifier}', ID: {transporter_id}")
            # Optional: update last_login
            return {'message':'Login successful', 'data':{'transporter_id':transporter_id, 'user_type':user_type, 'verified':is_verified}}
        else: logger.warning(f"Transporter login fail pwd: '{identifier}'."); raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')

    async def delete_transporter(self, conn: asyncpg.Connection, transporter_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete transporter ID: {transporter_id}")
        sql = "DELETE FROM transporters WHERE transporter_id = $1 RETURNING transporter_id"
        deleted_id = await self._execute_query(conn, sql, (transporter_id,), returning_id_column='transporter_id')
        if deleted_id == transporter_id: logger.info(f"Deleted transporter ID: {transporter_id}"); return True
        else: logger.warning(f"Attempt delete non-existent transporter ID: {transporter_id}"); return False

    async def update_transporter_status(self, conn: asyncpg.Connection, transporter_id: int, is_active: bool):
        # ... (uses conn for _execute_query) ...
        if not isinstance(is_active, bool): raise ValueError("is_active must be bool")
        sql = "UPDATE transporters SET is_active = $1, updated_at = NOW() WHERE transporter_id = $2"
        await self._execute_query(conn, sql, (is_active, transporter_id)); logger.info(f"Updated transporter {transporter_id} status: {is_active}")

# --- Stakeholders Class ---
class Stakeholders(BaseRepository):
    async def create_stakeholder(self, conn: asyncpg.Connection, stakeholder_data: dict):
        # ... (uses conn for fetchval and _execute_query) ...
        data_lower=lowercase_keys(stakeholder_data); check_required_fields(data_lower,['name','password','email','full_name'])
        email=data_lower['email']; check_sql="SELECT stakeholder_id FROM stakeholders WHERE lower(email)=lower($1)"
        if await conn.fetchval(check_sql, email): raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Stakeholder email '{email}' exists.")
        hashed_password=hash_password(data_lower['password']); user_type=data_lower.get('user_type','stakeholder'); is_email_verified=data_lower.get('is_email_verified',False); is_active=data_lower.get('is_active',True); added_by=data_lower.get('added_by'); added_by_type=data_lower.get('added_by_type', user_type)
        sql="INSERT INTO stakeholders (name, full_name, image, email, hashed_password, is_email_verified, user_type, is_active, rating, phone_number, registration_date, location, added_by, added_by_type, last_login) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),$11,$12,$13,NOW()) RETURNING stakeholder_id"
        try: added_by_id=int(added_by) if added_by is not None else None; rating_f = float(data_lower.get('rating',0.0) or 0.0)
        except: added_by_id=None; rating_f=0.0
        params=(data_lower['name'], data_lower['full_name'], data_lower.get('image'), email, hashed_password, is_email_verified, user_type, is_active, rating_f, data_lower.get('phone_number'), data_lower.get('location'), added_by_id, added_by_type)
        stakeholder_id=await self._execute_query(conn, sql, params, returning_id_column='stakeholder_id')
        if stakeholder_id: logger.info(f"Created stakeholder ID: {stakeholder_id}"); return {"stakeholder_id": stakeholder_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Stakeholder creation failed.")

    async def list_stakeholders(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        sql="SELECT * FROM stakeholders"
        results = await self._execute_query(conn, sql, fetch_all=True)
        if results: processed = []; [processed.append({**dict(item), **{k: v.isoformat() for k,v in item.items() if isinstance(v, (datetime,date))}}) for item in results]; return processed
        return []

    async def get_stakeholder_by_id(self, conn: asyncpg.Connection, stakeholder_id: int):
        # ... (uses conn for _execute_query) ...
        sql="SELECT * FROM stakeholders WHERE stakeholder_id = $1"
        result = await self._execute_query(conn, sql, (stakeholder_id,), fetch_one=True)
        if result: p_result=dict(result); [p_result.update({k: v.isoformat() for k,v in p_result.items() if isinstance(v, (datetime,date))})]; return p_result
        return None

    async def update_stakeholder(self, conn: asyncpg.Connection, stakeholder_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1;
        allowed=['name','full_name','image','is_active','rating','phone_number','location']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
            if k in ['stakeholder_id', 'email', 'registration_date', 'added_by', 'added_by_type', 'last_login', 'user_type', 'hashed_password', 'is_email_verified']: continue
            if k == 'password': hashed_pw=hash_password(v); set_clauses.append(f"hashed_password=${idx}"); params.append(hashed_pw); idx+=1
            elif k in allowed: set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        set_clauses.append(f"updated_at=NOW()")
        sql=f"UPDATE stakeholders SET {','.join(set_clauses)} WHERE stakeholder_id=${idx}"; params.append(stakeholder_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated stakeholder ID: {stakeholder_id}")

    async def login_stakeholder(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql="SELECT stakeholder_id, hashed_password, user_type, is_email_verified FROM stakeholders WHERE lower(name)=lower($1) OR lower(email)=lower($2)"
        params=(identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        stakeholder_id=result['stakeholder_id']; stored_hash=result['hashed_password']; user_type=result.get('user_type','stakeholder'); is_verified=result.get('is_email_verified',False)
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
            logger.info(f"Stakeholder login success '{identifier}', ID: {stakeholder_id}")
            # Optional: update last_login
            return {'message':'Login successful', 'data':{'stakeholder_id':stakeholder_id, 'user_type':user_type, 'verified':is_verified}}
        else: raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')

    async def delete_stakeholder(self, conn: asyncpg.Connection, stakeholder_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete stakeholder ID: {stakeholder_id}")
        sql = "DELETE FROM stakeholders WHERE stakeholder_id = $1 RETURNING stakeholder_id"
        deleted_id = await self._execute_query(conn, sql, (stakeholder_id,), returning_id_column='stakeholder_id')
        if deleted_id == stakeholder_id: logger.info(f"Deleted stakeholder ID: {stakeholder_id}"); return True
        else: logger.warning(f"Attempt delete non-existent stakeholder ID: {stakeholder_id}"); return False

    async def update_stakeholder_status(self, conn: asyncpg.Connection, stakeholder_id: int, is_active: bool):
        # ... (uses conn for _execute_query) ...
         if not isinstance(is_active, bool): raise ValueError("is_active must be bool")
         sql = "UPDATE stakeholders SET is_active = $1, updated_at = NOW() WHERE stakeholder_id = $2"
         await self._execute_query(conn, sql, (is_active, stakeholder_id)); logger.info(f"Updated stakeholder {stakeholder_id} status: {is_active}")

# --- Herbals Class ---
class Herbals(BaseRepository):
    async def create_herbal(self, conn: asyncpg.Connection, herbal_data: dict):
        # ... (uses conn for _execute_query) ...
        data_lower=lowercase_keys(herbal_data); check_required_fields(data_lower,['herbal_name','description','unit','price'])
        user_type=data_lower.get('user_type','herbal')
        sql="INSERT INTO herbals (herbal_name, description, unit, price, image_url, date_added, added_by, added_by_type, user_type) VALUES ($1,$2,$3,$4,$5,NOW(),$6,$7,$8) RETURNING herbal_id"
        try: price_f=float(data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price format.")
        params=(data_lower['herbal_name'],data_lower['description'],data_lower['unit'],price_f,data_lower.get('image_url'),data_lower.get('added_by'),data_lower.get('added_by_type',user_type),user_type)
        herbal_id=await self._execute_query(conn, sql, params, returning_id_column='herbal_id')
        if herbal_id: logger.info(f"Created herbal ID: {herbal_id}"); return {"herbal_id": herbal_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Herbal creation failed.")

    async def update_herbal(self, conn: asyncpg.Connection, herbal_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1; allowed=['herbal_name','description','unit','price','image_url']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
             if k in allowed:
                 if k=='price':
                      try: v=float(v)
                      except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
                 set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE herbals SET {','.join(set_clauses)} WHERE herbal_id=${idx}"; params.append(herbal_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated herbal ID: {herbal_id}")

    async def list_herbals(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        results = await self._execute_query(conn, "SELECT * FROM herbals ORDER BY herbal_id", fetch_all=True) # Added order
        return results or []

    async def get_herbal_by_id(self, conn: asyncpg.Connection, herbal_id: int):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM herbals WHERE herbal_id = $1"
        return await self._execute_query(conn, sql, (herbal_id,), fetch_one=True)

    async def delete_herbal(self, conn: asyncpg.Connection, herbal_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete herbal ID: {herbal_id}")
        sql = "DELETE FROM herbals WHERE herbal_id = $1 RETURNING herbal_id"
        deleted_id = await self._execute_query(conn, sql, (herbal_id,), returning_id_column='herbal_id')
        if deleted_id == herbal_id: logger.info(f"Deleted herbal ID: {herbal_id}"); return True
        else: logger.warning(f"Attempt delete non-existent herbal ID: {herbal_id}"); return False

# --- Meals Class ---
class Meals(BaseRepository):
    async def create_meal(self, conn: asyncpg.Connection, meal_data: dict):
        # ... (uses conn for _execute_query) ...
        data_lower=lowercase_keys(meal_data); check_required_fields(data_lower,['meal_name','meal_category','ingredients'])
        user_type=data_lower.get('user_type','meal')
        sql="INSERT INTO meals (meal_name,meal_category,ingredients,complementary_dishes,recipe,recipe_link,image_link,goal,dietary_preference,allergies,disease_management,cuisine_preferences,skill_level,prep_time,meal_description,date_added,date_last_edited,added_by,added_by_type,user_type) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,NOW(),NOW(),$16,$17,$18) RETURNING meal_id"
        params=(data_lower['meal_name'],data_lower['meal_category'],data_lower['ingredients'], data_lower.get('complementary_dishes'),data_lower.get('recipe'),data_lower.get('recipe_link'), data_lower.get('image_link'),data_lower.get('goal'),data_lower.get('dietary_preference'), data_lower.get('allergies'),data_lower.get('disease_management'),data_lower.get('cuisine_preferences'), data_lower.get('skill_level'),data_lower.get('prep_time'),data_lower.get('meal_description'), data_lower.get('added_by'),data_lower.get('added_by_type',user_type),user_type)
        meal_id=await self._execute_query(conn, sql, params, returning_id_column='meal_id')
        if meal_id: logger.info(f"Created meal ID: {meal_id}"); return {"meal_id": meal_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Meal creation failed.")

    async def update_meal(self, conn: asyncpg.Connection, meal_id: str, updates: dict):
        # ... (uses conn for _execute_query) ...
        mid=str(meal_id); updates_lower=lowercase_keys(updates);
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        updates_lower['date_last_edited']=datetime.now() # Auto update edit time
        set_clauses=[]; params=[]; idx=1; allowed=['meal_name','meal_category','ingredients','complementary_dishes','recipe','recipe_link','image_link','goal','dietary_preference','allergies','disease_management','cuisine_preferences','skill_level','prep_time','meal_description','date_last_edited']
        for k,v in updates_lower.items():
             if k in allowed: set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE meals SET {','.join(set_clauses)} WHERE meal_id=${idx}"; params.append(mid)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated meal ID: {meal_id}")

    async def list_meals(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        # This query joins ingredients and complementaries - keep as is
        sql_query = """
        WITH MealDetails AS (
            SELECT m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link, m.goal, m.dietary_preference, m.allergies, m.disease_management, m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description FROM meals m
        )
        SELECT md.*,
            COALESCE((SELECT STRING_AGG(p.produce_name, ', ') FROM meal_ingredients i JOIN produce p ON i.produce_id = p.produce_id WHERE i.meal_id = md.meal_id), '') AS ingredients,
            COALESCE((SELECT STRING_AGG(mc.meal_name, ', ') FROM meal_complementaries mc_link JOIN meals mc ON mc_link.complementary_dish_id = mc.meal_id WHERE mc_link.meal_id = md.meal_id), '') AS complementary_dishes
        FROM MealDetails md ORDER BY md.meal_id;
        """ # Added default order
        results = await self._execute_query(conn, sql_query, fetch_all=True)
        if not results: return []
        processed = []
        for row in results:
            meal=dict(row);
            meal_dict={"Meal_id":meal.get("meal_id"),"Meal_name":meal.get("meal_name"),"Meal_category":meal.get("meal_category"), "Recipe":meal.get("recipe"),"Recipe_link":meal.get("recipe_link"),"Image_link":meal.get("image_link"), "Goal":meal.get("goal"),"Dietary_preference":meal.get("dietary_preference"),"Allergies":meal.get("allergies"), "Disease_management":meal.get("disease_management"),"Cuisine_preferences":meal.get("cuisine_preferences"), "Skill_level":meal.get("skill_level"),"Prep_time":meal.get("prep_time"),"Meal_description":meal.get("meal_description"), "Ingredients":meal.get("ingredients") or "","Complementary_dishes":meal.get("complementary_dishes") or "", "Price":10000} # Default price
            processed.append(meal_dict)
        return processed

    async def get_meal_by_id(self, conn: asyncpg.Connection, meal_id: str):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM meals WHERE meal_id = $1" # Assuming meal_id is text
        result = await self._execute_query(conn, sql, (str(meal_id),), fetch_one=True)
        # Optional: Process result like in list_meals if needed
        return result

    async def delete_meal(self, conn: asyncpg.Connection, meal_id: str):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete meal ID: {meal_id}")
        sql = "DELETE FROM meals WHERE meal_id = $1 RETURNING meal_id"
        deleted_id = await self._execute_query(conn, sql, (str(meal_id),), returning_id_column='meal_id')
        if deleted_id == meal_id: logger.info(f"Deleted meal ID: {meal_id}"); return True
        else: logger.warning(f"Attempt delete non-existent meal ID: {meal_id}"); return False

# --- Produce Class ---
class Produce(BaseRepository):
    async def create_produce(self, conn: asyncpg.Connection, produce_data: dict):
        # ... (uses conn for _execute_query) ...
        data_lower=lowercase_keys(produce_data); check_required_fields(data_lower,['produce_name','unit_grams','calories'])
        user_type=data_lower.get('user_type','produce')
        sql="INSERT INTO produce (produce_name,unit_grams,calories,cholesterol,carbohydrates,proteins,fats,fiber,sugars,meal_type,source,nutritional_info,date_added,date_last_edited,added_by,added_by_type,user_type) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,NOW(),NOW(),$13,$14,$15) RETURNING produce_id"
        try: params=(data_lower['produce_name'],float(data_lower['unit_grams']),float(data_lower['calories']), data_lower.get('cholesterol'),data_lower.get('carbohydrates'),data_lower.get('proteins'), data_lower.get('fats'),data_lower.get('fiber'),data_lower.get('sugars'), data_lower.get('meal_type'),data_lower.get('source'),data_lower.get('nutritional_info'), data_lower.get('added_by'),data_lower.get('added_by_type',user_type),user_type)
        except (ValueError, TypeError) as e: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid produce format: {e}") from e
        produce_id=await self._execute_query(conn, sql, params, returning_id_column='produce_id')
        if produce_id: logger.info(f"Created produce ID: {produce_id}"); return {"produce_id": produce_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Produce creation failed.")

    async def update_produce(self, conn: asyncpg.Connection, produce_id: str, updates: dict):
        # ... (uses conn for _execute_query) ...
        pid=str(produce_id); updates_lower=lowercase_keys(updates);
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        updates_lower['date_last_edited']=datetime.now()
        set_clauses=[]; params=[]; idx=1; allowed=['produce_name','unit_grams','calories','cholesterol','carbohydrates','proteins','fats','fiber','sugars','meal_type','source','nutritional_info','date_last_edited']
        for k,v in updates_lower.items():
             if k in allowed: set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE produce SET {','.join(set_clauses)} WHERE produce_id=${idx}"; params.append(pid)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated produce ID: {produce_id}")

    async def list_produce(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        results = await self._execute_query(conn, "SELECT * FROM produce ORDER BY produce_id", fetch_all=True) # Added order
        return results or []

    async def get_produce_by_id(self, conn: asyncpg.Connection, produce_id: int): # Assuming int ID
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM produce WHERE produce_id = $1"
        return await self._execute_query(conn, sql, (produce_id,), fetch_one=True)

    async def delete_produce(self, conn: asyncpg.Connection, produce_id: int): # Assuming int ID
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete produce ID: {produce_id}")
        sql = "DELETE FROM produce WHERE produce_id = $1 RETURNING produce_id"
        deleted_id = await self._execute_query(conn, sql, (produce_id,), returning_id_column='produce_id')
        if deleted_id == produce_id: logger.info(f"Deleted produce ID: {produce_id}"); return True
        else: logger.warning(f"Attempt delete non-existent produce ID: {produce_id}"); return False

# --- Gadgets Class ---
class Gadgets(BaseRepository):
    async def create_gadget(self, conn: asyncpg.Connection, gadget_data: dict):
        # ... (uses conn for _execute_query) ...
        data_lower=lowercase_keys(gadget_data); check_required_fields(data_lower,['gadget_name','description','price'])
        user_type=data_lower.get('user_type','gadget')
        sql="INSERT INTO gadgets (gadget_name,description,brand,model,price,image_url,date_added,added_by,added_by_type,user_type) VALUES ($1,$2,$3,$4,$5,$6,NOW(),$7,$8,$9) RETURNING gadget_id"
        try: price_f=float(data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
        params=(data_lower['gadget_name'],data_lower['description'],data_lower.get('brand'), data_lower.get('model'),price_f,data_lower.get('image_url'), data_lower.get('added_by'),data_lower.get('added_by_type',user_type),user_type)
        gadget_id=await self._execute_query(conn, sql, params, returning_id_column='gadget_id')
        if gadget_id: logger.info(f"Created gadget ID: {gadget_id}"); return {"gadget_id": gadget_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Gadget creation failed.")

    async def update_gadget(self, conn: asyncpg.Connection, gadget_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1; allowed=['gadget_name','description','brand','model','price','image_url']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
             if k in allowed:
                 if k=='price':
                      try: v=float(v)
                      except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
                 set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE gadgets SET {','.join(set_clauses)} WHERE gadget_id=${idx}"; params.append(gadget_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated gadget ID: {gadget_id}")

    async def list_gadgets(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        results = await self._execute_query(conn, "SELECT * FROM gadgets ORDER BY gadget_id", fetch_all=True) # Added order
        return results or []

    async def get_gadget_by_id(self, conn: asyncpg.Connection, gadget_id: int):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM gadgets WHERE gadget_id = $1"
        return await self._execute_query(conn, sql, (gadget_id,), fetch_one=True)

    async def delete_gadget(self, conn: asyncpg.Connection, gadget_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete gadget ID: {gadget_id}")
        sql = "DELETE FROM gadgets WHERE gadget_id = $1 RETURNING gadget_id"
        deleted_id = await self._execute_query(conn, sql, (gadget_id,), returning_id_column='gadget_id')
        if deleted_id == gadget_id: logger.info(f"Deleted gadget ID: {gadget_id}"); return True
        else: logger.warning(f"Attempt delete non-existent gadget ID: {gadget_id}"); return False

# --- Spices Class ---
class Spices(BaseRepository):
    async def create_spice(self, conn: asyncpg.Connection, spice_data: dict):
        # ... (uses conn for _execute_query) ...
        data_lower=lowercase_keys(spice_data); check_required_fields(data_lower,['spice_name','description','price'])
        user_type=data_lower.get('user_type','spice')
        sql="INSERT INTO spices (spice_name,description,unit,price,image_url,date_added,added_by,added_by_type,user_type) VALUES ($1,$2,$3,$4,$5,NOW(),$6,$7,$8) RETURNING spice_id"
        try: price_f=float(data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
        params=(data_lower['spice_name'],data_lower['description'],data_lower.get('unit'), price_f,data_lower.get('image_url'),data_lower.get('added_by'), data_lower.get('added_by_type',user_type),user_type)
        spice_id=await self._execute_query(conn, sql, params, returning_id_column='spice_id')
        if spice_id: logger.info(f"Created spice ID: {spice_id}"); return {"spice_id": spice_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Spice creation failed.")

    async def update_spice(self, conn: asyncpg.Connection, spice_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1; allowed=['spice_name','description','unit','price','image_url']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
             if k in allowed:
                 if k=='price':
                     try: v=float(v)
                     except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
                 set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE spices SET {','.join(set_clauses)} WHERE spice_id=${idx}"; params.append(spice_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated spice ID: {spice_id}")

    async def list_spices(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        results = await self._execute_query(conn, "SELECT * FROM spices ORDER BY spice_id", fetch_all=True) # Added order
        return results or []

    async def get_spice_by_id(self, conn: asyncpg.Connection, spice_id: int):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT * FROM spices WHERE spice_id = $1"
        return await self._execute_query(conn, sql, (spice_id,), fetch_one=True)

    async def delete_spice(self, conn: asyncpg.Connection, spice_id: int):
        # ... (uses conn for fetchval via _execute_query) ...
        logger.warning(f"Attempting delete spice ID: {spice_id}")
        sql = "DELETE FROM spices WHERE spice_id = $1 RETURNING spice_id"
        deleted_id = await self._execute_query(conn, sql, (spice_id,), returning_id_column='spice_id')
        if deleted_id == spice_id: logger.info(f"Deleted spice ID: {spice_id}"); return True
        else: logger.warning(f"Attempt delete non-existent spice ID: {spice_id}"); return False
        
        # --- Supplements Class ---
class Supplements(BaseRepository):
    async def create_supplement(self, conn: asyncpg.Connection, supplement_data: dict):
        data_lower=lowercase_keys(supplement_data); check_required_fields(data_lower,['supplement_name','description','price'])
        user_type=data_lower.get('user_type','supplement')
        sql="INSERT INTO supplements (supplement_name,description,unit,price,image_url,date_added,added_by,added_by_type,user_type) VALUES ($1,$2,$3,$4,$5,NOW(),$6,$7,$8) RETURNING supplement_id"
        try: price_f=float(data_lower['price']);
        except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
        params=(data_lower['supplement_name'],data_lower['description'],data_lower.get('unit'), price_f,data_lower.get('image_url'),data_lower.get('added_by'), data_lower.get('added_by_type',user_type),user_type)
        supplement_id=await self._execute_query(conn, sql, params, returning_id_column='supplement_id')
        if supplement_id: logger.info(f"Created supplement ID: {supplement_id}"); return {"supplement_id": supplement_id, "UserType": user_type}
        else: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Supplement creation failed.")

    async def update_supplement(self, conn: asyncpg.Connection, supplement_id: int, updates: dict):
        updates_lower=lowercase_keys(updates); set_clauses=[]; params=[]; idx=1; allowed=['supplement_name','description','unit','price','image_url']
        if not updates_lower: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
        for k,v in updates_lower.items():
             if k in allowed:
                 if k=='price':
                     try: v=float(v)
                     except (ValueError, TypeError): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid price.")
                 set_clauses.append(f"{k}=${idx}"); params.append(v); idx+=1
        if not set_clauses: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        sql=f"UPDATE supplements SET {','.join(set_clauses)} WHERE supplement_id=${idx}"; params.append(supplement_id)
        await self._execute_query(conn, sql, tuple(params)); logger.info(f"Updated supplement ID: {supplement_id}")

    async def list_supplements(self, conn: asyncpg.Connection):
        results = await self._execute_query(conn, "SELECT * FROM supplements ORDER BY supplement_id", fetch_all=True) # Added order
        return results or []

    async def get_supplement_by_id(self, conn: asyncpg.Connection, supplement_id: int):
        sql = "SELECT * FROM supplements WHERE supplement_id = $1"
        return await self._execute_query(conn, sql, (supplement_id,), fetch_one=True)

    async def delete_supplement(self, conn: asyncpg.Connection, supplement_id: int):
        logger.warning(f"Attempting delete supplement ID: {supplement_id}")
        sql = "DELETE FROM supplements WHERE supplement_id = $1 RETURNING supplement_id"
        deleted_id = await self._execute_query(conn, sql, (supplement_id,), returning_id_column='supplement_id')
        if deleted_id == supplement_id: logger.info(f"Deleted supplement ID: {supplement_id}"); return True
        else: logger.warning(f"Attempt delete non-existent supplement ID: {supplement_id}"); return False


#orders class starts here, base repo already implemented up there no need of reimplementing it
import asyncpg # For asyncpg.Connection, asyncpg.PostgresError
import json
import logging # Assuming logger is an instance of logging.Logger and configured
import random
import string
from datetime import datetime, date
from typing import List, Dict, Any, Optional, Union, Tuple
from fastapi import HTTPException, status # Or from starlette.exceptions import HTTPException and from starlette.status import ...

# Assume BaseRepository is defined elsewhere and provides self._execute_query
# Assume notification_service and fcm_service are defined/imported and provide their respective methods
# Example: logger = logging.getLogger(__name__)


# Ensure BaseRepository is defined before this class, e.g.:
# class BaseRepository:
#     async def _execute_query(self, conn, query, params=None, fetch_all=False, fetch_val=False, returning_id_column=None):
#         # Implementation
#         pass

class Orders(BaseRepository): # Make sure BaseRepository is defined/imported
    ALLOWED_ORDER_TYPES = {'meal', 'supplement', 'gig', 'herbal', 'gadget', 'spice', 'produce'}
    ALLOWED_ORDER_STATUSES = {
        'cancelled', 'assigned', 'anyrider', 'rider_accepted', 'rider_rejected',
        'delivered', 'shipped', 'preparing', 'confirmed', 'completed', 'pending',
        'accepted', 'dispatched', 'picked up', 'delivering', 'verification needed' # Added 'verification needed'
    }
    ALLOWED_PAYMENT_STATUSES = {'failed', 'refunded', 'paid', 'pending', 'completed'}
    ALLOWED_PAYMENT_MODES = {
        'cash', 'momo', 'mobile money', 'Airtel Card', 'paypal', 'stripe',
        'debit card', 'credit card'
    }


    async def _send_order_notification(self, conn: asyncpg.Connection, user_id: str, user_type: str, order_id: str, new_status: str, notification_type: str, **kwargs):
        """
        Send order-related notification to a specific user type.

        Args:
            conn: Database connection
            user_id: User's ID (can be user_id, chefid, producer_id, transporter_id)
            user_type: Type of user ('user', 'chef', 'producer', 'transporter')
            order_id: Order ID
            new_status: New order status
            notification_type: Base notification type (e.g., 'order_created', 'order_status_changed')
            **kwargs: Additional metadata to include in the notification
        """
        try:
            # Get notification service using service accessor pattern
            notification_service = get_notification_service()
            
            # Prepare metadata for notification service
            metadata = {
                'order_id': order_id,
                'status': new_status.lower().replace(' ', '_'),  # Normalize status
                'notification_type': notification_type,
                'user_type': user_type,
                'timestamp': datetime.utcnow().isoformat(),
                **kwargs  # Include any additional metadata
            }

            # Log the notification attempt
            logger.info(f"Sending {notification_type} notification to {user_type} {user_id} for order {order_id} with status {new_status}")
            
            # Delegate all message crafting to the notification service
            asyncio.create_task(notification_service.send_notifications(
                user_ids=[str(user_id)],
                user_types=[user_type],
                notification_type=notification_type,
                metadata=metadata
            ))

        except Exception as e:
            logger.error(f"Error sending order notification to user {user_id} ({user_type}): {str(e)}", exc_info=True)

    async def _validate_product_id(self, conn: asyncpg.Connection, product_id: Union[str, int], order_type: str):
        if not product_id:
            if order_type != 'gig':
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"product_id required for {order_type} orders.")
            else:
                return
        order_type_l = order_type.lower().strip()
        table_map = {
            'meal': ('meals', 'meal_id'),
            'supplement': ('supplements', 'supplement_id'),
            'herbal': ('herbals', 'herbal_id'),
            'gadget': ('gadgets', 'gadget_id'),
            'spice': ('spices', 'spice_id'),
            'produce': ('produce', 'produce_id')
        }
        if order_type_l == 'gig':
            return
        if order_type_l not in table_map:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order_type: '{order_type}'.")
        table_name, id_column = table_map[order_type_l]
        sql = f"SELECT {id_column} FROM {table_name} WHERE {id_column}::text = $1::text"
        try:
            result = await conn.fetchval(sql, str(product_id))
            if result is None:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{order_type} with ID {product_id} not found")
        except Exception as e:
            logger.error(f"Error validating {order_type} ID {product_id}: {str(e)}", exc_info=True)
            if not isinstance(e, HTTPException):
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Error validating product: {str(e)}")
            raise
    async def create_order(self, conn: asyncpg.Connection, user_id: int, order_type: str,
                           items: Optional[List[Dict]] = None,
                           order_status: str = "pending", payment_status: str = "pending", payment_mode: str = "cash",
                           delivery_address: Optional[str] = None, notes: Optional[str] = None,
                           total_price: Optional[float] = None, amount_paid: float = 0.0,
                           product_id: Optional[Union[str, int]] = None,
                           chef_id: Optional[int] = None, producer_id: Optional[int] = None,
                           quantity: Optional[int] = None,
                           transporter_id: Optional[int] = None, transaction_id: Optional[str] = None
                           ) -> Dict[str, Any]:
        """
        Create a new order and send notification to the user.
        """
        try:
            order_type_l = str(order_type).lower().strip()
            gig_details_json: Optional[str] = None
            complementary_meals_serialized_json: Optional[str] = None
            derived_product_id = product_id
            derived_chef_id = chef_id
            derived_producer_id = producer_id
            calculated_quantity = 0
            calculated_total_price = 0.0

            if not user_id:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="user_id is required.")
            if order_type_l not in self.ALLOWED_ORDER_TYPES:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order_type: '{order_type}'.")
            if not items or not isinstance(items, list) or len(items) == 0:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="items list cannot be empty.")

            first_item = items[0]
            try:
                if order_type_l == 'gig':
                    gig_details = first_item.get('gig_details', {})
                    if not gig_details or not isinstance(gig_details, dict):
                        raise ValueError("Valid gig_details dictionary required within items for gig orders.")
                    gig_details_json = json.dumps(gig_details)
                    derived_product_id = None # Gigs don't have a product_id in the traditional sense
                    derived_chef_id = first_item.get('chef_id', chef_id)
                    derived_producer_id = first_item.get('producer_id', producer_id)
                    calculated_quantity = first_item.get('quantity', 1) # Default to 1 if not provided
                    calculated_total_price = float(first_item.get('price', 0.0)) * calculated_quantity
                else:
                    item_product_id = first_item.get('product_id')
                    if not derived_product_id and item_product_id:
                        derived_product_id = item_product_id
                    if not derived_product_id:
                        raise ValueError(f"product_id is required for order_type '{order_type_l}', either directly or in items.")
                    await self._validate_product_id(conn, derived_product_id, order_type_l)

                    derived_chef_id = first_item.get('chef_id', derived_chef_id)
                    derived_producer_id = first_item.get('producer_id', derived_producer_id)
                    calculated_quantity = int(first_item.get('quantity', 1)) # Default to 1
                    item_price = float(first_item.get('price', 0.0))
                    calculated_total_price = item_price * calculated_quantity

                    complementary_meals_data = first_item.get('bestservedwith')
                    if complementary_meals_data:
                        if not isinstance(complementary_meals_data, list):
                            raise ValueError("'bestservedwith' must be a list of objects.")
                        try:
                            complementary_meals_serialized_json = json.dumps(complementary_meals_data)
                            logger.debug(f"Serialized complementary_meals: {complementary_meals_serialized_json}")
                        except TypeError as e:
                            logger.error(f"Failed to serialize complementary_meals data: {complementary_meals_data}", exc_info=True)
                            raise ValueError(f"Invalid data in 'bestservedwith', cannot serialize to JSON: {e}")

                final_total_price = total_price if total_price is not None else calculated_total_price
                final_quantity = quantity if quantity is not None else calculated_quantity
                order_status_l = str(order_status).lower().strip()
                payment_status_l = str(payment_status).lower().strip()
                payment_mode_l = str(payment_mode).lower().strip()

                if order_status_l not in self.ALLOWED_ORDER_STATUSES:
                    raise ValueError(f"Invalid order_status: '{order_status}'. Allowed: {self.ALLOWED_ORDER_STATUSES}")
                if payment_status_l not in self.ALLOWED_PAYMENT_STATUSES:
                    raise ValueError(f"Invalid payment_status: '{payment_status}'. Allowed: {self.ALLOWED_PAYMENT_STATUSES}")

                is_airtel = payment_mode_l == 'airtel card'
                if not is_airtel and payment_mode_l not in self.ALLOWED_PAYMENT_MODES:
                    raise ValueError(f"Invalid payment_mode: '{payment_mode}'. Allowed: {self.ALLOWED_PAYMENT_MODES}")
                if is_airtel:
                    payment_mode_l = 'Airtel Card' # Normalize

                delivery_address_s = delivery_address or "Not specified"
                notes_s = notes or "No special instructions"
                price_f = float(final_total_price)
                paid_f = float(amount_paid)
                qty_i = int(final_quantity)
                user_id_i = int(user_id)
                prod_id_s = str(derived_product_id) if derived_product_id is not None else None
                chef_id_i = int(derived_chef_id) if derived_chef_id is not None else None
                producer_id_i = int(derived_producer_id) if derived_producer_id is not None else None
                transporter_id_i = int(transporter_id) if transporter_id is not None else None

            except (ValueError, TypeError, KeyError) as e:
                logger.warning(f"Invalid order data provided: {e}. Payload: {items}", exc_info=True)
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order data: {e}") from e
            except json.JSONDecodeError as e:
                logger.warning(f"Invalid JSON in gig_details: {e}. Payload: {items}", exc_info=True)
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid JSON format in gig_details: {e}") from e
            except HTTPException: # Re-raise specific HTTP exceptions
                raise
            except Exception as e: # Catch other unexpected errors
                logger.error(f"Unexpected error processing order data: {e}", exc_info=True)
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Server error processing order data: {e}") from e

            sql = """
                INSERT INTO orders (
                    user_id, order_type, product_id, chef_id, producer_id, transporter_id,
                    order_date, delivery_address, order_status, total_price, notes,
                    payment_status, payment_mode, amount_paid, transaction_id, quantity,
                    gig_details, complementary_meals
                )
                VALUES ($1,$2,$3,$4,$5,$6, NOW(), $7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
                RETURNING order_id
            """
            params: Tuple[Any, ...] = (
                user_id_i, order_type_l, prod_id_s, chef_id_i, producer_id_i, transporter_id_i,
                delivery_address_s, order_status_l, price_f, notes_s, payment_status_l,
                payment_mode_l, paid_f, transaction_id, qty_i, gig_details_json,
                complementary_meals_serialized_json
            )
            order_id = await self._execute_query(conn, sql, params, returning_id_column='order_id')

            if order_id:
                logger.info(f"Order created successfully for user {user_id_i} with order_id {order_id}")
                
                # Send notification to user
                await self._send_order_notification(
                    conn=conn,
                    user_id=str(user_id_i),
                    user_type='user',
                    order_id=str(order_id),
                    new_status=order_status_l,
                    notification_type='order_created',
                    order_type=order_type
                )
                
                # Send notification to chef if exists
                if chef_id_i is not None:
                    await self._send_order_notification(
                        conn=conn,
                        user_id=str(chef_id_i),
                        user_type='chef',
                        order_id=str(order_id),
                        new_status=order_status_l,
                        notification_type='order_created',
                        order_type=order_type
                    )
                    
                # Send notification to producer if exists
                if producer_id_i is not None:
                    await self._send_order_notification(
                        conn=conn,
                        user_id=str(producer_id_i),
                        user_type='producer',
                        order_id=str(order_id),
                        new_status=order_status_l,
                        notification_type='order_created',
                        order_type=order_type
                    )
                
                return {"message": "Order created", "order_id": order_id, "chef_id": derived_chef_id, "producer_id": derived_producer_id, "success": True}
            else:
                logger.error(f"Order creation attempt failed for user {user_id_i} (no ID returned).")
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Order creation failed unexpectedly (no ID returned).")

        except Exception as e: # Catch-all for other exceptions like DB connection issues
            logger.error(f"Error creating order for user {user_id}: {str(e)}", exc_info=True)
            if not isinstance(e, HTTPException): # Avoid re-wrapping HTTPExceptions
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"An unexpected error occurred: {str(e)}")
            raise

    async def read_orders(self, conn: asyncpg.Connection, order_id=None, chef_id=None, producer_id=None, user_id=None, transporter_id=None) -> List[Dict[str, Any]]:
        logger.info(f"Reading orders with criteria: order_id={order_id}, chef_id={chef_id}, producer_id={producer_id}, user_id={user_id}, transporter_id={transporter_id}")
        sql = """
            WITH MealDetails AS ( SELECT m.meal_id::text, m.meal_name, COALESCE(STRING_AGG(DISTINCT p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients FROM meals m LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id LEFT JOIN produce p ON mi.produce_id = p.produce_id GROUP BY m.meal_id, m.meal_name ),
                 SupplementDetails AS ( SELECT supplement_id::text, supplement_name AS product_name FROM supplements ), HerbalDetails AS ( SELECT herbal_id::text, herbal_name AS product_name FROM herbals ), GadgetDetails AS ( SELECT gadget_id::text, gadget_name AS product_name FROM gadgets ), SpiceDetails AS ( SELECT spice_id::text, spice_name AS product_name FROM spices ), ProduceDetails AS ( SELECT produce_id::text, produce_name AS product_name FROM produce )
            SELECT
                o.order_id, o.user_id, o.order_type, o.product_id, o.chef_id, o.producer_id, o.transporter_id,
                o.order_date, o.delivery_address, o.order_status, o.total_price, o.notes,
                o.payment_status, o.payment_mode, o.amount_paid, o.transaction_id, o.quantity,
                o.gig_details, o.complementary_meals,
                o.updated_at, -- Ensure this column exists in your 'orders' table
                COALESCE( md.meal_name, supd.product_name, hd.product_name, gd.product_name, sd.product_name, prod.product_name, CASE WHEN o.order_type = 'gig' THEN o.gig_details->>'gig_type' ELSE 'Unknown Product' END ) AS product_name,
                md.ingredients, producer.name AS producer_name, producer.location AS producer_address, chef.name AS chef_name, chef.location AS chef_address, transporter.name AS transporter_name, COALESCE(chef.location, producer.location, '') AS pickup_location
            FROM orders o
            LEFT JOIN MealDetails md ON o.product_id = md.meal_id AND o.order_type = 'meal'
            LEFT JOIN SupplementDetails supd ON o.product_id = supd.supplement_id AND o.order_type = 'supplement'
            LEFT JOIN HerbalDetails hd ON o.product_id = hd.herbal_id AND o.order_type = 'herbal'
            LEFT JOIN GadgetDetails gd ON o.product_id = gd.gadget_id AND o.order_type = 'gadget'
            LEFT JOIN SpiceDetails sd ON o.product_id = sd.spice_id AND o.order_type = 'spice'
            LEFT JOIN ProduceDetails prod ON o.product_id = prod.produce_id AND o.order_type = 'produce'
            LEFT JOIN producers producer ON o.producer_id = producer.producer_id
            LEFT JOIN chefs chef ON o.chef_id = chef.chefid -- Make sure join column 'chef.chefid' is correct
            LEFT JOIN transporters transporter ON o.transporter_id = transporter.transporter_id
            WHERE 1=1
        """
        params_list: List[Any] = []
        param_index = 1
        def _safe_int(val, field_name="ID"): # Helper nested function
            if val is None: return None
            try: return int(val)
            except (ValueError, TypeError):
                logger.warning(f"Invalid integer format for filter '{field_name}': '{val}'.")
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid format for {field_name}: '{val}'. Expected an integer.")
        try:
            if order_id is not None:
                sql += f" AND o.order_id = ${param_index}"
                params_list.append(_safe_int(order_id, "order_id"))
                param_index += 1
            if chef_id is not None:
                sql += f" AND o.chef_id = ${param_index}"
                params_list.append(_safe_int(chef_id, "chef_id"))
                param_index += 1
            if producer_id is not None:
                sql += f" AND o.producer_id = ${param_index}"
                params_list.append(_safe_int(producer_id, "producer_id"))
                param_index += 1
            if user_id is not None:
                sql += f" AND o.user_id = ${param_index}"
                params_list.append(_safe_int(user_id, "user_id"))
                param_index += 1
            if transporter_id is not None:
                sql += f" AND o.transporter_id = ${param_index}"
                params_list.append(_safe_int(transporter_id, "transporter_id"))
                param_index += 1

            sql += " ORDER BY o.order_date DESC"
            params_tuple = tuple(params_list)
            results = await self._execute_query(conn, sql, params_tuple, fetch_all=True)

            if not results:
                logger.info("No orders found matching criteria.")
                return []

            processed_results: List[Dict[str, Any]] = []
            for order_record in results:
                processed_order = dict(order_record) # Convert asyncpg.Record to dict
                for key, value in processed_order.items():
                    if isinstance(value, (datetime, date)) and value is not None:
                        processed_order[key] = value.isoformat()
                    # gig_details and complementary_meals might be JSON strings from DB,
                    # try to parse them if they are not None
                    if key in ['gig_details', 'complementary_meals'] and isinstance(value, str):
                        try:
                            processed_order[key] = json.loads(value)
                        except json.JSONDecodeError:
                            logger.warning(f"Failed to parse JSON for {key} in order {processed_order.get('order_id')}")
                            # Keep as string or set to None/Error, depending on desired behavior
                processed_results.append(processed_order)

            logger.info(f"Retrieved and processed {len(processed_results)} orders.")
            return processed_results

        except HTTPException: # Re-raise specific HTTP exceptions from _safe_int
            raise
        except Exception as e:
            logger.error(f"Error querying orders: {str(e)}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Error querying orders: {str(e)}")



# logger is alreay imported up there. keep this comment here


# Assume your OrdersCRUD class instance has a way to access the DB pool.
# Common patterns:
# 1. Passed in constructor:
#    class OrdersCRUD:
#        def __init__(self, db_pool: asyncpg.Pool, allowed_statuses: List[str], ...):
#            self.db_pool = db_pool
#            self.ALLOWED_ORDER_STATUSES = allowed_statuses
#
# 2. Accessed via app state (if OrdersCRUD instance has access to the FastAPI app instance or its state):
#    class OrdersCRUD:
#        def __init__(self, app_state, allowed_statuses: List[str], ...): # app_state could be app.state
#            self.app_state = app_state # and then use self.app_state.db_pool
#            self.ALLOWED_ORDER_STATUSES = allowed_statuses

    async def update_order_status(self, conn: asyncpg.Connection, order_id: int, new_status: str, transporter_id: Optional[int] = None, completion_code: Optional[str] = None) -> Dict[str, Any]:
        try:
            # ... (rest of the order fetching and initial status check logic remains IDENTICAL to your last working version) ...
            # This part is unchanged:
            order_query = """
                SELECT order_id, user_id, product_id, order_status, 
                       transporter_id, producer_id, order_type, chef_id 
                FROM orders 
                WHERE order_id = $1
            """
            order_row = await conn.fetchrow(order_query, order_id)

            if not order_row:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

            order = dict(order_row)
            original_status = order.get('order_status', '').lower().strip()
            # ... (user_id, meal_id parsing, final_status check ... all identical)

            current_status_from_db = order.get('order_status') 
            final_statuses = ['completed', 'delivered', 'complete'] 
            if current_status_from_db and current_status_from_db.lower() in final_statuses:
                logger.warning(f"Attempted to update order {order_id} which is already in final state: '{current_status_from_db}'. Ignoring update.")
                return {
                    "message": f"Order {order_id} is already in a final state ('{current_status_from_db}') and cannot be updated.", 
                    "success": True, 
                    "order_id": order_id, 
                    "status": current_status_from_db
                }

            original_order_id = order.get('order_id')
            # ... (original_order_id check, new_status_l validation against self.ALLOWED_ORDER_STATUSES ... all identical)
            if original_order_id is None: 
                logger.error(f"Fetched order for ID {order_id} is missing 'order_id' field.")
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal error processing order data.")

            new_status_l = str(new_status).lower().strip()
            if new_status_l not in self.ALLOWED_ORDER_STATUSES: # Assumes self.ALLOWED_ORDER_STATUSES is defined
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid status: '{new_status}'. Allowed: {', '.join(self.ALLOWED_ORDER_STATUSES)}")


            status_to_update = new_status_l
            # ... (completion code logic IDENTICAL) ...
            if new_status_l in ['completed', 'delivered', 'complete']:
                if completion_code is None: 
                    status_to_update = 'verification needed'
                    logger.info(f"Order {original_order_id}: Setting status to 'verification needed'. Checking/Generating completion code.")
                    existing_code = await conn.fetchval("SELECT completion_code FROM order_completions WHERE order_id = $1", original_order_id)
                    if existing_code is None:
                        generated_code = ''.join(random.choices(string.digits, k=6))
                        user_id_for_completion = order.get('user_id')
                        producer_id_for_completion = order.get('producer_id')
                        transporter_id_for_completion = order.get('transporter_id')
                        chef_id_for_completion = order.get('chef_id')

                        if user_id_for_completion is not None:
                            insert_sql = """
                                INSERT INTO order_completions (order_id, user_id, producer_id, transporter_id, chefid, completion_code)
                                VALUES ($1, $2, $3, $4, $5, $6)
                            """
                            try:
                                await conn.execute(insert_sql, original_order_id, user_id_for_completion, producer_id_for_completion, 
                                                   transporter_id_for_completion, chef_id_for_completion, generated_code)
                                logger.info(f"Completion code generated and stored for Order ID: {original_order_id}")
                            except asyncpg.PostgresError as e:
                                logger.error(f"DB error storing completion code for Order ID {original_order_id}: {e}", exc_info=True)
                            # Removed generic Exception catch here to avoid masking PostgresError above it
                        else:
                            logger.warning(f"Cannot store completion code for Order ID {original_order_id}: missing user_id.")
                else: 
                    logger.info(f"Order {original_order_id}: Attempting verification with provided code.")
                    stored_code = await conn.fetchval("SELECT completion_code FROM order_completions WHERE order_id = $1", original_order_id)
                    if stored_code and stored_code == completion_code:
                        status_to_update = new_status_l 
                        logger.info(f"Order {original_order_id}: Verification successful. Status set to '{status_to_update}'.")
                    else:
                        logger.warning(f"Order {original_order_id}: Verification failed. Invalid or missing completion code. Provided: '{completion_code}', Stored: '{stored_code}'")
                        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or missing completion code for verification.")
            
            # ... (database update logic IDENTICAL) ...
            update_fields = ["order_status = $1", "updated_at = NOW()"]
            params_update: List[Any] = [status_to_update]
            current_param_idx = 2 

            if status_to_update in ['assigned', 'picked up', 'delivering'] and transporter_id is not None:
                try:
                    t_id = int(transporter_id)
                    update_fields.append(f"transporter_id = ${current_param_idx}")
                    params_update.append(t_id)
                    current_param_idx += 1
                except (ValueError, TypeError):
                    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid transporter_id format: '{transporter_id}'. Must be an integer.")
            elif status_to_update == 'assigned' and transporter_id is None:
                 raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="transporter_id is required when setting status to 'assigned'.")

            params_update.append(original_order_id)
            
            sql_update = f"""
                UPDATE orders 
                SET {', '.join(update_fields)} 
                WHERE order_id = ${current_param_idx} 
                  AND order_status IS DISTINCT FROM $1 
                RETURNING order_id
            """
            status_actually_changed = False
            try:
                update_executed_result = await conn.fetchrow(sql_update, *params_update)
                if update_executed_result:
                    status_actually_changed = True
                    # ... (logging and notification logic IDENTICAL) ...
                    log_msg = f"Order {original_order_id} status updated to '{status_to_update}'"
                    if transporter_id is not None and status_to_update in ['assigned', 'picked up', 'delivering']:
                        log_msg += f" with transporter {transporter_id}"
                    logger.info(log_msg)
                else:
                    logger.info(f"Order {original_order_id} status is already '{status_to_update}'. No database change made.")

                user_id_to_notify = order.get('user_id')
                chef_id_to_notify = order.get('chef_id')
                producer_id_to_notify = order.get('producer_id')
                transporter_id_for_notification = transporter_id if status_to_update == 'assigned' and transporter_id is not None else order.get('transporter_id')
                
                current_order_type = order.get('order_type', 'order')
                base_notification_type = 'order_assigned' if status_to_update.lower() == 'assigned' else 'order_status_changed'
                
                try: # Assumes self._send_order_notification is defined in your class
                    if user_id_to_notify:
                        await self._send_order_notification(conn, str(user_id_to_notify), 'user', str(original_order_id), status_to_update, base_notification_type, order_type=current_order_type)
                    if chef_id_to_notify:
                        await self._send_order_notification(conn, str(chef_id_to_notify), 'chef', str(original_order_id), status_to_update, base_notification_type, order_type=current_order_type)
                    if producer_id_to_notify:
                        await self._send_order_notification(conn, str(producer_id_to_notify), 'producer', str(original_order_id), status_to_update, base_notification_type, order_type=current_order_type)
                    if transporter_id_for_notification:
                        await self._send_order_notification(conn, str(transporter_id_for_notification), 'transporter', str(original_order_id), status_to_update, base_notification_type, order_type=current_order_type)
                except Exception as e:
                    logger.error(f"Error sending notifications for order {original_order_id}: {str(e)}", exc_info=True)

            except asyncpg.PostgresError as e:
                logger.error(f"Database error updating order {original_order_id} status: {str(e)}", exc_info=True)
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to update order status: {str(e)}")
            
            # Calorie Logging Logic
            if current_order_type == 'meal':
                if status_actually_changed:
                    completion_statuses_for_calories = ['completed', 'delivered', 'complete']
                    was_completed_before = original_status in completion_statuses_for_calories
                    is_completed_now = status_to_update in completion_statuses_for_calories
                    
                    if is_completed_now and not was_completed_before:
                        logger.info(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}) transitioned from '{original_status}' to '{status_to_update}' - triggering calorie logging.")
                        # THE KEY CHANGE: No 'conn' is passed here.
                        # _log_calories_with_error_handling will acquire its own connection.
                        asyncio.create_task(self._log_calories_with_error_handling(original_order_id))
                    # ... (else debug logging for no calorie logging needed ... IDENTICAL)
                    else:
                        logger.debug(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}): No calorie logging needed. Transition: '{original_status}' -> '{status_to_update}'. Was completed: {was_completed_before}, Is now completed: {is_completed_now}. Status actually changed: {status_actually_changed}")

                # ... (else debug logging for status not changed ... IDENTICAL)
                else:
                    logger.debug(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}): Status did not actually change in DB. Skipping calorie logging trigger.")
            # ... (else debug logging for not a meal order ... IDENTICAL)
            else:
                 logger.debug(f"[INTERNAL] Order {original_order_id} is type '{current_order_type}', not 'meal'. Skipping calorie logging.")
            
            # ... (return statement IDENTICAL) ...
            return {
                "message": f"Order {original_order_id} status updated to '{status_to_update}'", 
                "success": True,
                "order_id": original_order_id,
                "status": status_to_update
            }

        except HTTPException:
            raise
        except Exception as e: # Catch-all for unexpected errors during the main request handling
            logger.error(f"Error updating order status for order_id {order_id}: {str(e)}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"An unexpected error occurred: {str(e)}")

    # This method is part of your existing Orders class
# Ensure these imports are at the top of your Python file:
# import asyncio
# import asyncpg
# import json
# import logging
# from typing import Any, Dict, List, Optional
# from fastapi import HTTPException, status
# from meal_algorithm4 import MealRecommendation4

# logger = logging.getLogger(__name__) # Assuming logger is set up

# This line assumes 'db_pool' is a global variable accessible in this module's scope
# (as defined in your backend startup code snippet).
# If 'Orders' class is in a different file, you'd need to import db_pool:
# from your_main_app_file import db_pool # Or wherever db_pool is defined

    async def _log_calories_with_error_handling(self, order_id: int):
        """
        Wrapper for log_meal_calories to be used with asyncio.create_task.
        Acquires its own database connection from the global 'db_pool'.
        """
        # Access the global db_pool directly.
        # Ensure 'db_pool' is in the scope where this method is defined,
        # or import it if it's in another module.
        # For example, if your Orders class is in 'orders_repo.py' and db_pool is in 'main.py':
        # At the top of 'orders_repo.py', you might have: from main import db_pool

        global db_pool # If db_pool is defined in the same file and is global.
                       # If imported, this 'global' keyword is not needed here.

        if db_pool is None:
            logger.error(f"[INTERNAL TASK] Global 'db_pool' is None for order {order_id}. Cannot log calories. Ensure the pool is initialized and accessible.")
            return

        new_conn = None
        try:
            logger.info(f"[INTERNAL TASK] Attempting to log calories for order {order_id} via _log_calories_with_error_handling using connection from global db_pool.")
            async with db_pool.acquire() as new_conn: # Acquire connection from the global pool
                async with new_conn.transaction():
                    # self.log_meal_calories is called with the NEWLY ACQUIRED connection
                    success = await self.log_meal_calories(new_conn, order_id)
            
            if success:
                logger.info(f"[INTERNAL TASK] Calorie logging task successfully processed for order {order_id}.")
            else:
                logger.warning(f"[INTERNAL TASK] Calorie logging task processed but indicated failure for order {order_id}.")
        
        except asyncpg.PostgresError as db_err:
            logger.error(f"[INTERNAL TASK] Database error during calorie logging for order {order_id}: {str(db_err)}", exc_info=True)
        except Exception as e:
            logger.error(f"[INTERNAL TASK] Unhandled error during calorie logging for order {order_id}: {str(e)}", exc_info=True)

    # NO CHANGES to update_order_status or log_meal_calories methods from the last version.
    # They were:
    # async def update_order_status(self, conn: asyncpg.Connection, order_id: int, ...):
    #     ...
    #     # When calling the background task:
    #     # asyncio.create_task(self._log_calories_with_error_handling(original_order_id)) # No conn passed
    #     ...
    #
    # async def log_meal_calories(self, conn: asyncpg.Connection, order_id: int) -> bool:
    #     # This method's internals are fine, it expects a valid conn.
    #     ...
    # log_meal_calories remains structurally the same, as it's designed to work with any valid connection.
    # The crucial part is that the connection it receives is now valid for its own execution context.
    async def log_meal_calories(self, conn: asyncpg.Connection, order_id: int) -> bool:
        """Logs calories for a completed meal order using order_id. Receives a dedicated connection."""
        try:
            logger.info(f"log_meal_calories: Starting for order {order_id} with provided connection.")
            order_query = "SELECT user_id, product_id, order_type FROM orders WHERE order_id = $1"
            order_row = await conn.fetchrow(order_query, order_id)

            if not order_row:
                logger.error(f"log_meal_calories: Order {order_id} not found in orders table.")
                return False
            
            if order_row['order_type'] != 'meal':
                logger.warning(f"log_meal_calories: Order {order_id} is type '{order_row['order_type']}', not 'meal'. Skipping calorie logging.")
                return False

            user_id = order_row['user_id']
            meal_id = order_row['product_id']

            if not user_id or not meal_id:
                logger.error(f"log_meal_calories: Missing user_id ({user_id}) or meal_id ({meal_id}) for order {order_id}.")
                return False
            
            logger.debug(f"log_meal_calories: Order {order_id} (type: meal) - User ID: {user_id}, Meal ID (Product ID): {meal_id}")

            from meal_algorithm4 import MealRecommendation4 
            
            recommender = MealRecommendation4(1) # As per your original
            logger.debug(f"log_meal_calories: Calculating calories for meal_id {meal_id} (order {order_id}).")
            
            meal_data = await recommender.calculate_meal_calories(str(meal_id)) 
            
            if not meal_data:
                logger.error(f"log_meal_calories: Failed to calculate calories for meal_id {meal_id} (order {order_id}). meal_data is empty.")
                return False

            calories_value_for_log = meal_data.get('calories', 'N/A')
            logger.debug(f"log_meal_calories: Calculated meal_data for meal_id {meal_id}. Calories: {calories_value_for_log}.")

            history_sql = """
                INSERT INTO calories_history (user_id, meal_id, calories, logged_at) 
                VALUES ($1, $2, $3::jsonb, CURRENT_TIMESTAMP)
            """
            await conn.execute(history_sql, user_id, str(meal_id), json.dumps(meal_data))
            logger.info(f"log_meal_calories: Successfully logged nutritional information for meal_id {meal_id} (order {order_id}) by user {user_id}.")
            return True

        except ImportError: # Specific error for import
            logger.error(f"log_meal_calories: Failed to import MealRecommendation4 for order {order_id}. Ensure 'meal_algorithm4.py' is accessible.", exc_info=True)
            return False
        except asyncpg.PostgresError as db_err: # Specific catch for DB errors within this function
            logger.error(f"log_meal_calories: Database error for order {order_id}: {str(db_err)}", exc_info=True)
            return False
        except Exception as e: # General catch for other errors in this function
            logger.error(f"log_meal_calories: Error logging meal calories for order {order_id}: {str(e)}", exc_info=True)
            return False
            

    async def delete_order(self, conn: asyncpg.Connection, order_id: int) -> Dict[str, Any]:
        try:
            order_id_i = int(order_id) # Ensure it's an int
        except (ValueError, TypeError):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid order_id format: '{order_id}'. Must be an integer.")

        sql = "DELETE FROM orders WHERE order_id = $1 RETURNING order_id"
        params = (order_id_i,)
        deleted_id = await self._execute_query(conn, sql, params, fetch_val=True) # Assumes fetch_val returns the value of the first column of the first row, or None

        if deleted_id == order_id_i:
            logger.info(f"Order {order_id_i} deleted successfully.")
            return {"message": f"Order {order_id_i} deleted", "success": True}
        else: # This means RETURNING order_id did not return the expected ID, implying row was not found or not deleted
            logger.warning(f"Attempted to delete order_id: {order_id_i}, but it was not found or not deleted.")
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Order {order_id_i} not found or could not be deleted.")
        
# --- Disbursements Class ---
class Disbursements(BaseRepository):
    # Methods updated to accept 'conn'
    async def list_chef_disbursements(self, conn: asyncpg.Connection, chef_id: Optional[int] = None, order_id: Optional[int] = None):
        query = "SELECT * FROM chef_disbursements WHERE TRUE"; params = []
        idx = 1
        if chef_id is not None: query += f" AND chef_id = ${idx}"; params.append(chef_id); idx+=1
        if order_id is not None: query += f" AND order_id = ${idx}"; params.append(order_id); idx+=1
        return await self._execute_query(conn, query, tuple(params), fetch_all=True)

    async def list_producer_disbursements(self, conn: asyncpg.Connection, producer_id: Optional[int] = None, order_id: Optional[int] = None):
        query = "SELECT * FROM producer_disbursements WHERE TRUE"; params = []
        idx = 1
        if producer_id is not None: query += f" AND producer_id = ${idx}"; params.append(producer_id); idx+=1
        if order_id is not None: query += f" AND order_id = ${idx}"; params.append(order_id); idx+=1
        return await self._execute_query(conn, query, tuple(params), fetch_all=True)

    async def list_transporter_disbursements(self, conn: asyncpg.Connection, transporter_id: Optional[int] = None, order_id: Optional[int] = None):
        query = "SELECT * FROM transporter_disbursements WHERE TRUE"; params = []
        idx = 1
        if transporter_id is not None: query += f" AND transporter_id = ${idx}"; params.append(transporter_id); idx+=1
        if order_id is not None: query += f" AND order_id = ${idx}"; params.append(order_id); idx+=1
        return await self._execute_query(conn, query, tuple(params), fetch_all=True)

    async def list_stakeholder_disbursements(self, conn: asyncpg.Connection, stakeholder_id: Optional[int] = None, order_id: Optional[int] = None):
        query = "SELECT * FROM stakeholder_disbursements WHERE TRUE"; params = []
        idx = 1
        if stakeholder_id is not None: query += f" AND stakeholder_id = ${idx}"; params.append(stakeholder_id); idx+=1
        if order_id is not None: query += f" AND order_id = ${idx}"; params.append(order_id); idx+=1
        return await self._execute_query(conn, query, tuple(params), fetch_all=True)

    async def update_chef_disbursement(self, conn: asyncpg.Connection, disbursement_id: int, updates: dict, chef_id: Optional[int] = None):
        set_parts = ["updated_at = NOW()"]
        params = []
        idx = 1
        # Build SET clauses dynamically, using COALESCE only if necessary/desired
        allowed_update_fields = ['chef_id','order_id','order_type','amount','disbursement_transaction_status','order_transaction_status']
        for field in allowed_update_fields:
            if field in updates:
                 set_parts.append(f"{field} = ${idx}")
                 params.append(updates[field])
                 idx += 1
        if not set_parts: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields to update.")

        query = f"UPDATE chef_disbursements SET {', '.join(set_parts)} WHERE id = ${idx}"
        params.append(disbursement_id)
        idx += 1
        if chef_id is not None:
            query += f" AND chef_id = ${idx}"
            params.append(chef_id)
        await self._execute_query(conn, query, tuple(params))

    # Repeat update pattern for Producer, Transporter, Stakeholder...
    async def update_producer_disbursement(self, conn: asyncpg.Connection, disbursement_id: int, updates: dict, producer_id: Optional[int] = None):
        set_parts=["updated_at=NOW()"]; params=[]; idx=1; allowed=['producer_id','order_id','order_type','amount','disbursement_transaction_status','order_transaction_status']
        for f in allowed:
            if f in updates: set_parts.append(f"{f}=${idx}"); params.append(updates[f]); idx+=1
        if len(set_parts)<=1: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        query=f"UPDATE producer_disbursements SET {','.join(set_parts)} WHERE id=${idx}"; params.append(disbursement_id); idx+=1
        if producer_id is not None: query+=f" AND producer_id=${idx}"; params.append(producer_id)
        await self._execute_query(conn, query, tuple(params))

    async def update_transporter_disbursement(self, conn: asyncpg.Connection, disbursement_id: int, updates: dict, transporter_id: Optional[int] = None):
        set_parts=["updated_at=NOW()"]; params=[]; idx=1; allowed=['transporter_id','order_id','order_type','amount','disbursement_transaction_status','order_transaction_status']
        for f in allowed:
            if f in updates: set_parts.append(f"{f}=${idx}"); params.append(updates[f]); idx+=1
        if len(set_parts)<=1: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        query=f"UPDATE transporter_disbursements SET {','.join(set_parts)} WHERE id=${idx}"; params.append(disbursement_id); idx+=1
        if transporter_id is not None: query+=f" AND transporter_id=${idx}"; params.append(transporter_id)
        await self._execute_query(conn, query, tuple(params))

    async def update_stakeholder_disbursement(self, conn: asyncpg.Connection, disbursement_id: int, updates: dict, stakeholder_id: Optional[int] = None):
        set_parts=["updated_at=NOW()"]; params=[]; idx=1; allowed=['stakeholder_id','order_id','order_type','amount','disbursement_transaction_status','order_transaction_status']
        for f in allowed:
            if f in updates: set_parts.append(f"{f}=${idx}"); params.append(updates[f]); idx+=1
        if len(set_parts)<=1: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields.")
        query=f"UPDATE stakeholder_disbursements SET {','.join(set_parts)} WHERE id=${idx}"; params.append(disbursement_id); idx+=1
        if stakeholder_id is not None: query+=f" AND stakeholder_id=${idx}"; params.append(stakeholder_id)
        await self._execute_query(conn, query, tuple(params))

    # --- Insert Methods ---
    async def insert_chef_disbursement(self, conn: asyncpg.Connection, chef_id: int, order_data: dict):
        query = "INSERT INTO chef_disbursements (chef_id,order_id,order_type,amount,disbursement_transaction_status,order_transaction_status,created_at) VALUES ($1,$2,$3,$4,$5,$6,NOW()) RETURNING id"
        params = (chef_id, order_data.get('order_id'), order_data.get('order_type'), order_data.get('amount'), order_data.get('disbursement_transaction_status'), order_data.get('order_transaction_status'),)
        return await self._execute_query(conn, query, params, returning_id_column='id')

    async def insert_producer_disbursement(self, conn: asyncpg.Connection, producer_id: int, order_data: dict):
        query = "INSERT INTO producer_disbursements (producer_id,order_id,order_type,amount,disbursement_transaction_status,order_transaction_status,created_at) VALUES ($1,$2,$3,$4,$5,$6,NOW()) RETURNING id"
        params = (producer_id, order_data.get('order_id'), order_data.get('order_type'), order_data.get('amount'), order_data.get('disbursement_transaction_status'), order_data.get('order_transaction_status'),)
        return await self._execute_query(conn, query, params, returning_id_column='id')

    async def insert_transporter_disbursement(self, conn: asyncpg.Connection, transporter_id: int, order_data: dict):
        query = "INSERT INTO transporter_disbursements (transporter_id,order_id,order_type,amount,disbursement_transaction_status,order_transaction_status,created_at) VALUES ($1,$2,$3,$4,$5,$6,NOW()) RETURNING id"
        params = (transporter_id, order_data.get('order_id'), order_data.get('order_type'), order_data.get('amount'), order_data.get('disbursement_transaction_status'), order_data.get('order_transaction_status'),)
        return await self._execute_query(conn, query, params, returning_id_column='id')

    async def insert_stakeholder_disbursement(self, conn: asyncpg.Connection, stakeholder_id: int, order_data: dict):
        query = "INSERT INTO stakeholder_disbursements (stakeholder_id,order_id,order_type,amount,disbursement_transaction_status,order_transaction_status,created_at) VALUES ($1,$2,$3,$4,$5,$6,NOW()) RETURNING id"
        params = (stakeholder_id, order_data.get('order_id'), order_data.get('order_type'), order_data.get('amount'), order_data.get('disbursement_transaction_status'), order_data.get('order_transaction_status'),)
        return await self._execute_query(conn, query, params, returning_id_column='id')

# --- Calculation Logic Class (No DB interaction, remains synchronous) ---
class CalculationLogic:
    # ... (implementation unchanged) ...
    def calculate_bmi(self, weight, height):
        if not height or height == 0: return 0.0
        try: weight_f=float(weight); height_f=float(height); height_m=height_f/100.0; return round(weight_f / (height_m**2), 1) if height_m!=0 else 0.0
        except (ValueError, TypeError) as e: logger.warning(f"BMI input err: w={weight}, h={height}. {e}"); return 0.0
    def calculate_bmi_category(self, bmi):
        try: bmi_f=float(bmi)
        except: logger.warning(f"BMI value err: {bmi}"); return 'Unknown'
        if bmi_f<18.5: return 'Underweight'
        elif 18.5<=bmi_f<24.9: return 'Normal weight'
        elif 25<=bmi_f<29.9: return 'Overweight'
        else: return 'Obesity'
    def calculate_ideal_weight(self, height, sex):
        try: height_f=float(height)
        except: logger.warning(f"Ideal Weight height err: {height}"); return 0.0
        sex_lower=str(sex).strip().lower() if sex else 'unknown'; ideal_weight_kg=0.0
        if sex_lower=='male': ideal_weight_kg=50+0.91*(height_f-152)
        elif sex_lower=='female': ideal_weight_kg=45.5+0.91*(height_f-152)
        else: logger.warning(f"Unknown sex '{sex}', using average."); ideal_weight_kg=47.75+0.91*(height_f-152)
        return round(max(ideal_weight_kg, 0), 1)
    def convert_age_range_to_age(self, age_range):
        if isinstance(age_range,(int,float)): return int(age_range)
        if isinstance(age_range,str):
            try:
                if '-' in age_range: age_min,age_max=map(int,age_range.split('-')); return (age_min+age_max)//2
                else: return int(age_range)
            except: logger.warning(f"Age range parse err '{age_range}', default 30."); return 30
        else: logger.warning(f"Invalid age type '{type(age_range)}', default 30."); return 30
    def calculate_bmr(self, weight, height, age_range, sex):
        try:
            weight_f = float(weight)
            height_f = float(height)
            age = self.convert_age_range_to_age(age_range)
            sex_lower = str(sex).strip().lower() if sex else 'unknown'

            if sex_lower == 'male':
                bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) + 5
            elif sex_lower == 'female':
                bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) - 161
            else:
                logger.warning(f"Unknown sex '{sex}' BMR, using male.")
                bmr = (10 * weight_f) + (6.25 * height_f) - (5 * age) + 5

            return round(max(bmr, 0))
        except Exception as e:
            logger.warning(f"BMR calc err: w={weight},h={height},age={age_range},sex={sex}. {e}")
            return 0
    def calculate_daily_calories(self, bmr, activity_level):
        try: bmr_f=float(bmr)
        except: logger.warning(f"Invalid BMR for TDEE: {bmr}"); return 0
        act_level=str(activity_level).strip().lower().replace(" ","_") if activity_level else 'sedentary'
        mults={'sedentary':1.2,'lightly_active':1.375,'moderately_active':1.55,'very_active':1.725,'extremely_active':1.9,'extra_active':1.9}
        mult=mults.get(act_level,1.2)
        if act_level not in mults: logger.warning(f"Unknown activity '{activity_level}', using sedentary.")
        return round(bmr_f * mult)


# --- GetAllMeals Class ---
class GetAllMeals(BaseRepository):
    async def fetch_all_meals(self, conn: asyncpg.Connection):
        # ... (uses conn for _execute_query) ...
        logger.debug("Fetching all meals...")
        sql_query = """
        WITH MealDetails AS (SELECT m.* FROM meals m)
        SELECT md.*,
               COALESCE((SELECT STRING_AGG(p.produce_name, ', ') FROM meal_ingredients i JOIN produce p ON i.produce_id = p.produce_id WHERE i.meal_id = md.meal_id), '') AS ingredients,
               COALESCE((SELECT STRING_AGG(mc.meal_name, ', ') FROM meal_complementaries mc_link JOIN meals mc ON mc_link.complementary_dish_id = mc.meal_id WHERE mc_link.meal_id = md.meal_id), '') AS complementary_dishes
        FROM MealDetails md ORDER BY md.meal_id;
        """
        try:
            all_meals_list = await self._execute_query(conn, sql_query, fetch_all=True) # Pass conn
            if all_meals_list is None: raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to get meals.")
            processed = [];
            for row in all_meals_list: meal_dict=dict(row); meal_dict.setdefault('price',10000); [meal_dict.update({k:v.isoformat()}) for k,v in meal_dict.items() if isinstance(v, (datetime, date))]; processed.append(meal_dict)
            logger.info(f"Fetched {len(processed)} meals.")
            return {"All_Meals": processed, "success": True}
        except HTTPException: raise
        except Exception as e: logger.error(f"Error fetch all meals: {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Unexpected server error.")


# --- Payment Gateway Functions (Remain Synchronous) ---
# ... (configure_paypal, create_payment_paypal, execute_payment_paypal, etc. unchanged) ...
# ... (configure_stripe, create_stripe_payment, execute_stripe_payment, etc. unchanged) ...
# ... (get_momo_api_user_key, get_momo_access_token, ensure_momo_token, etc. unchanged) ...
# Initial Payment Gateway Configurations
def configure_paypal(mode: str, client_id: str, client_secret: str):
    """Configures the PayPal SDK."""
    if not client_id or not client_secret: logger.error("PayPal config failed: ID/Secret required."); return
    try: paypalrestsdk.configure({'mode': mode, 'client_id': client_id, 'client_secret': client_secret}); logger.info(f"PayPal SDK configured: {mode}")
    except Exception as e: logger.error(f"PayPal config failed: {e}", exc_info=True)

def create_payment_paypal(amount: float, description: str, currency: str = "USD") -> Dict[str, Any]:
    """Creates a PayPal payment."""
    try:
        amount_f=float(amount); assert amount_f > 0; formatted_amount="{:.2f}".format(amount_f)
        api_base_url=os.getenv('API_BASE_URL','http://localhost:5000').rstrip('/'); return_url=f"{api_base_url}/rr/execute"; cancel_url=f"{api_base_url}/rr/cancel"
        payment_details={"intent":"sale", "payer":{"payment_method":"paypal"}, "transactions":[{"amount":{"total":formatted_amount,"currency":currency.upper()},"description":description or "ZINZI Payment"}], "redirect_urls":{"return_url":return_url,"cancel_url":cancel_url}}
        payment=paypalrestsdk.Payment(payment_details)
        if payment.create():
            approval_url=next((link.href for link in payment.links if link.rel=="approval_url"), None)
            if approval_url: logger.info(f"PayPal created (ID: {payment.id})."); return {"approval_url": approval_url, "payment_id": payment.id, "success": True}
            else: logger.error(f"PayPal created (ID: {payment.id}) no approval URL."); return {"error": "Failed get approval URL.", "success": False}
        else: err=payment.error if hasattr(payment,'error') and payment.error else "Unknown"; logger.error(f"PayPal creation failed: {err}"); err_msg=err.get('message','Unknown') if isinstance(err,dict) else str(err); return {"error":f"PayPal Error: {err_msg}", "success": False}
    except paypalrestsdk.exceptions.PayPalRESTfulException as pe: logger.error(f"PayPal API Error create: {pe}"); return {"error":f"PayPal API Error: {pe}", "success": False}
    except (ValueError, AssertionError) as ve: logger.error(f"Invalid amount PayPal: {ve}"); return {"error": str(ve), "success": False}
    except Exception as e: logger.error(f"Unexpected PayPal create error: {e}", exc_info=True); return {"error":"Unexpected error.", "success": False}

def execute_payment_paypal(payment_id: str, payer_id: str) -> Dict[str, Any]:
    """Executes a PayPal payment."""
    if not payment_id or not payer_id: return {"status": "failure", "error": "payment/payer ID required."}
    try:
        payment = paypalrestsdk.Payment.find(payment_id)
        if payment.execute({"payer_id": payer_id}): logger.info(f"PayPal exec success (ID: {payment_id}), State: {payment.state}"); return {"status": "success", "payment": payment.to_dict()}
        else: err=payment.error if hasattr(payment,'error') and payment.error else "Unknown"; logger.error(f"PayPal exec fail (ID: {payment_id}): {err}"); err_msg=err.get('message','Unknown') if isinstance(err,dict) else str(err); return {"status": "failure", "error": err_msg}
    except paypalrestsdk.exceptions.ResourceNotFound: logger.error(f"PayPal exec fail: ID '{payment_id}' not found."); return {"status": "failure", "error": "Payment not found."}
    except paypalrestsdk.exceptions.PayPalRESTfulException as pe: logger.error(f"PayPal API Error exec (ID: {payment_id}): {pe}"); return {"status": "failure", "error": f"PayPal API Error: {pe}"}
    except Exception as e: logger.error(f"Unexpected PayPal exec error (ID: {payment_id}): {e}", exc_info=True); return {"status": "failure", "error": "Unexpected error."}

def handle_payment_cancellation_paypal() -> Dict[str, Any]:
    """Handles PayPal cancellation."""
    logger.info("PayPal payment cancelled by user."); return {"status": "cancelled", "message": "Payment cancelled."}

def configure_stripe(secret_key: str):
    """Configures Stripe."""
    if not secret_key: logger.warning("Stripe Key missing."); return
    try: stripe.api_key=secret_key; logger.info("Stripe API key configured.")
    except Exception as e: logger.error(f"Stripe config failed: {e}", exc_info=True)

def create_stripe_payment(amount: float, description: str = "ZINZI Payment", currency: str = "usd") -> Dict[str, Any]:
    """Creates a Stripe Payment Intent."""
    if not stripe.api_key: return {"status": "failure", "error": "Stripe not configured."}
    try:
        amount_f=float(amount); assert amount_f > 0; amount_cents=int(round(amount_f * 100))
        payment_intent=stripe.PaymentIntent.create(amount=amount_cents, currency=currency.lower(), description=description)
        logger.info(f"Stripe PI created (ID: {payment_intent.id})")
        return {"status":"success", "client_secret":payment_intent.client_secret, "intent_id":payment_intent.id}
    except stripe.error.StripeError as e: logger.error(f"Stripe API error create PI: {e}"); return {"status":"failure", "error":str(e)}
    except (ValueError, AssertionError) as ve: logger.error(f"Invalid amount Stripe: {ve}"); return {"status": "failure", "error": str(ve)}
    except Exception as e: logger.error(f"Unexpected Stripe PI create error: {e}", exc_info=True); return {"status": "failure", "error": "Unexpected error."}

def execute_stripe_payment(payment_intent_id: str, payment_method_id: Optional[str] = None) -> Dict[str, Any]:
    """Checks Stripe Payment Intent status."""
    if not stripe.api_key: return {"status": "failure", "error": "Stripe not configured."}
    if not payment_intent_id: return {"status": "failure", "error": "Intent ID required."}
    try:
        intent=stripe.PaymentIntent.retrieve(payment_intent_id); status=intent.status
        logger.info(f"Checking Stripe PI {payment_intent_id}: Status {status}")
        if status=='succeeded': logger.info(f"Stripe PI {payment_intent_id} succeeded."); return {"status":"success", "payment":intent.to_dict()}
        elif status in ('requires_action','requires_confirmation'): logger.warning(f"Stripe PI {payment_intent_id} needs client action ({status})."); return {"status":status, "client_secret":intent.client_secret, "message":f"Requires client action ({status})."}
        elif status=='processing': logger.info(f"Stripe PI {payment_intent_id} processing."); return {"status":"processing", "message":"Processing."}
        elif status=='canceled': logger.warning(f"Stripe PI {payment_intent_id} canceled."); return {"status":"failure", "message":"Canceled."}
        elif status=='requires_payment_method': logger.warning(f"Stripe PI {payment_intent_id} failed: Needs payment method."); return {"status": "failure", "message":"Failed: Needs payment method."}
        else: logger.error(f"Stripe PI {payment_intent_id} failed/unexpected status: {status}."); return {"status": "failure", "message":f"Status: {status}"}
    except stripe.error.StripeError as e: logger.error(f"Stripe API error retrieve PI {payment_intent_id}: {e}"); return {"status":"failure", "error":str(e)}
    except Exception as e: logger.error(f"Unexpected Stripe PI check error {payment_intent_id}: {e}", exc_info=True); return {"status": "failure", "error": "Unexpected error."}

def handle_stripe_payment_cancellation() -> Dict[str, Any]:
    """Handles Stripe cancellation."""
    logger.info("Stripe payment likely cancelled."); return {"status": "cancelled", "message": "Payment not completed."}

# --- MoMo Global Variables and Functions ---
MOMO_API_KEY = os.getenv("MOMO_API_KEY")
MOMO_SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")
MOMO_API_USER_ID = os.getenv("MOMO_API_USER_ID")
MOMO_BASE_URL = os.getenv("MOMO_BASE_URL", "https://sandbox.momodeveloper.mtn.com").rstrip('/')
MOMO_TARGET_ENV = os.getenv("MOMO_TARGET_ENV", "sandbox")
MOMO_CALLBACK_URL = os.getenv("MOMO_CALLBACK_URL", 'chwezicreatives.com')
momo_headers: Dict[str, str] = {}; momo_access_token: str = ""; momo_token_expires_at: int = 0

def get_momo_api_user_key(user_id: str, subscription_key: str) -> Optional[str]:
    """Generates MoMo API Key (usually done via portal)."""
    # ... (implementation unchanged) ...
    if not user_id or not subscription_key: logger.error("MoMo UserID/SubKey needed for API key gen."); return None
    url=f"{MOMO_BASE_URL}/v1_0/apiuser/{user_id}/apikey"; headers={"Ocp-Apim-Subscription-Key": subscription_key}; logger.info(f"Req MoMo API Key for user {user_id}...")
    try:
        response=requests.post(url, headers=headers, timeout=10); response.raise_for_status()
        key_info=response.json(); api_key=key_info.get("apiKey")
        if api_key: logger.info(f"Generated MoMo API Key for user {user_id}."); return api_key
        else: logger.error(f"MoMo API Key gen fail {user_id}. Resp: {response.text}"); return None
    except requests.exceptions.RequestException as e: logger.error(f"MoMo API Key gen network/API err {user_id}: {e}", exc_info=True); return None
    except json.JSONDecodeError: logger.error(f"MoMo API Key gen JSON decode err {user_id}. Resp: {response.text}"); return None
    except Exception as e: logger.error(f"Unexpected MoMo API Key gen err {user_id}: {e}", exc_info=True); return None

def get_momo_access_token() -> bool:
    """Obtains MoMo access token."""
    # ... (implementation unchanged) ...
    global momo_access_token, momo_token_expires_at, momo_headers
    if not MOMO_API_USER_ID or not MOMO_SUBSCRIPTION_KEY: logger.critical("MoMo UserID/SubKey not configured."); return False
    api_key = MOMO_API_KEY;
    if not api_key: logger.critical("MoMo API Key not configured."); return False
    url = f"{MOMO_BASE_URL}/collection/token/"; auth_str=f"{MOMO_API_USER_ID}:{api_key}"; auth_b64=base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization":f"Basic {auth_b64}", "Ocp-Apim-Subscription-Key":MOMO_SUBSCRIPTION_KEY}
    try:
        logger.info("Requesting new MoMo Token..."); response=requests.post(url, headers=headers, timeout=15); response.raise_for_status()
        token_info=response.json(); new_token=token_info.get("access_token"); expires_in=token_info.get("expires_in",3500)
        if not new_token: logger.error(f"MoMo token missing: {token_info}"); return False
        momo_access_token=new_token; momo_token_expires_at=int(time.time())+expires_in-60
        momo_headers={"Authorization":f"Bearer {momo_access_token}", "X-Reference-Id":str(uuid.uuid4()), "X-Target-Environment":MOMO_TARGET_ENV, "Ocp-Apim-Subscription-Key":MOMO_SUBSCRIPTION_KEY, "Content-Type":"application/json"}
        logger.info("Obtained MoMo Token."); return True
    except requests.exceptions.RequestException as e: logger.error(f"MoMo token network/API err: {e}", exc_info=True); return False
    except json.JSONDecodeError: logger.error(f"MoMo token JSON decode err. Resp: {response.text}"); return False
    except Exception as e: logger.error(f"Unexpected MoMo token err: {e}", exc_info=True); return False

def ensure_momo_token() -> bool:
    """Checks MoMo token validity, refreshes if needed."""
    # ... (implementation unchanged) ...
    if time.time() >= momo_token_expires_at or not momo_access_token: logger.info("MoMo token expired/missing, refreshing..."); return get_momo_access_token()
    return True


def request_momo_payment(amount: float, currency: str, external_id: str, payer_number: str, payer_message: str, payee_note: str) -> Dict[str, Any]:
    """Requests MoMo payment."""
    if not ensure_momo_token():
        return {"status": "failure", "error": "MoMo auth failed."}

    url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay"
    tx_uuid = str(uuid.uuid4())
    current_headers = {**momo_headers, "X-Reference-Id": tx_uuid}

    try:
        payload = {
            "amount": str(float(amount)),
            "currency": currency.lower(),
            "externalId": str(external_id),
            "payer": {"partyIdType": "MSISDN", "partyId": str(payer_number)},
            "payerMessage": str(payer_message),
            "payeeNote": str(payee_note),
        }
    except (ValueError, TypeError) as e:
        logger.error(f"Invalid MoMo payload data: {e}")
        return {"status": "failure", "error": "Invalid data format."}

    try:
        logger.info(f"Req MoMo Payment: ExtID={external_id}, TxRef={tx_uuid}, Amt={amount}, Payer={payer_number}")
        response = requests.post(url, json=payload, headers=current_headers, timeout=30)

        if response.status_code == 202:
            logger.info(f"MoMo Req Accepted. TxRef={tx_uuid}. Await confirm {payer_number}.")
            return {"status": "pending", "transaction_ref": tx_uuid, "message": "Awaiting confirmation."}
        else:
            err_details = response.text
            try:
                err_details = response.json()
            except:
                pass
            logger.error(f"MoMo Req Failed. Status: {response.status_code}, TxRef: {tx_uuid}, Err: {err_details}")
            return {"status": "failure", "error": err_details}

    except requests.exceptions.Timeout:
        logger.error(f"MoMo Req Timeout. TxRef: {tx_uuid}.")
        return {"status": "failure", "error": "Request timed out."}
    except requests.exceptions.RequestException as e:
        logger.error(f"MoMo Req Network/API Err. TxRef: {tx_uuid}. Err: {e}", exc_info=True)
        return {"status": "failure", "error": f"Network/API Error: {e}"}
    except Exception as e:
        logger.error(f"Unexpected MoMo Req Err. TxRef: {tx_uuid}. Err: {e}", exc_info=True)
        return {"status": "failure", "error": "Unexpected error."}
    


def check_momo_payment_status(transaction_ref: str) -> Dict[str, Any]:
    """Checks MoMo payment status."""
    if not ensure_momo_token():
        return {"status": "failure", "error": "MoMo auth failed."}
    if not transaction_ref:
        return {"status": "failure", "error": "Tx ref required."}

    url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay/{transaction_ref}"
    current_headers = momo_headers

    try:
        logger.info(f"Checking MoMo Status TxRef: {transaction_ref}")
        response = requests.get(url, headers=current_headers, timeout=15)
        response.raise_for_status()

        status_data = response.json()
        current_status = status_data.get('status', 'UNKNOWN').upper()
        logger.info(f"MoMo Status OK TxRef: {transaction_ref}. Status: {current_status}")
        return {"status": "success", "payment_status": status_data}

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            logger.warning(f"MoMo tx ref '{transaction_ref}' not found (404).")
            return {"status": "not_found", "error": "Tx ref not found."}
        else:
            err_details = e.response.text
            try:
                err_details = e.response.json()
            except:
                pass
            logger.error(f"MoMo Status HTTP Err. TxRef: {transaction_ref}, Status: {e.response.status_code}, Err: {err_details}")
            return {"status": "failure", "error": err_details}

    except requests.exceptions.Timeout:
        logger.error(f"MoMo Status Timeout. TxRef: {transaction_ref}.")
        return {"status": "failure", "error": "Status check timeout."}
    except requests.exceptions.RequestException as e:
        logger.error(f"MoMo Status Network Err. TxRef: {transaction_ref}. Err: {e}", exc_info=True)
        return {"status": "failure", "error": f"Network/API Error: {e}"}
    except json.JSONDecodeError:
        logger.error(f"MoMo Status JSON decode err. TxRef: {transaction_ref}. Resp: {response.text}")
        return {"status": "failure", "error": "Invalid response."}
    except Exception as e:
        logger.error(f"MoMo Status Unexpected Err. TxRef: {transaction_ref}. Err: {e}", exc_info=True)
        return {"status": "failure", "error": "Unexpected error."}

# --- Backend Class Instantiations ---
# These instances are created once and used by endpoints via Depends(get_db)
auth_users = AuthenticationAndUsers()
chefs_crud = Chefs()
herbals_crud = Herbals()
meals_crud = Meals()
produce_crud = Produce()
producers_crud = Producers()

@app.get('/rr/users/{user_id}/combined_metrics')
async def get_combined_metrics_endpoint(user_id: int = Path(..., gt=0), limit: int = Query(10, ge=1, le=100), conn: asyncpg.Connection = Depends(get_db)):
    """
    Get combined metrics data for a user including preferences, metrics, calories history, and weight history.
    
    Args:
        user_id: User ID to fetch metrics for
        limit: Maximum number of history records to return (default: 10, max: 100)
    """
    try:
        return await auth_users.get_combined_metrics(conn, user_id, limit)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in combined metrics endpoint: {str(e)}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected error occurred")

@app.get('/rr/users/{user_id}/calorie_history')
async def get_user_calorie_history_endpoint(user_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    """Endpoint to list calorie history for a user by ID."""
    auth_repo = AuthenticationAndUsers()
    return await auth_repo.list_calorie_history(conn, user_id)
gadgets_crud = Gadgets()
spices_crud = Spices()
stakeholders_crud = Stakeholders()
orders_crud = Orders()  # Uses the async Orders class defined in this file
transporters_crud = Transporters()
calc_logic = CalculationLogic() # Doesn't need DB
meal_fetcher = GetAllMeals()
disbursement_handler = Disbursements()
supplements_crud = Supplements()
disbursement_handler = Disbursements()
supplements_crud = Supplements()


@app.get('/rr') #also used by my health status checking server o see if servr is up and okay
@alru_cache(maxsize=1)
async def welcome():
    """Welcome endpoint."""
    return {'message': 'Welcome to ZINZI.'} # Updated name

@app.get("/favicon.ico", include_in_schema=False)
async def get_favicon():
    return FileResponse("static/favicon.ico")

# === USER Endpoints ===
@app.post('/rr/signup_user', status_code=status.HTTP_201_CREATED)
async def signup_user_endpoint(user_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    try:
        name=user_data['name']; email=user_data['email']; password=user_data['password']; image=user_data.get('image')
        user_info = await auth_users.create_user(conn, {'Name': name, 'Email': email, 'Password': password, 'Image': image}) # Pass conn
        return {'message':'User registered. Verify email.', 'user_id': user_info['user_id']}
    except KeyError as ke:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f'Missing field: {ke}')

@app.post('/rr/verify_user')
async def verify_user_endpoint(verification_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    try:
        user_id=int(verification_data['user_id']); verification_code=verification_data['verification_code']
        if not verification_code: raise ValueError("verification_code required")
    except:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid input: user_id (int) and verification_code (str) required.')
    await auth_users.verify_user_email(conn, user_id, verification_code) # Pass conn
    return {'message': 'Email verification successful'}


@app.post("/test/log-meal-calories/{order_id}")
async def test_log_meal_calories(order_id: int, conn: asyncpg.Connection = Depends(get_db)): # Removed -> Dict[str, Any] for now to simplify if type hinting was an issue
    try:
        # Ensure 'orders_crud' is the correct instance of your class
        # that contains the 'log_meal_calories' method.
        success = await orders_crud.log_meal_calories(conn, order_id)
        if success:
            return {
                "success": True,
                "message": f"Successfully logged calories for order {order_id}"
            }
        else:
            # You might want to return a 400 or 500 status code here if it fails
            # For now, matching the previous structure:
            return {
                "success": False,
                "message": f"Failed to log calories for order {order_id}. Check logs for details."
            }
    except Exception as e:
        # logger.error(f"Error in test_log_meal_calories_endpoint for order {order_id}: {str(e)}", exc_info=True) # Assuming logger is available
        print(f"Error in test_log_meal_calories_endpoint for order {order_id}: {str(e)}") # Basic print for debugging
        raise HTTPException(
            status_code=500, # status.HTTP_500_INTERNAL_SERVER_ERROR
            detail=f"Failed to log calories: {str(e)}"
        )

@app.post('/rr/login_user')
async def login_user_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await auth_users.login_user(conn, identifier, password) # Pass conn

@app.get('/rr/rusers')
async def list_all_users_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    data = await auth_users.list_users(conn, user_id=None) # Pass conn
    return {'message': 'All users retrieved.', 'data': data or []}

@app.get('/rr/rusers/{user_id}')
async def get_user_by_id_endpoint(user_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    data = await auth_users.list_users(conn, user_id=user_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    return {'message': 'User retrieved.', 'data': data}

@app.patch('/rr/users/{user_id}')
async def update_user_endpoint(user_id: int = Path(..., gt=0), updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Endpoint to update a user by ID."""
    auth_users = AuthenticationAndUsers()
    try:
        success = await auth_users.update_user(conn, user_id, updates)
        if success:
            return {'message': f'User {user_id} updated successfully.'}
        else:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'User {user_id} not found.')
    except HTTPException:
        raise # Re-raise FastAPI HTTPExceptions
    except Exception as e:
        logger.error(f"Unexpected error updating user {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='An unexpected server error occurred.') from e

@app.delete('/rr/users/{user_id}', status_code=status.HTTP_200_OK)
async def delete_user_endpoint(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    success = await auth_users.delete_user(conn, user_id) # Pass conn
    if success: return {'message': f'User {user_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'User {user_id} not found.')

# === CHEF Endpoints ===
@app.post('/rr/signup_chef', status_code=status.HTTP_201_CREATED)
async def create_chef_endpoint(chef_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await chefs_crud.create_chef(conn, chef_data) # Pass conn

@app.post('/rr/login/chefs')
async def login_chef_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await chefs_crud.login_chef(conn, identifier, password) # Pass conn

@app.get('/rr/rchefs')
async def list_all_chefs_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await chefs_crud.list_chefs(conn, chef_id=None) # Pass conn
    return {'message': 'Chefs retrieved.', 'data': data}

@app.get('/rr/rchefs/{chef_id}')
async def get_chef_by_id_endpoint(chef_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data_list = await chefs_crud.list_chefs(conn, chef_id=chef_id) # Pass conn
    if not data_list: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Chef not found')
    return {'message': 'Chef retrieved.', 'data': data_list[0]}

@app.put('/rr/chefs/{chef_id}')
@app.patch('/rr/chefs/{chef_id}')
async def update_chef_endpoint(chef_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await chefs_crud.update_chef(conn, chef_id, updates) # Pass conn
    updated_chef_list = await chefs_crud.list_chefs(conn, chef_id=chef_id) # Pass conn
    if updated_chef_list: return {'message': 'Chef updated', 'data': updated_chef_list[0]}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Chef not found after update.')

@app.delete('/rr/chefs/{chef_id}', status_code=status.HTTP_200_OK)
async def delete_chef_endpoint(chef_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await chefs_crud.delete_chef(conn, chef_id) # Pass conn
    if success: return {'message': f'Chef {chef_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Chef {chef_id} not found.')

@app.patch('/rr/chefs/{chef_id}/status')
async def update_chef_status_endpoint(chef_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires boolean "is_active"')
    is_active = status_update['is_active']
    await chefs_crud.update_chef_status(conn, chef_id, is_active) # Pass conn
    return {'message': f'Chef {chef_id} status updated'}

#

# === New  version 4 Meal Recommendation Endpoint ---
meal_recommender = None  # Lazy-initialized meal recommender

# Global cache for meal recommendations
meal_recommenders = {}
meal_data_cache = {}

@app.get("/rr/meals2/{user_id}")
async def get_meal_recommendations(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """
    Get meal recommendations for a user.
    
    Args:
        user_id: User ID for whom to generate recommendations
    
    Returns:
        List of recommended meals
    """
    global meal_recommenders, meal_data_cache
    
    try:
        # Check if we have cached results for this user
        cache_key = f"user_{user_id}"
        if cache_key in meal_data_cache:
            cache_time, recommendations = meal_data_cache[cache_key]
            # Cache valid for 1 hour
            if datetime.now() - cache_time < timedelta(hours=1):
                return {"recommended_meals": recommendations, "success": True}
        
        # Initialize meal recommender on first request
        if user_id not in meal_recommenders:
            # Import here to avoid circular imports
            from meal_algorithm4 import MealRecommendation4
            # Preload the meal recommender at startup
            meal_recommenders[user_id] = MealRecommendation4(user_id)
        
        # Get recommendations
        recommendations = meal_recommenders[user_id].recommend_meals()
        
        # Cache the results
        meal_data_cache[cache_key] = (datetime.now(), recommendations)
        
        return {"recommended_meals": recommendations, "success": True}
        
    except Exception as e:
        logger.error(f"Error generating meal recommendations: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to generate meal recommendations")

@app.get("/rr/meal_calories/{meal_id}")
async def get_meal_calories(meal_id: str, conn: asyncpg.Connection = Depends(get_db)):
    """
    Calculate calories and nutritional information for a specific meal.
    
    Args:
        meal_id: ID of the meal to calculate calories for
    
    Returns:
        Dictionary containing:
        - calories: Total calories in the meal
        - nutritional_info: Full nutritional information
        - serving_size: Recommended serving size in grams
        - meal_name: Name of the meal
    """
    global meal_recommender
    
    try:
        # Lazy initialize the meal recommender
        if meal_recommender is None:
            from meal_algorithm4 import MealRecommendation4
            meal_recommender = MealRecommendation4(1)  # Use default user_id 1 since we only need meal info
        
        # Calculate meal calories asynchronously
        result = await meal_recommender.calculate_meal_calories(meal_id)
        
        if "error" in result:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=result["error"])
            
        return result
        
    except Exception as e:
        logger.error(f"Error calculating meal calories: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to calculate meal calories")

# === PRODUCER Endpoints ===
@app.post('/rr/aproducers', status_code=status.HTTP_201_CREATED)
async def add_producer_endpoint(producer_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await producers_crud.create_producer(conn, producer_data) # Pass conn

@app.post('/rr/login/producers')
async def login_producer_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await producers_crud.login_producer(conn, identifier, password) # Pass conn

@app.get('/rr/rproducers')
async def list_all_producers_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await producers_crud.list_producers(conn, producer_id=None) # Pass conn
    return {'message': 'Producers retrieved.', 'data': data}

@app.get('/rr/rproducers/{producer_id}')
async def get_producer_by_id_endpoint(producer_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data_list = await producers_crud.list_producers(conn, producer_id=producer_id) # Pass conn
    if not data_list: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Producer not found')
    return {'message': 'Producer retrieved.', 'data': data_list[0]}

@app.put('/rr/producers/{producer_id}')
@app.patch('/rr/producers/{producer_id}')
async def update_producer_endpoint(producer_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await producers_crud.update_producer(conn, producer_id, updates) # Pass conn
    updated_list = await producers_crud.list_producers(conn, producer_id=producer_id) # Pass conn
    if updated_list: return {'message': 'Producer updated', 'data': updated_list[0]}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Producer not found after update.')

@app.delete('/rr/producers/{producer_id}', status_code=status.HTTP_200_OK)
async def delete_producer_endpoint(producer_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await producers_crud.delete_producer(conn, producer_id) # Pass conn
    if success: return {'message': f'Producer {producer_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Producer {producer_id} not found.')

@app.patch('/rr/producers/{producer_id}/status')
async def update_producer_status_endpoint(producer_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires boolean "is_active"')
    is_active = status_update['is_active']
    await producers_crud.update_producer_status(conn, producer_id, is_active) # Pass conn
    return {'message': f'Producer {producer_id} status updated'}

# === TRANSPORTER Endpoints ===
@app.post('/rr/transporters/signup', status_code=status.HTTP_201_CREATED)
async def signup_transporter_endpoint(transporter_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await transporters_crud.create_transporter(conn, transporter_data) # Pass conn

@app.post('/rr/transporters/login')
async def login_transporter_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await transporters_crud.login_transporter(conn, identifier, password) # Pass conn

@app.get('/rr/transporters')
async def list_all_transporters_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await transporters_crud.list_transporters(conn, transporter_id=None) # Pass conn
    return {'message': 'Transporters retrieved.', 'data': data}

@app.get('/rr/transporters/{transporter_id}')
async def get_transporter_by_id_endpoint(transporter_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data_list = await transporters_crud.list_transporters(conn, transporter_id=transporter_id) # Pass conn
    if not data_list: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Transporter not found')
    return {'message': 'Transporter retrieved.', 'data': data_list[0]}

@app.put('/rr/transporters/{transporter_id}')
@app.patch('/rr/transporters/{transporter_id}')
async def update_transporter_endpoint(transporter_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await transporters_crud.update_transporter(conn, transporter_id, updates) # Pass conn
    updated_list = await transporters_crud.list_transporters(conn, transporter_id=transporter_id) # Pass conn
    if updated_list: return {'message': 'Transporter updated', 'data': updated_list[0]}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Transporter not found after update.')

@app.delete('/rr/transporters/{transporter_id}', status_code=status.HTTP_200_OK)
async def delete_transporter_endpoint(transporter_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await transporters_crud.delete_transporter(conn, transporter_id) # Pass conn
    if success: return {'message': f'Transporter {transporter_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Transporter {transporter_id} not found.')

@app.patch('/rr/transporters/{transporter_id}/status')
async def update_transporter_status_endpoint(transporter_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires boolean "is_active"')
    is_active = status_update['is_active']
    await transporters_crud.update_transporter_status(conn, transporter_id, is_active) # Pass conn
    return {'message': f'Transporter {transporter_id} status updated'}

# === STAKEHOLDER Endpoints ===

# === NOTIFICATION Endpoints ===
@app.post('/rr/notifications/tokens')
async def register_fcm_token(
    token_data: dict = Body(...),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Register or update an FCM token for a user.
    
    Args:
        token_data: {"token": str, "platform": str}
        conn: Database connection
    
    Returns:
        dict: Success message
    """
    try:
        token = token_data.get('token')
        platform = token_data.get('platform')
        user_type = token_data.get('user_type')
        user_id = token_data.get('user_id')

        if not all([token, platform, user_type, user_id]):
            raise HTTPException(status_code=400, detail="Missing required fields: token, platform, user_type, user_id")

        logger.info(f"Processing FCM token registration for user_id: {user_id}, platform: {platform}, user_type: {user_type}")
        
        # Get and initialize notification service
        notification_service = get_notification_service()
        
        # Convert user_id to integer
        user_id_int = int(user_id)
        
        # Store the token
        await notification_service.store_fcm_token(
            user_id_int,
            token,
            platform,
            user_type
        )
        
        logger.info(f"FCM token successfully registered for user_id: {user_id}")
        return {"message": "Token registered successfully"}
    except Exception as e:
        logger.error(f"Error registering FCM token: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/rr/notifications/tokens")
async def get_fcm_tokens(
    platform: Optional[str] = None,
    user_id: Optional[int] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Get FCM tokens for a user.
    
    Args:
        platform: Optional platform filter
        user_id: User's ID (integer)
        conn: Database connection
    
    Returns:
        List[dict]: List of FCM tokens
    """
    try:
        if not user_id:
            raise HTTPException(status_code=400, detail="user_id is required")
            
        # Get notification service
        notification_service = get_notification_service()
        
        tokens = await notification_service.get_fcm_tokens(conn, user_id, platform)
        return tokens
    except Exception as e:
        logger.error(f"Error getting FCM tokens: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/rr/notifications/tokens/{token_id}")
async def deactivate_fcm_token(
    token_id: int,
    user_id: Optional[int] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Deactivate an FCM token.
    
    Args:
        token_id: ID of the token to deactivate
        user_id: User's ID (integer)
        conn: Database connection
    
    Returns:
        dict: Success message
    """
    try:
        if not user_id:
            raise HTTPException(status_code=400, detail="user_id is required")
            
        # Get notification service
        notification_service = get_notification_service()
        
        success = await notification_service.deactivate_fcm_token(conn, token_id)
        
        if success:
            return {"message": "Token deactivated successfully"}
        else:
            raise HTTPException(status_code=500, detail="Failed to deactivate token")
    except Exception as e:
        logger.error(f"Error deactivating FCM token: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/rr/notifications/subscriptions")
async def subscribe_to_topic(
    subscription_data: dict = Body(...),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Subscribe a user to a notification topic.
    
    Args:
        subscription_data: {"user_id": int, "topic": str}
        conn: Database connection
    
    Returns:
        dict: Success message
    """
    try:
        user_id = int(subscription_data.get("user_id"))
        topic = subscription_data.get("topic")
        
        if not all([user_id, topic]):
            raise HTTPException(status_code=400, detail="Missing required fields")
            
        # Get notification service
        notification_service = get_notification_service()
        
        success = await notification_service.subscribe_to_topic(
            conn,
            user_id=user_id,
            topic=topic
        )
        
        if success:
            return {"message": "Subscribed to topic successfully"}
        else:
            raise HTTPException(status_code=500, detail="Failed to subscribe to topic")
    except Exception as e:
        logger.error(f"Error subscribing to topic: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/rr/notifications/subscriptions/{topic}")
async def unsubscribe_from_topic(
    topic: str,
    user_id: Optional[int] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Unsubscribe a user from a notification topic.
    
    Args:
        topic: Topic name
        user_id: User's ID (integer)
        conn: Database connection
    
    Returns:
        dict: Success message
    """
    try:
        if not user_id:
            raise HTTPException(status_code=400, detail="user_id is required")
            
        # Get notification service
        notification_service = get_notification_service()
        
        success = await notification_service.unsubscribe_from_topic(
            conn,
            user_id=user_id,
            topic=topic
        )
        
        if success:
            return {"message": "Unsubscribed from topic successfully"}
        else:
            raise HTTPException(status_code=500, detail="Failed to unsubscribe from topic")
    except Exception as e:
        logger.error(f"Error unsubscribing from topic: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/rr/notifications/send")
async def send_notification(
    request: Request,
    conn: asyncpg.Connection = Depends(get_db),
    notification_type: str = Body(..., embed=True, description="'order_status' or 'broadcast'"),
    user_ids: Union[str, List[str]] = Body(None, description="Single ID or list of IDs"),
    user_type: str = Body('user', description="Type of user (e.g., 'user', 'chef', 'producer', 'transporter')"),
    send_to_all: bool = Body(False, description="Send to all users"),
    order_id: Optional[str] = Body(None),
    message: Optional[str] = Body(None)
):
    # Validate notification type
    if notification_type not in ['order_status', 'broadcast']:
        raise HTTPException(status_code=400, detail="Invalid notification type")

    # Validate targeting parameters
    if not any([user_ids, send_to_all]):
        raise HTTPException(status_code=400, detail="Must specify user_ids or send_to_all")

    # Prepare payload
    payload = {
        "type": notification_type,
        "message": message
    }

    if notification_type == 'order_status':
        if not order_id:
            raise HTTPException(status_code=400, detail="Order ID required for status updates")
        payload['order_id'] = order_id

    # Convert single ID to list
    if isinstance(user_ids, str):
        user_ids = [user_ids]

    # Get FCM tokens
    if send_to_all:
        tokens = await conn.fetch("SELECT fcm_token FROM users WHERE fcm_token IS NOT NULL")
    elif user_ids:
        tokens = await conn.fetch(
            "SELECT fcm_token FROM users WHERE user_id = ANY($1) AND fcm_token IS NOT NULL",
            user_ids
        )

    # Get notification service
    notification_service = get_notification_service()

    # Send notifications asynchronously to avoid blocking
    asyncio.create_task(notification_service.send_notifications(
        user_ids=user_ids if not send_to_all else None,
        user_types=[user_type] if not send_to_all else None,
        notification_type=notification_type,
        metadata={
            **payload,
            'user_type': user_type,
            'timestamp': datetime.utcnow().isoformat()
        },
        title="Order Update" if notification_type == 'order_status' else "New Message",
        body=message
    ))

    # Return success immediately, notification sending is now non-blocking
    return {"success": True, "message": "Notification task created"}
async def send_batch_notifications(
    batch_data: dict = Body(...),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Send batch notifications to multiple users with improved validation and error handling
    
    Args:
        batch_data: {
            "notifications": [{
                "user_id": str,
                "user_type": str,
                "title": str, 
                "body": str,
                "data": dict
            }]
        }
    
    Returns:
        dict: {
            "sent_count": int,
            "failed_count": int,
            "failed_tokens": List[str],
            "notification_ids": List[str]
        }
    """
    try:
        # Validate batch input
        if not isinstance(batch_data.get('notifications'), list):
            raise HTTPException(status_code=400, detail="Notifications must be a list")
        
        # Initialize FCM service with connection pool
        fcm_service = FirebaseMessagingService(db_pool)
        user_identifiers = [
            {"user_id": n["user_id"], "user_type": n.get("user_type", "user")}
            for n in batch_data['notifications']
        ]
        
        # Batch retrieve valid FCM tokens
        valid_tokens = await fcm_service.get_valid_tokens_batch(user_identifiers)
        
        # Prepare messages with common notification template
        messages = [
            messaging.Message(
                notification=messaging.Notification(
                    title=n['title'],
                    body=n['body']
                ),
                data=n.get('data', {}),
                token=token
            )
            for n, token in zip(batch_data['notifications'], valid_tokens)
        ]
        
        # Send batch with exponential backoff
        successes, failed_tokens = await fcm_service.send_each_multicast(messages)
        
        # Handle token cleanup for failed deliveries
        if failed_tokens:
            await fcm_service.handle_send_errors(failed_tokens)
        
        return {
            "sent_count": successes,
            "failed_count": len(failed_tokens),
            "failed_tokens": failed_tokens,
            "notification_ids": [str(uuid.uuid4()) for _ in messages]
        }
        notification_type = notification_data.get("type")
        title = notification_data.get("title")
        body = notification_data.get("body")
        data = notification_data.get("data", {})
        
        if not all([user_id, notification_type, title, body]):
            raise HTTPException(status_code=400, detail="Missing required fields")
            
        # Get tokens for the user
        tokens = await notification_service.get_fcm_tokens(conn, user_id)
        
        if not tokens:
            raise HTTPException(status_code=400, detail="No active tokens found")
            
        # Log the notification
        notification_id = await notification_service.log_notification(
            conn,
            user_id=user_id,
            token=tokens[0]["token"],  # Use the first active token
            notification_type=notification_type,
            title=title,
            body=body,
            data=data
        )
        
        if not notification_id:
            raise HTTPException(status_code=500, detail="Failed to log notification")
            
        return {"notification_id": notification_id}
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/rr/notifications/history")
async def get_notification_history(
    limit: int = Query(50, ge=1),
    user_id: Optional[str] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Get notification history for a user.
    
    Args:
        limit: Maximum number of notifications to return
        user_id: User's ID (integer)
        conn: Database connection
    
    Returns:
        List[dict]: List of notification history items
    """
    try:
        if not user_id:
            raise HTTPException(status_code=400, detail="user_id is required")
            
        return await notification_service.get_notification_history(conn, user_id, limit)
    except Exception as e:
        logger.error(f"Error getting notification history: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
@app.post('/rr/create_stakeholders', status_code=status.HTTP_201_CREATED)
async def add_stakeholder_endpoint(stakeholder_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await stakeholders_crud.create_stakeholder(conn, stakeholder_data) # Pass conn

@app.post('/rr/login/stakeholders')
async def login_stakeholder_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await stakeholders_crud.login_stakeholder(conn, identifier, password) # Pass conn

@app.get('/rr/rstakeholders')
async def list_all_stakeholders_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await stakeholders_crud.list_stakeholders(conn) # Pass conn
    return {'message': 'Stakeholders retrieved.', 'data': data}

@app.get('/rr/rstakeholders/{stakeholder_id}')
async def get_stakeholder_by_id_endpoint(stakeholder_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data = await stakeholders_crud.get_stakeholder_by_id(conn, stakeholder_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Stakeholder not found')
    return {'message': 'Stakeholder retrieved.', 'data': data}

@app.put('/rr/stakeholders/{stakeholder_id}')
@app.patch('/rr/stakeholders/{stakeholder_id}')
async def update_stakeholder_endpoint(stakeholder_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await stakeholders_crud.update_stakeholder(conn, stakeholder_id, updates) # Pass conn
    updated_data = await stakeholders_crud.get_stakeholder_by_id(conn, stakeholder_id) # Pass conn
    if updated_data: return {'message': 'Stakeholder updated', 'data': updated_data}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Stakeholder not found after update.')

@app.delete('/rr/stakeholders/{stakeholder_id}', status_code=status.HTTP_200_OK)
async def delete_stakeholder_endpoint(stakeholder_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await stakeholders_crud.delete_stakeholder(conn, stakeholder_id) # Pass conn
    if success: return {'message': f'Stakeholder {stakeholder_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Stakeholder {stakeholder_id} not found.')

@app.patch('/rr/stakeholders/{stakeholder_id}/status')
async def update_stakeholder_status_endpoint(stakeholder_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'is_active' not in status_update or not isinstance(status_update['is_active'], bool): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires boolean "is_active"')
    is_active = status_update['is_active']
    await stakeholders_crud.update_stakeholder_status(conn, stakeholder_id, is_active) # Pass conn
    return {'message': f'Stakeholder {stakeholder_id} status updated'}

# === PRODUCT TYPE Endpoints ===

# --- Herbals ---
@app.post('/rr/aherbals', status_code=status.HTTP_201_CREATED)
async def add_herbal_endpoint(herbal_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await herbals_crud.create_herbal(conn, herbal_data) # Pass conn

@app.get('/rr/rherbals')
async def list_all_herbals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await herbals_crud.list_herbals(conn) # Pass conn
    return {'message': 'Herbals retrieved.', 'data': data or []}

@app.get('/rr/rherbals/{herbal_id}')
async def get_herbal_by_id_endpoint(herbal_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data = await herbals_crud.get_herbal_by_id(conn, herbal_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Herbal not found')
    return {'message': 'Herbal retrieved.', 'data': data}

@app.put('/rr/herbals/{herbal_id}')
@app.patch('/rr/herbals/{herbal_id}')
async def update_herbal_endpoint(herbal_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await herbals_crud.update_herbal(conn, herbal_id, updates) # Pass conn
    updated = await herbals_crud.get_herbal_by_id(conn, herbal_id) # Pass conn
    return {'message': 'Herbal updated successfully', 'data': updated or f"Herbal {herbal_id} not found after update"}

@app.delete('/rr/herbals/{herbal_id}', status_code=status.HTTP_200_OK)
async def delete_herbal_endpoint(herbal_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await herbals_crud.delete_herbal(conn, herbal_id) # Pass conn
    if success: return {'message': f'Herbal {herbal_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Herbal {herbal_id} not found.')

# --- Meals ---
@app.get('/rr/meals')
@alru_cache(maxsize=1)
async def list_all_meals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await meals_crud.list_meals(conn) # Pass conn
    return {'message': 'Meals retrieved.', 'data': data or []}

@app.get('/rr/meals/{meal_id}')
async def get_meal_by_id_endpoint(meal_id: str = Path(...), conn: asyncpg.Connection = Depends(get_db)):
    data = await meals_crud.get_meal_by_id(conn, meal_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Meal not found')
    return {'message': 'Meal retrieved.', 'data': data}

@app.post('/rr/meals', status_code=status.HTTP_201_CREATED)
async def create_meal_endpoint(meal_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     return await meals_crud.create_meal(conn, meal_data) # Pass conn

@app.put('/rr/umeals/{meal_id}')
@app.patch('/rr/umeals/{meal_id}')
async def update_meal_endpoint(meal_id: str, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await meals_crud.update_meal(conn, meal_id, updates) # Pass conn
    updated = await meals_crud.get_meal_by_id(conn, meal_id) # Pass conn
    return {'message': 'Meal updated successfully', 'data': updated or f"Meal {meal_id} not found after update"}

@app.delete('/rr/dmeals/{meal_id}', status_code=status.HTTP_200_OK)
async def delete_meal_endpoint(meal_id: str, conn: asyncpg.Connection = Depends(get_db)):
    success = await meals_crud.delete_meal(conn, meal_id) # Pass conn
    if success: return {'message': f'Meal {meal_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Meal {meal_id} not found.')

# --- Produce ---
@app.get('/rr/produce')
async def list_all_produce_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await produce_crud.list_produce(conn) # Pass conn
    return {'message': 'Produce retrieved.', 'data': data or []}

@app.get('/rr/produce/{produce_id}')
async def get_produce_by_id_endpoint(produce_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)): # Assuming int
    data = await produce_crud.get_produce_by_id(conn, produce_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Produce not found')
    return {'message': 'Produce retrieved.', 'data': data}

@app.post('/rr/produce', status_code=status.HTTP_201_CREATED)
async def create_produce_endpoint(produce_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     return await produce_crud.create_produce(conn, produce_data) # Pass conn

@app.put('/rr/uproduce/{produce_id}')
@app.patch('/rr/uproduce/{produce_id}')
async def update_produce_endpoint(produce_id: str, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)): # Assuming str based on method
    await produce_crud.update_produce(conn, produce_id, updates) # Pass conn
    updated = await produce_crud.get_produce_by_id(conn, int(produce_id)) # Assuming int lookup
    return {'message': 'Produce updated successfully', 'data': updated or f"Produce {produce_id} not found after update"}

@app.delete('/rr/dproduce/{produce_id}', status_code=status.HTTP_200_OK)
async def delete_produce_endpoint(produce_id: int, conn: asyncpg.Connection = Depends(get_db)): # Assuming int
    success = await produce_crud.delete_produce(conn, produce_id) # Pass conn
    if success: return {'message': f'Produce {produce_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Produce {produce_id} not found.')

# --- Gadgets ---
@app.get('/rr/gadgets')
async def list_all_gadgets_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await gadgets_crud.list_gadgets(conn) # Pass conn
    return {'message': 'Gadgets retrieved.', 'data': data or []}

@app.get('/rr/gadgets/{gadget_id}')
async def get_gadget_by_id_endpoint(gadget_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data = await gadgets_crud.get_gadget_by_id(conn, gadget_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Gadget not found')
    return {'message': 'Gadget retrieved.', 'data': data}

@app.post('/rr/gadgets', status_code=status.HTTP_201_CREATED)
async def create_gadget_endpoint(gadget_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     return await gadgets_crud.create_gadget(conn, gadget_data) # Pass conn

@app.put('/rr/gadgets/{gadget_id}')
@app.patch('/rr/gadgets/{gadget_id}')
async def update_gadget_endpoint(gadget_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await gadgets_crud.update_gadget(conn, gadget_id, updates) # Pass conn
    updated = await gadgets_crud.get_gadget_by_id(conn, gadget_id) # Pass conn
    return {'message': 'Gadget updated successfully', 'data': updated or f"Gadget {gadget_id} not found after update"}

@app.delete('/rr/gadgets/{gadget_id}', status_code=status.HTTP_200_OK)
async def delete_gadget_endpoint(gadget_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await gadgets_crud.delete_gadget(conn, gadget_id) # Pass conn
    if success: return {'message': f'Gadget {gadget_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Gadget {gadget_id} not found.')

# --- Spices ---
@app.get('/rr/spices')
async def list_all_spices_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await spices_crud.list_spices(conn) # Pass conn
    return {'message': 'Spices retrieved.', 'data': data or []}

@app.get('/rr/spices/{spice_id}')
async def get_spice_by_id_endpoint(spice_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data = await spices_crud.get_spice_by_id(conn, spice_id) # Pass conn
    if data is None: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Spice not found')
    return {'message': 'Spice retrieved.', 'data': data}

@app.post('/rr/spices', status_code=status.HTTP_201_CREATED)
async def create_spice_endpoint(spice_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
     return await spices_crud.create_spice(conn, spice_data) # Pass conn

@app.put('/rr/spices/{spice_id}')
@app.patch('/rr/spices/{spice_id}')
async def update_spice_endpoint(spice_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await spices_crud.update_spice(conn, spice_id, updates) # Pass conn
    updated = await spices_crud.get_spice_by_id(conn, spice_id) # Pass conn
    return {'message': 'Spice updated successfully', 'data': updated or f"Spice {spice_id} not found after update"}

@app.delete('/rr/spices/{spice_id}', status_code=status.HTTP_200_OK)
async def delete_spice_endpoint(spice_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await spices_crud.delete_spice(conn, spice_id) # Pass conn
    if success: return {'message': f'Spice {spice_id} deleted'}
    else: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Spice {spice_id} not found.')
    

# --- Supplements endpoints ---
@app.get('/rr/supplements')
async def list_all_supplements_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    data = await supplements_crud.list_supplements(conn) # Pass conn
    return {'message': 'Supplements retrieved.', 'data': data or []}

@app.get('/rr/supplements/{supplement_id}')
async def get_supplement_by_id_endpoint(supplement_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data = await supplements_crud.get_supplement_by_id(conn, supplement_id) # Pass conn
    if data is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Supplement not found')
    return {'message': 'Supplement retrieved.', 'data': data}

@app.post('/rr/supplements', status_code=status.HTTP_201_CREATED)
async def create_supplement_endpoint(supplement_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    return await supplements_crud.create_supplement(conn, supplement_data) # Pass conn

@app.put('/rr/supplements/{supplement_id}')
@app.patch('/rr/supplements/{supplement_id}')
async def update_supplement_endpoint(supplement_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    await supplements_crud.update_supplement(conn, supplement_id, updates) # Pass conn
    updated = await supplements_crud.get_supplement_by_id(conn, supplement_id) # Pass conn
    return {'message': 'Supplement updated successfully', 'data': updated or f"Supplement {supplement_id} not found after update"}

@app.delete('/rr/supplements/{supplement_id}', status_code=status.HTTP_200_OK)
async def delete_supplement_endpoint(supplement_id: int, conn: asyncpg.Connection = Depends(get_db)):
    success = await supplements_crud.delete_supplement(conn, supplement_id) # Pass conn
    if success:
        return {'message': f'Supplement {supplement_id} deleted'}
    else:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f'Supplement {supplement_id} not found.')

# --- Order Endpoints ---
@app.post('/rr/Aorders', status_code=status.HTTP_201_CREATED)
async def create_order_endpoint(order_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    logger.debug(f"Received order payload: {order_data}")
    try:
        user_id=order_data['user_id']; order_type=order_data['order_type']; product_id=order_data.get('product_id')
        delivery_address=order_data.get('delivery_address'); order_status=order_data.get('order_status','pending'); total_price=order_data.get('total_price',0.0)
        notes=order_data.get('notes'); payment_status=order_data.get('payment_status','pending'); payment_mode=order_data.get('payment_mode','cash')
        amount_paid=order_data.get('amount_paid',0.0); transaction_id=order_data.get('transaction_id'); quantity=order_data.get('quantity',1)
        transporter_id=order_data.get('transporter_id'); items=order_data.get('items')
        chef_id=order_data.get('chef_id'); producer_id=order_data.get('producer_id')
        if isinstance(items, list) and len(items) > 0:
             first=items[0]; chef_id=first.get('chef_id',chef_id); producer_id=first.get('producer_id',producer_id); product_id=first.get('product_id',product_id); quantity=first.get('quantity',quantity)
        is_gig = str(order_type).lower().strip() == 'gig'
        if not is_gig:
            if chef_id is None and producer_id is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='chef_id or producer_id required.')
            if chef_id is not None and producer_id is not None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot set both chef_id and producer_id.')
        async with conn.transaction():
            result = await orders_crud.create_order(conn=conn, user_id=user_id, order_type=order_type, product_id=product_id, chef_id=chef_id, producer_id=producer_id, delivery_address=delivery_address, order_status=order_status, total_price=total_price, notes=notes, payment_status=payment_status, payment_mode=payment_mode, amount_paid=amount_paid, transaction_id=transaction_id, quantity=quantity, transporter_id=transporter_id, items=items)
            # Notification should be triggered only after successful commit
            
            # Trigger notification for chef or producer
            notification_service = get_notification_service()
            order_id = result.get('order_id')
            chef_id = result.get('chef_id')
            producer_id = result.get('producer_id')
                
            if order_id and (chef_id or producer_id):
                recipient_id = chef_id or producer_id
                try:
                    # Send new order notification asynchronously to avoid blocking
                    recipient_type = 'chef' if chef_id else 'producer'
                    asyncio.create_task(notification_service.send_notifications(
                        user_ids=[str(recipient_id)],
                        user_types=[recipient_type],
                        notification_type='order_status_created',
                        metadata={
                            **result,
                            'user_type': recipient_type,
                            'timestamp': datetime.utcnow().isoformat(),
                            'status': 'created',
                            'order_id': order_id
                        }
                    ))
                    logger.info(f"New order notification task created for order {order_id} to user {recipient_id}")
                except Exception as notification_e:
                    logger.error(f"Failed to send new order notification for order {order_id} to user {recipient_id}: {notification_e}", exc_info=True)
            elif not (chef_id or producer_id):
                logger.warning(f"Could not send new order notification for order {order_id}: No chef_id or producer_id found in result.")
            else:
                logger.warning("Could not send new order notification: Order ID not found in result.")

        return result
    except KeyError as ke:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Missing order field: {ke}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Order creation error: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Order creation internal error.')

@app.get('/rr/get_completion_code/{order_id}')
async def get_completion_code_endpoint(order_id: int = Path(..., gt=0), user_id: Optional[int] = Query(None), conn: asyncpg.Connection = Depends(get_db)):
    """
    Fetches the completion code for a completed or delivered order.
    Optionally filters by user_id.
    """
    sql = """
    SELECT completion_code
    FROM order_completions
    WHERE order_id = $1
    """
    params: List[Any] = [order_id]
    param_counter = 2

    if user_id is not None:
        sql += f" AND user_id = ${param_counter}"
        params.append(user_id)

    try:
        completion_code = await conn.fetchval(sql, *params)
        if completion_code:
            log_msg = f"Fetched completion code for Order ID: {order_id}"
            if user_id is not None:
                log_msg += f", User ID: {user_id}"
            logger.info(log_msg)
            return {"completion_code": completion_code}
        else:
            log_msg = f"No completion code found for Order ID: {order_id}"
            if user_id is not None:
                log_msg += f", User ID: {user_id}"
            logger.warning(log_msg)
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Completion code not found for this order and user combination (or order not completed/delivered).")
    except asyncpg.PostgresError as e:
        logger.error(f"Database error fetching completion code for Order ID {order_id}, User ID {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An error occurred while fetching the completion code.") from e
    except Exception as e:
        logger.error(f"Unexpected error fetching completion code for Order ID {order_id}, User ID {user_id}: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected server error occurred.") from e

@app.get('/rr/orders')
async def get_orders_endpoint(order_id: Optional[int]=Query(None), chef_id: Optional[int]=Query(None), producer_id: Optional[int]=Query(None), user_id: Optional[int]=Query(None), transporter_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    data = await orders_crud.read_orders(conn=conn, order_id=order_id, chef_id=chef_id, producer_id=producer_id, user_id=user_id, transporter_id=transporter_id) # Pass conn
    return {'message': 'Orders retrieved.', 'data': data}

@app.patch('/rr/orders/{order_id}/status')
async def update_order_status_endpoint(order_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'order_status' not in status_update:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires "order_status"')

    new_status = status_update['order_status']
    transporter_id = status_update.get('transporter_id') # Optional transporter_id
    completion_code = status_update.get('completion_code') # Optional completion_code

    # Add validation for transporter_id if status is 'assigned'
    if str(new_status).lower().strip() == 'assigned' and transporter_id is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='"assigned" status needs "transporter_id"')

    # Assuming orders_crud is an instance of the Orders class
    result = await orders_crud.update_order_status(
        conn=conn,
        order_id=order_id,
        new_status=new_status,
        transporter_id=transporter_id,
        completion_code=completion_code # Pass the optional completion_code
    )
    # update_order_status now returns dict on success or raises exception
    return result


@app.delete('/rr/orders/{order_id}', status_code=status.HTTP_200_OK)
async def delete_order_endpoint(order_id: int, conn: asyncpg.Connection = Depends(get_db)):
    result = await orders_crud.delete_order(conn, order_id) # Pass conn
    # delete_order now returns dict on success or raises exception
    return result

# --- METRICS CRUD ---
@app.post('/rr/metrics', status_code=status.HTTP_201_CREATED)
async def create_metric_endpoint(metric_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    result = await auth_users.create_metric(conn, metric_data) # Pass conn
    return {'message': 'Metric created', 'data': result}

@app.get('/rr/metrics')
async def list_all_metrics_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """List all user metrics."""
    repo = AuthenticationAndUsers()
    metrics = await repo.list_metrics(conn)
    return {"metrics": metrics}

@app.get('/rr/metrics/{user_id}')
async def list_user_metrics_endpoint(user_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    """List metrics for a specific user by user ID."""
    repo = AuthenticationAndUsers()
    metrics = await repo.list_metrics(conn, user_id=user_id)
    if not metrics:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Metrics not found for user ID {user_id}")
    return {"metrics": metrics}

@app.put('/rr/metrics/{user_id}')
@app.patch('/rr/metrics/{user_id}')
async def update_metric_endpoint(user_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Update a user metric by user ID."""
    repo = AuthenticationAndUsers()
    await repo.update_metric(conn, user_id, updates)
    return {"message": f"Metric for user {user_id} updated successfully."}


@app.delete('/rr/metrics/{metric_id}', status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def delete_metric_endpoint(metric_id: int, conn: asyncpg.Connection = Depends(get_db)):
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail='Metric deletion not implemented')

# --- PREFERENCES CRUD ---
@app.post('/rr/preferences', status_code=status.HTTP_201_CREATED)
async def create_preference_endpoint(preference_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    result = await auth_users.create_preference(conn, preference_data) # Pass conn
    return {'message': 'Preference created', 'data': result}

@app.get('/rr/preferences')
async def list_all_preferences_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    """List all user preferences."""
    repo = AuthenticationAndUsers()
    preferences = await repo.list_preferences(conn)
    return {"preferences": preferences}

@app.get('/rr/preferences/{user_id}')
async def list_user_preferences_endpoint(user_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    """List preferences for a specific user by user ID."""
    repo = AuthenticationAndUsers()
    preferences = await repo.list_preferences(conn, user_id=user_id)
    if not preferences:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Preferences not found for user ID {user_id}")
    return {"preferences": preferences}


@app.get('/rr/debug/preferences/{preference_id}')
async def debug_get_preference(preference_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """Debug endpoint to get a specific preference by ID."""
    try:
        query = """
            SELECT * 
            FROM user_preferences 
            WHERE preference_id = $1
        """
        pref = await conn.fetchrow(query, preference_id)
        
        if not pref:
            return {
                "exists": False,
                "message": f"Preference ID {preference_id} not found"
            }
            
        return {
            "exists": True,
            "preference": dict(pref),
            "message": f"Found preference {preference_id}"
        }
    except Exception as e:
        logger.error(f"Error fetching preference {preference_id}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error fetching preference: {str(e)}"
        )

@app.put('/rr/users/{user_id}/preferences')
@app.patch('/rr/users/{user_id}/preferences')
async def update_user_preferences_endpoint(
    user_id: int = Path(..., gt=0), 
    updates: dict = Body(...),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Update preferences for a specific user by user ID.
    If the user doesn't have preferences, create them.
    """
    logger.info(f"Updating preferences for user {user_id} with data: {updates}")
    repo = AuthenticationAndUsers()
    
    try:
        # Check if user exists
        user_exists = await conn.fetchval("SELECT 1 FROM users WHERE user_id = $1", user_id)
        if not user_exists:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User with ID {user_id} not found"
            )
        
        # Get existing preferences
        existing_prefs = await repo.list_preferences(conn, user_id=user_id)
        
        if not existing_prefs:
            # No preferences exist, create new ones
            logger.info(f"No existing preferences found for user {user_id}, creating new preferences")
            
            # Set default values if not provided
            default_updates = {
                'goals': updates.get('goals', 'general_health'),
                'diet_type': updates.get('diet_type', 'balanced'),
                'food_restrictions': updates.get('food_restrictions', []),
                'cuisine_preferences': updates.get('cuisine_preferences', [])
            }
            
            # Create new preferences
            await repo.create_preference(conn, {'user_id': user_id, **default_updates})
            logger.info(f"Created new preferences for user {user_id}")
        else:
            # Update existing preferences
            preference_id = existing_prefs[0]['preference_id']
            logger.info(f"Updating existing preferences (ID: {preference_id}) for user {user_id}")
            await repo.update_preference(conn, preference_id, updates)
        
        # Get the updated preferences
        updated_prefs = await repo.list_preferences(conn, user_id=user_id)
        logger.info(f"Successfully updated preferences for user {user_id}")
        
        return {
            "message": "Preferences updated successfully.",
            "preferences": updated_prefs
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating preferences for user {user_id}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while updating preferences: {str(e)}"
        )


@app.delete('/rr/preferences/{preference_id}', status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def delete_preference_endpoint(preference_id: int, conn: asyncpg.Connection = Depends(get_db)):
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail='Preference deletion not implemented')

# --- Payment Endpoints (Remain sync, no Depends(get_db) needed) ---
# ... (Payment endpoints unchanged, they don't use the DB pool directly) ...
@app.post('/rr/pay', status_code=status.HTTP_201_CREATED)
async def create_payment_route(payment_data: dict = Body(...)):
    amount = payment_data.get('amount'); description = payment_data.get('description', "ZINZI payment")
    if amount is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Amount required")
    try:
        response = create_payment_paypal(amount, description) # Sync call
        if not response.get("success"): raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=response.get("error", "PayPal fail"))
        return response
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
    except Exception as e:
        logger.error(f"PayPal create err: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Payment error.")

@app.get('/rr/execute')
async def execute_payment_route(paymentId: str = Query(...), PayerID: str = Query(...)):
    try:
        response = execute_payment_paypal(paymentId, PayerID) # Sync call
        if response.get("status") != "success":
            sc = status.HTTP_404_NOT_FOUND if "not found" in response.get("error","") else status.HTTP_400_BAD_REQUEST
            raise HTTPException(status_code=sc, detail=response.get("error", "PayPal exec fail"))
        return response
    except Exception as e:
        logger.error(f"PayPal exec err (ID: {paymentId}): {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Payment exec error.")

@app.get('/rr/cancel')
async def handle_payment_cancellation_route():
    try:
        return handle_payment_cancellation_paypal() # Sync call
    except Exception as e:
        logger.error(f"PayPal cancel err: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Cancel handle error.")

@app.post('/rr/create_stripe_payment', status_code=status.HTTP_201_CREATED)
async def create_stripe_payment_route(payment_data: dict = Body(...)):
    amount = payment_data.get('amount')
    if amount is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Amount required")
    try:
        response = create_stripe_payment(amount) # Sync call
        if response.get("status") != "success": raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=response.get("error", "Stripe fail"))
        return response
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
    except Exception as e:
        logger.error(f"Stripe create err: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Payment error.")

@app.post('/rr/confirm_stripe_payment')
async def confirm_stripe_payment_route(confirm_data: dict = Body(...)):
    pi_id=confirm_data.get('paymentIntentId'); pm_id=confirm_data.get('paymentMethodId')
    if not pi_id: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="paymentIntentId required")
    try: return execute_stripe_payment(pi_id, pm_id) # Sync call
    except Exception as e: logger.error(f"Stripe confirm err (Intent: {pi_id}): {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Payment confirm error.")

@app.post('/rr/cancel_stripe_payment')
async def cancel_stripe_payment_route():
    try: return handle_stripe_payment_cancellation() # Sync call
    except Exception as e: logger.error(f"Stripe cancel err: {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Cancel handle error.")

@app.post('/rr/request_momo_payment')
async def request_momo_payment_route(momo_data: dict = Body(...)):
    try:
        amount=momo_data['amount']; payer_number=momo_data['payer_number']; currency=momo_data.get('currency','UGX'); ext_id=momo_data.get('external_id', str(uuid.uuid4())); payer_msg=momo_data.get('payer_message','Payment'); payee_note=momo_data.get('payee_note','Payment Request')
        amount_f=float(amount)
        result = request_momo_payment(amount_f, currency, ext_id, payer_number, payer_msg, payee_note) # Sync call
        if result.get("status") == "pending": return JSONResponse(content=result, status_code=status.HTTP_202_ACCEPTED)
        else: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=result.get("error", "MoMo request failed"))
    except (KeyError, ValueError) as ve: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Invalid MoMo input: {ve}")
    except Exception as e: logger.error(f"MoMo request err: {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="MoMo request error.")

@app.get('/rr/check_momo_payment_status')
async def check_momo_payment_status_route(transaction_ref: str = Query(...)):
    try:
        result = check_momo_payment_status(transaction_ref) # Sync call
        if result.get("status") == "success": return result
        elif result.get("status") == "not_found": raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=result.get("error", "Tx ref not found."))
        else: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=result.get("error", "MoMo status check failed."))
    except Exception as e: logger.error(f"MoMo status check err (Ref: {transaction_ref}): {e}", exc_info=True); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="MoMo status check error.")

@app.post('/rr/momo_callback')
@app.put('/rr/momo_callback')
async def momo_callback(request: Request):
    # ... (implementation unchanged) ...
    try:
        notification_data = await request.json()
        logger.info(f"MoMo Callback Received: {notification_data}")
        if not notification_data or not isinstance(notification_data, dict): logger.error("Invalid MoMo callback format."); return JSONResponse(content={"error":"Invalid format"}, status_code=status.HTTP_400_BAD_REQUEST)
        # TODO: Process notification securely
        return {"message": "Callback acknowledged"}
    except json.JSONDecodeError: logger.error("MoMo callback JSON decode err."); return JSONResponse(content={"error":"Invalid JSON"}, status_code=status.HTTP_400_BAD_REQUEST)
    except Exception as e: logger.error(f"MoMo callback process err: {e}", exc_info=True); return JSONResponse(content={"error":"Callback process failed"}, status_code=status.HTTP_500_INTERNAL_SERVER_ERROR)

# --- Recommendation Endpoints ---

@app.get("/rr/recommendations/v2/{user_id}")
async def get_recommendations_v2(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Recommendation V2 not fully implemented.")

@app.get("/rr/allmeals")
async def get_all_meals_endpoint(conn: asyncpg.Connection = Depends(get_db)):
    fetcher = GetAllMeals()
    return await fetcher.fetch_all_meals(conn) # Pass conn

# --- Disbursement Endpoints ---
# GET Endpoints
@app.get("/rr/disbursements/chef")
async def list_chef_disbursements_endpoint(chef_id: Optional[int]=Query(None), order_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    return await disbursement_handler.list_chef_disbursements(conn, chef_id, order_id)

@app.get("/rr/disbursements/producer")
async def list_producer_disbursements_endpoint(producer_id: Optional[int]=Query(None), order_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    return await disbursement_handler.list_producer_disbursements(conn, producer_id, order_id)

@app.get("/rr/disbursements/transporter")
async def list_transporter_disbursements_endpoint(transporter_id: Optional[int]=Query(None), order_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    return await disbursement_handler.list_transporter_disbursements(conn, transporter_id, order_id)

@app.get("/rr/disbursements/stakeholder")
async def list_stakeholder_disbursements_endpoint(stakeholder_id: Optional[int]=Query(None), order_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    return await disbursement_handler.list_stakeholder_disbursements(conn, stakeholder_id, order_id)

# PUT Endpoints
@app.put("/rr/disbursements/chef/{disbursement_id}")
async def update_chef_disbursement_endpoint(disbursement_id: int, updates: dict=Body(...), chef_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    await disbursement_handler.update_chef_disbursement(conn, disbursement_id, updates, chef_id)
    return {"message": "Chef disbursement updated"}

@app.put("/rr/disbursements/producer/{disbursement_id}")
async def update_producer_disbursement_endpoint(disbursement_id: int, updates: dict=Body(...), producer_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    await disbursement_handler.update_producer_disbursement(conn, disbursement_id, updates, producer_id)
    return {"message": "Producer disbursement updated"}

@app.put("/rr/disbursements/transporter/{disbursement_id}")
async def update_transporter_disbursement_endpoint(disbursement_id: int, updates: dict=Body(...), transporter_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    await disbursement_handler.update_transporter_disbursement(conn, disbursement_id, updates, transporter_id)
    return {"message": "Transporter disbursement updated"}

@app.put("/rr/disbursements/stakeholder/{disbursement_id}")
async def update_stakeholder_disbursement_endpoint(disbursement_id: int, updates: dict=Body(...), stakeholder_id: Optional[int]=Query(None), conn: asyncpg.Connection=Depends(get_db)):
    await disbursement_handler.update_stakeholder_disbursement(conn, disbursement_id, updates, stakeholder_id)
    return {"message": "Stakeholder disbursement updated"}

# POST Endpoints
@app.post("/rr/disbursements/chef", status_code=status.HTTP_201_CREATED)
async def create_chef_disbursement_endpoint(chef_id: int = Body(...), order_data: dict = Body(...), conn: asyncpg.Connection=Depends(get_db)): # Get chef_id from body if needed
    new_id = await disbursement_handler.insert_chef_disbursement(conn, chef_id, order_data)
    return {"message": "Chef disbursement created", "disbursement_id": new_id}

@app.post("/rr/disbursements/producer", status_code=status.HTTP_201_CREATED)
async def create_producer_disbursement_endpoint(producer_id: int=Body(...), order_data: dict = Body(...), conn: asyncpg.Connection=Depends(get_db)):
    new_id = await disbursement_handler.insert_producer_disbursement(conn, producer_id, order_data)
    return {"message": "Producer disbursement created", "disbursement_id": new_id}

@app.post("/rr/disbursements/transporter", status_code=status.HTTP_201_CREATED)
async def create_transporter_disbursement_endpoint(transporter_id: int = Body(...), order_data: dict = Body(...), conn: asyncpg.Connection=Depends(get_db)): # Get ID from body
    new_id = await disbursement_handler.insert_transporter_disbursement(conn, transporter_id, order_data)
    return {"message": "Transporter disbursement created", "disbursement_id": new_id}

@app.post("/rr/disbursements/stakeholder", status_code=status.HTTP_201_CREATED)
async def create_stakeholder_disbursement_endpoint(stakeholder_id: int=Body(...), order_data: dict = Body(...), conn: asyncpg.Connection=Depends(get_db)):
    new_id = await disbursement_handler.insert_stakeholder_disbursement(conn, stakeholder_id, order_data)
    return {"message": "Stakeholder disbursement created", "disbursement_id": new_id}

# --- Configuration Setup (Run before App Definition or in Lifespan) ---
# Moved configuration calls inside functions or removed if env vars are sufficient

# --- Remove __main__ block ---
