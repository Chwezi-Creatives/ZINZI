#cspell:disable
# --- AuthenticationAndUsers Class (Updated for asyncpg pool) ---
import os
import json
import random
import base64
import time
import uuid
import string
from datetime import datetime, timedelta, date, timezone
from functools import lru_cache  #for distance caching leave it synchronous.
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
import re  # For regular expressions
import paypalrestsdk # Keep sync for now
import stripe # Keep sync for now
import requests # Keep sync for now
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, validator

# --- FastAPI Imports ---
from services.fcm_service import FirebaseMessagingService
from fastapi import FastAPI, Request, Depends, HTTPException, status, Body, Query, Path, BackgroundTasks
from typing import Dict, Any, Optional, List, Union, Tuple
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware import Middleware
from fastapi.staticfiles import StaticFiles # Import StaticFiles
from contextlib import asynccontextmanager # For lifespan manager
from fastapi.responses import ORJSONResponse, FileResponse # Use ORJSON, Import FileResponse
import json
import asyncio
import math
from typing import Dict, Any, Optional, List, Union, Tuple
from functools import wraps
from meal_algorithm4 import MealRecommendation4
from location_service import LocationService
from services.fcm_service import FirebaseMessagingService
from services.disbursement_service import DisbursementService
from passlib.context import CryptContext

# Import notification service
from services.notification_service import NotificationService

# Import MoMo service
from services.momo_service import MomoService
from services.disbursement_service import disbursement_service

# Import LocationService for geofencing
from location_service import LocationService

# Initialize MoMo service
momo_service = MomoService()

# Import meal recommendation algorithm
from meal_algorithm4 import MealRecommendation4

# Global singleton instance of MealRecommendation4
meal_recommender = None

# --- Configuration Loading ---
load_dotenv()

# --- Logging Configuration ---
import sys

# Configure root logger with a more robust setup
def setup_logging():
    # Remove any existing handlers
    root_logger = logging.getLogger()
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Create a formatter
    formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
    
    # Try to set up a stream handler with error handling
    try:
        # Try stderr first
        handler = logging.StreamHandler(sys.stderr)
    except (OSError, IOError):
        try:
            # Fall back to stdout if stderr fails
            handler = logging.StreamHandler(sys.stdout)
        except (OSError, IOError):
            # If both fail, disable logging
            logging.disable(logging.CRITICAL)
            return
    
    # Configure the handler
    handler.setFormatter(formatter)
    
    # Configure the root logger
    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(handler)

# Initialize logging
setup_logging()

# Get logger for this module
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
    """Preload meal data and initialize the global MealRecommendation4 instance."""
    global meal_recommender
    try:
        logger.info("Initializing global MealRecommendation4 instance and preloading data...")
        
        # Create the singleton instance
        meal_recommender = MealRecommendation4(1)  # Use default user ID 1 for initialization
        
        # Trigger data loading into the shared cache
        meals = meal_recommender.fetch_all_meals()
        logger.info(f"Successfully initialized MealRecommendation4 and preloaded {len(meals)} meals into cache")
        return True
    except Exception as e:
        logger.error(f"Error initializing MealRecommendation4: {e}", exc_info=True)
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
            statement_cache_size=0, # Uncomment ONLY if needed for pgbouncer transaction/statement mode
            server_settings={
                'timezone': 'Africa/Nairobi',
                'application_name': 'zinzi_backend'
            }
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

# Define allowed origins for CORS
ALLOWED_ORIGINS = [
    "http://localhost:5000",
    "http://localhost:3000",
    "http://localhost:8080",
    "http://localhost:55282",
    "http://127.0.0.1",
    "http://127.0.0.1:5000",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8080",
    "http://192.168.1.2:55282",
    "https://zinzib.onrender.com",
    "https://zinzi-web.vercel.app:443",
    "https://zinzi-web.vercel.app:443",
    # Add your production domain here when deploying
]

# Use the lifespan manager
app = FastAPI(
    title="ZINZI",
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
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=600  # 10 minutes
)

# --- Subscription Endpoints ---
# (Moved after SubscriptionService class definition)

# --- Database Dependency ---
async def get_db() -> AsyncGenerator[asyncpg.Connection, None]:
    """FastAPI dependency to get a database connection from the pool."""
    # ... (rest of the code remains the same)
    ...
    if db_pool is None:
        logger.error("Attempted to acquire DB connection, but pool is not available.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database service is currently unavailable. Please try again later."
        )
    # Acquire connection from pool; automatically released when block exits
    async with db_pool.acquire() as connection:
        # SET TIMEZONE is now handled by the pool's `setup` parameter (init_connection)
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

    async def _execute_query(self, conn: asyncpg.Connection, sql: str, params: Optional[tuple] = None, 
                            fetch_one: bool = False, fetch_val: bool = False, fetch_all: bool = False, 
                            returning_id_column: Optional[str] = None) -> Any:
        """
        Executes SQL query asynchronously using the provided asyncpg connection.
        
        Args:
            conn: Database connection
            sql: SQL query to execute
            params: Query parameters
            fetch_one: If True, fetch a single row
            fetch_val: If True, fetch a single value
            fetch_all: If True, fetch all rows
            returning_id_column: Column name to return for INSERT ... RETURNING queries
            
        Returns:
            Query results based on the fetch_* parameters
            
        Raises:
            HTTPException: With appropriate status code and user-friendly message
        """
        results = None
        returned_id = None
        params = params or ()
        # Sanitize parameters for logging (avoid logging sensitive data)
        log_params = tuple('***' if any(s in str(p).lower() for s in ['password', 'token', 'secret', 'key']) 
                          else str(p) if isinstance(p, bytes) else p 
                          for p in params)
        
        # Log the SQL query with parameters (sanitized for logging)
        logger.debug(f"Executing SQL: {sql} | Params: {log_params}")

        try:
            # Use fetchval for RETURNING ID for simplicity and efficiency
            if returning_id_column:
                returned_id = await conn.fetchval(sql, *params)
                if returned_id is not None:
                    logger.debug(f"Returning {returning_id_column}: [ID: {returned_id}]")
                else:
                    logger.warning(f"Query with RETURNING {returning_id_column} did not return a value")
                return returned_id
                
            elif fetch_one:
                row = await conn.fetchrow(sql, *params)
                results = dict(row) if row else None
                logger.debug(f"Fetched one row: {'Found' if results else 'Not Found'}")
                return results
                
            elif fetch_all:
                rows = await conn.fetch(sql, *params)
                results = [dict(row) for row in rows]
                logger.debug(f"Fetched {len(results)} rows")
                return results
                
            else:  # Just execute (INSERT, UPDATE, DELETE without RETURNING)
                status_str = await conn.execute(sql, *params)
                logger.debug(f"Executed statement. Status: {status_str}")
                return status_str

        except asyncpg.PostgresError as e:
            # Log the full error details for debugging
            error_code = getattr(e, 'sqlstate', 'UNKNOWN')
            error_context = {
                'error_code': error_code,
                'error_message': str(e),
                'sql': sql,
                'params_type': str(type(params)),
                'params_length': len(params) if params else 0
            }
            logger.error(f"Database Error: {error_context}", exc_info=True)
            
            # Map specific database errors to appropriate HTTP status codes
            if error_code == '23505':  # unique_violation
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="A record with these details already exists"
                )
            elif error_code == '23503':  # foreign_key_violation
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid reference to another resource"
                )
            elif error_code == '23502':  # not_null_violation
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Required field is missing"
                )
            elif error_code == '42P01':  # undefined_table
                logger.critical(f"Database table does not exist: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="A system error occurred. Please try again later."
                )
            elif error_code == '42601':  # syntax_error
                logger.critical(f"SQL syntax error: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="A system error occurred. Please try again later."
                )
            else:
                # For all other database errors, return a generic error
                logger.error(f"Unhandled database error: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="A database error occurred. Please try again later."
                )

        except Exception as e:
            # Log the full error for debugging
            logger.critical(f"Unexpected error in _execute_query: {e}", exc_info=True)
            
            # Return a generic error to the client
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="An unexpected error occurred. Please try again later."
            )



# --- AuthenticationAndUsers Class (Updated for asyncpg pool) ---

