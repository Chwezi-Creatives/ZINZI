import psycopg2 # Replaced pyodbc
from datetime import datetime, date # Added date for type checking
import uuid # For MoMo X-Reference-Id
import random # For generating random numbers

# Assuming database.py is in the same directory or Python path
# and contains the get_db_connection function configured for PgBouncer
from database import get_db_connection
import logging
import bcrypt
import json # For potential future use with JSONB columns if needed

# --- Configuration Loading ---
from dotenv import load_dotenv # Moved import to top
load_dotenv()

# Configure logging for error reporting
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Helper Functions (Unchanged, assuming they are correct) ---
def check_required_fields(data, required_fields):
    """Checks if all required fields are present in the data dictionary."""
    data_keys_lower = {k.lower() for k in data.keys()}
    missing_fields = [field for field in required_fields if field.lower() not in data_keys_lower or not data.get(field)]
    if missing_fields:
        raise ValueError(f"Missing required fields: {', '.join(missing_fields)}")

def serialize_list(data_list):
    """Serializes a list into a comma-separated string."""
    return ','.join(map(str, data_list)) if isinstance(data_list, list) else ''

def deserialize_list(data_string):
    """Deserializes a comma-separated string into a list."""
    return data_string.split(',') if data_string else []
# --- End Helper Functions ---

# --- Base Class for Common DB Operations ---
class BaseRepository:
    def _execute_query(self, sql, params=None, fetch_one=False, fetch_all=False, commit=False, returning_id_column=None):
        """Executes a query, handles connection and cursor management.
           returning_id_column specifies the name of the ID column to return.
        """
        conn = None
        results = None
        returned_id = None
        try:
            conn = get_db_connection()
            if not conn:
                raise ConnectionError("Failed to get database connection.")

            # Use context manager for cursor
            with conn.cursor() as cursor:
                logger.debug(f"Executing SQL: {sql} with params: {params}")
                cursor.execute(sql, params or ())

                if returning_id_column: # Check if we expect an ID back
                    fetched = cursor.fetchone()
                    if fetched:
                        returned_id = fetched[0] # Get the actual ID value
                    logger.debug(f"Returning {returning_id_column}: {returned_id}")

                elif fetch_one: # Only fetch if not returning an ID
                    results = cursor.fetchone()
                    # If fetchone returns data, maybe convert to dict?
                    if results and cursor.description:
                         columns = [desc[0] for desc in cursor.description]
                         results = dict(zip(columns, results))
                    logger.debug(f"Fetched one: {results}")

                elif fetch_all: # Only fetch if not returning an ID
                    # Fetch column names for dict conversion
                    if cursor.description:
                         columns = [desc[0] for desc in cursor.description]
                         results = [dict(zip(columns, row)) for row in cursor.fetchall()]
                    else:
                         results = [] # Handle cases like empty results
                    logger.debug(f"Fetched all ({len(results)} rows)")

                if commit:
                    conn.commit()
                    logger.debug("Transaction committed.")

            # Return based on what was requested
            if returning_id_column:
                return returned_id
            else:
                return results

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Database Error executing query: {sql} | Params: {params} | Error: {e}", exc_info=True)
            if conn:
                try:
                    conn.rollback() # Rollback on error
                    logger.debug("Transaction rolled back due to error.")
                except psycopg2.Error as rb_err:
                    logger.error(f"Error during rollback: {rb_err}")
            # Re-raise a more specific or generic error for the caller
            raise ValueError(f"Database operation failed: {e}")
        finally:
            if conn:
                conn.close() # IMPORTANT: Release connection back to the pool
                logger.debug("Database connection closed.")

