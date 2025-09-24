#cspell:disable
from __future__ import annotations

import os
import logging
from typing import Dict, Any, Optional, AsyncGenerator, List
from contextlib import asynccontextmanager
import asyncpg
from fastapi import HTTPException, status
import bcrypt

# Get logger for this module
logger = logging.getLogger(__name__)

# Global database pool variable
db_pool: Optional[asyncpg.Pool] = None


def get_database_config() -> Dict[str, str]:
    """Get database configuration from environment variables."""
    config = {
        'host': os.getenv("DB_HOST"),
        'port': os.getenv("DB_PORT", "5432"),
        'name': os.getenv("DB_NAME", "zinzi"),
        'user': os.getenv("DB_USER"),
        'password': os.getenv("DB_PASSWORD"),
        'min_size': int(os.getenv("DB_POOL_MIN_SIZE", "2")),
        'max_size': int(os.getenv("DB_POOL_MAX_SIZE", "10"))
    }
    return config


def validate_database_config(config: Dict[str, Any]) -> List[str]:
    """Validate required database configuration variables."""
    required_vars = ['host', 'name', 'user', 'password']
    missing_vars = []
    
    for var in required_vars:
        if not config.get(var):
            missing_vars.append(f"DB_{var.upper()}")
    
    return missing_vars


async def create_database_pool() -> Optional[asyncpg.Pool]:
    """Create and return a database connection pool."""
    global db_pool
    
    logger.info("Initializing database pool...")
    
    # Get database configuration
    config = get_database_config()
    
    # Check for missing required variables
    missing_vars = validate_database_config(config)
    
    if missing_vars:
        error_msg = f"Database pool creation failed: Missing required environment variables: {', '.join(missing_vars)}."
        logger.critical(error_msg)
        return None
    
    # Use ssl=require for Render/cloud databases, adjust if needed
    db_url = f"postgresql://{config['user']}:{config['password']}@{config['host']}:{config['port']}/{config['name']}?ssl=require"
    logger.info(f"Database DSN constructed: postgresql://{config['user']}:*****@{config['host']}:{config['port']}/{config['name']}?ssl=require")
    
    try:
        # Initialize database pool
        db_pool = await asyncpg.create_pool(
            dsn=db_url,
            min_size=config['min_size'],
            max_size=config['max_size'],
            timeout=30,  # Connection acquisition timeout
            command_timeout=60,  # Default timeout for commands
            statement_cache_size=0,  # Uncomment ONLY if needed for pgbouncer transaction/statement mode
            server_settings={
                'timezone': 'Africa/Nairobi',
                'application_name': 'zinzi_backend'
            }
        )
        logger.info(f"Database connection pool created successfully (Min: {db_pool.get_min_size()}, Max: {db_pool.get_max_size()}).")
        return db_pool
    except (asyncpg.exceptions.PostgresError, OSError, Exception) as e:
        logger.critical(f"FATAL: Failed to create database pool: {e}", exc_info=True)
        return None


async def close_database_pool() -> None:
    """Close the database connection pool."""
    global db_pool
    
    if db_pool is not None:
        try:
            await db_pool.close()
            logger.info("Database pool closed")
        except Exception as e:
            logger.error(f"Error closing database pool: {e}")
        finally:
            db_pool = None


def get_database_pool() -> Optional[asyncpg.Pool]:
    """Get the current database pool."""
    return db_pool


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
        # SET TIMEZONE is now handled by the pool's `setup` parameter (init_connection)
        # Optional: Set transaction isolation level or other session settings here if needed
        # await connection.execute("SET TRANSACTION ISOLATION LEVEL READ COMMITTED")
        yield connection


# --- Consolidated BaseRepository (Takes connection as argument) ---
class BaseRepository:
    """
    Base repository class that provides common database operations.
    All repository classes should inherit from this class.
    """
    
    async def _verify_or_reset_password(self, conn, user_id: int, password: str, stored_hashed_password: str, table_name: str, id_column: str = 'id'):
        """
        Verify a password and reset it if the stored hash is invalid.
        
        Args:
            conn: Database connection
            user_id: ID of the user
            password: Plain text password to verify
            stored_hashed_password: The stored hashed password
            table_name: Name of the table containing the user
            id_column: Name of the ID column (default: 'id')
            
        Returns:
            bool: True if password is valid or was reset, False otherwise
        """
        try:
            # If no stored password, set a new one
            if not stored_hashed_password:
                logger.warning(f"No password set for {table_name} {user_id}, setting new password")
                return await self._reset_password(conn, user_id, password, table_name, id_column)
                
            # Check if stored hash is in correct bcrypt format
            if isinstance(stored_hashed_password, str):
                if stored_hashed_password.startswith('$2b$') and len(stored_hashed_password) == 60:
                    stored_hashed_pw_bytes = stored_hashed_password.encode('utf-8')
                    if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                        return True
                
                # If we get here, either the format is wrong or password doesn't match
                logger.warning(f"Invalid password hash format for {table_name} {user_id}, resetting password")
                return await self._reset_password(conn, user_id, password, table_name, id_column)
                
            elif isinstance(stored_hashed_password, bytes):
                if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_password):
                    return True
                
                # If we get here, password doesn't match
                return False
                
            # Invalid hash type
            logger.error(f"Invalid hashed_password type for {table_name} {user_id}. Type: {type(stored_hashed_password)}")
            return False
            
        except Exception as e:
            logger.error(f"Error during password verification for {table_name} {user_id}: {str(e)}")
            return False
    
    async def _reset_password(self, conn, user_id: int, new_password: str, table_name: str, id_column: str = 'id') -> bool:
        """
        Reset a user's password.
        
        Args:
            conn: Database connection
            user_id: ID of the user
            new_password: New plain text password
            table_name: Name of the table containing the user
            id_column: Name of the ID column (default: 'id')
            
        Returns:
            bool: True if password was reset successfully, False otherwise
        """
        try:
            new_hash = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt())
            update_sql = f"UPDATE {table_name} SET hashed_password = $1 WHERE {id_column} = $2"
            await self._execute_query(conn, update_sql, (new_hash.decode('utf-8'), user_id))
            logger.info(f"Successfully reset password for {table_name} {user_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to reset password for {table_name} {user_id}: {str(e)}")
            return False

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
            
            logger.error(f"Database error: {error_context}")
            
            # Map specific PostgreSQL errors to appropriate HTTP status codes
            if error_code in ['23505']:  # unique_violation
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="A record with the same unique value already exists."
                ) from e
            elif error_code in ['23503']:  # foreign_key_violation
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid reference to related data."
                ) from e
            elif error_code in ['23502']:  # not_null_violation
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Required field cannot be empty."
                ) from e
            elif error_code in ['42601', '42804']:  # syntax_error, datatype_mismatch
                logger.critical(f"SQL syntax or datatype error - this should not happen in production: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Internal server error occurred."
                ) from e
            else:
                # Generic database error
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Database service temporarily unavailable. Please try again later."
                ) from e
                
        except Exception as e:
            logger.error(f"Unexpected error during database operation: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="An unexpected error occurred while processing your request."
            ) from e