class AuthenticationAndUsers(BaseRepository):
    PASSWORD_RESET_CODE_EXPIRE_MINUTES = 10  # Code expires in 10 minutes
    PASSWORD_RESET_CODE_LENGTH = 6  # 6-digit code
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
    # Methods now accept 'conn' from Depends(get_db)   #currently a private method buill come back later to decide wether to make it a class of its own or a public method,etc
    async def request_password_reset(self, email: str, user_type: str, conn) -> dict:
        """
        Handle password reset request by generating and storing a reset code.
        
        This method checks if the email exists in the specified user type table,
        generates a reset code, stores it, and sends it to the user's email.
        Always returns a success response to prevent email enumeration.
        
        Args:
            email: User's email address
            user_type: Type of user (user, chef, producer, transporter)
            conn: Database connection
            
        Returns:
            dict: Response with status and message. In test mode, includes the reset code.
        """
        if not email or not user_type:
            logger.warning("Missing email or user_type in password reset request")
            return self._get_success_response()
            
        email = email.strip().lower()
        user_type = user_type.strip().lower()
        
        logger.info(f"Password reset requested for {email} (type: {user_type})")
        
        # Define valid user types and their corresponding tables/ID columns
        user_type_map = {
            'user': ('users', 'user_id'),
            'chef': ('chefs', 'chef_id'),
            'producer': ('producers', 'producer_id'),
            'transporter': ('transporters', 'transporter_id')
        }
        
        if user_type not in user_type_map:
            logger.warning(f"Invalid user_type in password reset request: {user_type}")
            return self._get_success_response()
            
        table_name, id_column = user_type_map[user_type]
        
        # First, check if the email exists in the specified table using a quick existence check
        start_time = time.time()
        try:
            user_id = await conn.fetchval(
                f"SELECT {id_column} FROM {table_name} WHERE lower(email) = $1 LIMIT 1",
                email
            )
            check_duration = (time.time() - start_time) * 1000  # Convert to milliseconds
            
            if not user_id:
                logger.info(f"[EMAIL_CHECK] Early exit - Email {email} not found in {table_name} (checked in {check_duration:.2f}ms)")
                # Return success response without revealing the email doesn't exist (security best practice)
                return self._get_success_response()
                
            logger.info(f"[PASSWORD_RESET] Starting password reset process for {email} (user_id: {user_id}, checked in {check_duration:.2f}ms)")
            
            # Generate and store the reset code within a transaction
            async with conn.transaction():
                code = await self._create_password_reset_code(conn, email, user_type)
                logger.info(f"[PASSWORD_RESET] Generated reset code for {email}")
                
                # In production, we would send an email here
                logger.warning("EMAIL SENDING TEMPORARILY DISABLED FOR TESTING")
                logger.warning(f"RESET CODE FOR {email}: {code}")
                
                # Return success response with test code
                return {
                    "status": "success",
                    "message": "Password reset code generated",
                    "test_code": code  # Only included in test mode
                }
                
        except Exception as e:
            logger.error(
                f"Error in password reset process for {email} (type: {user_type}): {e}",
                exc_info=True
            )
            return self._get_success_response()
    
    def _get_success_response(self) -> dict:
        """Return a success response to prevent email enumeration."""
        return {"status": "success", "message": "If your email is registered, you will receive a reset code"}

    async def _generate_reset_code(self) -> str:
        """Generate a 6-digit numeric code."""
        import random
        code = ''.join([str(random.randint(0, 9)) for _ in range(self.PASSWORD_RESET_CODE_LENGTH)])
        return code

    async def _create_password_reset_code(self, conn, email: str, user_type: str) -> str:
        """Create and store a password reset code."""
        from datetime import datetime, timedelta
        
        # First, verify the table exists and has the correct structure
        try:
            # Check if table exists and has required columns
            table_check = """
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'password_reset_codes'
            """
            columns = await conn.fetch(table_check)
            
            if not columns:
                logger.error("password_reset_codes table does not exist")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Password reset functionality is not properly configured"
                )
                
            # Log the table structure for debugging
            logger.info(f"password_reset_codes table structure: {[dict(col) for col in columns]}")
            
        except Exception as e:
            logger.error(f"Error checking password_reset_codes table: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to verify password reset configuration"
            )
        
        # Generate a 6-digit code
        code = await self._generate_reset_code()
        logger.info(f"[CODE_GENERATED] New reset code {code} generated for {email} (type: {user_type})")
        
        # Ensure we're using timezone-aware datetime for expiration
        expires_at = datetime.utcnow().replace(tzinfo=timezone.utc) + timedelta(minutes=self.PASSWORD_RESET_CODE_EXPIRE_MINUTES)
        logger.info(f"[CODE_STORAGE] Storing code {code} for {email}, expires at: {expires_at} (UTC)")
        
        # Delete any existing codes for this email and user_type
        try:
            logger.info(f"Deleting existing reset codes for {email} (type: {user_type})")
            result = await self._execute_query(
                conn,
                "DELETE FROM password_reset_codes WHERE email = $1 AND user_type = $2",
                (email, user_type)
            )
            logger.info(f"Deleted {result} existing reset codes")
        except Exception as e:
            logger.error(f"Error deleting existing reset codes: {e}", exc_info=True)
            # Continue anyway - we'll try to insert the new code
        
        # Insert the new code into the database
        sql = """
        INSERT INTO password_reset_codes (email, code, expires_at, user_type, is_used)
        VALUES ($1, $2, $3, $4, FALSE)
        RETURNING id, email, code, expires_at, user_type, is_used, created_at
        """
        
        try:
            logger.info(f"Storing new reset code in database for {email}")
            result = await self._execute_query(
                conn, 
                sql, 
                (email, code, expires_at, user_type),
                fetch_one=True
            )
            
            if result:
                db_record = dict(result)
                logger.info(f"[CODE_STORAGE_SUCCESS] Successfully stored code {code} in DB. Record ID: {db_record.get('id')}")
                logger.debug(f"[DB_RECORD] Full record: {db_record}")
                return code
            else:
                error_msg = "No result returned after inserting reset code"
                logger.error(f"[CODE_STORAGE_ERROR] {error_msg}")
                raise Exception(error_msg)
                
        except Exception as e:
            logger.error(f"Error creating password reset code: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create password reset code"
            )

    async def _validate_password_reset_code(self, conn, email: str, code: str, user_type: str) -> None:
        """
        Validate a password reset code.
        
        Args:
            conn: Database connection
            email: User's email address
            code: The reset code to validate
            user_type: Type of user (user, chef, producer, etc.)
            
        Raises:
            HTTPException: If the code is invalid, expired, or already used
        """
        logger.info(f"Validating reset code for {email} (type: {user_type})")
        
        # 1. Get the most recent reset code for this email/user_type
        reset_code = await self._get_reset_code(conn, email, code, user_type)
        if not reset_code:
            await self._log_failed_attempt(conn, email, user_type, "no_code_found")
            raise self._create_validation_error("Invalid or expired password reset code")
        
        # 2. Check if code is already used
        is_used = reset_code.get('is_code_used', False)
        if is_used:
            logger.warning(f"Reset code already used - ID: {reset_code.get('id')}, "
                         f"Used: {is_used}, Used Timestamp: {reset_code.get('used_at')}")
            await self._log_failed_attempt(conn, email, user_type, "code_already_used")
            raise self._create_validation_error("This password reset code has already been used")
        
        # 3. Check if code is expired
        # Ensure timezone-aware comparison
        if reset_code['expires_at'] < datetime.now(timezone.utc):
            await self._log_failed_attempt(conn, email, user_type, "code_expired")
            raise self._create_validation_error("Password reset code has expired")
        
        logger.info(f"Reset code validation successful for {email}")
    
    async def _get_reset_code(self, conn, email: str, code: str, user_type: str) -> Optional[dict]:
        """Helper to retrieve and log reset code details."""
        sql = """
        SELECT 
            id, 
            email,
            code,
            expires_at, 
            is_used,
            is_used as is_code_used,
            created_at
        FROM password_reset_codes
        WHERE email = $1 
          AND code = $2 
          AND user_type = $3
        ORDER BY created_at DESC
        """
        
        try:
            logger.debug(f"Querying reset code for - Email: '{email}', Code: '{code}', User Type: '{user_type}'")
            result = await self._execute_query(conn, sql, (email, code, user_type), fetch_one=True)
            
            if not result:
                logger.warning(f"No reset code found for - Email: '{email}', Code: '{code}', User Type: '{user_type}'")
                await self._log_missing_code(conn, email, code, user_type)
            else:
                logger.debug(f"Found reset code: ID={result.get('id')}, Expires: {result.get('expires_at')}, Used: {result.get('is_code_used')}")
                
            return result
        except Exception as e:
            logger.error(f"Error retrieving reset code for {email}: {e}", exc_info=True)
            return None
    
    async def _log_failed_attempt(self, conn, email: str, user_type: str, attempt_type: str) -> None:
        """Log failed password reset attempts for security monitoring."""
        logger.warning(f"Failed password reset attempt - Type: {attempt_type}, Email: {email}, User Type: {user_type}")
    
    def _create_validation_error(self, detail: str) -> HTTPException:
        """Create a standardized validation error response."""
        return HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=detail
        )
    
    async def _log_missing_code(self, conn, email: str, code: str, user_type: str) -> None:
        """Log details about missing reset codes for debugging."""
        all_codes_sql = """
        SELECT created_at, expires_at, is_used 
        FROM password_reset_codes 
        WHERE email = $1 AND user_type = $2
        ORDER BY created_at DESC
        """
        
        try:
            all_codes = await conn.fetch(all_codes_sql, email, user_type)
            logger.warning(f"No matching reset code found - Email: {email}, User Type: {user_type}")
            if all_codes:
                logger.info(f"Found {len(all_codes)} other reset code(s) for this email")
        except Exception as e:
            logger.error(f"Error logging missing code details: {e}")
    
    async def _mark_code_as_used(self, conn, email: str, code: str, user_type: str) -> None:
        """Mark a password reset code as used."""
        try:
            sql = """
            UPDATE password_reset_codes
            SET is_used = TRUE, used_at = NOW()
            WHERE email = $1 AND code = $2 AND user_type = $3
            """
            await conn.execute(sql, email, code, user_type)
            logger.info(f"Marked password reset code as used for {email}")
        except Exception as e:
            logger.error(f"Error marking password reset code as used for {email}: {e}")
            # Continue execution even if marking as used fails
    
    async def _send_password_reset_email(self, email: str, user_type: str, code: str) -> None:
        """
        Send a password reset email with the reset code.
        
        Args:
            email: The recipient's email address
            user_type: Type of user (user, chef, producer, etc.)
            code: The reset code to include in the email
        """
        try:
            logger.info(f"[EMAIL] Starting email send to {email}")
            logger.info(f"[EMAIL] Code being sent: {code} (length: {len(code)})")
            logger.info(f"[EMAIL] Code with quotes: '{code}'")
            logger.info(f"[EMAIL] User type: {user_type}")
            
            # Log the actual email content that will be sent
            email_content = f"""
            <html>
                <body>
                    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                        <h2>Password Reset Request</h2>
                        <p>Hello,</p>
                        <p>We received a request to reset the password for your {user_type.capitalize()} account.</p>
                        <p>Your password reset code is: <strong>{code}</strong></p>
                        <p>Please enter this code in the app to reset your password. This code will expire in 10 minutes.</p>
                        <p>If you didn't request this password reset, you can safely ignore this email.</p>
                        <p>Best regards,<br>The Zinzi Team</p>
                    </div>
                </body>
            </html>
            """
            logger.debug(f"[EMAIL] Email content preview: {email_content[:200]}...")
            
            # Email subject
            subject = "Your Password Reset Code"
            
            # Email body with HTML formatting
            body = f"""
            <html>
                <body>
                    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
                        <h2>Password Reset Request</h2>
                        <p>Hello,</p>
                        <p>We received a request to reset the password for your {user_type.capitalize()} account.</p>
                        <p>Your password reset code is: <strong>{code}</strong></p>
                        <p>Please enter this code in the app to reset your password. This code will expire in 10 minutes.</p>
                        <p>If you didn't request this password reset, you can safely ignore this email.</p>
                        <p>Best regards,<br>The Zinzi Team</p>
                    </div>
                </body>
            </html>
            """
            
            # Send the email
            await self._send_email(email, subject, body)
            logger.info(f"Password reset email sent successfully to {email}")
            
        except Exception as e:
            logger.error(f"Error sending password reset email to {email}: {e}", exc_info=True)
            # Re-raise the exception to be handled by the caller
            raise
    
    async def _send_email(self, to_email: str, subject: str, body: str) -> None:
        """
        Helper method to send an email using Gmail SMTP.
        
        Args:
            to_email: Recipient email address
            subject: Email subject
            body: Email body (HTML)
        """
        import smtplib
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart
        import os
        
        # Get email credentials from environment variables
        sender_email = os.getenv("GMAIL_USERNAME")
        password = os.getenv("GMAIL_APP_PASSWORD")
        
        if not sender_email or not password:
            logger.error("Email credentials not configured")
            return
            
        try:
            # Create message
            msg = MIMEMultipart()
            msg['From'] = sender_email
            msg['To'] = to_email
            msg['Subject'] = subject
            
            # Attach HTML body
            msg.attach(MIMEText(body, 'html'))
            
            # Connect to Gmail SMTP server and send email
            with smtplib.SMTP_SSL('smtp.gmail.com', 465) as server:
                server.login(sender_email, password)
                server.send_message(msg)
                
        except Exception as e:
            logger.error(f"Error sending email to {to_email}: {e}")
            raise

    async def _handle_email_verification(self, conn, email: str, user_id: int, user_type: str, verification_code: str = None) -> str:
        """
        Handles the email verification process - generates and stores a verification code.
        Returns the verification code for sending in a background task.
        
        Args:
            conn: Database connection
            email: User's email address
            user_id: User's ID
            user_type: Type of user (user, chef, producer, etc.)
            verification_code: Optional pre-generated verification code to use
            
        Returns:
            str: The verification code (generated or provided)
        """
        # Generate a new code if none provided
        if verification_code is None:
            verification_code = ''.join(random.choices(string.digits, k=6))
        
        # Delete any existing verification codes for this user
        await conn.execute(
            """
            DELETE FROM email_verifications 
            WHERE user_id = $1 AND user_type = $2
            """,
            user_id, user_type
        )
        
        try:
            # Insert new verification code
            await conn.execute(
                """
                INSERT INTO email_verifications 
                (user_id, verification_code, user_type, created_at, expires_at) 
                VALUES ($1, $2, $3, NOW(), NOW() + INTERVAL '10 minutes')
                """,
                user_id, verification_code, user_type
            )
            logger.info(f"Generated email verification code for user {user_id} ({user_type})")
            return verification_code
            
        except Exception as e:
            logger.error(f"Failed to generate email verification code for user {user_id}: {e}")
            # Re-raise the exception to be handled by the caller
            raise
            
    async def signup_user(self, conn: asyncpg.Connection, 
                         name: str, 
                         email: str, 
                         password: str, 
                         user_type: str = 'user',
                         image: Optional[str] = None,
                         phone: Optional[str] = None,
                         background_tasks: Optional[BackgroundTasks] = None) -> Dict[str, Any]:
        """
        Register a new user with the provided information.
        
        Args:
            conn: Database connection
            name: User's full name
            email: User's email address (will be converted to lowercase)
            password: Plain text password (will be hashed)
            user_type: Type of user (default: 'user')
            image: Optional URL to user's profile image
            phone: Optional user's phone number
            background_tasks: FastAPI BackgroundTasks instance for sending verification email asynchronously
            
        Returns:
            Dict containing user_id, phone, and success status
            
        Raises:
            HTTPException: If signup validation fails or user already exists
        """
        # Input validation
        email_lower = email.strip().lower()
        if not email_lower or '@' not in email_lower or '.' not in email_lower.split('@')[-1]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Please provide a valid email address"
            )
            
        if not name or len(name.strip()) < 2:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Please provide a valid name (at least 2 characters)"
            )
            
        if not password or len(password) < 3:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be atleast 3 characters long, prefered is 6 or 8 but 3 for now"
            )
        
        # Normalize user_type
        user_type = (user_type or 'user').lower().strip()
        
        # Hash password
        hashed_pw = hash_password(password)
        
        try:
            # Check if email already exists first, before starting a transaction
            existing_user = await conn.fetchval(
                "SELECT user_id FROM users WHERE lower(email) = $1 AND user_type = $2",
                email_lower, user_type
            )
            
            if existing_user:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"Email '{email}' is already registered for user type '{user_type}'"
                )
            
            # Start transaction after the initial check
            async with conn.transaction():
                # Insert the new user
                user_id = await conn.fetchval(
                    """
                    INSERT INTO users (name, email, hashed_password, user_type, phone_number, image, registration_date, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
                    RETURNING user_id
                    """,
                    name.strip(),
                    email_lower,
                    hashed_pw,
                    user_type,
                    phone.strip() if phone else None,
                    image.strip() if image else None
                )
                
                # Generate and store verification code (synchronously)
                verification_code = await self._handle_email_verification(conn, email_lower, user_id, user_type)
                
                # Schedule email sending in background if background_tasks is provided
                if background_tasks is not None:
                    background_tasks.add_task(
                        self.send_verification_email_gmail,
                        to_email=email_lower,
                        verification_code=verification_code
                    )
                else:
                    # Fallback to synchronous sending if no background_tasks provided
                    await self.send_verification_email_gmail(to_email=email_lower, verification_code=verification_code)
                
                logger.info(f"User '{name}' (ID: {user_id}) registered successfully with user type {user_type}")
                return {
                    "user_id": user_id, 
                    "phone": phone.strip() if phone else None, 
                    "email": email_lower,
                    "success": True,
                    "message": "User registered successfully. Please check your email for verification."
                }
                
        except HTTPException as he:
            # Re-raise HTTPException to maintain the original status code
            logger.warning(f"Signup failed for {email}: {he.detail}")
            raise he
        except ValueError as e:
            logger.warning(f"Signup validation failed for {email}: {e}")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
        except asyncpg.exceptions.UniqueViolationError as e:
            logger.warning(f"Signup failed due to unique constraint for {email}: {e.detail}")
            # Determine if it was email or name based on the error detail if possible
            detail = "Email or Name already exists."
            if 'email' in str(e.detail).lower() or 'users_email_key' in str(e.constraint_name): 
                detail = f"Email '{email}' is already registered."
            elif 'name' in str(e.detail).lower() or 'users_name_key' in str(e.constraint_name): 
                detail = f"Name '{name}' is already taken."
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail) from e
        except asyncpg.PostgresError as e:
            logger.error(f"Database error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An internal error occurred during signup.") from e
        except Exception as e:
            logger.error(f"Unexpected error during signup for {email}: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected server error occurred.") from e
    async def verify_user_email(self, conn: asyncpg.Connection, user_id: int, verification_code: str, user_type: str) -> None:
        # Get current timestamp for reference
        current_time = datetime.now()
        
        # Define mapping of user types to their respective tables and ID columns
        USER_TYPE_TABLES = {
            'user': 'users',
            'chef': 'chefs',
            'producer': 'producers',
            'transporter': 'transporters',
            'stakeholder': 'stakeholders'
        }
        
        # Normalize user_type to lowercase for case-insensitive comparison
        user_type_lower = user_type.lower()
        
        # Validate user_type
        if user_type_lower not in USER_TYPE_TABLES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f'Invalid user type: {user_type}. Must be one of: {list(USER_TYPE_TABLES.keys())}'
            )
        
        # Get the appropriate table name for this user type
        table_name = USER_TYPE_TABLES[user_type_lower]
        
        # Log the verification attempt with all relevant details
        logger.info(
            f"Verification attempt - "
            f"User ID: {user_id}, "
            f"Type: {user_type} (table: {table_name}), "
            f"Code: {verification_code}, "
            f"Current Time: {current_time}"
        )
        
        # First, check if there are any verification codes for this user at all
        user_codes_query = """
            SELECT verification_code, created_at, expires_at, 
                   NOW() > expires_at as is_expired,
                   expires_at - NOW() as time_remaining,
                   user_type as actual_user_type
            FROM email_verifications 
            WHERE user_id = $1 AND LOWER(user_type) = LOWER($2)
            ORDER BY created_at DESC
        """
        
        # Then check for the specific code (case-insensitive user_type)
        check_query = """
            SELECT verification_code, created_at, expires_at, 
                   NOW() > expires_at as is_expired,
                   expires_at - NOW() as time_remaining,
                   user_type as actual_user_type
            FROM email_verifications 
            WHERE user_id = $1 
              AND verification_code = $2 
              AND LOWER(user_type) = LOWER($3)
        """
        
        # Dynamic update query based on user type
        update_query = f"UPDATE {table_name} SET is_email_verified = TRUE WHERE "
        if user_type_lower == 'user':
            update_query += "user_id"
        elif user_type_lower == 'chef':
            update_query += "chefid"
        elif user_type_lower == 'producer':
            update_query += "producer_id"
        elif user_type_lower == 'transporter':
            update_query += "transporter_id"
        elif user_type_lower == 'stakeholder':
            update_query += "stakeholder_id"
        update_query += " = $1"
        
        delete_query = "DELETE FROM email_verifications WHERE user_id = $1 AND verification_code = $2"
        
        try:
            async with conn.transaction():
                # Get the verification record with expiration info
                record = await conn.fetchrow(check_query, user_id, verification_code, user_type)
                
                if not record:
                    # Log all verification codes for this user to help with debugging
                    user_codes = await conn.fetch(user_codes_query, user_id, user_type)
                    if user_codes:
                        codes_info = [
                            f"Code: {code['verification_code']} "
                            f"(Created: {code['created_at']}, "
                            f"Expires: {code['expires_at']}, "
                            f"Status: {'Expired' if code['is_expired'] else 'Active'})"
                            for code in user_codes
                        ]
                        logger.warning(
                            f"Verification failed - No matching code found. "
                            f"User ID: {user_id}, Type: {user_type}, "
                            f"Code provided: {verification_code}. "
                            f"User's verification codes: {', '.join(codes_info)}"
                        )
                    else:
                        logger.warning(
                            f"Verification failed - No verification codes found for user. "
                            f"User ID: {user_id}, Type: {user_type}, "
                            f"Code provided: {verification_code}"
                        )
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST, 
                        detail='Invalid verification code or incorrect user type.'
                    )
                
                # Log detailed verification status
                logger.info(
                    f"Verification details - "
                    f"Code created: {record['created_at']}, "
                    f"Expires at: {record['expires_at']}, "
                    f"Is expired: {record['is_expired']}, "
                    f"Time remaining: {record['time_remaining']}, "
                    f"User type in DB: {record['actual_user_type']}, "
                    f"User type provided: {user_type}"
                )
                
                if record['is_expired']:
                    logger.warning(
                        f"Verification failed - Code expired. "
                        f"Expired at: {record['expires_at']}, "
                        f"Current time: {current_time}"
                    )
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST, 
                        detail='Verification code has expired. Please request a new one.'
                    )
                
                # If we get here, verification is successful
                await conn.execute(update_query, user_id)
                await conn.execute(delete_query, user_id, verification_code)
                
                logger.info(
                    f"Verification successful - "
                    f"User ID: {user_id}, "
                    f"Type: {user_type}, "
                    f"Code verified at: {current_time}, "
                    f"Time to expiry: {record['time_remaining']}"
                )
                
        except HTTPException as he:
            raise
        except asyncpg.PostgresError as e:
            logger.error(
                f"Database error during verification - "
                f"User ID: {user_id}, Type: {user_type}, Error: {str(e)}", 
                exc_info=True
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
                detail='An error occurred during email verification.'
            ) from e
        except Exception as e:
            logger.error(
                f"Unexpected error during verification - "
                f"User ID: {user_id}, Type: {user_type}, Error: {str(e)}", 
                exc_info=True
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
                detail='An unexpected server error occurred during verification.'
            ) from e

    async def send_verification_email_gmail(self, to_email: str, verification_code: str):
        """
        Send verification email using Gmail SMTP with App Password authentication.
        
        Args:
            to_email: Recipient email address
            verification_code: The verification code to send
            
        Raises:
            Exception: If email sending fails
        """
        import smtplib
        import ssl
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart
        import os
        from dotenv import load_dotenv
        
        # Load environment variables
        load_dotenv()
        
        # Configuration - Update these in your .env file
        SMTP_SERVER = 'smtp.gmail.com'
        SMTP_PORT = 587  # For starttls
        SENDER_EMAIL = os.getenv('GMAIL_USERNAME')   # Your Gmail address
        APP_PASSWORD = os.getenv('GMAIL_APP_PASSWORD')  # Your 16-character app password
        
        if not APP_PASSWORD:
            error_msg = "GMAIL_APP_PASSWORD not found in environment variables"
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        try:
            logger.info(f"Attempting to send verification email to {to_email}")
            
            # Email styling and template
            subject = "🔐 Your ZINZI Verification Code"
            body = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body {{
                        font-family: 'Arial', sans-serif;
                        line-height: 1.6;
                        color: #333333;
                        max-width: 600px;
                        margin: 0 auto;
                        padding: 20px;
                    }}
                    .container {{
                        border: 1px solid #e0e0e0;
                        border-radius: 8px;
                        overflow: hidden;
                    }}
                    .header {{
                        background-color: #4CAF50;  /* ZINZI green */
                        padding: 20px;
                        text-align: center;
                    }}
                    .header img {{
                        max-width: 150px;
                        height: auto;
                    }}
                    .content {{
                        padding: 30px;
                        background-color: #ffffff;
                    }}
                    .verification-code {{
                        background-color: #f8f9fa;
                        border: 2px dashed #4CAF50;
                        color: #4CAF50;
                        font-size: 28px;
                        font-weight: bold;
                        letter-spacing: 5px;
                        padding: 15px 25px;
                        margin: 25px 0;
                        text-align: center;
                        border-radius: 4px;
                        display: inline-block;
                    }}
                    .button {{
                        display: inline-block;
                        padding: 12px 25px;
                        background-color: #4CAF50;
                        color: white !important;
                        text-decoration: none;
                        border-radius: 4px;
                        font-weight: bold;
                        margin: 15px 0;
                    }}
                    .footer {{
                        text-align: center;
                        padding: 20px;
                        font-size: 12px;
                        color: #999999;
                        background-color: #f8f9fa;
                    }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1 style="color: white; margin: 0;">ZINZI</h1>
                        <p style="color: white; margin: 5px 0 0 0;">Healthy Food, Happy Life</p>
                    </div>
                    
                    <div class="content">
                        <h2>Welcome to ZINZI! 🌱</h2>
                        <p>Thank you for joining our community of health-conscious individuals. To complete your registration, please verify your email address using the code below:</p>
                        
                        <div class="verification-code">
                            {verification_code}
                        </div>
                        
                        <p>This code will expire in soon for security reasons.</p>
                        
                        <p>If you didn't request this, please ignore this email or contact our support team if you have any concerns.</p>
                        
                        <p>Best regards,<br>The ZINZI Team</p>
                    </div>
                    
                    <div class="footer">
                        <p>© {datetime.now().year} ZINZI. All rights reserved.</p>
                        <p>Kampala, Uganda | <a href="https://zinzi.ug" style="color: #4CAF50; text-decoration: none;">zinzi.ug</a></p>
                    </div>
                </div>
            </body>
            </html>
            """
            
            # Create message container
            message = MIMEMultipart('alternative')
            message['From'] = SENDER_EMAIL
            message['To'] = to_email
            message['Subject'] = subject
            
            # Attach HTML version
            message.attach(MIMEText(body, 'html'))
            
            # Create secure connection with server and send email
            context = ssl.create_default_context()
            
            with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
                server.ehlo()  # Can be omitted
                server.starttls(context=context)
                server.ehlo()  # Can be omitted
                server.login(SENDER_EMAIL, APP_PASSWORD)
                server.send_message(message)
            
            logger.info(f"Verification email sent to {to_email}")
            
        except Exception as e:
            error_msg = f"Failed to send verification email to {to_email}: {str(e)}"
            logger.error(error_msg, exc_info=True)
            raise ConnectionError(error_msg) from e

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
        sql = "SELECT user_id, hashed_password, user_type, is_email_verified, phone_number FROM users WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        try:
            result = await self._execute_query(conn, sql, params, fetch_one=True)
            if not result:
                logger.warning(f"Login failed: Identifier '{identifier}' not found.")
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name or account not found.')
            user_id = result['user_id']; stored_hashed_password = result['hashed_password']; user_type = result.get('user_type', 'user'); is_verified = result.get('is_email_verified', False)
            if not is_verified:
                logger.warning(f"Login failed: Email not verified for user '{identifier}'")
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Email not verified. Please verify your email before logging in.')
            stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8') if isinstance(stored_hashed_password, str) else stored_hashed_password
            if not isinstance(stored_hashed_pw_bytes, bytes):
                 logger.error(f"Invalid hashed_password type for user {user_id}. Type: {type(stored_hashed_password)}")
                 raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Internal server error during login.')
            if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
                update_sql = "UPDATE users SET last_login = NOW() WHERE user_id = $1"
                try: await self._execute_query(conn, update_sql, (user_id,)) # Use _execute_query
                except Exception as update_err: logger.error(f"Failed to update last_login for user {user_id}: {update_err}")
                return {'message': 'Login successful', 'data': {'user_id': user_id, 'user_type': user_type, 'verified': is_verified, 'phone': result.get('phone_number')}}
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
    async def create_metric(
        self, 
        conn: asyncpg.Connection, 
        metric_data: Dict[str, Any],
        background_tasks: Optional[BackgroundTasks] = None
    ) -> Dict[str, int]:
        """
        Create a new user metric entry with synchronous calculation of non-goal-dependent fields.
        
        Args:
            conn: Database connection
            metric_data: Dictionary containing metric data
            background_tasks: Not used, kept for backward compatibility
            
        Returns:
            Dictionary containing the metric_id of the created record
        """
        metric_data_lower = lowercase_keys(metric_data)
        check_required_fields(metric_data_lower, ['user_id', 'weight', 'height', 'sex', 'activity_level', 'age_range'])
        
        try:
            # Extract and validate required fields
            user_id = int(metric_data_lower['user_id'])
            weight = float(metric_data_lower['weight'])
            height = float(metric_data_lower['height'])
            sex = str(metric_data_lower['sex']).lower()  # Ensure lowercase for consistency
            activity_level = str(metric_data_lower['activity_level']).lower()  # Ensure lowercase for consistency
            age_range = str(metric_data_lower['age_range']).strip()  # Required field, ensure string and trim whitespace
            
            # Extract optional fields with default values
            cholesterol_level = float(metric_data_lower['cholesterol_level']) if 'cholesterol_level' in metric_data_lower and metric_data_lower['cholesterol_level'] is not None else None
            sys_bp = float(metric_data_lower['sys_bp']) if 'sys_bp' in metric_data_lower and metric_data_lower['sys_bp'] is not None else None
            dia_bp = float(metric_data_lower['dia_bp']) if 'dia_bp' in metric_data_lower and metric_data_lower['dia_bp'] is not None else None
            pulse = float(metric_data_lower['pulse']) if 'pulse' in metric_data_lower and metric_data_lower['pulse'] is not None else None
            
            # Calculate non-goal-dependent metrics
            calc = CalculationLogic()
            bmi = calc.calculate_bmi(weight, height)
            bmi_category = calc.calculate_bmi_category(bmi) if bmi is not None else None
            
            # Calculate ideal weight and format it as a string with unit
            ideal_weight_value = calc.calculate_ideal_weight(height, sex) if sex else None
            ideal_weight = f"{ideal_weight_value:.1f} kg" if ideal_weight_value is not None else None
            
            bmr = calc.calculate_bmr(weight, height, age_range, sex) if age_range and sex else None
            
            # Insert the metric with all non-goal-dependent calculations
            sql = """
                INSERT INTO user_metrics 
                (user_id, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, 
                 age_range, sex, activity_level, bmi, bmi_category, ideal_weight, bmr)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
            """
            
            # Prepare parameters with proper type conversion
            params = (
                int(user_id),  # Ensure user_id is an integer
                float(weight),  # Convert to float explicitly
                float(height),  # Convert to float explicitly
                float(cholesterol_level) if cholesterol_level is not None else None,
                float(sys_bp) if sys_bp is not None else None,
                float(dia_bp) if dia_bp is not None else None,
                float(pulse) if pulse is not None else None,
                str(age_range) if age_range is not None else None,  # Ensure string
                str(sex).lower() if sex is not None else None,  # Ensure lowercase string
                str(activity_level).lower() if activity_level is not None else None,  # Ensure lowercase string
                float(bmi) if bmi is not None else None,  # Ensure float
                str(bmi_category) if bmi_category is not None else None,  # Ensure string
                str(ideal_weight) if ideal_weight is not None else None,  # Ensure string
                float(bmr) if bmr is not None else None  # Ensure float
            )
            
            # Execute the insert
            await conn.execute(sql, *params)
            logger.info("Successfully created user metrics")
            
            # Return success message
            return {"message": "User metrics created successfully"}
            
        except (ValueError, TypeError) as e:
            logger.error(f"Invalid metric data format: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid metric data format: {str(e)}"
            )
        except Exception as e:
            logger.error(f"Error creating metric: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to create metric: {str(e)}"
            )
        
    async def _calculate_and_update_metrics(
        self,
        conn: asyncpg.Connection,
        metric_id: int,
        user_id: int,
        weight: float,
        height: float,
        age_range: Optional[str],
        sex: Optional[str],
        activity_level: Optional[str]
    ) -> None:
        """
        Calculate and update daily calories for a given metric entry based on user goals.
        
        This method is designed to be run in the background when preferences are updated.
        If no goal is found in preferences, the calculation is skipped.
        
        Args:
            conn: Database connection
            metric_id: ID of the metric to update
            user_id: ID of the user
            weight: User's weight in kg
            height: User's height in cm (unused in this method, kept for backward compatibility)
            age_range: User's age range (unused in this method, kept for backward compatibility)
            sex: User's sex (unused in this method, kept for backward compatibility)
            activity_level: User's activity level (unused in this method, kept for backward compatibility)
        """
        try:
            # Get user preferences for goals if available
            pref_row = await conn.fetchrow(
                """
                SELECT goals 
                FROM user_preferences 
                WHERE user_id = $1 
                ORDER BY preference_id DESC
                LIMIT 1
                """,
                user_id
            )
            
            # Get activity level from user_metrics
            metrics_row = await conn.fetchrow(
                """
                SELECT activity_level 
                FROM user_metrics 
                WHERE user_id = $1 
                ORDER BY recorded_at DESC
                LIMIT 1
                """,
                user_id
            )
            
            # If no goals or activity level found, skip the calculation
            if not pref_row or not pref_row.get('goals') or not metrics_row or not metrics_row.get('activity_level'):
                logger.debug(f"No goals or activity level found for user {user_id}. Skipping daily calories calculation.")
                return
                
            goals = pref_row['goals']
            activity_level = metrics_row['activity_level']
            
            # Get the latest metrics to calculate BMR
            metrics_row = await conn.fetchrow(
                """
                SELECT bmr FROM user_metrics 
                WHERE user_id = $1 
                ORDER BY recorded_at DESC 
                LIMIT 1
                """,
                user_id
            )
            
            if not metrics_row or metrics_row['bmr'] is None:
                logger.debug(f"No BMR found for user {user_id}. Cannot calculate daily calories.")
                return
                
            bmr = float(metrics_row['bmr'])
            
            # Calculate daily calories based on BMR, activity level, and goals
            calc = CalculationLogic()
            daily_calories = calc.calculate_daily_calories(bmr, activity_level, goals)
            
            if daily_calories is not None:
                daily_cals = float(daily_calories)
                
                # Update only the daily_calories field for the most recent metric
                result = await conn.execute(
                    """
                    WITH latest_metric AS (
                        SELECT metric_id 
                        FROM user_metrics 
                        WHERE user_id = $1 
                        ORDER BY recorded_at DESC 
                        LIMIT 1
                        FOR UPDATE
                    )
                    UPDATE user_metrics um
                    SET daily_calories = $2::numeric
                    FROM latest_metric lm
                    WHERE um.metric_id = lm.metric_id
                    RETURNING um.metric_id
                    """,
                    user_id,
                    daily_cals
                )
                
                if not result or 'UPDATE 0' in result:
                    logger.warning(f"No metrics found to update daily calories for user_id: {user_id}")
                else:
                    logger.info(f"Successfully updated daily calories to {daily_cals} for user_id: {user_id} (goal: {goals})")
            
        except Exception as e:
            logger.error(f"Error calculating daily calories for user_id {user_id}: {e}", exc_info=True)
            # Don't re-raise to prevent background tasks from failing silently

    async def _mark_code_as_used(self, conn, email: str, code: str, user_type: str) -> None:
        """
        Mark a password reset code as used in the database.
        
        Args:
            conn: Database connection
            email: User's email address
            code: The reset code to mark as used
            user_type: Type of user (user, chef, producer, etc.)
            
        Note:
            This method logs errors but does not raise exceptions to avoid
            failing the password reset process if marking the code fails.
        """
        logger.info(f"Marking reset code as used - Email: {email}")
        
        try:
            result = await self._execute_query(
                conn,
                """
                UPDATE password_reset_codes 
                SET is_used = TRUE 
                WHERE email = $1 
                  AND code = $2 
                  AND user_type = $3
                RETURNING id
                """,
                (email, code, user_type),
                fetch_one=True
            )
            
            if not result:
                logger.warning(f"No matching reset code found to mark as used - Email: {email}")
            else:
                logger.info(f"Successfully marked reset code as used - ID: {result['id']}")
                
        except Exception as e:
            logger.error(
                f"Error marking reset code as used - Email: {email}, Error: {e}",
                exc_info=True
            )

    async def _recalculate_daily_calories_in_new_connection(self, user_id: int):
        """
        Recalculate and update daily calories in a new database connection.
        This is a helper method that can be called without blocking the main request.
        """
        # Use the global db_pool
        global db_pool
        if not db_pool:
            logger.error("Database pool is not initialized")
            return
            
        async with db_pool.acquire() as conn:
            try:
                # Fetch the latest metrics for the user
                metric_row = await conn.fetchrow(
                    """
                    SELECT metric_id, weight, height, age_range, sex, activity_level
                    FROM user_metrics 
                    WHERE user_id = $1 
                    ORDER BY recorded_at DESC 
                    LIMIT 1
                    """,
                    user_id
                )
                
                if not metric_row:
                    logger.warning(f"No metrics found for user {user_id} when recalculating daily calories")
                    return
                
                metric_id = metric_row['metric_id']
                
                # Call the main calculation method with the required parameters
                await self._calculate_and_update_metrics(
                    conn=conn,
                    metric_id=metric_id,
                    user_id=user_id,
                    weight=float(metric_row['weight']),
                    height=float(metric_row['height']),
                    age_range=metric_row['age_range'],
                    sex=metric_row['sex'],
                    activity_level=metric_row['activity_level']
                )
                
                logger.info(f"Successfully completed daily calories recalculation for user {user_id}")
                
            except Exception as e:
                logger.error(f"Error in _recalculate_daily_calories for user_id {user_id}: {e}", exc_info=True)
    
    async def _recalculate_daily_calories(self, conn: asyncpg.Connection, user_id: int):
        """
        Recalculate and update daily calories using the provided connection.
        This is kept for backward compatibility with synchronous calls.
        """
        try:
            # Fetch the latest metrics for the user
            metric_row = await conn.fetchrow(
                """
                SELECT metric_id, weight, height, age_range, sex, activity_level
                FROM user_metrics 
                WHERE user_id = $1 
                ORDER BY recorded_at DESC 
                LIMIT 1
                """,
                user_id
            )
            
            if not metric_row:
                logger.warning(f"No metrics found for user {user_id} when recalculating daily calories")
                return
            
            metric_id = metric_row['metric_id']
            
            # Call the main calculation method with the required parameters
            await self._calculate_and_update_metrics(
                conn=conn,
                metric_id=metric_id,
                user_id=user_id,
                weight=float(metric_row['weight']),
                height=float(metric_row['height']),
                age_range=metric_row['age_range'],
                sex=metric_row['sex'],
                activity_level=metric_row['activity_level']
            )
            
            logger.info(f"Successfully triggered daily calories recalculation for user {user_id}")
            
        except Exception as e:
            logger.error(f"Error in _recalculate_daily_calories for user_id {user_id}: {e}", exc_info=True)

    async def update_metric(self, conn: asyncpg.Connection, user_id: int, updates: Dict[str, Any]):
        # Update independent fields for latest metric row for this user
        updates_lower = lowercase_keys(updates)
        set_clauses = []
        params = []
        idx = 1
        allowed = ['age_range','weight','height','bmi','ideal_weight','daily_calories',
                 'cholesterol_level','sys_bp','dia_bp','pulse','sex','activity_level','goals']
        
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates.")
            
        # Strictly map and validate update keys
        unknown_keys = [k for k in updates_lower if k not in allowed]
        if unknown_keys:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail=f"Unknown or misspelled fields: {', '.join(unknown_keys)}. Allowed fields: {', '.join(allowed)}."
            )
            
        # Define expected types for each field
        field_types = {
            'age_range': str,
            'weight': float,
            'height': float,
            'bmi': float,
            'ideal_weight': str,  # Stored as string with unit (e.g. '71.8 kg')
            'daily_calories': float,
            'cholesterol_level': float,
            'sys_bp': float,
            'dia_bp': float,
            'pulse': float,
            'sex': str,
            'activity_level': str,
            'goals': str
        }
        
        # Log the update payload and types for debugging
        logger.info(f"update_metric: user_id={user_id}, updates={updates_lower}")
        
        # Process updates
        for k in allowed:
            if k in updates_lower:
                v = updates_lower[k]
                # Strict validation for string fields
                if k in ['age_range', 'sex', 'activity_level', 'goals']:
                    if v is not None and not isinstance(v, str):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST, 
                            detail=f"Field '{k}' must be a string, got {type(v).__name__}: {v}"
                        )
                # Cast to correct type if not None
                if v is not None and k in field_types:
                    try:
                        if k == 'ideal_weight':
                            # Special handling for ideal_weight to ensure consistent formatting
                            if isinstance(v, (int, float)):
                                v = f"{float(v):.1f} kg"
                            elif isinstance(v, str) and 'kg' not in v:
                                try:
                                    # If it's a string without 'kg', try to convert to float and format
                                    v = f"{float(v):.1f} kg"
                                except (ValueError, TypeError):
                                    logger.warning(f"Invalid ideal_weight format: {v}")
                                    continue
                        else:
                            v = field_types[k](v)
                    except (ValueError, TypeError) as e:
                        logger.warning(f"Failed to cast {k}={v} to {field_types[k].__name__}: {e}")
                        continue
                
                set_clauses.append(f"{k}=${idx}")
                params.append(v)
                idx += 1
        
        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields to update.")
        
        # Update the user metrics
        update_sql = f"""
            UPDATE user_metrics 
            SET {', '.join(set_clauses)}, recorded_at = NOW()
            WHERE user_id = ${idx}
            RETURNING *
        """
        
        try:
            # Execute the update and get the updated row
            updated_row = await conn.fetchrow(update_sql, *params, user_id)
            if not updated_row:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User metrics not found")
                
            logger.info(f"Updated metrics for user_id: {user_id}")
            
            # Check if we need to trigger a recalculation of daily calories
            # Recalculate if any field affecting BMR or activity/goals changes
            needs_recalculation = any(field in updates_lower for field in 
                                   ['weight', 'height', 'age_range', 'sex', 'activity_level', 'goals'])
            
            # Check if we need to update metrics based on changed fields
            metrics_to_update = {}
            calc = CalculationLogic()
            
            # Get current values from updates or existing row
            current_weight = float(updates_lower.get('weight', updated_row['weight']))
            current_height = float(updates_lower.get('height', updated_row['height']))
            current_sex = str(updates_lower.get('sex', updated_row.get('sex', ''))).lower()
            current_age_range = str(updates_lower.get('age_range', updated_row.get('age_range', '')))
            
            # 1. Recalculate BMI if weight or height changed
            if 'weight' in updates_lower or 'height' in updates_lower:
                if current_weight and current_height:
                    new_bmi = calc.calculate_bmi(current_weight, current_height)
                    metrics_to_update['bmi'] = new_bmi
                    logger.info(f"Recalculated BMI to {new_bmi} for user_id: {user_id}")
                    
                    # 2. Recalculate BMI Category based on new BMI
                    bmi_category = calc.calculate_bmi_category(new_bmi)
                    metrics_to_update['bmi_category'] = bmi_category
                    logger.info(f"Updated BMI category to {bmi_category} for user_id: {user_id}")
            
            # 3. Recalculate Ideal Weight if height or sex changed
            if 'height' in updates_lower or 'sex' in updates_lower:
                if current_height and current_sex:
                    ideal_weight_value = calc.calculate_ideal_weight(current_height, current_sex)
                    ideal_weight = f"{ideal_weight_value:.1f} kg"  # Format as string with unit
                    metrics_to_update['ideal_weight'] = ideal_weight
                    logger.info(f"Recalculated ideal weight to {ideal_weight} for user_id: {user_id}")
            
            # 4. Recalculate BMR if weight, height, age_range, or sex changed
            bmr_fields = ['weight', 'height', 'age_range', 'sex']
            if any(field in updates_lower for field in bmr_fields):
                if all(v for v in [current_weight, current_height, current_age_range, current_sex]):
                    bmr = calc.calculate_bmr(current_weight, current_height, current_age_range, current_sex)
                    metrics_to_update['bmr'] = bmr
                    logger.info(f"Recalculated BMR to {bmr} for user_id: {user_id}")
            
            # Update all calculated metrics in a single query if we have any to update
            if metrics_to_update:
                set_clauses = []
                params = []
                param_index = 1
                
                for field, value in metrics_to_update.items():
                    set_clauses.append(f"{field} = ${param_index}")
                    params.append(value)
                    param_index += 1
                
                # Add user_id and metric_id to params
                params.extend([user_id, updated_row['metric_id']])
                
                # Execute the update
                await conn.execute(
                    f"""
                    UPDATE user_metrics 
                    SET {', '.join(set_clauses)}
                    WHERE user_id = ${param_index} AND metric_id = ${param_index + 1}
                    """,
                    *params
                )
                logger.info(f"Updated metrics for user_id {user_id}: {', '.join(metrics_to_update.keys())}")
            
            if needs_recalculation:
                # Start an async task to recalculate daily calories without blocking
                # Don't pass the connection to the background task, it will get its own
                asyncio.create_task(self._recalculate_daily_calories_in_new_connection(user_id))
                logger.info(f"Started async recalculation of daily calories for user_id: {user_id}")
            
            # Always insert a new entry in metrics_history whenever weight is updated
            if 'weight' in updates_lower:
                try:
                    weight_f = float(updates_lower['weight'])
                    logger.info(f"[METRICS_HISTORY] Preparing to log weight update - User: {user_id}, New Weight: {weight_f}")
                    result = await conn.execute(
                        """
                        INSERT INTO metrics_history (user_id, weight, logged_at) 
                        VALUES ($1, $2, NOW())
                        """,
                        user_id, weight_f
                    )
                    logger.info(f"[METRICS_HISTORY] Successfully logged new weight {weight_f} for user {user_id} in metrics_history. Rows affected: {result}")
                except Exception as e:
                    logger.error(f"[METRICS_HISTORY] Failed to log weight in metrics_history. User: {user_id}, Error: {e}", exc_info=True)
            
            return {"message": "Metrics updated successfully", "user_id": user_id}
            
        except Exception as e:
            logger.error(f"Error updating metrics for user_id {user_id}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to update metrics: {str(e)}"
            )

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
    async def create_preference(
        self, 
        conn: asyncpg.Connection, 
        preference_data: Dict[str, Any],
        background_tasks: Optional[BackgroundTasks] = None
    ) -> Dict[str, int]:
        """
        Create a new user preference entry and trigger metric recalculation if goals are provided.
        
        Args:
            conn: Database connection
            preference_data: Dictionary containing preference data
            background_tasks: Optional FastAPI BackgroundTasks instance for non-blocking operations
            
        Returns:
            Dictionary containing the preference_id of the created record
        """
        preference_data_lower = lowercase_keys(preference_data)
        check_required_fields(preference_data_lower, ['user_id'])
        
        try:
            # Extract and validate fields
            user_id = int(preference_data_lower['user_id'])
            goals = preference_data_lower.get('goals')
            
            # Insert into user_preferences table
            sql = """
                INSERT INTO user_preferences 
                (user_id, goals, food_restrictions, diet_type, cuisine_preferences)
                VALUES ($1, $2, $3, $4, $5)
            """
            
            # Handle food_restrictions and cuisine_preferences as strings
            food_restrictions = preference_data_lower.get('food_restrictions')
            if isinstance(food_restrictions, list):
                food_restrictions = ','.join(str(item).strip() for item in food_restrictions if item)
                
            cuisine_preferences = preference_data_lower.get('cuisine_preferences')
            if isinstance(cuisine_preferences, list):
                cuisine_preferences = ','.join(str(item).strip() for item in cuisine_preferences if item)
            
            diet_type = preference_data_lower.get('diet_type')
            
            params = (
                user_id,
                goals,
                food_restrictions,
                diet_type,
                cuisine_preferences
            )
            
            # Execute the insert
            await conn.execute(sql, *params)
            logger.info("Created new user preferences")
            
            # If goals were provided, trigger a recalculation of daily calories
            if goals:
                # Get the latest metrics to check if we have enough data
                metrics_row = await conn.fetchrow(
                    """
                    SELECT metric_id, weight, height, age_range, sex, activity_level 
                    FROM user_metrics 
                    WHERE user_id = $1 
                    ORDER BY recorded_at DESC 
                    LIMIT 1
                    """,
                    user_id
                )
                
                if metrics_row:
                    # If we have background tasks, use them
                    if background_tasks is not None:
                        background_tasks.add_task(
                            self._recalculate_daily_calories,
                            conn,
                            user_id
                        )
                        logger.info(f"Queued background calculation of daily calories for user_id: {user_id}")
                    else:
                        # Otherwise, run it synchronously
                        await self._recalculate_daily_calories(conn, user_id)
                else:
                    logger.info(f"No metrics found for user {user_id}. Will recalculate when metrics are added.")
            
            return {"message": "Preferences created successfully"}
            
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail="Invalid user_id format. Must be an integer."
            )
        except Exception as e:
            logger.error(f"Error creating preference: {str(e)}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to create preference: {str(e)}"
            )

    async def update_preference(
        self, 
        conn: asyncpg.Connection, 
        preference_id: int, 
        updates: Dict[str, Any],
        background_tasks: Optional[BackgroundTasks] = None
    ) -> Dict[str, Any]:
        """
        Update an existing user preference entry and trigger metric recalculation if needed.
        
        Args:
            conn: Database connection
            preference_id: ID of the preference to update
            updates: Dictionary containing fields to update
            background_tasks: Optional FastAPI BackgroundTasks instance for non-blocking operations
            
        Returns:
            Dictionary containing the updated preference
        """
        updates_lower = lowercase_keys(updates)
        set_clauses = []
        params = []
        idx = 1
        allowed = ['goals', 'food_restrictions', 'allergies', 'diet_type', 'cuisine_preferences']
        
        if not updates_lower:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No updates provided.")
            
        # Track if we need to trigger a recalculation
        needs_recalculation = False
        
        for k, v in updates_lower.items():
            if k in allowed:
                # Check if this is a field that affects daily calories
                if k == 'goals':
                    needs_recalculation = True
                
                # Handle the value based on its type
                if v is None:
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(None)
                elif k == 'food_restrictions' and isinstance(v, list):
                    # Special handling for food_restrictions list
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(','.join(str(item).strip() for item in v if item) if v else None)
                elif k == 'cuisine_preferences' and isinstance(v, list):
                    # Convert list to comma-separated string for cuisine_preferences
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(','.join(str(item).strip() for item in v if item) if v else None)
                elif isinstance(v, list):
                    # For other list fields, convert to JSON string
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(json.dumps(v) if v else None)
                else:
                    # If it's already a string, use as is
                    set_clauses.append(f"{k} = ${idx}")
                    params.append(str(v).strip() if v is not None else None)
                idx += 1
        
        if not set_clauses:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No valid fields to update.")
            
        # First, get the user_id for this preference
        pref_row = await conn.fetchrow(
            "SELECT user_id FROM user_preferences WHERE preference_id = $1",
            preference_id
        )
        
        if not pref_row:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Preference not found.")
            
        user_id = pref_row['user_id']
            
        # Update the preference
        sql = f"""
            UPDATE user_preferences 
            SET {', '.join(set_clauses)}
            WHERE preference_id = ${idx}
            RETURNING *
        """
        params.append(preference_id)
        
        try:
            result = await conn.fetchrow(sql, *params)
            if not result:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Preference not found.")
                
            # Convert comma-separated strings back to lists for response
            result_dict = dict(result)
            if 'food_restrictions' in result_dict and result_dict['food_restrictions']:
                result_dict['food_restrictions'] = [item.strip() for item in result_dict['food_restrictions'].split(',') if item.strip()]
            else:
                result_dict['food_restrictions'] = []
            
            logger.info(f"Successfully updated preference ID: {preference_id}")
            
            # Trigger recalculation of daily calories if needed
            if needs_recalculation:
                # Check if we have metrics for this user
                metrics_row = await conn.fetchrow(
                    """
                    SELECT metric_id FROM user_metrics 
                    WHERE user_id = $1 
                    ORDER BY recorded_at DESC 
                    LIMIT 1
                    """,
                    user_id
                )
                
                if metrics_row:
                    if background_tasks is not None:
                        background_tasks.add_task(
                            self._recalculate_daily_calories,
                            conn,
                            user_id
                        )
                        logger.info(f"Queued background calculation of daily calories for user_id: {user_id}")
                    else:
                        await self._recalculate_daily_calories(conn, user_id)
            
            # Return the updated preference
            return result_dict
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
        allowed = ['name', 'location', 'password', 'is_email_verified', 'user_type', 'image']

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
        sql = "SELECT * FROM user_preferences"
        params = []
        if user_id is not None:
            sql += " WHERE user_id = $1"
            params.append(user_id)
        preferences = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if preferences:
            processed = []
            for row in preferences:
                p_pref = dict(row)
                p_pref['food_restrictions'] = deserialize_list(p_pref.get('food_restrictions',''))
                # Keep cuisine_preferences as string, don't deserialize
                processed.append(p_pref)
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
            logger.error(f"Error fetching calorie history for user {user_id}: {str(e)}")
            raise

# Import subscription service at the top with other imports
from services.subscription_service import SubscriptionService, SubscriptionStatus, PlanStatusResponse

# Initialize subscription service
subscription_service = SubscriptionService()

# --- Subscription Endpoints ---

@app.get("/api/subscription/plans", response_model=List[Dict[str, Any]])
async def list_subscription_plans(conn: asyncpg.Connection = Depends(get_db)):
    """
    Get all active subscription plans
    """
    try:
        return await subscription_service.get_subscription_plans(conn)
    except Exception as e:
        logger.error(f"Error fetching subscription plans: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch subscription plans"
        )

@app.get("/api/subscription/status", response_model=PlanStatusResponse)
async def get_subscription_status(
    user_id: int = Query(..., description="User ID to check subscription status for"),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Get the current subscription status for a user
    """
    try:
        return await subscription_service.get_subscription_status(conn, user_id)
    except Exception as e:
        logger.error(f"Error getting subscription status for user {user_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get subscription status"
        )

@app.post("/api/subscription/subscribe", response_model=Dict[str, Any])
async def subscribe(
    subscription_data: Dict[str, Any] = Body(...),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Subscribe a user to a plan
    
    Request body should contain:
    - user_id: int - ID of the user subscribing
    - plan_id: int - ID of the plan to subscribe to
    - payment_transaction_id: str (optional) - ID of the payment transaction
    """
    try:
        user_id = subscription_data.get('user_id')
        plan_id = subscription_data.get('plan_id')
        payment_transaction_id = subscription_data.get('payment_transaction_id')
        
        if not user_id or not plan_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="user_id and plan_id are required"
            )
            
        async with conn.transaction():
            subscription = await subscription_service.create_subscription(
                conn, user_id, plan_id, payment_transaction_id
            )
            return {"success": True, "subscription": subscription}
            
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error creating subscription: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create subscription"
        )

@app.post("/api/subscription/cancel", response_model=Dict[str, Any])
async def cancel_subscription(
    user_id: int = Body(..., embed=True, description="ID of the user whose subscription to cancel"),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Cancel a user's active subscription
    """
    try:
        async with conn.transaction():
            success = await subscription_service.cancel_subscription(conn, user_id)
            if not success:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="No active subscription found to cancel"
                )
            return {"success": True, "message": "Subscription cancelled successfully"}
            
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error cancelling subscription for user {user_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel subscription"
        )

# --- Other Classes (Chefs, Producers, etc. Updated for asyncpg pool) ---
# Repeat the pattern for ALL classes that interact with the database:
# 1. Remove __init__ if it only dealt with DB connection.
# 2. Add 'conn: asyncpg.Connection' as the first argument to all methods performing DB operations.
# 3. Call self._execute_query(conn, ...) within those methods.

# Removed duplicate BaseRepository class - using the more comprehensive one above

class Chefs(BaseRepository):
    # _validate_stock remains synchronous helper
    def _validate_stock(self, stock_data, is_chef=True):
        logger.info(f"Validating stock data: {stock_data}")
        if stock_data is None: 
            logger.info("Stock data is None, returning empty list")
            return []
            
        if not isinstance(stock_data, list): 
            error_msg = f"Stock must be a list, got {type(stock_data)}"
            logger.error(error_msg)
            raise ValueError(error_msg)
            
        id_field = 'meal_id' if is_chef else 'produce_id'
        logger.info(f"Validating stock items with id_field: {id_field}")
        
        validated_stock = []
        for i, item in enumerate(stock_data):
            logger.info(f"Validating stock item {i}: {item}")
            
            if not isinstance(item, dict): 
                error_msg = f"Stock item must be a dict, got {type(item)}"
                logger.error(error_msg)
                raise ValueError(error_msg)
            
            # Create a case-insensitive dict for field lookup
            item_lower = {str(k).lower(): v for k, v in item.items()}
            
            # Get name with case-insensitive lookup
            name_val = None
            for name_key in ['name', 'Name', 'NAME']:
                if name_key in item:
                    name_val = item[name_key]
                    break
                
            logger.info(f"Item {i} Name value: {name_val} (type: {type(name_val)})")
            
            if not isinstance(name_val, str) or not name_val.strip():
                error_msg = f"Stock item Name required. Got: {name_val} (type: {type(name_val)})"
                logger.error(error_msg)
                raise ValueError("Stock item Name required")
            
            # Create validated item with correct case
            validated_item = {
                'Name': name_val.strip(),
                id_field: item.get(id_field),
                'price': item_lower.get('price'),
                'image': item_lower.get('image'),
                'quantity': item_lower.get('quantity')
            }
            
            # Log field values for debugging
            logger.info(f"Item {i} {id_field} value: {validated_item[id_field]} (type: {type(validated_item[id_field]) if validated_item[id_field] is not None else 'None'})")
            
            # Validate ID field if present
            if validated_item[id_field] is not None and not isinstance(validated_item[id_field], str):
                error_msg = f"{id_field} must be string or null, got {type(validated_item[id_field])}"
                logger.error(error_msg)
                raise ValueError(error_msg)
            
            # Validate quantity if present
            qty_val = validated_item['quantity']
            logger.info(f"Item {i} quantity value: {qty_val} (type: {type(qty_val) if qty_val is not None else 'None'})")
            
            if qty_val is not None:
                try: 
                    validated_item['quantity'] = float(qty_val)
                except (ValueError, TypeError) as e:
                    error_msg = f"Stock quantity must be number or null, got {qty_val} ({type(qty_val)})"
                    logger.error(error_msg)
                    raise ValueError("Stock quantity must be number or null") from e
                    
            validated_stock.append(validated_item)
            
        logger.info("Stock validation successful")
        return validated_stock

    async def create_chef(self, conn: asyncpg.Connection, chef_data: dict, background_tasks: Optional[BackgroundTasks] = None):
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
        if chef_id:
            # Initialize AuthenticationAndUsers to access email verification
            auth = AuthenticationAndUsers()
            # Generate and store verification code (synchronously)
            verification_code = await auth._handle_email_verification(conn, email, chef_id, user_type)
            # Schedule email sending in background if background_tasks is provided
            if background_tasks is not None:
                background_tasks.add_task(
                    auth.send_verification_email_gmail,
                    to_email=email,
                    verification_code=verification_code
                )
            else:
                # Fallback to synchronous sending if no background_tasks provided
                await auth.send_verification_email_gmail(to_email=email, verification_code=verification_code)
            logger.info(f"Created chef ID: {chef_id}")
            return {"Chef_id": chef_id, "user_type": user_type, "message": "Chef created"}
        else: 
            logger.error(f"Chef creation failed for {email}")
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Chef creation failed.")

    async def list_chefs(self, conn: asyncpg.Connection, chef_id=None):
        # Explicitly list all columns except sensitive ones
        columns = [
            'chefid', 'name', 'email', 'image', 'is_email_verified', 'user_type',
            'chef_type', 'is_active', 'rating', 'phone_number', 'experience',
            'serviceradius', 'responsetime', 'minnotice', 'punctuality',
            'teamsize', 'equipment', 'bio', 'availability', 'languages',
            'specialties', 'certifications', 'registration_date', 'location',
            'samplemenu', 'added_by', 'added_by_type', 'last_login',
            'pricing', 'stock'
        ]
        
        sql = f"SELECT {', '.join(columns)} FROM chefs"
        params = []
        
        if chef_id is not None:
            try:
                cid = int(chef_id)
                sql += " WHERE chefid = $1"
                params.append(cid)
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid chef_id."
                )
                
        chefs_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if chefs_list is None:
            return []
            
        processed_chefs = []
        for chef_dict in chefs_list:
            processed_chef = dict(chef_dict)
            list_fields = [
                'equipment', 'availability', 'languages', 'specialties',
                'certifications', 'samplemenu', 'stock'
            ]
            
            # Deserialize JSON strings to Python objects
            for field in list_fields:
                processed_chef[field] = deserialize_list_from_json_string(processed_chef.get(field))
            
            # Extract price from pricing JSON if available
            try:
                pricing_data = json.loads(processed_chef.get('pricing') or '{}')
                extracted_price = pricing_data.get('starting_price', 0.0)
                processed_chef['price'] = extracted_price if extracted_price is not None else 0.0
            except json.JSONDecodeError:
                logger.warning(f"Bad pricing JSON for chef {processed_chef.get('chefid')}")
                processed_chef['price'] = 0.0
            
            # Convert datetime objects to ISO format strings
            for k, v in list(processed_chef.items()):
                if isinstance(v, (datetime, date)):
                    processed_chef[k] = v.isoformat()
            
            processed_chefs.append(processed_chef)
        
        if chef_id and not processed_chefs:
            logger.warning(f"Chef not found ID: {chef_id}")
            return []
            
        return processed_chefs

    def _check_restricted_fields(self, updates: dict, restricted_fields: list = None):
        """
        Check if any restricted fields are being updated.
        
        Args:
            updates: Dictionary of updates to check
            restricted_fields: List of field names that cannot be updated
            
        Raises:
            HTTPException: 403 if any restricted fields are found in updates
        """
        if restricted_fields is None:
            restricted_fields = ['email', 'phone_number']
            
        restricted_updates = [f for f in restricted_fields if f in updates]
        if restricted_updates:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"The following fields cannot be updated: {', '.join(restricted_updates)}",
                headers={"X-Error-Code": "FIELD_UPDATE_NOT_ALLOWED"}
            )

    async def update_chef(self, conn: asyncpg.Connection, chef_id: int, updates: dict):
        # Check for restricted fields first
        self._check_restricted_fields(updates)
        
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

    async def login_chef(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT chefid, hashed_password, user_type, is_email_verified, phone_number FROM chefs WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result: 
            logger.warning(f"Chef login fail: '{identifier}'")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        chef_id = result['chefid']; stored_hash = result['hashed_password']; user_type = result['user_type']; is_verified = result['is_email_verified']
        if not is_verified:
            logger.warning(f"Login failed: Email not verified for chef '{identifier}'")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Email not verified. Please verify your email before logging in.')
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash type chef {chef_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
            logger.info(f"Chef login success '{identifier}', ID: {chef_id}")
            # Optional: Update last_login
            # update_sql = "UPDATE chefs SET last_login = NOW() WHERE chefid = $1"
            # try: await self._execute_query(conn, update_sql, (chef_id,))
            # except Exception as update_err: logger.error(f"Failed last_login update chef {chef_id}: {update_err}")
            return {'message': 'Login successful', 'data': {'chef_id': chef_id, 'user_type': user_type, 'verified': is_verified, 'phone': result.get('phone_number')}}
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
        updates_lower = lowercase_keys(updates)
        
        # Check for restricted fields first
        self._check_restricted_fields(updates_lower)
        
        set_clauses = []; params = []; idx = 1;
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

    async def create_producer(self, conn: asyncpg.Connection, producer_data: dict, background_tasks: Optional[BackgroundTasks] = None):
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
        if producer_id: 
            # Initialize AuthenticationAndUsers to access email verification
            auth = AuthenticationAndUsers()
            # Generate and store verification code (synchronously)
            verification_code = await auth._handle_email_verification(conn, email, producer_id, user_type)
            # Schedule email sending in background if background_tasks is provided
            if background_tasks is not None:
                background_tasks.add_task(
                    auth.send_verification_email_gmail,
                    to_email=email,
                    verification_code=verification_code
                )
            else:
                # Fallback to synchronous sending if no background_tasks provided
                await auth.send_verification_email_gmail(to_email=email, verification_code=verification_code)
            logger.info(f"Created producer ID: {producer_id}")
            return {"producer_id": producer_id, "UserType": user_type}
        else: 
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Producer creation failed.")

    async def list_producers(self, conn: asyncpg.Connection, producer_id=None):
        # Explicitly list all columns except sensitive ones
        columns = [
            'producer_id', 'name', 'image', 'email', 'is_email_verified', 'user_type',
            'producer_type', 'is_active', 'rating', 'phone_number', 'registration_date',
            'location', 'added_by', 'added_by_type', 'last_login', 'reviews', 'stock'
        ]
        
        sql = f"SELECT {', '.join(columns)} FROM producers"
        params = []
        
        if producer_id is not None:
            try:
                pid = int(producer_id)
                sql += " WHERE producer_id = $1"
                params.append(pid)
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid producer_id."
                )
                
        producers_list = await self._execute_query(conn, sql, tuple(params), fetch_all=True)
        if producers_list is None:
            return []
            
        processed = []
        for row in producers_list:
            p_prod = dict(row)
            
            # Deserialize stock JSON string to Python object
            if 'stock' in p_prod:
                p_prod['stock'] = deserialize_list_from_json_string(p_prod['stock'])
            
            # Convert datetime objects to ISO format strings
            for key, value in list(p_prod.items()):
                if isinstance(value, (datetime, date)):
                    p_prod[key] = value.isoformat()
            
            processed.append(p_prod)
        
        if producer_id is not None and not processed:
            logger.warning(f"Producer not found ID: {producer_id}")
            return []
            
        return processed

    async def login_producer(self, conn: asyncpg.Connection, identifier: str, password: str):
        # ... (uses conn for _execute_query) ...
        sql = "SELECT producer_id, hashed_password, user_type, is_email_verified, phone_number FROM producers WHERE lower(name) = lower($1) OR lower(email) = lower($2)"
        params = (identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result:
            logger.warning(f"Producer login fail: '{identifier}'")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        producer_id=result['producer_id']; stored_hash=result['hashed_password']; user_type=result['user_type']; is_verified=result['is_email_verified']
        if not is_verified:
            logger.warning(f"Login failed: Email not verified for producer '{identifier}'")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Email not verified. Please verify your email before logging in.')
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash producer {producer_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
             logger.info(f"Producer login success '{identifier}', ID: {producer_id}")
             # Optional: update last_login
             return {'message':'Login successful', 'data':{'producer_id':producer_id, 'user_type':user_type, 'verified':is_verified, 'phone': result.get('phone_number')}}
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
    async def create_transporter(self, conn: asyncpg.Connection, transporter_data: dict, background_tasks: Optional[BackgroundTasks] = None):
        # ... (uses conn for fetchval and _execute_query) ...
        data_lower=lowercase_keys(transporter_data); check_required_fields(data_lower,['name','password','email'])
        email=data_lower['email']; check_sql="SELECT transporter_id FROM transporters WHERE lower(email)=lower($1)"
        if await conn.fetchval(check_sql, email): raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"Transporter email '{email}' exists.")
        hashed_password=hash_password(data_lower['password']); user_type=data_lower.get('user_type','transporter'); is_active=data_lower.get('is_active',False)
        sql="INSERT INTO transporters (name, email, hashed_password, phone_number, profile_image_url, vehicle_type, license_plate, is_active, rating, location, registration_date, user_type, reviews) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11, $12) RETURNING transporter_id"
        params=(data_lower['name'], email, hashed_password, data_lower.get('phone_number'), data_lower.get('profile_image_url'), data_lower.get('vehicle_type'), data_lower.get('license_plate'), is_active, data_lower.get('rating',0.0), data_lower.get('location'), user_type, data_lower.get('reviews'))
        transporter_id=await self._execute_query(conn, sql, params, returning_id_column='transporter_id')
        if transporter_id: 
            # Initialize AuthenticationAndUsers to access email verification
            auth = AuthenticationAndUsers()
            # Generate and store verification code (synchronously)
            verification_code = await auth._handle_email_verification(conn, email, transporter_id, user_type)
            # Schedule email sending in background if background_tasks is provided
            if background_tasks is not None:
                background_tasks.add_task(
                    auth.send_verification_email_gmail,
                    to_email=email,
                    verification_code=verification_code
                )
            else:
                # Fallback to synchronous sending if no background_tasks provided
                await auth.send_verification_email_gmail(to_email=email, verification_code=verification_code)
            logger.info(f"Created transporter ID: {transporter_id}")
            return {"transporter_id": transporter_id, "UserType": user_type, "message":"Transporter created"}
        else: 
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Transporter creation failed.")

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

    def _check_restricted_fields(self, updates: dict, restricted_fields: list = None):
        """
        Check if any restricted fields are being updated.
        
        Args:
            updates: Dictionary of updates to check
            restricted_fields: List of field names that cannot be updated
            
        Raises:
            HTTPException: 403 if any restricted fields are found in updates
        """
        if restricted_fields is None:
            restricted_fields = ['transporter_id', 'email', 'registration_date', 'user_type']
            
        restricted_updates = [field for field in updates if field in restricted_fields]
        if restricted_updates:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f'Cannot update restricted fields: {", ".join(restricted_updates)}'
            )

    async def update_transporter(self, conn: asyncpg.Connection, transporter_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates)
        
        # Check for restricted fields first
        self._check_restricted_fields(updates_lower)
        
        set_clauses=[]; params=[]; idx=1;
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
        sql="SELECT transporter_id, hashed_password, user_type, is_email_verified, phone_number FROM transporters WHERE lower(name)=lower($1) OR lower(email)=lower($2)"
        params=(identifier.lower(), identifier.lower())
        result = await self._execute_query(conn, sql, params, fetch_one=True)
        if not result:
            logger.warning(f"Transporter login fail: '{identifier}'")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        transporter_id=result['transporter_id']; stored_hash=result['hashed_password']; user_type=result.get('user_type','transporter'); is_verified=result.get('is_email_verified',True) # Assume verified if column missing
        if not is_verified:
            logger.warning(f"Login failed: Email not verified for transporter '{identifier}'")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Email not verified. Please verify your email before logging in.')
        stored_hash_bytes = stored_hash.encode() if isinstance(stored_hash, str) else stored_hash
        if not isinstance(stored_hash_bytes, bytes): logger.error(f"Bad hash transporter {transporter_id}"); raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Login error.')
        if bcrypt.checkpw(password.encode(), stored_hash_bytes):
            logger.info(f"Transporter login success '{identifier}', ID: {transporter_id}")
            # Optional: update last_login
            return {'message':'Login successful', 'data':{'transporter_id':transporter_id, 'user_type':user_type, 'verified':is_verified, 'phone': result.get('phone_number')}}
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
    async def create_stakeholder(self, conn: asyncpg.Connection, stakeholder_data: dict, background_tasks: Optional[BackgroundTasks] = None):
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
        if stakeholder_id: 
            # Initialize AuthenticationAndUsers to access email verification
            auth = AuthenticationAndUsers()
            # Generate and store verification code (synchronously)
            verification_code = await auth._handle_email_verification(conn, email, stakeholder_id, user_type)
            # Schedule email sending in background if background_tasks is provided
            if background_tasks is not None:
                background_tasks.add_task(
                    auth.send_verification_email_gmail,
                    to_email=email,
                    verification_code=verification_code
                )
            else:
                # Fallback to synchronous sending if no background_tasks provided
                await auth.send_verification_email_gmail(to_email=email, verification_code=verification_code)
            logger.info(f"Created stakeholder ID: {stakeholder_id}")
            return {"stakeholder_id": stakeholder_id, "UserType": user_type}
        else: 
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Stakeholder creation failed.")

    async def list_stakeholders(self, conn: asyncpg.Connection):
        # Explicitly list all columns except sensitive ones
        columns = [
            'stakeholder_id', 'name', 'full_name', 'image', 'email', 'is_email_verified', 
            'user_type', 'is_active', 'rating', 'phone_number', 'registration_date', 
            'location', 'added_by', 'added_by_type', 'last_login'
        ]
        
        sql = f"SELECT {', '.join(columns)} FROM stakeholders"
        results = await self._execute_query(conn, sql, fetch_all=True)
        
        if not results:
            return []
            
        processed = []
        for item in results:
            # Convert row to dict
            row_dict = dict(item)
            
            # Convert datetime objects to ISO format strings
            for key, value in list(row_dict.items()):
                if isinstance(value, (datetime, date)):
                    row_dict[key] = value.isoformat()
            
            processed.append(row_dict)
            
        return processed

    async def get_stakeholder_by_id(self, conn: asyncpg.Connection, stakeholder_id: int):
        # Explicitly list all columns except sensitive ones
        columns = [
            'stakeholder_id', 'name', 'full_name', 'image', 'email', 'is_email_verified', 
            'user_type', 'is_active', 'rating', 'phone_number', 'registration_date', 
            'location', 'added_by', 'added_by_type', 'last_login'
        ]
        
        sql = f"SELECT {', '.join(columns)} FROM stakeholders WHERE stakeholder_id = $1"
        result = await self._execute_query(conn, sql, (stakeholder_id,), fetch_one=True)
        
        if not result:
            return None
            
        # Convert row to dict
        result_dict = dict(result)
        
        # Convert datetime objects to ISO format strings
        for key, value in list(result_dict.items()):
            if isinstance(value, (datetime, date)):
                result_dict[key] = value.isoformat()
                
        return result_dict

    async def update_stakeholder(self, conn: asyncpg.Connection, stakeholder_id: int, updates: dict):
        # ... (uses conn for _execute_query) ...
        updates_lower=lowercase_keys(updates)
        
        # Check for restricted fields first
        self._check_restricted_fields(updates_lower)
        
        set_clauses=[]; params=[]; idx=1;
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
        if not result:
            logger.warning(f"Stakeholder login fail: '{identifier}'")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='wrong password or name.')
        stakeholder_id=result['stakeholder_id']; stored_hash=result['hashed_password']; user_type=result.get('user_type','stakeholder'); is_verified=result.get('is_email_verified',False)
        if not is_verified:
            logger.warning(f"Login failed: Email not verified for stakeholder '{identifier}'")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Email not verified. Please verify your email before logging in.')
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
        set_clauses=[]; params=[]; idx=1; allowed=['meal_name','meal_category','ingredients','complementary_dishes','recipe','recipe_link','image_link','goal','dietary_preference','allergies','disease_management','cuisine_preferences','skill_level','prep_time','meal_description','date_last_edited','price']
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
            SELECT m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link, m.goal, m.dietary_preference, m.allergies, m.disease_management, m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description, COALESCE(m.price, 0) as price FROM meals m
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
            meal_dict={"Meal_id":meal.get("meal_id"),"Meal_name":meal.get("meal_name"),"Meal_category":meal.get("meal_category"), "Recipe":meal.get("recipe"),"Recipe_link":meal.get("recipe_link"),"Image_link":meal.get("image_link"), "Goal":meal.get("goal"),"Dietary_preference":meal.get("dietary_preference"),"Allergies":meal.get("allergies"), "Disease_management":meal.get("disease_management"),"Cuisine_preferences":meal.get("cuisine_preferences"), "Skill_level":meal.get("skill_level"),"Prep_time":meal.get("prep_time"),"Meal_description":meal.get("meal_description"), "Ingredients":meal.get("ingredients") or "","Complementary_dishes":meal.get("complementary_dishes") or "", "Price":meal.get("price", 0)}
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
    ALLOWED_PAYMENT_STATUSES = {'failed', 'refunded', 'paid', 'pending', 'completed', 'processing_payment'}
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
    async def create_order(
        self,
        conn: asyncpg.Connection,
        user_id: int,
        order_type: str,
        user_type: str,
        items: Optional[List[Dict]] = None,
        order_status: str = "pending",
        payment_status: str = "pending",
        payment_mode: str = "cash",
        delivery_address: Optional[str] = None,
        notes: Optional[str] = None,
        total_price: Optional[float] = None,
        amount_paid: float = 0.0,
        product_id: Optional[Union[str, int]] = None,
        chef_id: Optional[int] = None,
        producer_id: Optional[int] = None,
        quantity: Optional[int] = None,
        transporter_id: Optional[int] = None,
        transaction_id: Optional[str] = None,
        user_phone: Optional[str] = None
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

            # Extract bulk order details if present
            is_bulk_order = False
            bulk_order_details = None
            
            if items and len(items) > 0 and 'is_bulk_order' in items[0]:
                is_bulk_order = items[0]['is_bulk_order']
                bulk_order_details = items[0].get('bulk_order_details')
                
            sql = """
                INSERT INTO orders (
                    user_id, user_type, order_type, product_id, chef_id, producer_id, transporter_id,
                    order_date, delivery_address, order_status, total_price, notes,
                    payment_status, payment_mode, amount_paid, transaction_id, quantity,
                    gig_details, complementary_meals, user_phone,
                    is_bulk_order, bulk_order_details
                )
                VALUES ($1,$2,$3,$4,$5,$6,$7, NOW(), $8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
                RETURNING order_id
            """
            params: Tuple[Any, ...] = (
                user_id_i, user_type, order_type_l, prod_id_s, chef_id_i, producer_id_i, transporter_id_i,
                delivery_address_s, order_status_l, price_f, notes_s, payment_status_l,
                payment_mode_l, paid_f, transaction_id, qty_i, gig_details_json,
                complementary_meals_serialized_json, user_phone,
                is_bulk_order, json.dumps(bulk_order_details) if bulk_order_details else None
            )
            # Execute the query and get the raw result
            result = await conn.fetchrow(sql, *params)
            if not result or 'order_id' not in result:
                logger.error(f"Order creation failed - no order_id returned from database. Result: {result}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Order creation failed (no order ID returned from database)"
                )
            order_id = result['order_id']

            if not order_id:
                logger.error(f"Order creation attempt failed for user {user_id_i} (no ID returned).")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Order creation failed unexpectedly (no ID returned)."
                )

            logger.info(f"Order created successfully for user {user_id_i} (type: {user_type}) with order_id {order_id}")
            logger.debug(f"Order details - user_id: {user_id_i}, user_type: {user_type}, order_type: {order_type_l}")
            
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
            
            return {
                "message": "Order created",
                "order_id": order_id,
                "chef_id": derived_chef_id,
                "producer_id": derived_producer_id,
                "success": True
            }

        except Exception as e: # Catch-all for other exceptions like DB connection issues
            logger.error(f"Error creating order for user {user_id} (type: {user_type}): {str(e)}", exc_info=True)
            if not isinstance(e, HTTPException): # Avoid re-wrapping HTTPExceptions
                error_detail = f"An unexpected error occurred while processing your order"
                logger.error(f"Order creation failed - User ID: {user_id}, User Type: {user_type}, Error: {str(e)}")
                raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=error_detail)
            raise

    async def read_orders(self, conn: asyncpg.Connection, order_id=None, chef_id=None, producer_id=None, user_id=None, transporter_id=None, user_type: Optional[str] = None) -> List[Dict[str, Any]]:
        # Log all incoming parameters for debugging
        logger.info(f"[read_orders] Received parameters - order_id: {order_id}, chef_id: {chef_id}, producer_id: {producer_id}, "
                   f"user_id: {user_id}, transporter_id: {transporter_id}, user_type: {user_type}")
        
        # Validate user_type when user_id is provided
        if user_id is not None and user_type is None:
            error_msg = "User type is required when filtering by user_id"
            logger.error(f"Validation error in read_orders: {error_msg}. User ID: {user_id}")
            raise ValueError(error_msg)
            
        # If order_id is provided, we can optimize the query by making it the primary filter
        if order_id is not None:
            try:
                order_id_int = int(order_id)  # Ensure order_id is an integer
                logger.info(f"[read_orders] Order ID provided: {order_id_int}, optimizing query for order lookup")
            except (ValueError, TypeError) as e:
                logger.error(f"Invalid order_id format: {order_id}. Error: {str(e)}")
                raise ValueError(f"Invalid order_id format: {order_id}. Must be a valid integer.")
        sql = """
            WITH MealDetails AS ( SELECT m.meal_id::text, m.meal_name, COALESCE(STRING_AGG(DISTINCT p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients FROM meals m LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id LEFT JOIN produce p ON mi.produce_id = p.produce_id GROUP BY m.meal_id, m.meal_name ),
                 SupplementDetails AS ( SELECT supplement_id::text, supplement_name AS product_name FROM supplements ), HerbalDetails AS ( SELECT herbal_id::text, herbal_name AS product_name FROM herbals ), GadgetDetails AS ( SELECT gadget_id::text, gadget_name AS product_name FROM gadgets ), SpiceDetails AS ( SELECT spice_id::text, spice_name AS product_name FROM spices ), ProduceDetails AS ( SELECT produce_id::text, produce_name AS product_name FROM produce )
            SELECT
                o.order_id, o.user_id, o.order_type, o.product_id, o.chef_id, o.producer_id, o.transporter_id,
                o.order_date, o.delivery_address, o.order_status, o.total_price, o.notes,
                o.payment_status, o.payment_mode, o.amount_paid, o.transaction_id, o.quantity, o.user_phone,
                o.restaurant_phone, o.gig_details, o.complementary_meals,
                o.updated_at, o.is_bulk_order, o.bulk_order_details,
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
                
                # user_type is required when user_id is provided
                if not user_type:
                    error_msg = "User type cannot be empty when filtering by user_id"
                    logger.error(f"Validation error in read_orders: {error_msg}. User ID: {user_id}")
                    raise ValueError(error_msg)
                
                sql += f" AND o.user_type = ${param_index}"
                params_list.append(str(user_type).lower())
                param_index += 1
                logger.debug(f"Filtering orders by user_id: {user_id}, user_type: {user_type}")
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
            
            # Calculate distances if transporter_id is provided
            if transporter_id is not None:
                await self._add_distances_to_orders(conn, processed_results)
                
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

    @staticmethod
    @lru_cache(maxsize=4096)
    def haversine(coord1: Tuple[float, float], coord2: Tuple[float, float]) -> float:
        """
        Calculate the great circle distance between two points 
        on the earth specified in decimal degrees.
        
        This function uses LRU cache to improve performance when the same 
        coordinate pairs are used repeatedly.
        
        Args:
            coord1: Tuple of (latitude, longitude) for first point
            coord2: Tuple of (latitude, longitude) for second point
            
        Returns:
            Distance in kilometers between the two points
            
        Cache Details:
            - Max cache size: 4,096 unique coordinate pairs
            - Memory usage: ~32KB (8 bytes per float * 4 floats * 1,024 entries)
            - Hit ratio: Expected >90% for repeated coordinate calculations
        """
        # Convert decimal degrees to radians 
        lat1, lon1 = coord1
        lat2, lon2 = coord2
        lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
        
        # Haversine formula 
        dlat = lat2 - lat1 
        dlon = lon2 - lon1 
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a)) 
        
        # Radius of earth in kilometers
        return 6371.0 * c
    
    # Pre-compile regex patterns once at module level
    _COORD_PATTERNS = [
        # Combined pattern for most common formats
        re.compile(
            r'(?x)'  # Verbose mode for better readability
            r'[\[\(]?\s*'  # Optional opening bracket or parenthesis
            r'([+-]?\d{1,3}\.\d+)\s*'  # First number (lat)
            r'[,\s/]+'  # Separator (comma, space, or slash)
            r'([+-]?\d{1,3}\.\d+)\s*'  # Second number (lng)
            r'[\]\)]?'  # Optional closing bracket or parenthesis
            r'|'  # OR
            r'([-+]?\d{1,3}\.\d+)[°º]?\s*[NS]?[,\s/]+([-+]?\d{1,3}\.\d+)[°º]?\s*[EW]?'  # With degree symbols
        ),
    ]
    
    @classmethod
    def _extract_coordinates(cls, address: Optional[str]) -> Optional[Tuple[float, float]]:
        """
        Efficiently extract coordinates from address string in various formats.
        Optimized for performance with pre-compiled regex patterns.
        
        Handles formats like:
        - "lat, lng"
        - "(lat, lng)" or "[lat, lng]"
        - '"lat", "lng"' or "'lat', 'lng'"
        - "Some Address (lat, lng)"
        - "lat°N, lng°E"
        
        Returns:
            Tuple[float, float] or None: (latitude, longitude) if valid, None otherwise
        """
        if not address or not isinstance(address, str) or len(address) > 200:  # Quick length check
            return None
            
        # Try pre-compiled patterns first (fast path)
        for pattern in cls._COORD_PATTERNS:
            if match := pattern.search(address):
                # Check which group matched (accounts for alternation in the pattern)
                lat_str = match.group(1) or match.group(3)
                lng_str = match.group(2) or match.group(4)
                
                try:
                    lat, lng = float(lat_str), float(lng_str)
                    # Validate ranges
                    if -90 <= lat <= 90 and -180 <= lng <= 180:
                        return (lat, lng)
                except (ValueError, TypeError):
                    continue
        
        # Fast path for simple comma/space separated numbers (common case)
        try:
            # Quick check if string contains at least one digit and a comma/space
            if any(c.isdigit() for c in address) and any(c in address for c in ', '):
                # Extract first two numbers using a simple state machine
                nums = []
                current = []
                for c in address + ' ':
                    if c in '+-.0123456789':
                        current.append(c)
                    elif current:
                        try:
                            num = float(''.join(current))
                            if -180 <= num <= 180:  # Valid coordinate range
                                nums.append(num)
                                if len(nums) == 2:
                                    lat, lng = nums
                                    if -90 <= lat <= 90:  # Additional lat validation
                                        return (lat, lng)
                                    break
                        except ValueError:
                            pass
                        current = []
        except Exception:
            pass
            
        return None
    
    async def _add_distances_to_orders(self, conn: asyncpg.Connection, orders: List[Dict[str, Any]], batch_size: int = 10) -> None:
        """
        Add distance field to each order by calculating haversine distance
        between pickup location and delivery address using parallel processing.
        
        Args:
            conn: Database connection
            orders: List of order dictionaries to process
            batch_size: Number of orders to process concurrently
        """
        async def process_order(order: Dict[str, Any]) -> None:
            """Process a single order to calculate and add distance."""
            try:
                # Get pickup location (prefer chef_address, fall back to pickup_location)
                pickup_loc = order.get('chef_address') or order.get('pickup_location')
                delivery_loc = order.get('delivery_address')
                
                # Skip if either location is missing
                if not pickup_loc or not delivery_loc:
                    order['distance'] = None
                    return
                
                # Extract coordinates from addresses
                pickup_coords = self._extract_coordinates(pickup_loc)
                delivery_coords = self._extract_coordinates(delivery_loc)
                
                if not pickup_coords or not delivery_coords:
                    order['distance'] = None
                    logger.warning(f"Could not extract coordinates for order {order.get('order_id')}: "
                                 f"pickup_coords={pickup_coords is not None}, delivery_coords={delivery_coords is not None}")
                    return
                
                # Calculate distance in thread pool
                loop = asyncio.get_event_loop()
                distance_km = await loop.run_in_executor(
                    None,  # Use default ThreadPoolExecutor
                    lambda: self.haversine(pickup_coords, delivery_coords)
                )
                order['distance'] = round(distance_km, 2)  # Round to 2 decimal places
                
            except Exception as e:
                order['distance'] = None
                logger.error(f"Error calculating distance for order {order.get('order_id')}: {str(e)}", exc_info=True)
        
        # Process orders in batches to balance concurrency and memory usage
        for i in range(0, len(orders), batch_size):
            batch = orders[i:i + batch_size]
            # Process current batch concurrently
            await asyncio.gather(*[
                process_order(order) for order in batch
            ], return_exceptions=True)
            
            # Small sleep between batches to prevent resource exhaustion
            if i + batch_size < len(orders):
                await asyncio.sleep(0.1)
    
    async def update_order_status(self, conn: asyncpg.Connection, order_id: int, new_status: str, transporter_id: Optional[int] = None, completion_code: Optional[str] = None, restaurant_phone: Optional[str] = None) -> Dict[str, Any]:
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
            
            # Add restaurant_phone to update fields if provided
            if restaurant_phone is not None:
                update_fields.append(f"restaurant_phone = ${current_param_idx}")
                params_update.append(restaurant_phone)
                current_param_idx += 1

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
            
            # Process post-status-update actions
            if status_actually_changed:
                # Check if order is being marked as completed/delivered
                completion_statuses = ['completed', 'delivered', 'complete']
                was_completed_before = original_status in completion_statuses
                is_completed_now = status_to_update in completion_statuses
                
                # Trigger calorie logging for meal orders
                if current_order_type == 'meal':
                    if is_completed_now and not was_completed_before:
                        logger.info(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}) transitioned from '{original_status}' to '{status_to_update}' - triggering calorie logging.")
                        asyncio.create_task(self._log_calories_with_error_handling(original_order_id))
                    else:
                        logger.debug(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}): No calorie logging needed. Transition: '{original_status}' -> '{status_to_update}'. Was completed: {was_completed_before}, Is now completed: {is_completed_now}. Status actually changed: {status_actually_changed}")
                else:
                    logger.debug(f"[INTERNAL] Order {original_order_id} is type '{current_order_type}', not 'meal'. Skipping calorie logging.")
                
                # Trigger disbursements for completed orders
                if is_completed_now and not was_completed_before:
                    logger.info(f"[DISBURSEMENT] Order {original_order_id} marked as completed - queueing disbursement task")
                    
                    # Define the background task outside the create_task call for better error handling
                    async def _process_disbursement_async():
                        task_id = f"disburse_order_{original_order_id}_{int(time.time())}"
                        try:
                            logger.info(f"[DISBURSEMENT][{task_id}] Starting disbursement process")
                            async with db_pool.acquire() as conn:
                                try:
                                    await disbursement_service.process_order_disbursements(conn, original_order_id)
                                    logger.info(f"[DISBURSEMENT][{task_id}] Successfully processed disbursements for order {original_order_id}")
                                except Exception as proc_err:
                                    logger.error(f"[DISBURSEMENT][{task_id}] Error in disbursement processing: {str(proc_err)}", exc_info=True)
                                    # Consider adding retry logic here if needed
                        except Exception as task_err:
                            logger.error(f"[DISBURSEMENT][{task_id}] Failed to acquire connection or process disbursement: {str(task_err)}", exc_info=True)
                    
                    # Start the background task with error handling
                    try:
                        task = asyncio.create_task(_process_disbursement_async())
                        # Add a callback to log if the task fails
                        def log_task_result(t):
                            try:
                                t.result()  # This will raise any unhandled exceptions
                            except asyncio.CancelledError:
                                logger.warning(f"[DISBURSEMENT] Disbursement task for order {original_order_id} was cancelled")
                            except Exception as e:
                                logger.error(f"[DISBURSEMENT] Unhandled exception in disbursement task for order {original_order_id}: {str(e)}", exc_info=True)
                        
                        task.add_done_callback(log_task_result)
                        logger.info(f"[DISBURSEMENT] Successfully queued disbursement task for order {original_order_id}")
                    except Exception as e:
                        logger.error(f"[DISBURSEMENT] Failed to create disbursement task for order {original_order_id}: {str(e)}", exc_info=True)
                        # Don't re-raise to avoid failing the main request
            else:
                logger.debug(f"[INTERNAL] Order {original_order_id} (type: {current_order_type}): Status did not actually change in DB. Skipping post-update actions.")
            
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
        try:
            if db_pool is None:
                logger.error(f"[INTERNAL TASK] Global 'db_pool' is None for order {order_id}. Cannot log calories. Ensure the pool is initialized and accessible.")
                return

            logger.info(f"[INTERNAL TASK] Attempting to log calories for order {order_id}")
            try:
                async with db_pool.acquire() as conn:
                    async with conn.transaction():
                        success = await self.log_meal_calories(conn, order_id)
                        if success:
                            logger.info(f"[INTERNAL TASK] Successfully logged calories for order {order_id}")
                        else:
                            logger.warning(f"[INTERNAL TASK] Calorie logging completed with failure for order {order_id}")
            except Exception as inner_e:
                logger.error(f"[INTERNAL TASK] Error in calorie logging transaction for order {order_id}: {str(inner_e)}", exc_info=True)
        except Exception as e:
            logger.error(f"[INTERNAL TASK] Unhandled error in _log_calories_with_error_handling for order {order_id}: {str(e)}", exc_info=True)
        # Don't re-raise to avoid crashing the background task

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

            global meal_recommender
            if meal_recommender is None:
                logger.error("log_meal_calories: Meal recommender singleton not initialized")
                return False
                
            logger.debug(f"log_meal_calories: Calculating calories for meal_id {meal_id} (order {order_id}).")
            
            # Use the global singleton instance
            meal_data = await meal_recommender.calculate_meal_calories(str(meal_id)) 
            
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
    def _categorize_goal(self, goal: str) -> str:
        """
        Categorize the user's goal for calculation purposes.
        
        Args:
            goal: The user's goal string
            
        Returns:
            str: Goal category ('weight_loss', 'muscle_gain', 'maintain', 'health_condition', 'general_wellness')
        """
        if not goal:
            return 'general_wellness'
            
        goal = str(goal).lower()
        
        # Weight-related goals
        if any(term in goal for term in ["lose weight", "weight loss"]):
            return "weight_loss"
        if any(term in goal for term in ["gain muscle", "muscle gain"]):
            return "muscle_gain"
        if any(term in goal for term in ["maintain", "satiety"]):
            return "maintain"
            
        # Health conditions that might affect calculations in the future
        health_conditions = ["diabetes", "hypertension", "joint pain", "postpartum", "inflammation"]
        if any(condition in goal for condition in health_conditions):
            return "health_condition"
            
        return "general_wellness"

    def _get_goal_adjustment_factor(self, goal: str) -> float:
        """
        Get the calorie adjustment factor based on the goal category.
        
        Args:
            goal: The user's goal string
            
        Returns:
            float: Adjustment factor to apply to TDEE
        """
        goal_category = self._categorize_goal(goal)
        
        adjustment_factors = {
            "weight_loss": -0.15,    # 15% reduction for weight loss
            "muscle_gain": 0.15,     # 15% increase for muscle gain
            "maintain": 0.0,         # No adjustment for maintenance/satiety
            "health_condition": 0.0,  # No adjustment by default for health conditions
            "general_wellness": 0.0   # No adjustment for general wellness
        }
        
        return adjustment_factors.get(goal_category, 0.0)

    def calculate_daily_calories(self, bmr, activity_level, goals=None):
        """
        Calculate daily calories based on BMR, activity level, and weight goal.
        
        Args:
            bmr: Basal Metabolic Rate
            activity_level: User's activity level
            goals: Optional weight goal string (supports various formats)
            
        Returns:
            int: Adjusted daily calorie target
        """
        try:
            bmr_f = float(bmr)
        except (ValueError, TypeError):
            logger.warning(f"Invalid BMR for TDEE: {bmr}")
            return 0
            
        # Get activity multiplier
        act_level = str(activity_level).lower().strip() if activity_level else 'sedentary'
        mults = {
            'sedentary': 1.2,
            'lightly active': 1.375,
            'moderately active': 1.55,
            'very active': 1.725,
            'extra_active': 1.9
        }
        mult = mults.get(act_level, 1.2)
        if act_level not in mults:
            logger.warning(f"Unknown activity '{activity_level}', using sedentary.")
            
        # Calculate base TDEE
        daily_calories = round(bmr_f * mult)
        
        # Apply goal-based adjustments if goals are provided
        if goals:
            adjustment_percent = self._get_goal_adjustment_factor(goals)
            daily_calories = int(daily_calories * (1 + adjustment_percent))
            logger.info(f"Applied {adjustment_percent*100:.1f}% adjustment for goal: {goals}")
            
        return daily_calories


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


# --- MoMo Payment Endpoints ---
@app.post("/rr/momo/request-payment", response_class=ORJSONResponse)
async def request_momo_payment(
    amount: float = Body(..., gt=0, description="Amount to be paid"),
    currency: str = Body(None, regex=r'^[A-Z]{3}$', description="Currency code (e.g., 'UGX', 'USD'). Defaults to MOMO_CURRENCY from .env or 'UGX'"),
    payer_number: str = Body(..., description="Payer's phone number (MSISDN) with country code"),
    payer_message: str = Body(None, description="Message to be shown to the payer. Defaults to 'Payment of {amount} {currency} to ZINZI'"),
    payee_note: str = Body(None, description="Note about the payment for the payee. Defaults to 'Thank you for your payment'"),
    external_id: str = Body(None, description="External reference ID (will be generated if not provided)"),
    db: asyncpg.Connection = Depends(get_db)
):
    """
    Request a payment from a user via MoMo.
    
    This endpoint initiates a payment request to the specified phone number.
    The user will receive a prompt to approve the payment on their device.
    """
    try:
        # Generate a unique external ID if not provided
        if not external_id:
            external_id = f"ZINZI_PAY_{int(time.time())}"
            
        # Request payment
        result = await momo_service.request_payment(
            amount=amount,
            currency=currency,
            external_id=external_id,
            payer_number=payer_number,
            payer_message=payer_message,
            payee_note=payee_note
        )
        
        # Log the payment request in the database
        try:
            # Use the transaction_id from the result, or fallback to the external_id
            transaction_id = result.get("transaction_id") or external_id
            await db.execute(
                """
                INSERT INTO payment_transactions 
                (transaction_id, external_id, amount, currency, status, payment_method, payment_details)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                transaction_id,
                external_id,
                amount,
                currency or "UGX",  # Default to UGX if currency is None
                "PENDING",
                "momo",
                json.dumps({
                    "payer_number": payer_number,
                    "payer_message": payer_message,
                    "payee_note": payee_note,
                    "momo_response": result
                })
            )
            logger.info(f"Successfully logged payment to database. Transaction ID: {transaction_id}, External ID: {external_id}")
        except Exception as e:
            logger.error(f"Failed to log MoMo payment to database: {str(e)}")
            logger.error(f"Result data: {result}")
        
        return {
            "success": True,
            "transaction_id": result.get("financialTransactionId"),
            "external_id": external_id,
            "status": result.get("status"),
            "message": "Payment request initiated successfully"
        }
    except Exception as e:
        logger.error(f"Error in MoMo payment request: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to process payment request: {str(e)}"
        )