# --- CRUD operations for Users ---
class Users(BaseRepository):

    def hash_password(self, password):
        """Hashes a password using bcrypt."""
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def create_user(self, user_data):
        """Creates a new user in the database."""
        user_data_lower = {k.lower(): v for k, v in user_data.items()}
        check_required_fields(user_data_lower, ['name', 'password', 'email'])

        email = user_data_lower['email']
        # 1. Check if email exists
        # user_id is correct
        check_sql = "SELECT user_id FROM users WHERE lower(email) = lower(%s)"
        existing_user = self._execute_query(check_sql, (email,), fetch_one=True)

        if existing_user:
            raise ValueError(f"A user with email '{email}' already exists.")

        # 2. Insert new user
        hashed_password = self.hash_password(user_data_lower['password'])
        user_type = user_data_lower.get('user_type', 'user')
        is_email_verified = user_data_lower.get('is_email_verified', False) # Use boolean
        is_active = user_data_lower.get('is_active', True) # Use boolean
        added_by = user_data_lower.get('added_by', 0) # Assuming 0 or None indicates self-registration

        sql = """
            INSERT INTO users (name, email, hashed_password, is_email_verified, user_type, is_active,
            rating, phone_number, registration_date, location, added_by, added_by_type, last_login)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, NOW())
            RETURNING user_id
        """
        params = (
            user_data_lower['name'], email, hashed_password,
            is_email_verified, user_type, is_active,
            user_data_lower.get('rating', 0.0), # Use float for rating
            user_data_lower.get('phone_number'),
            user_data_lower.get('location'),
            added_by,
            user_data_lower.get('added_by_type', user_type) # Default to own type
        )
        # user_id is correct
        user_id = self._execute_query(sql, params, commit=True, returning_id_column='user_id')

        if user_id:
            logger.info(f"Created user with ID: {user_id}, Email: {email}, User Type: {user_type}")
            return {"UserId": user_id, "UserType": user_type}
        else:
            raise ValueError("User creation failed, no ID returned.")


    def list_users(self, user_id=None):
        """Lists users, optionally filtered by user_id."""
        sql = "SELECT * FROM users"
        params = []
        if user_id:
            # user_id is correct
            sql += " WHERE user_id = %s"
            params.append(user_id)

        users_list = self._execute_query(sql, params, fetch_all=True)
        if user_id and not users_list:
             logger.warning(f"No user found with ID: {user_id}")
             return None
        return users_list


    def login_user(self, identifier, password):
        """Authenticates a user by name or email."""
        sql = """
            SELECT user_id, hashed_password, user_type, is_email_verified -- Added verification check
            FROM users
            WHERE lower(name) = lower(%s) OR lower(email) = lower(%s) -- Case-insensitive
        """
        params = (identifier, identifier)

        result_dict = self._execute_query(sql, params, fetch_all=True) # fetch_all returns list of dicts
        result = result_dict[0] if result_dict else None # Get the first dict if exists

        if not result:
            logger.warning(f"Login attempt failed: Identifier '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401

        # Access by key from the dictionary
        user_id = result['user_id'] # user_id is correct
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']
        is_verified = result['is_email_verified'] # Check verification status


        # Ensure stored_hashed_password is bytes for bcrypt
        if isinstance(stored_hashed_password, str):
            stored_hashed_password_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
             stored_hashed_password_bytes = stored_hashed_password
        else:
             logger.error(f"Unexpected password hash type for user {user_id}: {type(stored_hashed_password)}")
             return {'message': 'Internal server error during login.'}, 500


        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_password_bytes):
            if not is_verified:
                 logger.warning(f"Login attempt for user ID {user_id}: Account not verified.")
                 return {'message': 'Account not verified. Please check your email.', 'user_id': user_id, 'verified': False}, 403

            # update_sql = "UPDATE users SET last_login = NOW() WHERE user_id = %s"
            # self._execute_query(update_sql, (user_id,), commit=True)
            logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
            # Return user_id which is correct
            return {'message': 'Login successful', 'user_id': user_id, 'user_type': user_type, 'verified': True}, 200
        else:
            logger.warning(f"Login attempt failed: Invalid password for identifier '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401

    # --- Metrics Methods ---
    def create_metric(self, metric_data):
        metric_data_lower = {k.lower(): v for k, v in metric_data.items()}
        check_required_fields(metric_data_lower, ['user_id', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse'])
        sql = """
            INSERT INTO user_metrics (user_id, age_range, weight, height, cholesterol_level,
            sys_bp, dia_bp, pulse, recorded_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW())
            RETURNING metric_id
        """
        params = (
            metric_data_lower['user_id'], metric_data_lower.get('age_range'), metric_data_lower['weight'],
            metric_data_lower['height'], metric_data_lower['cholesterol_level'], metric_data_lower['sys_bp'],
            metric_data_lower['dia_bp'], metric_data_lower['pulse']
        )
        # Corrected: metricid -> metric_id
        metric_id = self._execute_query(sql, params, commit=True, returning_id_column='metric_id')
        logger.info(f"Created metric with ID: {metric_id} for User ID: {metric_data_lower['user_id']}")
        # Corrected: MetricId -> metric_id (consistent key name)
        return {"metric_id": metric_id}

    def update_metric(self, metric_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # Corrected: WHERE metricid -> WHERE metric_id
        sql = f"UPDATE user_metrics SET {', '.join(set_clauses)} WHERE metric_id = %s"
        params = list(updates_lower.values()) + [metric_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated metric with ID: {metric_id}")


    def list_metrics(self, user_id=None):
        sql = "SELECT * FROM user_metrics"
        params = []
        if user_id:
            # user_id is correct
            sql += " WHERE user_id = %s"
            params.append(user_id)
        return self._execute_query(sql, params, fetch_all=True)

    # --- Metric History Methods ---
    def create_metric_history(self, metric_history_data):
        metric_history_data_lower = {k.lower(): v for k, v in metric_history_data.items()}
        check_required_fields(metric_history_data_lower, ['user_id', 'weight'])
        sql = """
            INSERT INTO metrics_history (user_id, weight, logged_at) VALUES (%s, %s, NOW())
            RETURNING log_id
        """
        params = (metric_history_data_lower['user_id'], metric_history_data_lower['weight'])
        # Corrected: logid -> log_id
        log_id = self._execute_query(sql, params, commit=True, returning_id_column='log_id')
        logger.info(f"Created metric history with Log ID: {log_id} for User ID: {metric_history_data_lower['user_id']}")
        # Corrected: MetricHistoryId -> log_id
        return {"log_id": log_id}

    def update_metric_history(self, log_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # Corrected: WHERE logid -> WHERE log_id
        sql = f"UPDATE metrics_history SET {', '.join(set_clauses)} WHERE log_id = %s"
        params = list(updates_lower.values()) + [log_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated metric history with Log ID: {log_id}")

    def list_metric_history(self, user_id=None):
        sql = "SELECT * FROM metrics_history"
        params = []
        if user_id:
            # user_id correct
            sql += " WHERE user_id = %s"
            params.append(user_id)
        return self._execute_query(sql, params, fetch_all=True)

    # --- Preferences Methods ---
    def create_preference(self, preference_data):
        preference_data_lower = {k.lower(): v for k, v in preference_data.items()}
        check_required_fields(preference_data_lower, ['user_id', 'goals', 'diet_type'])
        sql = """
            INSERT INTO user_preferences (user_id, goals, diet_type, food_restrictions, cuisine_preferences)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING preference_id
        """
        params = (
            preference_data_lower['user_id'], preference_data_lower['goals'],
            preference_data_lower['diet_type'], preference_data_lower.get('food_restrictions'),
            preference_data_lower.get('cuisine_preferences')
        )
        # Corrected: preferenceid -> preference_id
        preference_id = self._execute_query(sql, params, commit=True, returning_id_column='preference_id')
        logger.info(f"Created preference with ID: {preference_id} for User ID: {preference_data_lower['user_id']}")
        # Corrected: PreferenceId -> preference_id
        return {"preference_id": preference_id}

    def update_preference(self, preference_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # Corrected: WHERE preferenceid -> WHERE preference_id
        sql = f"UPDATE user_preferences SET {', '.join(set_clauses)} WHERE preference_id = %s"
        params = list(updates_lower.values()) + [preference_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated preference with ID: {preference_id}")

    def list_preferences(self, user_id=None):
        sql = "SELECT * FROM user_preferences"
        params = []
        if user_id:
            # user_id correct
            sql += " WHERE user_id = %s"
            params.append(user_id)
        return self._execute_query(sql, params, fetch_all=True)


# --- CRUD operations for Chefs ---
class Chefs(BaseRepository):
    def hash_password(self, password):
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def create_chef(self, chef_data):
        chef_data_lower = {k.lower(): v for k, v in chef_data.items()}
        check_required_fields(chef_data_lower, ['name', 'password', 'email'])

        email = chef_data_lower['email']
        # chefid is correct (as per user instruction)
        check_sql = "SELECT chefid FROM chefs WHERE lower(email) = lower(%s)"
        existing_chef = self._execute_query(check_sql, (email,), fetch_one=True)
        if existing_chef:
            raise ValueError(f"A chef with email '{email}' already exists.")

        equipment = serialize_list(chef_data_lower.get('equipment', []))
        availability = serialize_list(chef_data_lower.get('availability', []))
        languages = serialize_list(chef_data_lower.get('languages', []))
        specialties = serialize_list(chef_data_lower.get('specialties', []))
        certifications = serialize_list(chef_data_lower.get('certifications', []))

        hashed_password = self.hash_password(chef_data_lower['password'])
        user_type = chef_data_lower.get('user_type', 'chef')
        is_email_verified = chef_data_lower.get('is_email_verified', False)
        is_active = chef_data_lower.get('is_active', True)
        added_by = chef_data_lower.get('added_by', 0)

        sql = """
            INSERT INTO chefs (name, image, email, hashed_password, is_email_verified, user_type,
            chef_type, is_active, rating, price, phone_number, experience, serviceradius,
            responsetime, minnotice, punctuality, teamsize, equipment, bio, availability,
            languages, specialties, certifications, samplemenu, reviews,
            registration_date, location, added_by, added_by_type, last_login)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, NOW())
            RETURNING chefid
        """
        params = (
            chef_data_lower['name'], chef_data_lower.get('image'), email,
            hashed_password, is_email_verified, user_type,
            chef_data_lower.get('chef_type', 'Individual'), is_active,
            chef_data_lower.get('rating', 0.0), chef_data_lower.get('price'), chef_data_lower.get('phone_number'),
            chef_data_lower.get('experience'), chef_data_lower.get('serviceradius'),
            chef_data_lower.get('responsetime'), chef_data_lower.get('minnotice'),
            chef_data_lower.get('punctuality', 0.0), chef_data_lower.get('teamsize'), equipment,
            chef_data_lower.get('bio'), availability, languages, specialties, certifications,
            chef_data_lower.get('samplemenu'), chef_data_lower.get('reviews'),
            chef_data_lower.get('location'), added_by,
            chef_data_lower.get('added_by_type', user_type)
        )
        # chefid is correct
        chef_id = self._execute_query(sql, params, commit=True, returning_id_column='chefid')
        if chef_id:
            logger.info(f"Created chef with ID: {chef_id}, Email: {email}, User Type: {user_type}")
            # ChefID key correct
            return {"ChefID": chef_id, "UserType": user_type}
        else:
            raise ValueError("Chef creation failed, no ID returned.")


    def list_chefs(self, chef_id=None):
        sql = "SELECT * FROM chefs"
        params = []
        if chef_id is not None:
            # chefid is correct
            sql += " WHERE chefid = %s"
            params.append(chef_id)

        chefs_list = self._execute_query(sql, params, fetch_all=True)
        if chef_id and not chefs_list:
             logger.warning(f"No chef found with ID: {chef_id}")
             return None
        return chefs_list


    def update_chef(self, chef_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        for key in ['equipment', 'availability', 'languages', 'specialties', 'certifications']:
             if key in updates_lower and isinstance(updates_lower[key], list):
                 updates_lower[key] = serialize_list(updates_lower[key])

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # chefid is correct
        sql = f"UPDATE chefs SET {', '.join(set_clauses)} WHERE chefid = %s"
        params = list(updates_lower.values()) + [chef_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated chef with ID: {chef_id}")


    def login_chef(self, identifier, password):
        sql = """
            SELECT chefid, hashed_password, user_type
            FROM chefs
            WHERE lower(name) = lower(%s) OR lower(email) = lower(%s) -- Case-insensitive
        """
        params = (identifier, identifier)
        result_dict = self._execute_query(sql, params, fetch_all=True) # fetch_all returns list of dicts
        result = result_dict[0] if result_dict else None # Get the first dict if exists

        if not result:
            logger.warning(f"Chef login attempt failed: Identifier '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401

        # chefid is correct
        chef_id = result['chefid']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']

        if isinstance(stored_hashed_password, str):
             stored_hashed_password_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
             stored_hashed_password_bytes = stored_hashed_password
        else:
            logger.error(f"Unexpected password hash type for chef {chef_id}: {type(stored_hashed_password)}")
            return {'message': 'Internal server error during login.'}, 500

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_password_bytes):
            logger.info(f"Chef login successful for identifier '{identifier}', Chef ID: {chef_id}")
            # chef_id is correct
            return {'message': 'Login successful', 'chef_id': chef_id, 'user_type': user_type}, 200
        else:
            logger.warning(f"Chef login attempt failed: Invalid password for identifier '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401

# --- CRUD operations for Producers ---
class Producers(BaseRepository):
    def hash_password(self, password):
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def create_producer(self, producer_data):
        producer_data_lower = {k.lower(): v for k, v in producer_data.items()}
        check_required_fields(producer_data_lower, ['name', 'password', 'email'])

        email = producer_data_lower['email']
        # Corrected: producerid -> producer_id
        check_sql = "SELECT producer_id FROM producers WHERE lower(email) = lower(%s)"
        existing_producer = self._execute_query(check_sql, (email,), fetch_one=True)
        if existing_producer:
            raise ValueError(f"A producer with email '{email}' already exists.")

        hashed_password = self.hash_password(producer_data_lower['password'])
        user_type = producer_data_lower.get('user_type', 'producer')
        is_email_verified = producer_data_lower.get('is_email_verified', False)
        is_active = producer_data_lower.get('is_active', True)
        added_by = producer_data_lower.get('added_by', 0)

        sql = """
            INSERT INTO producers (name, image, email, hashed_password, is_email_verified, user_type,
            producer_type, is_active, rating, phone_number, registration_date,
            location, added_by, added_by_type, last_login)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, NOW())
            RETURNING producer_id
        """
        params = (
            producer_data_lower['name'], producer_data_lower.get('image'), email,
            hashed_password, is_email_verified, user_type,
            producer_data_lower.get('producer_type', 'Individual'), is_active,
            producer_data_lower.get('rating', 0.0), producer_data_lower.get('phone_number'),
            producer_data_lower.get('location'), added_by,
            producer_data_lower.get('added_by_type', user_type)
        )
        # Corrected: producerid -> producer_id
        producer_id = self._execute_query(sql, params, commit=True, returning_id_column='producer_id')
        if producer_id:
            logger.info(f"Created producer with ID: {producer_id}, Email: {email}, User Type: {user_type}")
            # Corrected: ProducerID -> producer_id
            return {"producer_id": producer_id, "UserType": user_type}
        else:
            raise ValueError("Producer creation failed, no ID returned.")


    def list_producers(self, producer_id=None):
        sql = "SELECT * FROM producers"
        params = []
        if producer_id:
            # Corrected: producerid -> producer_id
            sql += " WHERE producer_id = %s"
            params.append(producer_id)

        producers_list = self._execute_query(sql, params, fetch_all=True)
        if producer_id and not producers_list:
             logger.warning(f"No producer found with ID: {producer_id}")
             return None
        return producers_list


    def update_producer(self, producer_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # Corrected: WHERE producerid -> WHERE producer_id
        sql = f"UPDATE producers SET {', '.join(set_clauses)} WHERE producer_id = %s"
        params = list(updates_lower.values()) + [producer_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated producer with ID: {producer_id}")


    def login_producer(self, identifier, password):
        sql = """
            SELECT producer_id, hashed_password, user_type
            FROM producers
            WHERE lower(name) = lower(%s) OR lower(email) = lower(%s) -- Case-insensitive
        """
        params = (identifier, identifier)
        result_dict = self._execute_query(sql, params, fetch_all=True)
        result = result_dict[0] if result_dict else None

        if not result:
            logger.warning(f"Producer login attempt failed: Identifier '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401

        # Corrected: producerid -> producer_id
        producer_id = result['producer_id']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']

        if isinstance(stored_hashed_password, str):
             stored_hashed_password_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
             stored_hashed_password_bytes = stored_hashed_password
        else:
            logger.error(f"Unexpected password hash type for producer {producer_id}: {type(stored_hashed_password)}")
            return {'message': 'Internal server error during login.'}, 500


        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_password_bytes):
            logger.info(f"Producer login successful for identifier '{identifier}', Producer ID: {producer_id}")
            # Corrected: producer_id key
            return {'message': 'Login successful', 'producer_id': producer_id, 'user_type': user_type}, 200
        else:
            logger.warning(f"Producer login attempt failed: Invalid password for identifier '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401


# --- CRUD operations for Stakeholders ---
class Stakeholders(BaseRepository):
    def hash_password(self, password):
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    def create_stakeholder(self, stakeholder_data):
        stakeholder_data_lower = {k.lower(): v for k, v in stakeholder_data.items()}
        check_required_fields(stakeholder_data_lower, ['name', 'password', 'email', 'full_name'])

        email = stakeholder_data_lower['email']
        # Corrected: stakeholderid -> stakeholder_id
        check_sql = "SELECT stakeholder_id FROM stakeholders WHERE lower(email) = lower(%s)"
        existing_stakeholder = self._execute_query(check_sql, (email,), fetch_one=True)
        if existing_stakeholder:
            raise ValueError(f"A stakeholder with email '{email}' already exists.")

        hashed_password = self.hash_password(stakeholder_data_lower['password'])
        user_type = stakeholder_data_lower.get('user_type', 'stakeholder')
        is_email_verified = stakeholder_data_lower.get('is_email_verified', False)
        is_active = stakeholder_data_lower.get('is_active', True)
        added_by = stakeholder_data_lower.get('added_by', 0)

        sql = """
            INSERT INTO stakeholders (name, full_name, image, email, hashed_password,
            is_email_verified, user_type, is_active, rating, phone_number,
            registration_date, location, added_by, added_by_type, last_login)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s, NOW())
            RETURNING stakeholder_id
        """
        params = (
            stakeholder_data_lower['name'], stakeholder_data_lower['full_name'], stakeholder_data_lower.get('image'),
            email, hashed_password, is_email_verified,
            user_type, is_active, stakeholder_data_lower.get('rating', 0.0),
            stakeholder_data_lower.get('phone_number'), stakeholder_data_lower.get('location'),
            added_by, stakeholder_data_lower.get('added_by_type', user_type)
        )
        # Corrected: stakeholderid -> stakeholder_id
        stakeholder_id = self._execute_query(sql, params, commit=True, returning_id_column='stakeholder_id')
        if stakeholder_id:
            logger.info(f"Created stakeholder with ID: {stakeholder_id}, Email: {email}, User Type: {user_type}")
            # Corrected: StakeholderID -> stakeholder_id
            return {"stakeholder_id": stakeholder_id, "UserType": user_type}
        else:
            raise ValueError("Stakeholder creation failed, no ID returned.")


    def list_stakeholders(self):
        sql = "SELECT * FROM stakeholders"
        return self._execute_query(sql, fetch_all=True)

    def get_stakeholder_by_id(self, stakeholder_id):
         # Corrected: stakeholderid -> stakeholder_id
         sql = "SELECT * FROM stakeholders WHERE stakeholder_id = %s"
         result = self._execute_query(sql, (stakeholder_id,), fetch_all=True)
         return result[0] if result else None


    def update_stakeholder(self, stakeholder_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower:
            raise ValueError("At least one field must be provided for updates.")

        set_clauses = [f"{key} = %s" for key in updates_lower.keys()]
        # Corrected: WHERE stakeholderid -> WHERE stakeholder_id
        sql = f"UPDATE stakeholders SET {', '.join(set_clauses)} WHERE stakeholder_id = %s"
        params = list(updates_lower.values()) + [stakeholder_id]

        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated stakeholder with ID: {stakeholder_id}")


    def login_stakeholder(self, identifier, password):
        sql = """
            SELECT stakeholder_id, hashed_password, user_type
            FROM stakeholders
            WHERE lower(name) = lower(%s) OR lower(email) = lower(%s) -- Case-insensitive
        """
        params = (identifier, identifier)
        result_dict = self._execute_query(sql, params, fetch_all=True)
        result = result_dict[0] if result_dict else None

        if not result:
            logger.warning(f"Stakeholder login attempt failed: Identifier '{identifier}' not found.")
            return {'message': 'Invalid credentials or account not found.'}, 401

        # Corrected: stakeholderid -> stakeholder_id
        stakeholder_id = result['stakeholder_id']
        stored_hashed_password = result['hashed_password']
        user_type = result['user_type']

        if isinstance(stored_hashed_password, str):
             stored_hashed_password_bytes = stored_hashed_password.encode('utf-8')
        elif isinstance(stored_hashed_password, bytes):
             stored_hashed_password_bytes = stored_hashed_password
        else:
            logger.error(f"Unexpected password hash type for stakeholder {stakeholder_id}: {type(stored_hashed_password)}")
            return {'message': 'Internal server error during login.'}, 500

        if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_password_bytes):
            logger.info(f"Stakeholder login successful for identifier '{identifier}', Stakeholder ID: {stakeholder_id}")
            # Corrected: stakeholder_id key
            return {'message': 'Login successful', 'stakeholder_id': stakeholder_id, 'user_type': user_type}, 200
        else:
            logger.warning(f"Stakeholder login attempt failed: Invalid password for identifier '{identifier}'.")
            return {'message': 'Invalid credentials.'}, 401

# --- CRUD operations for Herbals ---
class Herbals(BaseRepository):
    def create_herbal(self, herbal_data):
        herbal_data_lower = {k.lower(): v for k, v in herbal_data.items()}
        check_required_fields(herbal_data_lower, ['herbal_name', 'description', 'unit', 'price'])
        user_type = herbal_data_lower.get('user_type', 'herbal')
        sql = """
            INSERT INTO herbals (herbal_name, description, unit, price, image_url, date_added,
            added_by, added_by_type, user_type)
            VALUES (%s, %s, %s, %s, %s, NOW(), %s, %s, %s)
            RETURNING herbal_id -- Corrected: herbalid -> herbal_id
        """
        params = (
            herbal_data_lower['herbal_name'], herbal_data_lower['description'], herbal_data_lower['unit'],
            herbal_data_lower['price'], herbal_data_lower.get('image_url'),
            herbal_data_lower.get('added_by'), herbal_data_lower.get('added_by_type', user_type), user_type
        )
        herbal_id = self._execute_query(sql, params, commit=True, returning_id_column='herbal_id')
        logger.info(f"Created herbal with ID: {herbal_id}")
        # Corrected: HerbalID -> herbal_id
        return {"herbal_id": herbal_id, "UserType": user_type}

    def update_herbal(self, herbal_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = [f"{k} = %s" for k in updates_lower.keys()]
        sql = f"UPDATE herbals SET {', '.join(set_clauses)} WHERE herbal_id = %s"
        params = list(updates_lower.values()) + [herbal_id]
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated herbal ID: {herbal_id}")

    def list_herbals(self):
        sql = "SELECT * FROM herbals"
        return self._execute_query(sql, fetch_all=True)

# --- CRUD operations for Meals ---
class Meals(BaseRepository):
     def create_meal(self, meal_data):
        meal_data_lower = {k.lower(): v for k, v in meal_data.items()}
        check_required_fields(meal_data_lower, ['meal_name', 'meal_category', 'ingredients'])
        user_type = meal_data_lower.get('user_type', 'meal')
        sql = """
            INSERT INTO meals (meal_name, meal_category, ingredients,
            complementary_dishes, recipe, recipe_link, image_link,
            goal, dietary_preference, allergies, disease_management,
            cuisine_preferences, skill_level, prep_time, meal_description,
            date_added, date_last_edited, added_by, added_by_type, user_type)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), %s, %s, %s)
            RETURNING meal_id -- Corrected: mealid -> meal_id
        """
        params = (
            meal_data_lower['meal_name'], meal_data_lower['meal_category'], meal_data_lower['ingredients'],
            meal_data_lower.get('complementary_dishes'), meal_data_lower.get('recipe'), meal_data_lower.get('recipe_link'),
            meal_data_lower.get('image_link'), meal_data_lower.get('goal'), meal_data_lower.get('dietary_preference'),
            meal_data_lower.get('allergies'), meal_data_lower.get('disease_management'),
            meal_data_lower.get('cuisine_preferences'), meal_data_lower.get('skill_level'),
            meal_data_lower.get('prep_time'), meal_data_lower.get('meal_description'),
            meal_data_lower.get('added_by'), meal_data_lower.get('added_by_type', user_type), user_type
        )
        meal_id = self._execute_query(sql, params, commit=True, returning_id_column='meal_id')
        logger.info(f"Created meal with ID: {meal_id}")
        # Corrected: MealID -> meal_id
        return {"meal_id": meal_id, "UserType": user_type}

     def update_meal(self, meal_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower: raise ValueError("No updates provided.")
        updates_lower['date_last_edited'] = datetime.now()
        set_clauses = [f"{k} = %s" for k in updates_lower.keys()]
        sql = f"UPDATE meals SET {', '.join(set_clauses)} WHERE meal_id = %s"
        params = list(updates_lower.values()) + [meal_id]
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated meal ID: {meal_id}")

     def list_meals(self):
        sql = "SELECT * FROM meals"
        return self._execute_query(sql, fetch_all=True)

# --- CRUD operations for Produce ---
class Produce(BaseRepository):
    def create_produce(self, produce_data):
        produce_data_lower = {k.lower(): v for k, v in produce_data.items()}
        check_required_fields(produce_data_lower, ['produce_name', 'unit_grams', 'calories'])
        user_type = produce_data_lower.get('user_type', 'produce')
        sql = """
            INSERT INTO produce (produce_name, unit_grams, calories, cholesterol,
            carbohydrates, proteins, fats, fiber, sugars, meal_type,
            source, nutritional_info, date_added, date_last_edited,
            added_by, added_by_type, user_type)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), %s, %s, %s)
            RETURNING produce_id -- Corrected: produceid -> produce_id
        """
        params = (
            produce_data_lower['produce_name'], produce_data_lower['unit_grams'], produce_data_lower['calories'],
            produce_data_lower.get('cholesterol'), produce_data_lower.get('carbohydrates'),
            produce_data_lower.get('proteins'), produce_data_lower.get('fats'),
            produce_data_lower.get('fiber'), produce_data_lower.get('sugars'),
            produce_data_lower.get('meal_type'), produce_data_lower.get('source'),
            produce_data_lower.get('nutritional_info'),
            produce_data_lower.get('added_by'), produce_data_lower.get('added_by_type', user_type), user_type
        )
        produce_id = self._execute_query(sql, params, commit=True, returning_id_column='produce_id')
        logger.info(f"Created produce with ID: {produce_id}")
        # Corrected: ProduceID -> produce_id
        return {"produce_id": produce_id, "UserType": user_type}

    def update_produce(self, produce_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower: raise ValueError("No updates provided.")
        updates_lower['date_last_edited'] = datetime.now()
        set_clauses = [f"{k} = %s" for k in updates_lower.keys()]
        sql = f"UPDATE produce SET {', '.join(set_clauses)} WHERE produce_id = %s"
        params = list(updates_lower.values()) + [produce_id]
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated produce ID: {produce_id}")

    def list_produce(self):
        sql = "SELECT * FROM produce"
        return self._execute_query(sql, fetch_all=True)

# --- CRUD operations for Gadgets ---
class Gadgets(BaseRepository):
    def create_gadget(self, gadget_data):
        gadget_data_lower = {k.lower(): v for k, v in gadget_data.items()}
        check_required_fields(gadget_data_lower, ['gadget_name', 'description', 'price'])
        user_type = gadget_data_lower.get('user_type', 'gadget')
        sql = """
            INSERT INTO gadgets (gadget_name, description, brand, model,
            price, image_url, date_added, added_by, added_by_type, user_type)
            VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s)
            RETURNING gadget_id -- Corrected: gadgetid -> gadget_id
        """
        params = (
            gadget_data_lower['gadget_name'], gadget_data_lower['description'],
            gadget_data_lower.get('brand'), gadget_data_lower.get('model'),
            gadget_data_lower['price'], gadget_data_lower.get('image_url'),
            gadget_data_lower.get('added_by'), gadget_data_lower.get('added_by_type', user_type), user_type
        )
        gadget_id = self._execute_query(sql, params, commit=True, returning_id_column='gadget_id')
        logger.info(f"Created gadget with ID: {gadget_id}")
        # Corrected: GadgetID -> gadget_id
        return {"gadget_id": gadget_id, "UserType": user_type}

    def update_gadget(self, gadget_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = [f"{k} = %s" for k in updates_lower.keys()]
        sql = f"UPDATE gadgets SET {', '.join(set_clauses)} WHERE gadget_id = %s"
        params = list(updates_lower.values()) + [gadget_id]
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated gadget ID: {gadget_id}")

    def list_gadgets(self):
        sql = "SELECT * FROM gadgets"
        return self._execute_query(sql, fetch_all=True)

# --- CRUD operations for Spices ---
class Spices(BaseRepository):
    def create_spice(self, spice_data):
        spice_data_lower = {k.lower(): v for k, v in spice_data.items()}
        check_required_fields(spice_data_lower, ['spice_name', 'description', 'price', 'added_by'])
        user_type = spice_data_lower.get('user_type', 'spice')
        sql = """
            INSERT INTO spices (spice_name, description, unit, price,
            image_url, date_added, added_by, added_by_type, user_type)
            VALUES (%s, %s, %s, %s, %s, NOW(), %s, %s, %s)
            RETURNING spice_id -- Corrected: spiceid -> spice_id
        """
        params = (
            spice_data_lower['spice_name'], spice_data_lower['description'],
            spice_data_lower.get('unit'), spice_data_lower['price'],
            spice_data_lower.get('image_url'),
            spice_data_lower['added_by'], spice_data_lower.get('added_by_type', user_type), user_type
        )
        spice_id = self._execute_query(sql, params, commit=True, returning_id_column='spice_id')
        logger.info(f"Created spice with ID: {spice_id}")
        # Corrected: SpiceID -> spice_id
        return {"spice_id": spice_id, "UserType": user_type}

    def update_spice(self, spice_id, updates):
        updates_lower = {k.lower(): v for k, v in updates.items()}
        if not updates_lower: raise ValueError("No updates provided.")
        set_clauses = [f"{k} = %s" for k in updates_lower.keys()]
        sql = f"UPDATE spices SET {', '.join(set_clauses)} WHERE spice_id = %s"
        params = list(updates_lower.values()) + [spice_id]
        self._execute_query(sql, tuple(params), commit=True)
        logger.info(f"Updated spice ID: {spice_id}")

    def list_spices(self):
        sql = "SELECT * FROM spices"
        return self._execute_query(sql, fetch_all=True)

# --- CRUD operations for Orders ---
class Orders(BaseRepository):
    ALLOWED_ORDER_TYPES = {'supplement', 'herbal', 'gadget', 'spice', 'produce', 'meal'}
    ALLOWED_ORDER_STATUSES = {'cancelled', 'delivered', 'shipped', 'preparing', 'confirmed', 'pending'}
    ALLOWED_PAYMENT_STATUSES = {'failed', 'refunded', 'paid', 'pending'}
    ALLOWED_PAYMENT_MODES = {'cash', 'momo', 'mobile money', 'Airtel Card', 'paypal', 'stripe', 'debit card', 'credit card'}

    def create_order(self, user_id, order_type, product_id=None, chef_id=None, producer_id=None,
                     delivery_address=None, order_status="Pending", total_price=0.0,
                     notes=None, payment_status="Pending", payment_mode="cash",
                     amount_paid=0.0, transaction_id=None, quantity=1):

        order_type = str(order_type).lower()
        order_status = str(order_status).lower()
        payment_status = str(payment_status).lower()
        payment_mode = str(payment_mode).lower() if payment_mode else "cash"

        if not user_id: raise ValueError("user_id is required")
        if not order_type: raise ValueError("order_type is required")
        if order_type not in self.ALLOWED_ORDER_TYPES: raise ValueError(f"Invalid order_type: {order_type}")
        if order_status not in self.ALLOWED_ORDER_STATUSES: raise ValueError(f"Invalid order_status: {order_status}")
        if payment_status not in self.ALLOWED_PAYMENT_STATUSES: raise ValueError(f"Invalid payment_status: {payment_status}")
        if payment_mode not in self.ALLOWED_PAYMENT_MODES: raise ValueError(f"Invalid payment_mode: {payment_mode}")

        delivery_address = delivery_address or "Not specified"
        notes = notes or "No special instructions"

        try:
             total_price = float(total_price)
             amount_paid = float(amount_paid)
             quantity = int(quantity)
             user_id = int(user_id)
             # product_id depends on order_type, handle potential None
             product_id = int(product_id) if product_id is not None else None
             chef_id = int(chef_id) if chef_id is not None else None # chefid remains chefid
             producer_id = int(producer_id) if producer_id is not None else None # Corrected: producerid -> producer_id
        except (ValueError, TypeError) as e:
            raise ValueError(f"Invalid numeric value provided for order: {e}")

        # chefid is correct, producer_id is correct
        sql = """
            INSERT INTO orders (
                user_id, order_type, product_id, chef_id, producer_id,
                order_date, delivery_address, order_status, total_price,
                notes, payment_status, payment_mode,
                amount_paid, transaction_id, quantity
            )
            VALUES (%s, %s, %s, %s, %s, NOW(), %s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING order_id
        """
        params = (
            user_id, order_type, product_id, chef_id, producer_id,
            delivery_address, order_status, total_price,
            notes, payment_status, payment_mode,
            amount_paid, transaction_id, quantity
        )

        try:
            # Corrected: orderid -> order_id
            order_id = self._execute_query(sql, params, commit=True, returning_id_column='order_id')
            if order_id:
                logger.info(f"Order successfully created with order_id: {order_id}")
                return {
                    "message": "Order created successfully",
                    "orders": [{"message": "Order created successfully", "order_id": order_id, "success": True}],
                    "success": True
                }
            else:
                 raise ValueError("Order creation failed, no ID returned.")
        except ValueError as ve:
             logger.error(f"Error creating order: {ve}", exc_info=True)
             return {"message": str(ve), "orders": [{"message": str(ve), "order_id": None, "success": False}], "success": False}
        except Exception as e:
            logger.error(f"Unexpected error creating order: {e}", exc_info=True)
            err_msg = "Failed to create order due to a server error."
            return {"message": err_msg, "orders": [{"message": err_msg, "order_id": None, "success": False}], "success": False}


    def read_orders(self, order_id=None, chef_id=None, producer_id=None, user_id=None):
        # Corrected: mealid -> meal_id, produceid -> produce_id
        sql = """
            WITH MealDetails AS (
                SELECT
                    m.meal_id,
                    m.meal_name,
                    COALESCE(STRING_AGG(p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
                FROM meals m
                LEFT JOIN meal_ingredients mi ON mi.meal_id = m.meal_id
                LEFT JOIN produce p ON mi.produce_id = p.produce_id
                GROUP BY m.meal_id, m.meal_name
            )
            SELECT
                o.order_id, o.user_id, o.order_type, o.product_id,
                o.chef_id, o.producer_id, o.order_date, o.delivery_address,
                o.order_status, o.total_price, o.notes, o.payment_status,
                o.payment_mode, o.amount_paid, o.transaction_id, o.quantity,
                md.meal_name,
                md.ingredients,
                p.name AS producer_name,
                c.name AS chef_name
            FROM orders o
            LEFT JOIN MealDetails md ON o.product_id = md.meal_id -- Assumes product_id refers to meal_id here
            LEFT JOIN producers p ON o.producer_id = p.producer_id -- producer_id correct
            LEFT JOIN chefs c ON o.chef_id = c.chefid -- chefid correct
            WHERE 1=1
        """
        params = []

        if order_id is not None:
            # Corrected: orderid -> order_id
            sql += " AND o.order_id = %s"
            params.append(order_id)
        if chef_id is not None:
            # chefid correct
            sql += " AND o.chef_id = %s"
            params.append(chef_id)
        if producer_id is not None:
            # Corrected: producerid -> producer_id
            sql += " AND o.producer_id = %s"
            params.append(producer_id)
        if user_id is not None:
            # user_id correct
            sql += " AND o.user_id = %s"
            params.append(user_id)

        sql += " ORDER BY o.order_date DESC"

        results = self._execute_query(sql, tuple(params), fetch_all=True)
        logger.info(f"Retrieved {len(results)} orders matching criteria.")
        return results


# --- Usage Example (Updated PK names in response keys for consistency) ---
if __name__ == "__main__":
    # Instantiate repositories directly
    users_repo = Users()
    chefs_repo = Chefs()
    producers_repo = Producers()
    stakeholders_repo = Stakeholders()
    herbals_repo = Herbals()
    meals_repo = Meals()
    produce_repo = Produce()
    gadgets_repo = Gadgets()
    spices_repo = Spices()
    orders_repo = Orders()

    try:
        print("--- Testing User Operations ---")
        # Create a unique user for testing each run
        test_email = f"testuser_{random.randint(10000, 99999)}@example.com"
        test_name = f"Test User {random.randint(1000,9999)}"
        created_user_response = users_repo.create_user({
            'name': test_name,
            'password': 'password123',
            'email': test_email,
            'phone_number': '555-0123',
            'location': 'Testville'
        })
        print(f"Created User Response: {created_user_response}")
        user_id = created_user_response['UserId'] # This key comes from the return dict, keep as is unless modifying return

        login_response, status_code = users_repo.login_user(test_email, 'password123')
        print(f"Login Response (Status {status_code}): {login_response}")

        # Create a metric for the user
        metric_response = users_repo.create_metric({
            'user_id': user_id,
            'age_range': '36-45',
            'weight': 85.5,
            'height': 180,
            'cholesterol_level': 210,
            'sys_bp': 130,
            'dia_bp': 85,
            'pulse': 75
        })
        print(f"Created Metric Response: {metric_response}")
        metric_id = metric_response['metric_id'] # Use corrected key

        # Update metric
        users_repo.update_metric(metric_id, {'weight': 84.0, 'pulse': 72})
        print(f"Updated metric ID: {metric_id}")


        # Create a metric history for the user
        metric_history_response = users_repo.create_metric_history({
            'user_id': user_id,
            'weight': 86.0
        })
        print(f"Created Metric History Response: {metric_history_response}")
        log_id = metric_history_response['log_id'] # Use corrected key

        # List all metrics for the user
        metrics_result = users_repo.list_metrics(user_id=user_id) # list_metrics returns the list directly
        print(f"\nAll Metrics for User ID {user_id}:")
        if metrics_result:
             for metric in metrics_result:
                 print(metric)
        else:
             print("No metrics found.")


        # List all metric history for the user
        history_result = users_repo.list_metric_history(user_id=user_id) # list_metric_history returns the list
        print(f"\nAll Metric History for User ID {user_id}:")
        if history_result:
            for history in history_result:
                 print(history)
        else:
             print("No metric history found.")

        # Create user preferences
        preference_response = users_repo.create_preference({
            'user_id': user_id,
            'goals': 'Maintain Weight',
            'diet_type': 'Mediterranean',
            'food_restrictions': 'Shellfish',
            'cuisine_preferences': 'Italian, Greek'
        })
        print(f"\nCreated Preference Response: {preference_response}")
        preference_id = preference_response['preference_id'] # Use corrected key

        # Update the user's preferences
        users_repo.update_preference(preference_id, {'goals': 'Improve Cardio', 'cuisine_preferences': 'Italian, Greek, Spanish'})
        print(f"Updated preference ID: {preference_id}")


        # List preferences for the user
        preferences_result = users_repo.list_preferences(user_id=user_id) # list_preferences returns the list
        print(f"\nAll Preferences for User ID {user_id}:")
        if preferences_result:
             for pref in preferences_result:
                 print(pref)
        else:
             print("No preferences found.")


        print("\n--- Testing Chef Operations ---")
        # Create a unique chef
        test_chef_email = f"chef_{random.randint(1000,9999)}@examplechef.com"
        test_chef_name = f"Chef Gustava {random.randint(100,999)}"
        created_chef_response = chefs_repo.create_chef({
             'name': test_chef_name,
             'email': test_chef_email,
             'password': 'chefpassword!',
             'price': 50.0,
             'experience': 10,
             'specialties': ['French', 'Pastry']
        })
        print(f"Created Chef Response: {created_chef_response}")
        chef_id = created_chef_response['ChefID'] # Keep original response key

        chef_login_resp, chef_status = chefs_repo.login_chef(test_chef_email, 'chefpassword!')
        print(f"Chef Login Response (Status {chef_status}): {chef_login_resp}")

        all_chefs = chefs_repo.list_chefs() # list_chefs returns the list
        print(f"\nListed {len(all_chefs)} Chefs.")


        print("\n--- Testing Order Operations ---")
        # First, create a gadget to order
        gadget = gadgets_repo.create_gadget({
            'gadget_name': 'Smart Blender X2',
            'description': 'High power blender Pro',
            'price': 130.00,
            'brand': 'BlendMaster'
        })
        gadget_id = gadget['gadget_id'] # Use corrected key

        order_response = orders_repo.create_order(
            user_id=user_id,
            order_type='gadget',
            product_id=gadget_id,
            # producer_id=some_producer_id, # Example if needed
            chef_id=chef_id, # Example linking an order to a chef
            total_price=135.50,
            quantity=1,
            delivery_address='456 Oak Ave, Testville',
            payment_mode='stripe',
            payment_status='paid',
            amount_paid=135.50,
            transaction_id='pi_123xyz'
        )
        print(f"Create Order Response: {order_response}")
        # order_id is correct in the response dict

        # List orders for the user
        user_orders = orders_repo.read_orders(user_id=user_id) # read_orders returns the list
        print(f"\nOrders for User ID {user_id}:")
        if user_orders:
             for order in user_orders:
                 print(order)
        else:
             print("No orders found for this user.")


    except ValueError as ve:
        logger.error(f"Validation Error in main execution: {ve}", exc_info=True)
        print(f"ValueError: {ve}")
    except ConnectionError as ce:
         logger.error(f"Connection Error in main execution: {ce}", exc_info=True)
         print(f"ConnectionError: {ce}")
    except Exception as ex:
        logger.error(f"Unexpected error in main execution: {ex}", exc_info=True)
        print(f"Unexpected error: {ex}")