@app.get("/rr/momo/payment-status/{reference_id}", response_class=ORJSONResponse)
async def get_momo_payment_status(
    reference_id: str = Path(..., description="MoMo transaction ID or external ID"),
    db: asyncpg.Connection = Depends(get_db)
):
    """
    Check the status of a MoMo payment.
    
    This endpoint checks the current status of a previously initiated payment.
    Can be queried using either the transaction_id or external_id.
    """
    try:
        # Check if we have the transaction in our database using either transaction_id or external_id
        transaction = await db.fetchrow(
            """
            SELECT * FROM payment_transactions 
            WHERE transaction_id = $1 OR external_id = $1
            """,
            reference_id
        )
        
        if not transaction:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Transaction with ID {reference_id} not found"
            )
            
        transaction_id = transaction["transaction_id"]
            
        # Call MoMo API to get the current status
        momo_service = MomoService()
        status_info = await momo_service.check_payment_status(transaction_id)
        
        # Update our database with the latest status
        await db.execute(
            """
            UPDATE payment_transactions 
            SET status = $1, updated_at = NOW()
            WHERE transaction_id = $2
            """,
            status_info.get("status"),
            transaction_id
        )
        
        return {
            "success": True,
            "transaction_id": transaction_id,
            "external_id": transaction.get("external_id"),
            "status": status_info.get("status"),
            "details": status_info
        }
    except HTTPException as he:
        # Re-raise HTTP exceptions as-is
        raise he
    except Exception as e:
        logger.error(f"Error checking MoMo payment status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to check payment status: {str(e)}"
        )

@app.post("/rr/momo/disburse", response_class=ORJSONResponse)
async def disburse_funds(
    amount: float = Body(..., gt=0, description="Amount to disburse"),
    currency: str = Body(None, regex=r'^[A-Z]{3}$', description="Currency code (e.g., 'UGX'). Defaults to MOMO_CURRENCY from .env or 'UGX'"),
    payee_id: str = Body(..., description="Recipient's ID (phone number or account number)"),
    payee_id_type: str = Body("MSISDN", description="Type of payee ID (default: MSISDN for phone number)"),
    payer_message: str = Body(None, description="Message to the recipient. Defaults to 'Payment of {amount} {currency} from ZINZI'"),
    payee_note: str = Body(None, description="Note about the payment. Defaults to 'Payment for services'"),
    external_id: str = Body(None, description="External reference ID (will be generated if not provided)"),
    db: asyncpg.Connection = Depends(get_db)
):
    """
    Disburse funds to a recipient via MoMo.
    
    This endpoint initiates a disbursement to the specified recipient.
    """
    try:
        # Generate a unique external ID if not provided
        if not external_id:
            external_id = f"ZINZI_DISB_{int(time.time())}"
            
        # Perform disbursement
        result = await momo_service.disburse_funds(
            amount=amount,
            currency=currency,
            external_id=external_id,
            payee_id=payee_id,
            payee_id_type=payee_id_type,
            payer_message=payer_message,
            payee_note=payee_note
        )
        
        # Log the disbursement in the database
        try:
            # Use transaction_id from the result, fallback to external_id if not available
            transaction_id = result.get("transaction_id") or external_id
            
            await db.execute(
                """
                INSERT INTO disbursement_transactions 
                (transaction_id, external_id, amount, currency, status, recipient_id, recipient_type, details)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                transaction_id,
                external_id,
                amount,
                currency or "UGX",  # Default to UGX if currency is None
                result.get("status", "PENDING"),
                payee_id,
                payee_id_type,
                json.dumps({
                    "payer_message": payer_message,
                    "payee_note": payee_note,
                    "momo_response": result
                })
            )
            logger.info(f"Successfully logged disbursement to database with transaction_id: {transaction_id}")
        except Exception as e:
            logger.error(f"Failed to log MoMo disbursement to database: {str(e)}", exc_info=True)
            # Continue even if database logging fails, as the disbursement was successful
        
        return {
            "success": True,
            "transaction_id": result.get("transaction_id"),
            "external_id": external_id,
            "status": result.get("status"),
            "message": "Disbursement initiated successfully"
        }
    except Exception as e:
        logger.error(f"Error in MoMo disbursement: {str(e)}", exc_info=True)
        error_detail = str(e)
        if "Failed to get disbursement token" in error_detail:
            error_detail = "Failed to authenticate with MoMo API. Please check your MoMo API credentials."
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_detail
        )

@app.get("/rr/momo/disbursement-status/{reference_id}", response_class=ORJSONResponse)
async def get_disbursement_status(
    reference_id: str = Path(..., description="Disbursement reference ID"),
    db: asyncpg.Connection = Depends(get_db)
):
    """
    Check the status of a MoMo disbursement.
    
    This endpoint checks the current status of a previously initiated disbursement.
    """
    try:
        # Check if we have the disbursement in our database
        disbursement = await db.fetchrow(
            "SELECT * FROM disbursement_transactions WHERE transaction_id = $1 OR external_id = $1",
            reference_id
        )
        
        if not disbursement:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Disbursement not found"
            )
        
        # Get the latest status from MoMo
        status_info = await momo_service.check_disbursement_status(
            disbursement["transaction_id"]
        )
        
        # Update the disbursement status in our database
        await db.execute(
            """
            UPDATE disbursement_transactions 
            SET status = $1, updated_at = NOW()
            WHERE id = $2
            RETURNING *
            """,
            status_info.get("status"),
            disbursement["id"]
        )
        
        return {
            "success": True,
            "transaction_id": disbursement["transaction_id"],
            "external_id": disbursement["external_id"],
            "status": status_info.get("status"),
            "details": status_info
        }
    except Exception as e:
        logger.error(f"Error checking MoMo disbursement status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Failed to check disbursement status: {str(e)}"
        )

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
    logger.info("Stripe payment likely cancelled.")
    return {"status": "cancelled", "message": "Payment not completed."}


# Rate Limiting and Brute Force Protection
class RateLimiter:
    def __init__(self):
        # Format: {ip: {'attempts': int, 'first_attempt': timestamp, 'last_attempt': timestamp, 'blocked_until': timestamp}}
        self.ip_tracker = {}
        # Format: {username: {'attempts': int, 'blocked_until': timestamp}}
        self.account_tracker = {}
        self.cleanup_interval = 3600  # Clean up old entries every hour
        self.last_cleanup = time.time()
        
    def _cleanup_old_entries(self):
        current_time = time.time()
        if current_time - self.last_cleanup < self.cleanup_interval:
            return
            
        # Clean up IP tracker
        for ip in list(self.ip_tracker.keys()):
            entry = self.ip_tracker[ip]
            # Remove entries older than 24 hours
            if current_time - entry['last_attempt'] > 86400:
                del self.ip_tracker[ip]
                
        # Clean up account tracker
        for username in list(self.account_tracker.keys()):
            entry = self.account_tracker[username]
            # Remove entries that are no longer blocked and older than 24 hours
            if 'blocked_until' in entry and entry['blocked_until'] < current_time:
                if current_time - entry.get('last_attempt', 0) > 86400:
                    del self.account_tracker[username]
                    
        self.last_cleanup = current_time
    
    def check_rate_limit(self, ip: str, username: str) -> Optional[Dict[str, Any]]:
        """Check if the request should be rate limited.
        
        Returns:
            Dict with 'blocked' (bool) and 'retry_after' (int) if blocked, None otherwise
        """
        current_time = time.time()
        self._cleanup_old_entries()
        
        # Check account-based rate limiting first
        account_entry = self.account_tracker.get(username, {'attempts': 0})
        if 'blocked_until' in account_entry and account_entry['blocked_until'] > current_time:
            return {
                'blocked': True,
                'retry_after': int(account_entry['blocked_until'] - current_time),
                'reason': 'account_blocked',
                'message': 'Too many failed login attempts. Please try again later.'
            }
            
        # Check IP-based rate limiting
        ip_entry = self.ip_tracker.get(ip, {'attempts': 0, 'first_attempt': current_time})
        
        # Reset counter if last attempt was more than 15 minutes ago
        if current_time - ip_entry.get('last_attempt', 0) > 900:  # 15 minutes
            ip_entry = {'attempts': 0, 'first_attempt': current_time}
            
        # Update attempt count and timestamps
        ip_entry['attempts'] += 1
        ip_entry['last_attempt'] = current_time
        self.ip_tracker[ip] = ip_entry
        
        # Implement sliding window rate limiting
        time_window = 900  # 15 minutes in seconds
        max_attempts = 5   # Maximum 5 attempts per 15 minutes per IP
        
        if ip_entry['attempts'] > max_attempts:
            # Calculate how long to block (exponential backoff)
            block_duration = min(3600, 60 * (2 ** (ip_entry['attempts'] - max_attempts)))  # Cap at 1 hour
            ip_entry['blocked_until'] = current_time + block_duration
            self.ip_tracker[ip] = ip_entry
            
            return {
                'blocked': True,
                'retry_after': block_duration,
                'reason': 'ip_blocked',
                'message': 'Too many requests. Please try again later.'
            }
            
        return None
    
    def record_failed_attempt(self, username: str):
        """Record a failed login attempt for an account."""
        current_time = time.time()
        entry = self.account_tracker.get(username, {'attempts': 0, 'last_attempt': 0})
        
        # Reset counter if last attempt was more than 15 minutes ago
        if current_time - entry.get('last_attempt', 0) > 900:  # 15 minutes
            entry = {'attempts': 0, 'last_attempt': current_time}
            
        entry['attempts'] += 1
        entry['last_attempt'] = current_time
        
        # Block account after 3 failed attempts
        if entry['attempts'] >= 3:
            # Exponential backoff: 5 minutes * 2^(attempts - 3), max 24 hours
            block_duration = min(86400, 300 * (2 ** (entry['attempts'] - 3)))
            entry['blocked_until'] = current_time + block_duration
            
        self.account_tracker[username] = entry
        
    def clear_attempts(self, username: str, ip: str = None):
        """Clear failed attempts for a successful login."""
        if username in self.account_tracker:
            del self.account_tracker[username]
        if ip and ip in self.ip_tracker:
            del self.ip_tracker[ip]

    @staticmethod
    def get_client_ip(request: Request) -> str:
        """Get the client's IP address.
        
        Args:
            request: FastAPI Request object
            
        Returns:
            str: Client's IP address
        """
        # Try to get X-Forwarded-For header for proxies
        x_forwarded_for = request.headers.get('x-forwarded-for')
        if x_forwarded_for:
            # Get the first IP in the list (original client IP)
            ip = x_forwarded_for.split(',')[0].strip()
        else:
            # Fall back to request client host
            ip = request.client.host
        return ip

# Initialize rate limiter
rate_limiter = RateLimiter()


@app.post('/rr/login2', status_code=status.HTTP_200_OK)  # Changed from '/rr/admin/login' for security
async def admin_login_endpoint(
    request: Request,
    username: str = Body(..., embed=True),
    password: str = Body(..., embed=True),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Authenticate an admin user with rate limiting and brute force protection.
    
    Args:
        username: Admin username
        password: Admin password
        
    Returns:
        Dict with login status and admin user data if successful
        
    Raises:
        HTTPException: If authentication fails or rate limit is exceeded
    """
    # Get client IP for rate limiting
    client_ip = RateLimiter.get_client_ip(request)
    
    # Check rate limits
    rate_limit = rate_limiter.check_rate_limit(client_ip, username)
    if rate_limit and rate_limit['blocked']:
        retry_after = rate_limit['retry_after']
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            headers={"Retry-After": str(retry_after)},
            detail={
                'message': rate_limit['message'],
                'retry_after': retry_after,
                'status': 'error'
            }
        )
    
    try:
        # Attempt login
        result = await admin_users.login_admin(conn, username, password)
        
        # Clear failed attempts on successful login
        rate_limiter.clear_attempts(username, client_ip)
        
        return result
        
    except HTTPException as he:
        # Record failed attempt for rate limiting
        if he.status_code in [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN]:
            rate_limiter.record_failed_attempt(username)
            
            # Check if account is now blocked
            account_entry = rate_limiter.account_tracker.get(username, {})
            if 'blocked_until' in account_entry:
                retry_after = int(account_entry['blocked_until'] - time.time())
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    headers={"Retry-After": str(retry_after)},
                    detail={
                        'message': 'Account temporarily locked due to too many failed attempts. Please try again later.',
                        'retry_after': retry_after,
                        'status': 'error'
                    }
                )
                
        # Re-raise the original exception
        raise
        
    except Exception as e:
        logger.error(f"Error in admin login endpoint: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='An error occurred during authentication.'
        )
import warnings

class AdminUsers(BaseRepository):
    """Handles admin user authentication and management."""
    
    def __init__(self):
        # Suppress bcrypt version warning
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            self.pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    
    async def login_admin(self, conn: asyncpg.Connection, username: str, password: str) -> Dict[str, Any]:
        """
        Authenticate an admin user.
        
        Args:
            conn: Database connection
            username: Admin username
            password: Plain text password
            
        Returns:
            Dict with login status and user data if successful
            
        Raises:
            HTTPException: If authentication fails
        """
        try:
            # Query the admin user by username (case-sensitive)
            # Only select columns that exist in the console_users table
            sql = """
                SELECT id, username, password_hash, role, created_at
                FROM console_users 
                WHERE username = $1
            """
            result = await self._execute_query(conn, sql, (username,), fetch_one=True)
            
            if not result:
                logger.warning(f"Admin login failed: Username '{username}' not found")
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail='Invalid username or password.'
                )
                
            stored_hash = result.get('password_hash')
            if not stored_hash or not stored_hash.startswith('$2'):
                logger.error(f"Invalid password hash format for admin user: {username}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail='Authentication error.'
                )
                
            # Verify password using bcrypt
            if not self.pwd_context.verify(password, stored_hash):
                logger.warning(f"Admin login failed: Invalid password for user: {username}")
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail='Invalid username or password.'
                )
                
            # Update last login time
            try:
                update_sql = """
                    UPDATE console_users 
                    SET last_login = NOW() 
                    WHERE id = $1
                """
                await self._execute_query(conn, update_sql, (result['id'],))
            except Exception as update_err:
                logger.error(f"Failed to update last_login for admin {username}: {update_err}")
            
            logger.info(f"Admin login successful: {username}")
            return {
                'message': 'Login successful',
                'data': {
                    'admin_id': result['id'],
                    'username': result['username'],
                    'role': result['role'],
                    'created_at': result['created_at'].isoformat() if result.get('created_at') else None
                }
            }
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Error during admin login: {str(e)}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail='An error occurred during authentication.'
            )

# --- Backend Class Instantiations ---
# These instances are created once and used by endpoints via Depends(get_db)
auth_users = AuthenticationAndUsers()
chefs_crud = Chefs()
producers_crud = Producers()
transporters_crud = Transporters()
orders_crud = Orders() 
herbals_crud = Herbals()
meals_crud = Meals()
gadgets_crud = Gadgets()
spices_crud = Spices()
stakeholders_crud = Stakeholders()
calc_logic = CalculationLogic() 
meal_fetcher = GetAllMeals()
disbursement_handler = Disbursements()
supplements_crud = Supplements()
produce_crud = Produce()
admin_users = AdminUsers()  # Add admin users instance


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
    return await auth_users.list_calorie_history(conn, user_id)

@app.post("/auth/request-password-reset", status_code=status.HTTP_202_ACCEPTED)
async def request_password_reset(
    email: str = Body(..., embed=True),
    user_type: str = Body(..., embed=True),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Request a password reset for a user.
    
    This will generate a 6-digit password reset code and send it to the user's email.
    The code will be valid for 10 minutes.
    
    Args:
        email: User's email address
        user_type: Type of user (user, chef, producer, transporter)
        
    Returns:
        dict: Success message (doesn't reveal if email exists for security)
    """
    try:
        # Normalize inputs
        email = email.strip().lower()
        user_type = user_type.strip().lower()
        
        # Define valid user types and their corresponding tables/ID columns
        user_type_map = {
            'user': ('users', 'user_id'),
            'chef': ('chefs', 'chefid'), #chefid is not an error. dont change it to chef_id or ou willbreak the chefs table
            'producer': ('producers', 'producer_id'),
            'transporter': ('transporters', 'transporter_id')
        }
        
        if user_type not in user_type_map:
            logger.info(f"Invalid user type in password reset request: {user_type}")
            return {"message": "If your email is registered, you will receive a password reset code"}
            
        table_name, id_column = user_type_map[user_type]
        
        # Check if user exists and get their ID in a single query
        user_id = await conn.fetchval(
            f"SELECT {id_column} FROM {table_name} WHERE lower(email) = $1",
            email.lower()
        )
        
        if not user_id:
            # Don't reveal if the email exists or not for security
            logger.info(f"Password reset requested for non-existent email: {email} (type: {user_type})")
            return {"message": "If your email is registered, you will receive a password reset code"}
        
        # Generate and store password reset code
        stored_reset_code = await auth_users._create_password_reset_code(conn, email, user_type)
            
        # Send password reset email with code in background
        email_subject = "Password Reset Request"
        email_body = f"""
        <html>
            <body>
                <h2>ZINZI password reset request</h2>
                <p>You have requested to reset your password. Please use the following code to proceed:</p>
                <h3>{stored_reset_code}</h3>
                <p>This code will expire in 10 minutes.</p>
                <p>If you did not request this, please ignore this email.</p>
            </body>
        </html>
        """
        
        # Send the email
        asyncio.create_task(auth_users._send_email(email, email_subject, email_body))
        
        logger.info(f"Password reset code generated for {email} (type: {user_type})")
        return {"message": "If your email is registered, you will receive a password reset code"}
        
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error in request_password_reset: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while processing your request"
        )

@app.post("/auth/verify-reset-code", status_code=status.HTTP_200_OK)
async def verify_reset_code(
    email: str = Body(..., embed=True),
    code: str = Body(..., embed=True),
    user_type: str = Body(..., embed=True),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Verify a password reset code.
    
    Args:
        email: User's email address
        code: The 6-digit reset code
        user_type: Type of user (user, chef, producer, transporter)
        
    Returns:
        dict: Success message if code is valid
    """
    try:
        # Normalize inputs
        email = email.strip().lower()
        user_type = user_type.strip().lower()
        code = code.strip()
        
        # Validate the code
        await auth_users._validate_password_reset_code(conn, email, code, user_type)
        
        return {"message": "Reset code is valid"}
        
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error in verify_reset_code: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while verifying the reset code"
        )

@app.post("/auth/reset-password", status_code=status.HTTP_200_OK)
async def reset_password(
    email: str = Body(..., embed=True),
    code: str = Body(..., embed=True),
    new_password: str = Body(..., embed=True),
    user_type: str = Body(..., embed=True),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Reset a user's password using a valid reset code.
    
    Args:
        email: User's email address
        code: The 6-digit reset code
        new_password: The new password to set
        user_type: Type of user (user, chef, producer, transporter)
        
    Returns:
        dict: Success message
    """
    # Start a transaction
    transaction = conn.transaction()
    try:
        # Start the transaction
        await transaction.start()
        
        # Normalize inputs
        email = email.lower().strip()
        user_type = user_type.lower().strip()
        code = code.strip()
        
        # Validate inputs
        if not all([email, code, new_password, user_type]):
            await transaction.rollback()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="All fields are required"
            )
            
        # Validate password strength
        if len(new_password) < 8:
            await transaction.rollback()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be at least 8 characters long"
            )
            
        # Initialize repository
        auth_users = AuthenticationAndUsers()
        
        # Validate the reset code (will raise HTTPException if invalid)
        await auth_users._validate_password_reset_code(conn, email, code, user_type)
        
        # Hash the new password
        hashed_password = hash_password(new_password)
        
        # Update the password in the appropriate table based on user_type
        table_map = {
            'user': 'users',
            'chef': 'chefs',
            'producer': 'producers',
            'transporter': 'transporters'
        }
        
        if user_type not in table_map:
            await transaction.rollback()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid user type: {user_type}"
            )
            
        table_name = table_map[user_type]
        id_column = 'user_id' if user_type == 'user' else f'{user_type}_id'
        
        try:
            # Update the password
            result = await conn.execute(
                f"""
                UPDATE {table_name}
                SET hashed_password = $1, updated_at = NOW()
                WHERE email = $2
                RETURNING {id_column}
                """,
                hashed_password, email
            )
            
            if result == 'UPDATE 0':
                await transaction.rollback()
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="User not found"
                )
            
            # Mark the code as used
            await auth_users._mark_code_as_used(conn, email, code, user_type)
            
            # Commit the transaction if all operations succeed
            await transaction.commit()
            
            logger.info(f"Password reset successful for {email} (type: {user_type})")
            return {"message": "Password has been reset successfully"}
            
        except Exception as e:
            await transaction.rollback()
            logger.error(f"Database error during password reset for {email}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="An error occurred while updating your password"
            )
            
    except HTTPException as he:
        # Re-raise HTTP exceptions as-is
        if 'transaction' in locals() and not transaction.is_closed():
            await transaction.rollback()
        raise he
        
    except Exception as e:
        # Rollback on any other exception
        if 'transaction' in locals() and not transaction.is_closed():
            await transaction.rollback()
            
        logger.error(f"Error in reset_password: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while resetting your password"
        )

@app.get('/rr') #also used by my health status checking server o see if servr is up and okay
@alru_cache(maxsize=1)
async def welcome():
    """Welcome endpoint."""
    return {'message': 'Welcome to ZINZI.'} # Updated name

@app.get("/favicon.ico", include_in_schema=False)
async def get_favicon():
    return FileResponse("static/favicon.ico")

# === USER Endpoints ===
@app.post("/rr/resend_verification_email", status_code=status.HTTP_202_ACCEPTED)
async def resend_verification_email(
    user_id: int = Body(..., embed=True),
    user_type: str = Body(..., embed=True),
    conn: asyncpg.Connection = Depends(get_db)
):
    """
    Resend verification email to the user with a new verification code.
    
    Args:
        user_id: ID of the user to resend verification email to
        user_type: Type of the user (e.g., 'user', 'chef', 'producer')
        
    Returns:
        dict: Status message indicating success or failure
    """
    # Normalize user_type to lowercase for consistency
    user_type_lower = user_type.lower().strip()
    
    try:
        # Get user's email based on user_type
        email_to_send = None
        user_type_to_send = user_type_lower
        
        # Map user types to their respective tables
        user_type_mapping = {
            'user': 'users',
            'chef': 'chefs',
            'producer': 'producers',
            'transporter': 'transporters'
        }
        
        table_name = user_type_mapping.get(user_type_lower)
        if not table_name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid user type: {user_type}"
            )
        
        # Get user's email from the appropriate table
        email_result = await conn.fetchval(
            f"SELECT email FROM {table_name} WHERE {table_name.rstrip('s')}_id = $1",
            user_id
        )
        
        if not email_result:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User with ID {user_id} not found in {table_name} table"
            )
            
        email_to_send = email_result.lower().strip()
        
        # Background task to handle verification code and email sending
        async def send_verification_email():
            logger.info(f"Attempting to resend verification email to {email_to_send}")
            try:
                # Get a new connection from the pool for the background task
                async with db_pool.acquire() as bg_conn:
                    auth_handler = AuthenticationAndUsers()
                    # Let _handle_email_verification handle code generation and storage
                    # This will also handle deleting any existing codes for this user
                    verification_code = await auth_handler._handle_email_verification(
                        bg_conn, email_to_send, user_id, user_type_lower
                    )
                    # Send the email with the verification code
                    await auth_handler.send_verification_email_gmail(
                        to_email=email_to_send, 
                        verification_code=verification_code
                    )
                    # Success message is logged in _send_verification_email
            except Exception as e:
                logger.error(f"Error in background email sending task: {e}", exc_info=True)
        
        # Start the background task
        asyncio.create_task(send_verification_email())
        
        return {"message": "Verification email resent successfully"}
        
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error resending verification email: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An error occurred while resending the verification email"
        )

@app.post('/rr/signup_user', status_code=status.HTTP_201_CREATED)
async def signup_user_endpoint(
    user_data: dict = Body(...), 
    background_tasks: BackgroundTasks = BackgroundTasks(),
    conn: asyncpg.Connection = Depends(get_db)
):
    try:
        name = user_data['name']
        email = user_data['email']
        password = user_data['password']
        image = user_data.get('image')
        user_type = user_data.get('user_type', 'user')
        phone = user_data.get('phone_number')
        
        # Call signup_user directly with background_tasks
        result = await auth_users.signup_user(
            conn=conn,
            name=name,
            email=email,
            password=password,
            user_type=user_type,
            image=image,
            phone=phone,
            background_tasks=background_tasks
        )
        
        return {
            'message': 'User registered. Please check your email for verification.',
            'user_id': result['user_id'],
            'user_type': user_type,
            'phone': result['phone']
        }
    except HTTPException as he:
        # Re-raise HTTPException to maintain the original status code and detail
        raise he
    except KeyError as ke:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail=f'Missing required field: {ke}'
        )

@app.post('/rr/verify_user')
async def verify_user_endpoint(verification_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # ... (implementation unchanged, uses conn from dependency) ...
    try:
        user_id=int(verification_data['user_id']); verification_code=verification_data['verification_code']; user_type=verification_data['user_type']
        if not verification_code: raise ValueError("verification_code required")
        if not user_type: raise ValueError("user_type required")
    except KeyError as ke:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f'Invalid input: Missing field {ke}. user_id (int), verification_code (str), and user_type (str) required.')
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f'Invalid input: {ve}')
    except Exception as e:
        logger.error(f"Unexpected error parsing verification data: {e}", exc_info=True)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="An unexpected error occurred while processing input.")
    await auth_users.verify_user_email(conn, user_id, verification_code, user_type) # Pass conn and user_type
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
async def create_chef_endpoint(
    chef_data: dict = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    conn: asyncpg.Connection = Depends(get_db)
):
    return await chefs_crud.create_chef(conn, chef_data, background_tasks) # Pass conn and background_tasks

@app.post('/rr/login/chefs')
async def login_chef_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await chefs_crud.login_chef(conn, identifier, password) # Pass conn

@app.get('/rr/rchefs')
async def list_all_chefs_endpoint(
    geo_fenced_location: Optional[str] = Query(None, description="Optional location to filter chefs by proximity (e.g., '1.2921, 36.8219' or 'Nairobi, Kenya')"),
    radius_km: Optional[float] = Query(None, description="Optional. Maximum distance in kilometers for geofencing. Uses GEO_RADIUS from .env or 5.0km if not provided"),
    conn: asyncpg.Connection = Depends(get_db)
):
    data = await chefs_crud.list_chefs(conn, chef_id=None)  # Pass conn
    
    # Apply geofencing if location is provided
    if geo_fenced_location:
        data = await LocationService.geo_fence_entities(
            entities=data,
            user_location=geo_fenced_location,
            location_field='location',  # Field in chef data that contains location string
            radius_km=radius_km  # Pass the optional radius_km parameter
        )
        
    return {'message': 'Chefs retrieved.', 'data': data}

@app.get('/rr/rchefs/{chef_id}')
async def get_chef_by_id_endpoint(chef_id: int = Path(..., gt=0), conn: asyncpg.Connection = Depends(get_db)):
    data_list = await chefs_crud.list_chefs(conn, chef_id=chef_id) # Pass conn
    if not data_list: raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Chef not found')
    return {'message': 'Chef retrieved.', 'data': data_list[0]}

@app.put('/rr/chefs/{chef_id}')
@app.patch('/rr/chefs/{chef_id}')
async def update_chef_endpoint(chef_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    # Log the incoming request data for debugging
    logger.info(f"Received update request for chef {chef_id}")
    logger.info(f"Update data: {updates}")
    if 'stock' in updates:
        logger.info(f"Stock data type: {type(updates['stock'])}")
        if isinstance(updates['stock'], list) and updates['stock']:
            logger.info(f"First stock item: {updates['stock'][0]}")
            logger.info(f"First stock item type: {type(updates['stock'][0])}")
    
    try:
        await chefs_crud.update_chef(conn, chef_id, updates) # Pass conn
        updated_chef_list = await chefs_crud.list_chefs(conn, chef_id=chef_id) # Pass conn
        if updated_chef_list: 
            return {'message': 'Chef updated', 'data': updated_chef_list[0]}
        else: 
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, 
                            detail='Chef not found after update.')
    except Exception as e:
        logger.error(f"Error updating chef {chef_id}: {str(e)}", exc_info=True)
        raise

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

@app.get("/rr/meals2/{user_id}")
async def get_meal_recommendations(user_id: int, conn: asyncpg.Connection = Depends(get_db)):
    """
    Get meal recommendations for a user.
    
    Args:
        user_id: User ID for whom to generate recommendations
    
    Returns:
        List of recommended meals with success status
    """
    global meal_recommender
    
    if meal_recommender is None:
        logger.error("Meal recommender not initialized")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Meal recommendation service not available"
        )
    
    try:
        # Update the user ID for this request
        meal_recommender.user_id = user_id
        
        # Get recommendations using the singleton instance
        recommendations = meal_recommender.recommend_meals()
        
        return {"recommended_meals": recommendations, "success": True}
        
    except Exception as e:
        logger.error(f"Error generating meal recommendations: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
            detail="Failed to generate meal recommendations"
        )

@app.get("/rr/meal_calories/{meal_id}") # PS: meal_id is str not int
async def get_meal_calories(meal_id: str, conn: asyncpg.Connection = Depends(get_db)):
    """
    Get detailed nutrition information for a specific meal.
    
    Args:
        meal_id: ID of the meal to get calories for
    
    Returns:
        Dict containing detailed nutrition information
    """
    try:
        # Get detailed meal info using the meals_crud instance
        meal_info = await meal_recommender.calculate_meal_calories(str(meal_id)) 
        
        if not meal_info:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Meal with ID {meal_id} not found"
            )
            
        return {
            "success": True,
            "meal_id": meal_id,
            "calories": meal_info.get('calories', 0),
            "nutrition_info": {
                "protein": meal_info.get('protein', 0),
                "carbs": meal_info.get('carbs', 0),
                "fats": meal_info.get('fats', 0),
                # Include any other nutrition fields you need
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting meal calories for meal {meal_id}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get meal calories: {str(e)}"
        )

# === PRODUCER Endpoints ===
@app.post('/rr/aproducers', status_code=status.HTTP_201_CREATED)
async def add_producer_endpoint(
    producer_data: dict = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    conn: asyncpg.Connection = Depends(get_db)
):
    return await producers_crud.create_producer(conn, producer_data, background_tasks) # Pass conn and background_tasks

@app.post('/rr/login/producers')
async def login_producer_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await producers_crud.login_producer(conn, identifier, password) # Pass conn

@app.get('/rr/rproducers')
async def list_all_producers_endpoint(
    geo_fenced_location: Optional[str] = Query(None, description="Optional location to filter producers by proximity (e.g., '1.2921, 36.8219' or 'Nairobi, Kenya')"),
    radius_km: Optional[float] = Query(None, description="Optional. Maximum distance in kilometers for geofencing. Uses GEO_RADIUS from .env or 5.0km if not provided"),
    conn: asyncpg.Connection = Depends(get_db)
):
    data = await producers_crud.list_producers(conn, producer_id=None)  # Pass conn
    
    # Apply geofencing if location is provided
    if geo_fenced_location:
        data = await LocationService.geo_fence_entities(
            entities=data,
            user_location=geo_fenced_location,
            location_field='location',  # Field in producer data that contains location string
            radius_km=radius_km  # Pass the optional radius_km parameter
        )
        
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
async def signup_transporter_endpoint(
    transporter_data: dict = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    conn: asyncpg.Connection = Depends(get_db)
):
    return await transporters_crud.create_transporter(conn, transporter_data, background_tasks) # Pass conn and background_tasks

@app.post('/rr/transporters/login')
async def login_transporter_endpoint(login_data: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    identifier=login_data.get('identifier'); password=login_data.get('password')
    if not identifier or not password: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Identifier/password required')
    return await transporters_crud.login_transporter(conn, identifier, password) # Pass conn

@app.get('/rr/transporters')
async def list_all_transporters_endpoint(
    geo_fenced_location: Optional[str] = Query(None, description="Optional location to filter transporters by proximity (e.g., '1.2921, 36.8219' or 'Nairobi, Kenya')"),
    radius_km: Optional[float] = Query(None, description="Optional. Maximum distance in kilometers for geofencing. Uses GEO_RADIUS from .env or 5.0km if not provided"),
    conn: asyncpg.Connection = Depends(get_db)
):
    data = await transporters_crud.list_transporters(conn, transporter_id=None)  # Pass conn
    
    # Apply geofencing if location is provided
    if geo_fenced_location:
        data = await LocationService.geo_fence_entities(
            entities=data,
            user_location=geo_fenced_location,
            location_field='location',  # Field in transporter data that contains location string
            radius_km=radius_km  # Pass the optional radius_km parameter
        )
        
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
        token_data: {"token": str, "platform": str, "user_type": str, "user_id": str/int}
        conn: Database connection
    
    Returns:
        dict: Success message
    """
    try:
        logger.info(f"Received FCM token registration request: {token_data}")
        
        token = token_data.get('token')
        platform = token_data.get('platform')
        user_type = token_data.get('user_type')
        user_id = token_data.get('user_id')
        app_version = token_data.get('app_version')  # Optional field

        if not all([token, platform, user_type, user_id]):
            error_msg = f"Missing required fields in token registration. " \
                       f"Token: {bool(token)}, Platform: {platform}, " \
                       f"User Type: {user_type}, User ID: {user_id}"
            logger.error(error_msg)
            raise HTTPException(
                status_code=400, 
                detail="Missing required fields. Please provide token, platform, user_type, and user_id."
            )
        
        # Convert user_id to integer
        try:
            user_id_int = int(user_id)
        except (ValueError, TypeError) as e:
            error_msg = f"Invalid user_id format: {user_id}. Must be a number."
            logger.error(f"{error_msg} Error: {str(e)}")
            raise HTTPException(status_code=400, detail=error_msg)
        
        logger.info(f"Storing FCM token for user_id: {user_id_int}, type: {user_type}, platform: {platform}")
        
        # Store the token
        try:
            # Get the notification service instance
            notification_service = get_notification_service()
            await notification_service.store_fcm_token(
                user_id=user_id_int,
                token=token,
                platform=platform,
                user_type=user_type,
                app_version=app_version  # Pass the optional app_version
            )
            
            logger.info(f"FCM token successfully registered for user_id: {user_id_int}")
            return {"message": "Token registered successfully"}
        except HTTPException as http_err:
            logger.error(f"HTTP error in store_fcm_token: {str(http_err)}")
            raise
        except Exception as e:
            error_msg = f"Failed to store FCM token: {str(e)}"
            logger.error(error_msg, exc_info=True)  # Include full traceback
            raise HTTPException(status_code=500, detail=error_msg)
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        error_msg = f"Unexpected error during FCM token registration: {str(e)}"
        logger.error(error_msg, exc_info=True)  # Include full traceback
        raise HTTPException(status_code=500, detail=error_msg)

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
@app.post('/rr/stakeholders', status_code=status.HTTP_201_CREATED)
async def add_stakeholder_endpoint(
    stakeholder_data: dict = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks(),
    conn: asyncpg.Connection = Depends(get_db)
):
    return await stakeholders_crud.create_stakeholder(conn, stakeholder_data, background_tasks) # Pass conn and background_tasks

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
    logger.debug(f"Received order payload: {order_data}")
    try:
        # First, validate required payment fields are present and in the correct format
        required_payment_fields = {
            'payment_mode': (str, ['momo', 'cash']),  # Field: (type, allowed_values)
            'payment_phone_number': (str, None),  # Just validate type
            'total_price': ((int, float), None)  # Can be int or float
        }
        
        missing_fields = [field for field in required_payment_fields if field not in order_data]
        if missing_fields:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Missing required payment fields: {', '.join(missing_fields)}"
            )
            
        # Validate field types and values
        for field, (field_type, allowed_values) in required_payment_fields.items():
            value = order_data[field]
            
            # Check type
            if not isinstance(value, field_type) and not (field_type == (int, float) and isinstance(value, (int, float))):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid type for {field}. Expected {field_type}, got {type(value).__name__}"
                )
                
            # Check allowed values if specified
            if allowed_values and str(value).lower() not in allowed_values:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid value for {field}. Must be one of: {', '.join(allowed_values)}"
                )
        
        # Ensure payment_status is not set by client
        if 'payment_status' in order_data:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="payment_status cannot be set by client. It is determined by the server."
            )
        
        # Extract required fields with validation
        try:
            user_id = int(order_data['user_id'])
            order_type = str(order_data['order_type']).strip()
            user_type = str(order_data['user_type']).strip()
            payment_mode = str(order_data['payment_mode']).lower()
            payment_phone_number = str(order_data['payment_phone_number']).strip()
            total_price = float(order_data['total_price'])
            
            if total_price <= 0:
                raise ValueError("total_price must be greater than 0")
                
            if not payment_phone_number:
                raise ValueError("payment_phone_number cannot be empty")
                
        except (ValueError, KeyError) as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid order data: {str(e)}"
            )
        
        # Initialize payment variables with default values
        transaction_id = None
        payment_status = 'pending'
        amount_paid = 0.0
        
        # Get total price, for gig orders try to get from gig details if not in order_data
        if order_type == 'gig' and not order_data.get('total_price') and order_data.get('items') and len(order_data['items']) > 0:
            # Extract price from the first item's gig_details if available
            first_item = order_data['items'][0]
            if first_item.get('gig_details') and 'price' in first_item['gig_details']:
                total_price = float(first_item['gig_details']['price'])
                logger.info(f"[ORDER] Using gig price from gig_details: {total_price}")
            else:
                total_price = 0.0
        else:
            total_price = float(order_data.get('total_price', 0.0))
        
        # Get and validate phone number (required for all orders)
        user_phone = order_data.get('payment_phone_number')
        if not user_phone:
            logger.error("Phone number is required for order placement")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Phone number is required for order placement"
            )
        
        # Process MoMo payment if payment mode is 'momo'
        if payment_mode == 'momo':
            logger.info(f"[PAYMENT] Starting MoMo payment process for order from user {user_id}")
            logger.debug(f"[PAYMENT] Payment details - Amount: {total_price}, User: {user_id}")
            
            # Use the already validated phone number for MoMo payment
            payer_number = user_phone
            
            if total_price <= 0:
                error_msg = f"[PAYMENT] Invalid payment amount: {total_price}"
                if order_type == 'gig':
                    error_msg += ". Please ensure the gig has a valid price set in gig_details"
                logger.error(error_msg)
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=error_msg
                )
            
            # Generate a unique external ID for the transaction with extra random digits and underscores
            timestamp = int(time.time())
            random_suffix = str(random.randint(1000, 9999))  # 4-digit random number
            external_id = f"ZINZI_{timestamp}_{random_suffix}_{user_id}"
            logger.debug(f"[PAYMENT] Generated external ID: {external_id}")
            
            try:
                # Let MomoService handle all the payment logic
                payment_result = await momo_service.request_payment(
                    amount=total_price,
                    payer_number=payer_number
                )
                
                # Extract transaction details from the result
                # Use the external_id as the transaction_id for the order to ensure consistency
                transaction_id = external_id  # Use the same external_id we generated for MoMo
                payment_status = 'paid'  # Set status to indicate payment is being processed
                amount_paid = total_price  # Set amount_paid to total_price immediately
                
                logger.info(f"[PAYMENT] MoMo payment initiated successfully. Transaction ID: {transaction_id}")
                logger.info("[PAYMENT] Payment processing completed successfully")
                
            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"[PAYMENT] Error processing MoMo payment: {str(e)}", exc_info=True)
                logger.info("[PAYMENT] Payment processing failed")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Error processing payment: {str(e)}"
                )
        else:
            # For non-MoMo payments, use provided or default values
            transaction_id = order_data.get('transaction_id')
            payment_status = order_data.get('payment_status', 'pending')
            amount_paid = order_data.get('amount_paid', 0.0)
            
            # For cash on delivery, set status to pending
            if payment_mode == 'cash':
                payment_status = 'pending'
                amount_paid = 0.0
        
        # Update order data with payment details
        order_data.update({
            'transaction_id': transaction_id,
            'payment_status': payment_status,
            'amount_paid': amount_paid,
            'total_price': total_price,
            'payment_mode': payment_mode
        })
        
        logger.info(f"[ORDER] Creating order with payment status: {payment_status}")
        
        # Extract other order fields
        product_id = order_data.get('product_id')
        delivery_address = order_data.get('delivery_address')
        order_status = order_data.get('order_status', 'pending')
        notes = order_data.get('notes')
        quantity = order_data.get('quantity', 1)
        transporter_id = order_data.get('transporter_id')
        items = order_data.get('items')
        chef_id = order_data.get('chef_id')
        producer_id = order_data.get('producer_id')
        if isinstance(items, list) and len(items) > 0:
             first=items[0]; chef_id=first.get('chef_id',chef_id); producer_id=first.get('producer_id',producer_id); product_id=first.get('product_id',product_id); quantity=first.get('quantity',quantity)
        is_gig = str(order_type).lower().strip() == 'gig'
        if not is_gig:
            if chef_id is None and producer_id is None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='chef_id or producer_id required.')
            if chef_id is not None and producer_id is not None: raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot set both chef_id and producer_id.')
        async with conn.transaction():
            # user_type is now required and will be validated by create_order
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
                items=items, 
                user_type=user_type,  # This is now required
                user_phone=user_phone  # Pass the validated phone number
            )
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
async def get_orders_endpoint(
    order_id: Optional[int] = Query(None),
    chef_id: Optional[int] = Query(None),
    producer_id: Optional[int] = Query(None),
    user_id: Optional[int] = Query(None),
    transporter_id: Optional[int] = Query(None),
    user_type: Optional[str] = Query(None),
    conn: asyncpg.Connection = Depends(get_db)
):
    # Require user_type when user_id is provided
    if user_id is not None and user_type is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="user_type is required when user_id is provided"
        )
        
    data = await orders_crud.read_orders(
        conn=conn,
        order_id=order_id,
        chef_id=chef_id,
        producer_id=producer_id,
        user_id=user_id,
        transporter_id=transporter_id,
        user_type=user_type
    )
    return {'message': 'Orders retrieved.', 'data': data}

@app.patch('/rr/orders/{order_id}/status')
async def update_order_status_endpoint(order_id: int, status_update: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    if 'order_status' not in status_update:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Requires "order_status"')

    new_status = status_update['order_status']
    transporter_id = status_update.get('transporter_id') # Optional transporter_id
    completion_code = status_update.get('completion_code') # Optional completion_code
    restaurant_phone = status_update.get('restaurant_phone') # Optional restaurant_phone

    # Add validation for transporter_id if status is 'assigned'
    if str(new_status).lower().strip() == 'assigned' and transporter_id is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='"assigned" status needs "transporter_id"')

    # Update order status with all provided parameters
    result = await orders_crud.update_order_status(
        conn=conn,
        order_id=order_id,
        new_status=new_status,
        transporter_id=transporter_id,
        completion_code=completion_code, # Pass the optional completion_code
        restaurant_phone=restaurant_phone # Pass the optional restaurant_phone
    )
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
    return {"metrics": metrics}
@app.put('/rr/metrics/{user_id}')
@app.patch('/rr/metrics/{user_id}')
async def update_metric_endpoint(user_id: int, updates: dict = Body(...), conn: asyncpg.Connection = Depends(get_db)):
    """Update a user metric by user ID."""
    repo = AuthenticationAndUsers()
    await repo.update_metric(conn, user_id, updates)
    
    # Trigger async recalculation if weight is in updates
    if 'weight' in updates:
        # Create a new database connection for the background task
        async def _recalculate():
            try:
                async with db_pool.acquire() as task_conn:
                    await repo._recalculate_daily_calories(task_conn, user_id)
                    logger.info(f"Completed async recalculation of daily calories for user {user_id} after weight update")
            except Exception as e:
                logger.error(f"Error in background recalculation for user {user_id}: {str(e)}", exc_info=True)
        
        asyncio.create_task(_recalculate())
        logger.info(f"Triggered async recalculation of daily calories for user {user_id} after weight update")
    
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
        
        # Trigger async recalculation if goals is in updates
        if 'goals' in updates:
            # Create a new database connection for the background task
            async def _recalculate():
                try:
                    async with db_pool.acquire() as task_conn:
                        await repo._recalculate_daily_calories(task_conn, user_id)
                        logger.info(f"Completed async recalculation of daily calories for user {user_id} after preferences update")
                except Exception as e:
                    logger.error(f"Error in background recalculation for user {user_id}: {str(e)}", exc_info=True)
            
            asyncio.create_task(_recalculate())
            logger.info(f"Triggered async recalculation of daily calories for user {user_id} after preferences update")
        
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


@app.post('/rr/momo_callback')
@app.put('/rr/momo_callback')
async def momo_callback(
    request: Request,
    db: asyncpg.Connection = Depends(get_db)
):
    """
    Handle MoMo API callbacks for payment and disbursement status updates.
    This endpoint is called by MoMo servers to notify about transaction status changes.
    """
    try:
        # Get raw body for signature verification
        body_bytes = await request.body()
        payload = json.loads(body_bytes)
        
        logger.info(f"Received MoMo callback: {json.dumps(payload, indent=2)}")
        
        # Extract required fields from the callback
        external_id = payload.get('externalId')
        if not external_id:
            logger.error("Missing external_id in MoMo callback")
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={"status": "error", "message": "Missing external_id in callback"}
            )
            
        transaction_id = payload.get('financialTransactionId') or external_id
        status_value = payload.get('status', '').upper()
        amount = payload.get('amount')
        currency = payload.get('currency', 'UGX')
        
        # Log the callback details
        logger.info(f"Processing MoMo callback for transaction {transaction_id} (external_id: {external_id}): {status_value}")
        
        # Check if we already have this transaction
        existing_tx = await db.fetchrow(
            "SELECT * FROM payment_transactions WHERE transaction_id = $1 OR external_id = $2",
            transaction_id, external_id
        )
        
        if existing_tx:
            # Update existing transaction
            await db.execute(
                """
                UPDATE payment_transactions 
                SET status = $1, 
                    updated_at = NOW(),
                    payment_details = COALESCE(payment_details, '{}'::jsonb) || $2::jsonb
                WHERE transaction_id = $3 OR external_id = $4
                """,
                status_value,
                json.dumps({"callback": payload, "updated_at": datetime.utcnow().isoformat()}),
                transaction_id,
                external_id
            )
            logger.info(f"Updated existing transaction {transaction_id} with status {status_value}")
        else:
            # Create new transaction record if not found
            await db.execute(
                """
                INSERT INTO payment_transactions 
                (transaction_id, external_id, amount, currency, status, payment_method, payment_details)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                transaction_id,
                external_id,
                amount,
                currency,
                status_value,
                "momo",
                json.dumps({"callback": payload, "created_at": datetime.utcnow().isoformat()})
            )
            logger.info(f"Created new transaction record for {transaction_id}")
        
        # Update order status if payment is successful
        if status_value == "SUCCESSFUL":
            try:
                # Check if there's an order with this transaction ID
                order = await db.fetchrow(
                    "SELECT order_id, user_id, order_status, total_price FROM orders WHERE transaction_id = $1",
                    external_id
                )
                
                if order:
                    order_id = order['order_id']
                    user_id = order['user_id']
                    current_status = order['order_status']
                    total_price = order['total_price']
                    
                    # Only update if order is not already completed
                    if current_status not in ['completed', 'delivered']:
                        # Only update payment_status, leave order_status unchanged
                        await db.execute(
                            """
                            UPDATE orders 
                            SET payment_status = 'completed',
                                updated_at = NOW()
                            WHERE order_id = $1
                            """,
                            order_id
                        )
                        
                        # Log the status update
                        await db.execute(
                            """
                            INSERT INTO order_status_history 
                            (order_id, status, notes, created_at)
                            VALUES ($1, $2, $3, NOW())
                            """,
                            order_id,
                            new_status,
                            f"Payment confirmed via MoMo. Transaction ID: {transaction_id}"
                        )
                        
                        logger.info(f"Updated order {order_id} status to {new_status} after successful payment")
                        
                        # Send notification to user
                        try:
                            notification_service = get_notification_service()
                            await notification_service.send_notifications(
                                user_ids=[str(user_id)],
                                notification_type='payment_successful',
                                metadata={
                                    'order_id': order_id,
                                    'amount': float(total_price),
                                    'transaction_id': transaction_id,
                                    'status': new_status,
                                    'timestamp': datetime.utcnow().isoformat()
                                }
                            )
                            logger.info(f"Sent payment success notification for order {order_id}")
                        except Exception as notif_error:
                            logger.error(f"Failed to send payment notification: {str(notif_error)}", exc_info=True)
                        
            except Exception as order_error:
                logger.error(f"Error updating order status: {str(order_error)}", exc_info=True)
        elif status_value == "FAILED":
            # Handle failed payment
            try:
                # Find the order with this transaction ID
                order = await db.fetchrow(
                    """
                    SELECT order_id, user_id, order_status, total_price, payment_status, 
                           created_at, updated_at, transaction_id, payment_method
                    FROM orders 
                    WHERE transaction_id = $1
                    """,
                    external_id
                )
                
                if order:
                    # Send failure notification
                    notification_service = get_notification_service()
                    await notification_service.send_notifications(
                        user_ids=[str(order['user_id'])],
                        notification_type='payment_failed',
                        metadata={
                            'order_id': order['order_id'],
                            'amount': float(order['total_price']),
                            'transaction_id': transaction_id,
                            'reason': payload.get('reason', 'Payment processing failed'),
                            'timestamp': datetime.utcnow().isoformat()
                        }
                    )
                    logger.info(f"Sent payment failed notification for order {order['order_id']}")
            except Exception as notif_error:
                logger.error(f"Failed to send payment failure notification: {str(notif_error)}", exc_info=True)
        
        # Return success response to MoMo
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"status": "success", "message": "Callback processed successfully"}
        )
        
    except json.JSONDecodeError as je:
        logger.error(f"Invalid JSON in MoMo callback: {str(je)}")
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content={"status": "error", "message": "Invalid JSON payload"}
        )
    except Exception as e:
        logger.error(f"Error processing MoMo callback: {str(e)}", exc_info=True)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"status": "error", "message": "Internal server error"}
        )

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

# --- Batch Price Updates ---
class BatchUpdates:
    """Handles batch update operations across different categories"""
    
    # Map category names to their respective CRUD classes and ID fields
    CATEGORY_MAP = {
        'meals': (Meals, 'meal_id', str),
        'herbals': (Herbals, 'herbal_id', int),
        'gadgets': (Gadgets, 'gadget_id', int),
        'produce': (Produce, 'produce_id', int),
        'spices': (Spices, 'spice_id', int),
        'supplements': (Supplements, 'supplement_id', int)
    }

    @classmethod
    async def batch_update_prices(cls, conn: asyncpg.Connection, category: str, updates: list[dict]) -> dict:
        """
        Update prices for multiple items in a category in a single transaction.
        
        Args:
            conn: Database connection
            category: The category name (e.g., 'meals', 'herbals')
            updates: List of dicts with 'id' and 'price' keys
            
        Returns:
            dict: Results of the batch operation
        """
        if category not in cls.CATEGORY_MAP:
            raise ValueError(f"Unsupported category: {category}")

        crud_class, id_field, id_type = cls.CATEGORY_MAP[category]
        crud = crud_class()
        results = {'success': [], 'errors': []}
        success_count = 0
        error_count = 0

        try:
            async with conn.transaction():
                for update in updates:
                    try:
                        item_id = update.get('id')
                        price = update.get('price')
                        
                        # Validate and convert ID type
                        try:
                            item_id = id_type(item_id)
                        except (ValueError, TypeError) as e:
                            results['errors'].append({
                                'id': item_id,
                                'error': f'Invalid ID type for {category}: {e}'
                            })
                            error_count += 1
                            continue

                        # Update the item with proper field name for the category
                        price_field = 'price'  # Default field name
                        if category == 'meals':
                            price_field = 'price'
                        elif category == 'herbals':
                            price_field = 'price'
                        elif category == 'gadgets':
                            price_field = 'price'
                        elif category == 'produce':
                            price_field = 'price_per_unit'  # Example: produce might use different field
                        elif category == 'spices':
                            price_field = 'price'  # Spices use 'price' field as per update_spice method
                            
                        update_data = {price_field: float(price) if price is not None else None}
                        
                        # Get the appropriate update method
                        update_method = getattr(crud, f'update_{category[:-1]}', None)
                        
                        if not update_method:
                            update_method = getattr(crud, 'update_meal', None)  # Fallback to update_meal if exists
                        
                        if not update_method:
                            raise ValueError(f"No update method found for category: {category}")
                            
                        await update_method(conn, item_id, update_data)
                        
                        results['success'].append({
                            'id': item_id,
                            'price': price
                        })
                        success_count += 1
                        
                    except Exception as e:
                        error_msg = str(e)
                        logger.error(f"Error updating {category} {item_id}: {error_msg}")
                        results['errors'].append({
                            'id': item_id,
                            'error': error_msg
                        })
                        error_count += 1

            return {
                'status': 'completed',
                'success_count': success_count,
                'error_count': error_count,
                'results': results
            }

        except Exception as e:
            logger.error(f"Batch update transaction failed: {str(e)}")
            raise

@app.patch('/rr/batch-update-prices')
async def batch_update_prices_endpoint(
    batch_data: dict = Body(..., example={
        "category": "meals",  # or 'herbals', 'gadgets', etc.
        "updates": [
            {"id": "M123", "price": 10.99},
            {"id": "M124", "price": 15.99}
        ]
    }),
    conn: asyncpg.Connection = Depends(get_db)
):
    """Endpoint for batch updating prices across different categories"""
    try:
        category = batch_data.get('category', '').lower()
        updates = batch_data.get('updates', [])
        
        if not updates:
            raise HTTPException(
                status_code=400,
                detail="No updates provided"
            )
            
        if not category or category not in BatchUpdates.CATEGORY_MAP:
            valid_categories = ", ".join(BatchUpdates.CATEGORY_MAP.keys())
            raise HTTPException(
                status_code=400,
                detail=f"Invalid category. Must be one of: {valid_categories}"
            )
        
        # Process the batch update
        result = await BatchUpdates.batch_update_prices(conn, category, updates)
        return JSONResponse(content=result)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Batch update failed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Batch update failed: {str(e)}"
        )

# --- Configuration Setup (Run before App Definition or in Lifespan) ---
# Moved configuration calls inside functions or removed if env vars are sufficient       

# --- Remove __main__ block ---
