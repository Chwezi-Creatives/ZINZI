# Cspell:disable
import os
import json
import random
import string
from datetime import datetime, timedelta, date # Added date
from dotenv import load_dotenv
import bcrypt
import psycopg2 # Replaced pyodbc
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
# import base64 # Duplicate import removed
import time
import uuid # Added for MoMo
from typing import Dict, Any, Optional, List

# Import the centralized connection function (using PgBouncer assumed)
from database import get_db_connection

# --- Configuration Loading ---
load_dotenv()

# Access the API base URL
apibaseurl = os.getenv('OR1', 'https://default.url')
momocallbackurl=os.getenv('OR11', 'https://default.url')

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__) # Use logger instance

# --- Helper Functions ---
def hash_password(password):
    """Hashes a password using bcrypt."""
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def generate_random_code(length=6, use_digits=True, use_uppercase=True):
    """Generates a random alphanumeric code."""
    chars = ""
    if use_digits:
        chars += string.digits
    if use_uppercase:
        chars += string.ascii_uppercase
    if not chars:
        raise ValueError("At least one character set (digits/uppercase) must be enabled.")
    return ''.join(random.choices(chars, k=length))

# Consider using PostgreSQL ARRAY or JSONB types for lists in the DB
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

            with conn.cursor() as cursor:
                logger.debug(f"Executing SQL: {sql} with params: {params}")
                cursor.execute(sql, params or ())

                if returning_id_column:
                    fetched = cursor.fetchone()
                    if fetched:
                        returned_id = fetched[0]
                    logger.debug(f"Returning {returning_id_column}: {returned_id}")

                elif fetch_one:
                    fetched = cursor.fetchone()
                    if fetched and cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        results = dict(zip(columns, fetched))
                    else:
                        results = None # Ensure None if no data
                    logger.debug(f"Fetched one: {results}")

                elif fetch_all:
                    if cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
                    else:
                        results = []
                    logger.debug(f"Fetched all ({len(results)} rows)")

                if commit:
                    conn.commit()
                    logger.debug("Transaction committed.")

            if returning_id_column:
                return returned_id
            else:
                return results

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Database Error executing query: {sql} | Params: {params} | Error: {e}", exc_info=True)
            if conn:
                try:
                    conn.rollback()
                    logger.debug("Transaction rolled back due to error.")
                except psycopg2.Error as rb_err:
                    logger.error(f"Error during rollback: {rb_err}")
            raise ValueError(f"Database operation failed: {e}")
        finally:
            if conn:
                conn.close()
                logger.debug("Database connection closed.")

# --- Authentication Class ---
class Authentication:

    def signup_user(self, name, email, password):
        """Signs up a new user, hashes password, and initiates email verification."""
        hashed_pw = hash_password(password)
        verification_code = generate_random_code(length=6, use_digits=True, use_uppercase=False)
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Signup failed: Database connection failed.")
                # Returning None might be handled differently depending on caller
                return {"error": "Database service unavailable.", "success": False}

            with conn.cursor() as cursor:
                # user_id is correct
                email_query = "SELECT user_id FROM users WHERE lower(email) = lower(%s)"
                cursor.execute(email_query, (email,))
                if cursor.fetchone():
                    logger.warning(f"Signup attempt failed: Email '{email}' already registered.")
                    return {"error": "Email is already registered.", "success": False}

                # user_id is correct
                name_query = "SELECT user_id FROM users WHERE lower(name) = lower(%s)"
                cursor.execute(name_query, (name,))
                if cursor.fetchone():
                    logger.warning(f"Signup attempt failed: Name '{name}' already taken.")
                    return {"error": "Name is already taken.", "success": False}

                insert_query = """
                    INSERT INTO users (name, email, hashed_password, registration_date, is_email_verified)
                    VALUES (%s, %s, %s, NOW(), FALSE)
                    RETURNING user_id
                """
                cursor.execute(insert_query, (name, email, hashed_pw))
                # user_id is correct
                user_id = cursor.fetchone()[0]

                # user_id is correct
                verification_query = """
                    INSERT INTO email_verifications (user_id, verification_code, expires_at)
                    VALUES (%s, %s, NOW() + INTERVAL '15 minutes')
                    ON CONFLICT (user_id) DO UPDATE SET verification_code = EXCLUDED.verification_code, expires_at = EXCLUDED.expires_at
                """
                cursor.execute(verification_query, (user_id, verification_code))

                conn.commit()

            self.send_verification_email_gmail(email, verification_code)

            logger.info(f"User '{name}' (ID: {user_id}) registered. Verification email sent to {email}.")
            # user_id is correct
            return {"user_id": user_id, "success": True}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error during signup for email {email}: {e}", exc_info=True)
            if conn: conn.rollback()
            return {"error": f"An internal error occurred during signup.", "success": False}
        finally:
            if conn: conn.close()


    def login_user(self, identifier, password):
        """Logs in a user by name or email."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Login failed: Database connection failed.")
                return {'message': 'Login service unavailable. Please try again later.'}, 503

            with conn.cursor() as cursor:
                # user_id is correct
                query = """
                    SELECT user_id, hashed_password, is_email_verified, user_type
                    FROM users
                    WHERE lower(name) = lower(%s) OR lower(email) = lower(%s)
                """
                cursor.execute(query, (identifier, identifier))
                result = cursor.fetchone() # Returns tuple

                if not result:
                    logger.warning(f"Login attempt failed for identifier '{identifier}': Not found.")
                    return {'message': 'Invalid credentials or account not found.'}, 401

                # user_id is correct
                user_id, stored_hashed_pw_str, verified, user_type = result

                stored_hashed_pw_bytes = stored_hashed_pw_str.encode('utf-8')

                if bcrypt.checkpw(password.encode('utf-8'), stored_hashed_pw_bytes):
                    if not verified:
                         logger.info(f"Login attempt for user ID {user_id}: Account not verified.")
                         # user_id is correct
                         return {'message': 'Account not verified. Please check your email.', 'user_id': user_id, 'verified': False}, 403

                    logger.info(f"Login successful for identifier '{identifier}', User ID: {user_id}")
                    # user_id is correct
                    return {'message': 'Login successful', 'user_id': user_id, 'user_type': user_type, 'verified': True}, 200
                else:
                    logger.warning(f"Login attempt failed for identifier '{identifier}': Invalid password.")
                    return {'message': 'Invalid credentials.'}, 401

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error during login for identifier '{identifier}': {e}", exc_info=True)
            return {'message': 'An error occurred during login. Please try again.'}, 500
        finally:
            if conn: conn.close()

    # --- Gmail Sending Logic ---
    def send_verification_email_gmail(self, to_email, verification_code):
        # ... (Gmail sending logic remains the same - no DB interaction) ...
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None
        token_file = 'token.json'
        client_secret_file = 'client_secret_769800441200-vlojtkiqv165kbumgmjsku2rbm97h217.apps.googleusercontent.com.json'

        if not os.path.exists(client_secret_file):
             logger.error(f"Gmail client secret file not found at: {client_secret_file}")
             print(f"Error: Gmail client secret file not found at: {client_secret_file}")
             raise FileNotFoundError(f"Client secrets file '{client_secret_file}' not found.")

        if os.path.exists(token_file):
            try:
                creds = Credentials.from_authorized_user_file(token_file, SCOPES)
            except Exception as e:
                logger.warning(f"Error loading {token_file}, will re-authenticate: {e}")
                creds = None

        needs_refresh = False
        if creds:
            try:
                if creds.expiry and creds.expiry < (datetime.utcnow().replace(tzinfo=None) + timedelta(minutes=5)):
                     needs_refresh = True
                if needs_refresh and creds.refresh_token:
                    logger.info("Refreshing Gmail API token...")
                    creds.refresh(Request())
                    logger.info("Token refreshed successfully.")
                elif not creds.valid:
                    needs_refresh = True
            except RefreshError as e:
                logger.error(f"Error refreshing Gmail token (may require re-consent): {e}")
                creds = None
            except Exception as e:
                logger.error(f"Unexpected error checking/refreshing Gmail token: {e}")
                creds = None

        if not creds or not creds.valid:
            try:
                 logger.info("No valid Gmail credentials found, starting authentication flow...")
                 flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES)
                 creds = flow.run_local_server(port=8080)
                 logger.info("Gmail authentication successful.")
            except Exception as e:
                 logger.error(f"Gmail authentication flow failed: {e}")
                 print(f"Error: Failed to authenticate with Google: {e}")
                 raise ConnectionError("Failed to obtain Google API credentials.")

        try:
            with open(token_file, 'w') as token:
                token.write(creds.to_json())
            logger.debug(f"Gmail credentials saved to {token_file}")
        except IOError as e:
            logger.error(f"Error saving Gmail token to {token_file}: {e}")

        try:
            service = build('gmail', 'v1', credentials=creds)
            subject = "Your ZINZI Verification Code"
            body = f"Your verification code is: {verification_code}\nPlease enter this code in the ZINZI app to verify your account."
            message = MIMEText(body)
            message['to'] = to_email
            message['from'] = 'me'
            message['subject'] = subject
            raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()

            send_message = service.users().messages().send(
                userId="me",
                body={'raw': raw_message}
            ).execute()
            logger.info(f"Verification email sent to {to_email}. Message ID: {send_message.get('id')}")
            print(f"Verification email sent to {to_email}.")

        except Exception as e:
            logger.error(f"Error sending Gmail email to {to_email}: {e}", exc_info=True)
            print(f"Error: Could not send verification email via Gmail: {e}")
            # Consider raising or returning error

    # --- End Gmail Logic ---

    def verify_user_email(self, user_id, verification_code):
        """Verifies a user's email using the provided code."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Email verification failed: Database connection failed.")
                return {'message': 'Verification service unavailable.'}, 503

            with conn.cursor() as cursor:
                # user_id is correct
                query = """
                    SELECT verification_code
                    FROM email_verifications
                    WHERE user_id = %s AND verification_code = %s AND expires_at > NOW()
                """
                cursor.execute(query, (user_id, verification_code))
                result = cursor.fetchone()

                if not result:
                    logger.warning(f"Email verification failed for user ID {user_id}: Invalid or expired code.")
                    return {'message': 'Invalid or expired verification code'}, 400

                # user_id is correct
                update_query = "UPDATE users SET is_email_verified = TRUE WHERE user_id = %s"
                cursor.execute(update_query, (user_id,))

                # user_id is correct
                delete_query = "DELETE FROM email_verifications WHERE user_id = %s AND verification_code = %s"
                cursor.execute(delete_query, (user_id, verification_code))

                conn.commit()
                logger.info(f"Email successfully verified for user ID {user_id}.")
                return {'message': 'Email verification successful'}, 200

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error during email verification for user ID {user_id}: {e}", exc_info=True)
            if conn: conn.rollback()
            return {'message': 'An error occurred during email verification.'}, 500
        finally:
            if conn: conn.close()

# --- Updatelists Class (Consider Renaming e.g., UserProfileManager) ---
class Updatelists:

    # --- Metrics Calculations (No DB changes needed) ---
    def calculate_bmi(self, weight, height):
        if not height: return 0.0
        height_in_meters = height / 100.0
        return round(weight / (height_in_meters ** 2), 1) if height_in_meters else 0.0

    def calculate_bmi_category(self, bmi):
        if bmi < 18.5: return 'Underweight'
        if 18.5 <= bmi < 24.9: return 'Normal weight'
        if 25 <= bmi < 29.9: return 'Overweight'
        return 'Obesity'

    def calculate_ideal_weight(self, height, sex):
        sex = str(sex).strip().lower()
        if sex == 'male': ideal = 50 + 0.91 * (height - 152)
        elif sex == 'female': ideal = 45.5 + 0.91 * (height - 152)
        else: ideal = 47.75 + 0.91 * (height - 152)
        return round(max(ideal, 0), 1)

    def convert_age_range_to_age(self, age_range):
        try:
            if isinstance(age_range, str) and '-' in age_range:
                 age_min, age_max = map(int, age_range.split('-'))
                 return (age_min + age_max) // 2
            elif isinstance(age_range, (int, float)):
                 return int(age_range)
            else:
                 logger.warning(f"Invalid age range format '{age_range}', using default 30.")
                 return 30
        except ValueError:
            logger.warning(f"Error parsing age range '{age_range}', using default 30.")
            return 30

    def calculate_bmr(self, weight, height, age_range, sex):
        age = self.convert_age_range_to_age(age_range)
        sex = str(sex).strip().lower()
        if sex == 'male': bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
        elif sex == 'female': bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
        else: bmr = (10 * weight) + (6.25 * height) - (5 * age) - 78
        return round(max(bmr, 0))

    def calculate_daily_calories(self, bmr, activity_level):
        activity_level = str(activity_level).strip().lower().replace(" ", "_")
        activity_multiplier = {
            'sedentary': 1.2, 'lightly_active': 1.375, 'moderately_active': 1.55,
            'very_active': 1.725, 'extremely_active': 1.9, 'extra_active': 1.9
        }
        multiplier = activity_multiplier.get(activity_level, 1.2)
        return round(bmr * multiplier)
    # --- End Metrics Calculations ---

    def add_user_metrics(self, user_id, age_range, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, sex, activity_level):
        """Adds or updates user metrics, calculates derived values, and logs history."""
        conn = None
        try:
            user_id = int(user_id)
            weight = float(weight)
            height = float(height)
            cholesterol_level = float(cholesterol_level) if cholesterol_level is not None else None
            sys_bp = int(sys_bp) if sys_bp is not None else None
            dia_bp = int(dia_bp) if dia_bp is not None else None
            pulse = int(pulse) if pulse is not None else None
            sex = str(sex).strip() if sex else None
            activity_level = str(activity_level).strip() if activity_level else None
            age_range = str(age_range).strip() if age_range else None
        except (ValueError, TypeError) as e:
            logger.error(f"Invalid input type for user metrics (User ID: {user_id}): {e}")
            return {"error": f"Invalid input provided: {e}", "success": False}

        bmi = self.calculate_bmi(weight, height)
        bmi_category = self.calculate_bmi_category(bmi)
        ideal_weight = self.calculate_ideal_weight(height, sex)
        bmr = self.calculate_bmr(weight, height, age_range, sex)
        daily_calories = self.calculate_daily_calories(bmr, activity_level)

        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Add/Update metrics failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                # **Corrected: `cholestrol_level` -> `cholesterol_level` if it was a typo**
                # Verify this column name in your actual `user_metrics` table!
                upsert_query = """
                    INSERT INTO user_metrics (
                        user_id, weight, height, cholesterol_level, sys_bp, dia_bp, pulse,
                        age_range, sex, activity_level, bmi, bmi_category, ideal_weight, bmr, daily_calories, recorded_at
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
                    ON CONFLICT (user_id) DO UPDATE SET
                        weight = EXCLUDED.weight, height = EXCLUDED.height,
                        cholesterol_level = EXCLUDED.cholesterol_level, -- VERIFY NAME
                        sys_bp = EXCLUDED.sys_bp, dia_bp = EXCLUDED.dia_bp, pulse = EXCLUDED.pulse,
                        age_range = EXCLUDED.age_range, sex = EXCLUDED.sex, activity_level = EXCLUDED.activity_level,
                        bmi = EXCLUDED.bmi, bmi_category = EXCLUDED.bmi_category, ideal_weight = EXCLUDED.ideal_weight,
                        bmr = EXCLUDED.bmr, daily_calories = EXCLUDED.daily_calories, recorded_at = NOW();
                """
                params = (
                    user_id, weight, height, cholesterol_level, sys_bp, dia_bp, pulse,
                    age_range, sex, activity_level, bmi, bmi_category, ideal_weight, bmr, daily_calories
                )
                cursor.execute(upsert_query, params)
                message = f"Metrics added/updated for user ID {user_id}."

                self.log_user_metrics_history(cursor, user_id, weight)

                conn.commit()
            logger.info(message)
            return {"message": message, "success": True, "calculated_metrics": {
                 "bmi": bmi, "bmi_category": bmi_category, "ideal_weight": ideal_weight,
                 "bmr": bmr, "daily_calories": daily_calories
            }}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error updating metrics for user ID {user_id}: {e}", exc_info=True)
            if conn: conn.rollback()
            return {"error": "An internal error occurred while updating metrics.", "success": False}
        finally:
            if conn: conn.close()

    def log_user_metrics_history(self, cursor, user_id, weight):
        """Logs user weight metric into history table using an existing cursor."""
        # user_id is correct
        insert_query = """
            INSERT INTO metrics_history (user_id, weight, logged_at)
            VALUES (%s, %s, NOW())
        """
        try:
            cursor.execute(insert_query, (user_id, weight))
            logger.debug(f"Logged weight {weight} for user ID {user_id} in history.")
        except (psycopg2.Error, Exception) as e:
            logger.error(f"Failed to log metric history for user ID {user_id}: {e}", exc_info=True)
            raise # Propagate error to caller for transaction control

    def get_user_metrics(self, user_id):
        """Fetches the latest user metrics."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Get metrics failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                # **Corrected: `Cholestrol_level` -> `cholesterol_level` (verify in DB)**
                # user_id is correct
                query = """
                    SELECT weight, height, cholesterol_level, sys_bp, dia_bp, pulse,
                           age_range, bmi, bmi_category, ideal_weight, bmr,
                           daily_calories, recorded_at, sex, activity_level
                    FROM user_metrics
                    WHERE user_id = %s
                """
                cursor.execute(query, (user_id,))
                result = cursor.fetchone() # Returns tuple

                if result:
                    columns = [desc[0] for desc in cursor.description]
                    metrics_dict = dict(zip(columns, result))
                    if metrics_dict.get('recorded_at'):
                        metrics_dict['recorded_at'] = metrics_dict['recorded_at'].isoformat()
                    logger.debug(f"Fetched metrics for user ID {user_id}.")
                    return {"metrics": metrics_dict, "success": True}
                else:
                    logger.warning(f"No metrics found for user ID {user_id}.")
                    return {"message": f"No metrics found for user ID {user_id}.", "success": False}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error fetching metrics for user ID {user_id}: {e}", exc_info=True)
            return {"error": "An internal error occurred while fetching metrics.", "success": False}
        finally:
            if conn: conn.close()

    def add_user_preferences(self, user_id, goals, diet_type, food_restrictions, cuisine_preferences=None):
        """Adds or updates user preferences."""
        conn = None
        try:
            user_id = int(user_id)
            goals = str(goals).strip() if goals else None
            diet_type = str(diet_type).strip() if diet_type else None
            food_restrictions_str = serialize_list([fr.strip() for fr in food_restrictions if fr and fr.strip()]) if isinstance(food_restrictions, list) else str(food_restrictions or '').strip()
            cuisine_preferences_str = serialize_list([cp.strip() for cp in cuisine_preferences if cp and cp.strip()]) if isinstance(cuisine_preferences, list) else str(cuisine_preferences or '').strip()

            conn = get_db_connection()
            if conn is None:
                 logger.error("Add/Update preferences failed: Database connection failed.")
                 return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                 # user_id is correct
                 upsert_query = """
                     INSERT INTO user_preferences (user_id, goals, diet_type, food_restrictions, cuisine_preferences)
                     VALUES (%s, %s, %s, %s, %s)
                     ON CONFLICT (user_id) DO UPDATE SET
                         goals = EXCLUDED.goals, diet_type = EXCLUDED.diet_type,
                         food_restrictions = EXCLUDED.food_restrictions, cuisine_preferences = EXCLUDED.cuisine_preferences;
                 """
                 params = (user_id, goals, diet_type, food_restrictions_str or None, cuisine_preferences_str or None) # Use None for empty strings
                 cursor.execute(upsert_query, params)
                 conn.commit()
                 message = f"Preferences added/updated for user ID {user_id}."
                 logger.info(message)
                 return {"message": message, "success": True}

        except (ValueError, TypeError) as e:
             logger.error(f"Invalid input type for user preferences (User ID: {user_id}): {e}")
             return {"error": f"Invalid input provided: {e}", "success": False}
        except (psycopg2.Error, Exception) as e:
             logger.error(f"Error updating preferences for user ID {user_id}: {e}", exc_info=True)
             if conn: conn.rollback()
             return {"error": "An internal error occurred while updating preferences.", "success": False}
        finally:
             if conn: conn.close()

    def fetch_user_preferences(self, user_id):
        """Fetches user preferences."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Fetch preferences failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                # user_id is correct
                query = """
                    SELECT user_id, goals, diet_type, food_restrictions, cuisine_preferences
                    FROM user_preferences
                    WHERE user_id = %s
                """
                cursor.execute(query, (user_id,))
                result = cursor.fetchone() # Returns tuple

                if result:
                    columns = [desc[0] for desc in cursor.description]
                    prefs_dict = dict(zip(columns, result))
                    prefs_dict['food_restrictions'] = deserialize_list(prefs_dict.get('food_restrictions', ''))
                    prefs_dict['cuisine_preferences'] = deserialize_list(prefs_dict.get('cuisine_preferences', ''))
                    logger.debug(f"Fetched preferences for user ID {user_id}.")
                    return {"preferences": prefs_dict, "success": True}
                else:
                    logger.warning(f"No preferences found for user ID {user_id}.")
                    return {"message": f"No preferences found for user ID {user_id}.", "success": False}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error fetching preferences for user ID {user_id}: {e}", exc_info=True)
            return {"error": "An internal error occurred while fetching preferences.", "success": False}
        finally:
            if conn: conn.close()

    def get_metrics_history(self, user_id):
        """Fetches user metrics history."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Get metrics history failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                # user_id is correct
                query = """
                    SELECT weight, logged_at
                    FROM metrics_history
                    WHERE user_id = %s
                    ORDER BY logged_at ASC
                """
                cursor.execute(query, (user_id,))
                results = cursor.fetchall() # Returns list of tuples
                history = [{"weight": row[0], "logged_at": row[1].isoformat()} for row in results]
                logger.debug(f"Fetched {len(history)} metrics history records for user ID {user_id}.")
                return {"history": history, "success": True}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error fetching metrics history for user ID {user_id}: {e}", exc_info=True)
            return {"error": "An internal error occurred while fetching metrics history.", "success": False}
        finally:
            if conn: conn.close()

    # --- Chef Methods ---
    def add_chef(self, data):
        """Inserts chef data into the database."""
        # (chefid is kept as is, no changes needed here based on instructions)
        # ... (rest of add_chef implementation remains the same) ...
        conn = None
        languages_str = serialize_list(data.get('languages', []))
        equipment_str = serialize_list(data.get('equipment', []))
        availability_str = serialize_list(data.get('availability', []))
        specialties_str = serialize_list(data.get('specialties', []))
        certifications_str = serialize_list(data.get('certifications', []))
        sample_menu_str = serialize_list(data.get('sample_menu', []))
        hashed_password = None
        if 'password' in data and data['password']:
            hashed_password = hash_password(data['password'])
        elif 'hashed_password' in data:
            hashed_password = data['hashed_password']
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Add chef failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}
            with conn.cursor() as cursor:
                 insert_query = """
                     INSERT INTO chefs (
                         image, name, price, location, experience, email, hashed_password,
                         responsetime, minnotice, teamsize, equipment, bio,
                         availability, languages, specialties, certifications, samplemenu,
                         registration_date, last_login, is_active, user_type
                     )
                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), TRUE, 'chef')
                     RETURNING chefid
                 """
                 params = (
                     data.get('image'), data.get('name'), data.get('price'),
                     data.get('location'), data.get('experience'), data.get('email'), hashed_password,
                     data.get('response_time'), data.get('min_notice'),
                     data.get('team_size'), equipment_str, data.get('bio'),
                     availability_str, languages_str, specialties_str, certifications_str,
                     sample_menu_str
                 )
                 cursor.execute(insert_query, params)
                 chef_id = cursor.fetchone()[0]
                 conn.commit()
                 logger.info(f"Added chef '{data.get('name')}' with ID: {chef_id}.")
                 return {"chef_id": chef_id, "success": True}
        except (psycopg2.Error, Exception) as e:
             logger.error(f"Error adding chef '{data.get('name')}': {e}", exc_info=True)
             if conn: conn.rollback()
             if isinstance(e, psycopg2.IntegrityError) and 'unique constraint' in str(e).lower():
                 return {"error": "Chef with this email or name might already exist.", "success": False}
             return {"error": "An internal error occurred while adding the chef.", "success": False}
        finally:
             if conn: conn.close()

    def get_chefs(self):
        """Fetches all chefs from the database."""
        # (chefid is kept as is, no changes needed here based on instructions)
        # ... (rest of get_chefs implementation remains the same) ...
        conn = None
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Get chefs failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False, "chefs": []}
            with conn.cursor() as cursor:
                select_query = 'SELECT * FROM chefs ORDER BY name'
                cursor.execute(select_query)
                columns = [desc[0] for desc in cursor.description]
                chefs_list = []
                for row in cursor.fetchall():
                    chef_dict = dict(zip(columns, row))
                    for key in ['languages', 'specialties', 'certifications', 'samplemenu', 'availability', 'equipment']:
                         if key in chef_dict and isinstance(chef_dict[key], str):
                              chef_dict[key] = deserialize_list(chef_dict[key])
                    for key in ['registration_date', 'last_login']:
                        if key in chef_dict and isinstance(chef_dict[key], (datetime, date)):
                            chef_dict[key] = chef_dict[key].isoformat()
                    chefs_list.append(chef_dict)
                logger.debug(f"Fetched {len(chefs_list)} chefs.")
                return {"chefs": chefs_list, "success": True}
        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error retrieving chefs: {e}", exc_info=True)
            return {"error": "An internal error occurred while retrieving chefs.", "success": False, "chefs": []}
        finally:
            if conn: conn.close()

    # --- Product Catalog / Meal Data Methods ---
    # Assuming PK is product_id, meal_id respectively and need correction
    def add_product_to_catalog(self, product_name, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, meal_id=None):
        """Adds a product to the 'product_catalog' table."""
        conn = None
        try:
            conn = get_db_connection()
            if conn is None: return {"error": "DB connection failed.", "success": False}
            with conn.cursor() as cursor:
                # **Corrected: RETURNING productid -> RETURNING product_id**
                # **Corrected: mealid -> meal_id in VALUES list**
                insert_query = """
                    INSERT INTO product_catalog
                    (product_name, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, meal_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING product_id
                """
                params = (product_name, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, meal_id)
                cursor.execute(insert_query, params)
                product_id = cursor.fetchone()[0]
                conn.commit()
                logger.info(f"Product '{product_name}' (ID: {product_id}) added to catalog.")
                return {"product_id": product_id, "success": True}
        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error adding product '{product_name}' to catalog: {e}", exc_info=True)
            if conn: conn.rollback()
            return {"error": "Failed to add product.", "success": False}
        finally:
            if conn: conn.close()

    def calculate_nutritional_contributions(self, products: List[Dict]):
        """Calculates total nutrients from a list of products with percentage contributions."""
        # ... (calculation logic remains the same) ...
        totals = {'calories': 0.0, 'cholesterol': 0.0, 'protein': 0.0, 'carbs': 0.0, 'fat': 0.0}
        if not products: return tuple(totals.values())
        for product in products:
            try:
                percentage = float(product.get('PercentageContribution', 0)) / 100.0
                totals['calories'] += float(product.get('Calories', 0)) * percentage
                totals['cholesterol'] += float(product.get('Cholesterol_content', 0)) * percentage
                totals['protein'] += float(product.get('Protein_content', 0)) * percentage
                totals['carbs'] += float(product.get('Carbohydrate_content', 0)) * percentage
                totals['fat'] += float(product.get('Fat_content', 0)) * percentage
            except (ValueError, TypeError, KeyError) as e:
                logger.warning(f"Skipping product due to invalid data: {product}. Error: {e}")
                continue
        return tuple(round(v, 2) for v in totals.values())


    def update_meal_data(self, meal_id, meal_name, products):
        """Updates a meal in the 'meal_data' table based on product contributions."""
        conn = None
        total_calories, total_cholesterol, total_protein, total_carbs, total_fat = self.calculate_nutritional_contributions(products)
        try:
            conn = get_db_connection()
            if conn is None: return {"error": "DB connection failed.", "success": False}
            with conn.cursor() as cursor:
                # **Corrected: WHERE mealid -> WHERE meal_id**
                # **Corrected: `Cholestrol_content` -> `cholesterol_content` (verify in DB)**
                update_query = """
                    UPDATE meal_data
                    SET mealname = %s, calories = %s, cholesterol_content = %s, protein_content = %s,
                        carbohydrate_content = %s, fat_content = %s,
                        nutrition_details = %s
                    WHERE meal_id = %s
                """
                params = (
                    meal_name, total_calories, total_cholesterol, total_protein, total_carbs, total_fat,
                    "Updated based on product contributions", meal_id
                )
                cursor.execute(update_query, params)
                rows_affected = cursor.rowcount
                conn.commit()
                if rows_affected > 0:
                    logger.info(f"Meal data updated for Meal ID {meal_id}.")
                    return {"success": True, "message": f"Meal ID {meal_id} updated."}
                else:
                    logger.warning(f"No meal data found to update for Meal ID {meal_id}.")
                    return {"success": False, "message": f"Meal ID {meal_id} not found."}
        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error updating meal data for Meal ID {meal_id}: {e}", exc_info=True)
            if conn: conn.rollback()
            return {"error": "Failed to update meal data.", "success": False}
        finally:
            if conn: conn.close()

    def add_meal_data(self, meal_name, products, user_id):
        """Adds a new meal to the 'meal_data' table based on product contributions."""
        conn = None
        total_calories, total_cholesterol, total_protein, total_carbs, total_fat = self.calculate_nutritional_contributions(products)
        try:
            conn = get_db_connection()
            if conn is None: return {"error": "DB connection failed.", "success": False}
            with conn.cursor() as cursor:
                 # **Corrected: RETURNING mealid -> RETURNING meal_id**
                 # **Corrected: `Cholestrol_content` -> `cholesterol_content` (verify in DB)**
                 # user_id is correct
                 insert_query = """
                     INSERT INTO meal_data
                     (mealname, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, user_id)
                     VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                     RETURNING meal_id
                 """
                 params = (
                     meal_name, total_calories, total_cholesterol, total_protein, total_carbs, total_fat,
                     "Calculated based on product contributions", user_id
                 )
                 cursor.execute(insert_query, params)
                 meal_id = cursor.fetchone()[0]
                 conn.commit()
                 logger.info(f"New meal '{meal_name}' (ID: {meal_id}) added to meal_data.")
                 return {"meal_id": meal_id, "success": True}
        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error adding new meal data '{meal_name}': {e}", exc_info=True)
            if conn: conn.rollback()
            return {"error": "Failed to add new meal data.", "success": False}
        finally:
            if conn: conn.close()

# --- Meal Recommendation Classes (Refactored) ---

class BaseMealRecommender:
    def __init__(self, user_id: int):
        # user_id correct
        self.user_id = user_id
        self.user_preferences = self._get_user_preferences()
        self.user_metrics = self._get_user_metrics()
        self._validate_user_data()

    def _get_db_connection(self):
        conn = get_db_connection()
        if conn is None:
            logger.error(f"RecSystem ({self.__class__.__name__}): Database connection failed for User ID {self.user_id}.")
            raise ConnectionError("Database service unavailable.")
        return conn

    def _validate_user_data(self):
        if not self.user_preferences: logger.warning(f"RecSystem ({self.__class__.__name__}): No preferences found for User ID {self.user_id}.")
        if not self.user_metrics: logger.warning(f"RecSystem ({self.__class__.__name__}): No metrics found for User ID {self.user_id}.")

    def _execute_query(self, query: str, params: tuple = (), fetch_one: bool = False, fetch_all: bool = False) -> Optional[Any]:
        # ... (Base _execute_query remains the same) ...
        conn = None
        try:
            conn = self._get_db_connection()
            with conn.cursor() as cursor:
                cursor.execute(query, params)
                if fetch_one:
                    row = cursor.fetchone()
                    if row and cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        return dict(zip(columns, row))
                    return None # Return None if no row
                elif fetch_all:
                    if cursor.description:
                        columns = [desc[0] for desc in cursor.description]
                        return [dict(zip(columns, row)) for row in cursor.fetchall()]
                    return [] # Return empty list if no description/rows
                else:
                    conn.commit()
                    return None
        except (psycopg2.Error, Exception) as e:
            logger.error(f"RecSystem ({self.__class__.__name__}) DB Error for User ID {self.user_id}: Query: {query[:100]}... Params: {params} Error: {e}", exc_info=True)
            if conn: conn.rollback()
            raise ValueError(f"Database operation failed: {e}") from e
        finally:
            if conn: conn.close()

    def _get_user_preferences(self) -> Optional[Dict]:
        """Fetches and processes user preferences."""
        # user_id is correct
        query = """
            SELECT goals, diet_type, food_restrictions, cuisine_preferences
            FROM user_preferences WHERE user_id = %s
        """
        # Use fetch_one which now returns dict or None
        result = self._execute_query(query, (self.user_id,), fetch_one=True)
        if not result: return None

        return {
            "goals": result.get('goals', '').strip().lower() if result.get('goals') else None,
            "diet_type": result.get('diet_type', '').strip().lower() if result.get('diet_type') else None,
            "food_restrictions": deserialize_list(result.get('food_restrictions', '')),
            "cuisine_preferences": deserialize_list(result.get('cuisine_preferences', '')),
        }


    def _get_user_metrics(self) -> Optional[Dict]:
        """Fetches and processes user metrics."""
        # user_id is correct
        query = """
            SELECT weight, height, cholesterol_level, sys_bp, dia_bp, pulse, age_range, sex, activity_level, daily_calories, bmr, bmi, bmi_category
            FROM user_metrics WHERE user_id = %s
        """
        # Use fetch_one which now returns dict or None
        metrics = self._execute_query(query, (self.user_id,), fetch_one=True)
        if not metrics: return None

        metrics['sex'] = metrics.get('sex', 'male').strip().lower()
        metrics['activity_level'] = metrics.get('activity_level', 'sedentary').strip().lower()
        return metrics

    def _fetch_produce_data(self, produce_names: List[str]) -> Dict[str, Dict]:
        """Fetches nutritional data for a list of produce names."""
        # ... (remains the same, uses produce_name which is likely not a PK) ...
        if not produce_names: return {}
        normalized_lookup = {name.strip().lower(): name for name in produce_names}
        query_params = tuple(normalized_lookup.keys())
        query = f"""
            SELECT produce_name, calories, unit_grams, cholesterol, carbohydrates, proteins, fats, fiber, sugars
            FROM produce
            WHERE lower(produce_name) IN ({','.join(['%s'] * len(query_params))})
        """
        results = self._execute_query(query, query_params, fetch_all=True)
        produce_dict = {}
        for row in results:
            produce_dict[row['produce_name'].lower()] = {
                "calories": row.get('calories', 0.0) or 0.0, "unit_grams": row.get('unit_grams', 100.0) or 100.0,
                "cholesterol": row.get('cholesterol', 0.0) or 0.0, "carbohydrates": row.get('carbohydrates', 0.0) or 0.0,
                "proteins": row.get('proteins', 0.0) or 0.0, "fats": row.get('fats', 0.0) or 0.0,
                "fiber": row.get('fiber', 0.0) or 0.0, "sugars": row.get('sugars', 0.0) or 0.0,
            }
        return produce_dict

    def _calculate_meal_nutrition(self, ingredients_str: Optional[str], produce_data: Dict[str, Dict]) -> Dict[str, float]:
        """Calculates aggregated nutritional info for a meal based on its ingredients."""
        # ... (remains the same) ...
        nutrition = {"calories": 0.0, "proteins": 0.0, "carbohydrates": 0.0, "fats": 0.0, "fiber": 0.0, "sugars": 0.0, "cholesterol": 0.0, "total_grams": 0.0}
        if not ingredients_str: return nutrition
        ingredient_names = [name.strip().lower() for name in ingredients_str.split(",") if name.strip()]
        for name_lower in ingredient_names:
            data = produce_data.get(name_lower)
            if data:
                grams = data['unit_grams']
                nutrition["calories"] += data['calories']; nutrition["proteins"] += data['proteins']
                nutrition["carbohydrates"] += data['carbohydrates']; nutrition["fats"] += data['fats']
                nutrition["fiber"] += data['fiber']; nutrition["sugars"] += data['sugars']
                nutrition["cholesterol"] += data['cholesterol']; nutrition["total_grams"] += grams
            else: logger.warning(f"RecSystem ({self.__class__.__name__}) User {self.user_id}: Nutritional data not found for ingredient '{name_lower}'.")
        for key in nutrition: nutrition[key] = round(nutrition[key], 1)
        return nutrition

# Recommendation Algorithm Version 1 (Refactored)
class MealRecommendation1(BaseMealRecommender):

    def fetch_all_meals_with_ingredients(self):
        """Fetches all meals with aggregated ingredients."""
        # **Corrected: meal_id, produce_id**
        query = """
            SELECT
                m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link,
                m.goal, m.dietary_preference, m.allergies, m.disease_management,
                m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description,
                COALESCE(STRING_AGG(p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
            FROM meals m
            LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id -- Corrected join
            LEFT JOIN produce p ON mi.produce_id = p.produce_id -- Corrected join
            GROUP BY m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link,
                     m.goal, m.dietary_preference, m.allergies, m.disease_management,
                     m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description
        """
        all_meals = self._execute_query(query, fetch_all=True)

        all_ingredient_names = set()
        if all_meals:
            for meal in all_meals:
                if meal.get('ingredients'):
                    all_ingredient_names.update(name.strip() for name in meal['ingredients'].split(",") if name.strip())
        self.produce_data_cache = self._fetch_produce_data(list(all_ingredient_names))

        if all_meals:
            for meal in all_meals:
                meal['calculated_nutrition'] = self._calculate_meal_nutrition(
                    meal.get('ingredients'), self.produce_data_cache
                )
        return all_meals

    def filter_meals(self, all_meals):
        """Filters meals based on user preferences."""
        # ... (filtering logic remains the same) ...
        if not all_meals or not self.user_preferences: return []
        prefs = self.user_preferences; filtered = []
        for meal in all_meals:
            meal_diet = [d.strip().lower() for d in meal.get('dietary_preference', '').split(',')] if meal.get('dietary_preference') else []
            meal_allergens = [a.strip().lower() for a in meal.get('allergies', '').split(',')] if meal.get('allergies') else []
            meal_cuisines = [c.strip().lower() for c in meal.get('cuisine_preferences', '').split(',')] if meal.get('cuisine_preferences') else []
            if prefs['diet_type'] and prefs['diet_type'] not in meal_diet and meal_diet: continue
            if prefs['food_restrictions'] and any(res in meal_allergens for res in prefs['food_restrictions']): continue
            if prefs['cuisine_preferences'] and not any(cp in meal_cuisines for cp in prefs['cuisine_preferences']): continue
            user_goal = prefs.get('goals'); meal_goal = meal.get('goal', '').strip().lower() if meal.get('goal') else None
            if user_goal and meal_goal and user_goal != meal_goal: continue
            filtered.append(meal)
        logger.info(f"RecSystem (V1) User {self.user_id}: Filtered {len(all_meals)} meals down to {len(filtered)}.")
        return filtered

    def recommend_meals(self):
        """Generates recommendations using V1 logic."""
        # ... (remains largely the same, error handling improved) ...
        if not self.user_preferences: return {"error": "User preferences not found.", "success": False}
        try:
            all_meals = self.fetch_all_meals_with_ingredients()
            if all_meals is None: return {"error": "Failed to retrieve meals.", "success": False}
            recommended_meals = self.filter_meals(all_meals)
            for meal in recommended_meals: meal.setdefault('price', 10000)
            logger.info(f"RecSystem (V1) User {self.user_id}: Generated {len(recommended_meals)} recommendations.")
            return {"recommended_meals": recommended_meals, "success": True}
        except (ConnectionError, ValueError) as e: return {"error": str(e), "success": False}
        except Exception as e:
             logger.error(f"RecSystem (V1) User {self.user_id}: Unexpected error recommending meals: {e}", exc_info=True)
             return {"error": "Unexpected error during recommendation.", "success": False}


# Recommendation Algorithm Version 2 (Refactored)
class MealRecommendation2(BaseMealRecommender):

    def __init__(self, user_id: int):
        super().__init__(user_id)
        self.daily_calorie_budget = self._calculate_daily_calorie_budget()
        logger.info(f"RecSystem (V2) User {self.user_id}: Initialized with Calorie Budget: {self.daily_calorie_budget}")

    def _calculate_daily_calorie_budget(self) -> float:
        """Calculates TDEE based on user metrics and adjusts for goals."""
        # ... (calculation logic remains the same) ...
        if not self.user_metrics: logger.warning(f"RecSystem (V2) User {self.user_id}: Metrics missing, using default budget 2000 kcal."); return 2000.0
        bmr = self.user_metrics.get('bmr'); daily_calories = self.user_metrics.get('daily_calories')
        if bmr is None: helper = Updatelists(); bmr = helper.calculate_bmr(self.user_metrics.get('weight', 70), self.user_metrics.get('height', 170), self.user_metrics.get('age_range', '25-35'), self.user_metrics.get('sex', 'male')); logger.debug(f"RecSystem (V2) User {self.user_id}: Calculated missing BMR: {bmr}")
        if daily_calories is not None: tdee = float(daily_calories); logger.debug(f"RecSystem (V2) User {self.user_id}: Using pre-calculated Daily Calories (TDEE): {tdee}")
        else: helper = Updatelists(); activity_level = self.user_metrics.get('activity_level', 'sedentary'); tdee = helper.calculate_daily_calories(bmr, activity_level); logger.debug(f"RecSystem (V2) User {self.user_id}: Calculated TDEE: {tdee} (BMR: {bmr}, Activity: {activity_level})")
        goal = self.user_preferences.get('goals') if self.user_preferences else None; adjustment = 0
        if goal == "weight loss": adjustment = -500
        elif goal == "muscle gain": adjustment = 300
        final_budget = max(1200, tdee + adjustment); logger.info(f"RecSystem (V2) User {self.user_id}: Goal='{goal}', TDEE={tdee}, Adjustment={adjustment}, Final Budget={final_budget}")
        return round(final_budget, 1)

    def fetch_all_meals_with_nutrition(self) -> List[Dict]:
        """Fetches all meals and calculates detailed nutrition for each."""
        # **Corrected: meal_id, produce_id**
        query = """
            SELECT
                m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link,
                m.goal, m.dietary_preference, m.allergies, m.disease_management,
                m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description,
                COALESCE(STRING_AGG(p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients
            FROM meals m
            LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id -- Corrected join
            LEFT JOIN produce p ON mi.produce_id = p.produce_id -- Corrected join
            GROUP BY m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link,
                     m.goal, m.dietary_preference, m.allergies, m.disease_management,
                     m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description
        """
        all_meals = self._execute_query(query, fetch_all=True)
        if not all_meals: return []

        all_ingredient_names = set()
        for meal in all_meals:
            if meal.get('ingredients'):
                all_ingredient_names.update(name.strip() for name in meal['ingredients'].split(",") if name.strip())
        self.produce_data_cache = self._fetch_produce_data(list(all_ingredient_names))

        for meal in all_meals:
            meal['nutritional_info'] = self._calculate_meal_nutrition(
                meal.get('ingredients'), self.produce_data_cache
            )
        return all_meals

    def _calculate_calorie_density(self, meal: Dict) -> float:
        """Calculates calorie density (kcal/gram) for a meal."""
        # ... (remains the same) ...
        calories = meal.get('nutritional_info', {}).get('calories', 0.0); total_grams = meal.get('nutritional_info', {}).get('total_grams', 0.0)
        return round(calories / total_grams, 2) if total_grams > 0 else 0.0

    def _calculate_serving_size(self, meal: Dict) -> float:
        """Estimates serving size (grams) based on target calories (e.g., budget / 3 meals)."""
        # ... (remains the same) ...
        target_calories_per_meal = self.daily_calorie_budget / 3.0; calories_per_100g = 0
        if target_calories_per_meal <= 0: return 0.0
        total_grams = meal.get('nutritional_info', {}).get('total_grams', 0.0); total_calories = meal.get('nutritional_info', {}).get('calories', 0.0)
        if total_grams > 0: calories_per_100g = (total_calories / total_grams) * 100
        if calories_per_100g <= 0: logger.warning(f"RecSystem (V2) User {self.user_id}: Cannot calculate serving size for meal '{meal.get('meal_name')}' due to zero/missing calorie info."); return 100.0
        serving_size_grams = (target_calories_per_meal / calories_per_100g) * 100
        return round(max(50, serving_size_grams), 1)

    def filter_and_score_meals(self, all_meals: List[Dict]) -> List[Dict]:
        """Filters meals based on preferences and calculates serving size."""
        # ... (filtering and scoring logic remains the same) ...
        if not all_meals or not self.user_preferences: return []
        prefs = self.user_preferences; filtered_meals = []
        for meal in all_meals:
            meal_diet = [d.strip().lower() for d in meal.get('dietary_preference', '').split(',')] if meal.get('dietary_preference') else []
            meal_allergens = [a.strip().lower() for a in meal.get('allergies', '').split(',')] if meal.get('allergies') else []
            if prefs['diet_type'] and prefs['diet_type'] not in meal_diet and meal_diet: continue
            if prefs['food_restrictions'] and any(res in meal_allergens for res in prefs['food_restrictions']): continue
            serving_size_g = self._calculate_serving_size(meal); meal['recommended_serving_g'] = serving_size_g
            nutrition_per_100g = {}; total_grams = meal.get('nutritional_info', {}).get('total_grams', 0.0)
            if total_grams > 0:
                factor = serving_size_g / 100.0
                for key, val in meal['nutritional_info'].items():
                     if key != 'total_grams': per_100g = (val / total_grams) * 100 if total_grams else 0; nutrition_per_100g[key] = round(per_100g, 1)
            meal['nutrition_per_serving'] = {}
            if nutrition_per_100g:
                 for key, per_100g_val in nutrition_per_100g.items(): meal['nutrition_per_serving'][key] = round(per_100g_val * (serving_size_g / 100.0) , 1)
            meal_cuisines = [c.strip().lower() for c in meal.get('cuisine_preferences', '').split(',')] if meal.get('cuisine_preferences') else []; cuisine_match_score = 0
            if prefs['cuisine_preferences']:
                 if any(cp in meal_cuisines for cp in prefs['cuisine_preferences']): cuisine_match_score = 1
            meal['score'] = cuisine_match_score
            filtered_meals.append(meal)
        filtered_meals.sort(key=lambda x: x.get('score', 0), reverse=True)
        logger.info(f"RecSystem (V2) User {self.user_id}: Filtered {len(all_meals)} meals down to {len(filtered_meals)} applicable meals.")
        return filtered_meals

    def recommend_meals(self) -> Dict:
        """Generates recommendations using V2 logic."""
        # ... (remains largely the same, error handling improved) ...
        if not self.user_preferences or not self.user_metrics:
             missing = []; error_msg = f"User {', '.join(missing)} not found."
             if not self.user_preferences: missing.append("preferences")
             if not self.user_metrics: missing.append("metrics")
             logger.warning(f"RecSystem (V2) User {self.user_id}: {error_msg}")
             return {"error": error_msg, "success": False}
        try:
            all_meals = self.fetch_all_meals_with_nutrition()
            if all_meals is None: return {"error": "Failed to retrieve meals.", "success": False}
            recommended_meals = self.filter_and_score_meals(all_meals)
            for meal in recommended_meals: meal.setdefault('price', 10000)
            logger.info(f"RecSystem (V2) User {self.user_id}: Generated {len(recommended_meals)} recommendations.")
            return {"recommended_meals": recommended_meals, "success": True}
        except (ConnectionError, ValueError) as e: return {"error": str(e), "success": False}
        except Exception as e:
             logger.error(f"RecSystem (V2) User {self.user_id}: Unexpected error recommending meals: {e}", exc_info=True)
             return {"error": "Unexpected error during recommendation.", "success": False}


# --- GetAllMeals Class (Refactored) ---
class GetAllMeals:
    def Fetch_All_Meals(self):
        """Fetches all meals with ingredients and complementary dishes."""
        conn = None
        logger.debug("Fetching all meals...")
        try:
            conn = get_db_connection()
            if conn is None:
                logger.error("Fetch_All_Meals failed: Database connection failed.")
                return {"error": "Database service unavailable", "success": False}

            with conn.cursor() as cursor:
                # **Corrected: meal_id, produce_id**
                # Assumes meal_complementaries table links meal_id to complementary_dish_id (which is also a meal_id)
                sql_query = """
                    WITH MealDetails AS (
                        SELECT
                            m.meal_id, m.meal_name, m.meal_category, m.recipe, m.recipe_link, m.image_link,
                            m.goal, m.dietary_preference, m.allergies, m.disease_management,
                            m.cuisine_preferences, m.skill_level, m.prep_time, m.meal_description
                        FROM meals m
                    )
                    SELECT
                        md.*,
                        COALESCE(STRING_AGG(DISTINCT p.produce_name, ', ' ORDER BY p.produce_name), '') AS ingredients,
                        COALESCE(STRING_AGG(DISTINCT mc.meal_name, ', ' ORDER BY mc.meal_name), '') AS complementary_dishes
                    FROM MealDetails md
                    LEFT JOIN meal_ingredients mi ON mi.meal_id = md.meal_id -- Corrected join
                    LEFT JOIN produce p ON mi.produce_id = p.produce_id -- Corrected join
                    LEFT JOIN meal_complementaries mcl ON mcl.meal_id = md.meal_id -- Corrected join
                    LEFT JOIN meals mc ON mcl.complementary_dish_id = mc.meal_id -- Corrected join
                    GROUP BY
                        md.meal_id, md.meal_name, md.meal_category, md.recipe, md.recipe_link, md.image_link,
                        md.goal, md.dietary_preference, md.allergies, md.disease_management,
                        md.cuisine_preferences, md.skill_level, md.prep_time, md.meal_description;
                """
                cursor.execute(sql_query)
                results = cursor.fetchall() # List of tuples
                columns = [desc[0] for desc in cursor.description]

                all_meals_list = []
                for row in results:
                    meal_dict = dict(zip(columns, row))
                    meal_dict['price'] = meal_dict.get('price', 10000)
                    for key, value in meal_dict.items():
                         if isinstance(value, (datetime, date)):
                              meal_dict[key] = value.isoformat()
                    all_meals_list.append(meal_dict)

                logger.info(f"Fetched {len(all_meals_list)} meals.")
                return {"All_Meals": all_meals_list, "success": True}

        except (psycopg2.Error, Exception) as e:
            logger.error(f"Error fetching all meals: {e}", exc_info=True)
            return {"error": "An internal error occurred while fetching meals.", "success": False}
        finally:
            if conn:
                logger.debug("Closing database connection.")
                conn.close()


# --- Payment Methods (No DB interaction, kept as is) ---
# ... (PayPal, Stripe, MoMo configuration and functions remain unchanged) ...
# PayPal configuration function
def configure_paypal(mode, client_id, client_secret):
    paypalrestsdk.configure({
        'mode': mode, # "sandbox" or "live"
        'client_id': client_id,
        'client_secret': client_secret
    })
    logger.info(f"PayPal SDK configured for mode: {mode}")

def create_payment_paypal(amount, description, currency="USD"): # Added currency
    """Creates a PayPal payment object."""
    try:
        formatted_amount = "{:.2f}".format(float(amount))
        payment = paypalrestsdk.Payment({
            "intent": "sale", "payer": {"payment_method": "paypal"},
            "transactions": [{"amount": {"total": formatted_amount, "currency": currency},"description": description}],
            "redirect_urls": {
                "return_url": f"{os.getenv('API_BASE_URL', apibaseurl)}/rr/execute",
                "cancel_url": f"{os.getenv('API_BASE_URL', apibaseurl)}/rr/cancel"
            }
        })
        if payment.create():
            approval_url = next((link.href for link in payment.links if link.rel == "approval_url"), None)
            if approval_url:
                logger.info(f"PayPal payment created. Approval URL: {approval_url}")
                return {"approval_url": approval_url, "payment_id": payment.id, "success": True}
            else: logger.error("PayPal payment created but no approval URL found."); return {"error": "Payment creation failed: No approval URL.", "success": False}
        else: logger.error(f"PayPal payment creation failed: {payment.error}"); return {"error": f"Payment creation failed: {payment.error.get('message', 'Unknown PayPal error')}", "success": False}
    except paypalrestsdk.exceptions.PayPalRESTfulException as pe: logger.error(f"PayPal API Error during creation: {pe}"); return {"error": f"PayPal API Error: {pe}", "success": False}
    except Exception as e: logger.error(f"Unexpected error creating PayPal payment: {e}", exc_info=True); return {"error": "An unexpected error occurred during payment creation.", "success": False}

def execute_payment_paypal(payment_id, payer_id):
    """Executes a PayPal payment."""
    try:
        payment = paypalrestsdk.Payment.find(payment_id)
        if payment.execute({"payer_id": payer_id}): logger.info(f"PayPal payment {payment_id} executed successfully. Status: {payment.state}"); return {"status": "success", "payment": payment.to_dict()}
        else: logger.error(f"PayPal payment execution failed for ID {payment_id}: {payment.error}"); return {"status": "failure", "error": payment.error.get('message', 'Unknown PayPal error')}
    except paypalrestsdk.exceptions.ResourceNotFound: logger.error(f"PayPal payment execution failed: Payment ID {payment_id} not found."); return {"status": "failure", "error": "Payment not found."}
    except paypalrestsdk.exceptions.PayPalRESTfulException as pe: logger.error(f"PayPal API Error during execution for ID {payment_id}: {pe}"); return {"status": "failure", "error": f"PayPal API Error: {pe}"}
    except Exception as e: logger.error(f"Unexpected error executing PayPal payment {payment_id}: {e}", exc_info=True); return {"status": "failure", "error": "An unexpected error occurred during payment execution."}

def handle_payment_cancellation_paypal():
    """Handles PayPal payment cancellation."""
    logger.info("PayPal payment cancelled by user."); return {"status": "cancelled", "message": "Payment was cancelled."}

# Stripe configuration function
def configure_stripe(secret_key):
    stripe.api_key = secret_key; logger.info("Stripe API key configured.")

def create_stripe_payment(amount, description="Payment for ZINZI Health Service", currency="usd"):
    """Creates a Stripe PaymentIntent."""
    try:
        amount_cents = int(round(float(amount) * 100))
        if amount_cents <= 0: logger.error("Stripe payment creation failed: Amount must be positive."); return {"status": "failure", "error": "Amount must be greater than zero"}
        payment_intent = stripe.PaymentIntent.create(amount=amount_cents, currency=currency.lower(), description=description)
        logger.info(f"Stripe PaymentIntent {payment_intent.id} created successfully.")
        return {"status": "success", "client_secret": payment_intent.client_secret, "intent_id": payment_intent.id}
    except stripe.error.StripeError as e: logger.error(f"Stripe API error during PaymentIntent creation: {e}"); return {"status": "failure", "error": str(e)}
    except Exception as e: logger.error(f"Unexpected error creating Stripe PaymentIntent: {e}", exc_info=True); return {"status": "failure", "error": "An unexpected server error occurred."}

def execute_stripe_payment(payment_intent_id, payment_method_id=None):
    """Confirms a Stripe PaymentIntent."""
    try:
        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        if intent.status == 'succeeded': logger.info(f"Stripe PaymentIntent {payment_intent_id} succeeded."); return {"status": "success", "payment": intent.to_dict()}
        elif intent.status == 'requires_action' or intent.status == 'requires_confirmation': logger.warning(f"Stripe PaymentIntent {payment_intent_id} requires further action (Status: {intent.status})."); return {"status": "requires_action", "client_secret": intent.client_secret, "message": "Payment requires further action."}
        else: logger.error(f"Stripe PaymentIntent {payment_intent_id} failed or is in unexpected state (Status: {intent.status})."); return {"status": "failure", "message": f"Payment status: {intent.status}"}
    except stripe.error.StripeError as e: logger.error(f"Stripe API error retrieving/confirming PaymentIntent {payment_intent_id}: {e}"); return {"status": "failure", "error": str(e)}
    except Exception as e: logger.error(f"Unexpected error checking Stripe PaymentIntent {payment_intent_id}: {e}", exc_info=True); return {"status": "failure", "error": "An unexpected server error occurred."}

def handle_stripe_payment_cancellation():
    """Handles Stripe payment cancellation."""
    logger.info("Stripe payment cancelled or abandoned."); return {"status": "cancelled", "message": "Payment was not completed."}

# MoMo Payment Logic
X_REFERENCE_ID = os.getenv("X_REFERENCE_ID")
MOMO_API_KEY = os.getenv("MOMO_API_KEY")
MOMO_SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")
MOMO_API_USER_ID = os.getenv("MOMO_API_USER_ID")
MOMO_BASE_URL = os.getenv("MOMO_BASE_URL", "https://sandbox.momodeveloper.mtn.com")
MOMO_TARGET_ENV = os.getenv("MOMO_TARGET_ENV", "sandbox")
MOMO_CALLBACK_URL = os.getenv("MOMO_CALLBACK_URL", momocallbackurl)
momo_headers = {}; momo_access_token = ""; momo_token_expires_at = 0

def get_momo_api_user_key(user_id: str, subscription_key: str) -> Optional[str]:
    """Generates an API Key for a specific API user."""
    if not user_id or not subscription_key: logger.error("MoMo API User ID and Subscription Key are required to generate API Key."); return None
    key_gen_url = f"{MOMO_BASE_URL}/v1_0/apiuser/{user_id}/apikey"; headers = {"Ocp-Apim-Subscription-Key": subscription_key}
    try:
        response = requests.post(key_gen_url, headers=headers); response.raise_for_status()
        api_key = response.json().get("apiKey")
        if api_key: logger.info(f"MoMo API Key generated successfully for user {user_id}."); return api_key
        else: logger.error(f"Failed to generate MoMo API Key for user {user_id}. Response: {response.text}"); return None
    except requests.exceptions.RequestException as e: logger.error(f"Error generating MoMo API Key for user {user_id}: {e}", exc_info=True); return None

def get_momo_access_token() -> bool:
    """Retrieves or refreshes the MoMo API access token."""
    global momo_access_token, momo_token_expires_at, momo_headers
    if not MOMO_API_USER_ID or not MOMO_SUBSCRIPTION_KEY: logger.critical("MoMo API User ID or Subscription Key not configured."); return False
    current_api_key = MOMO_API_KEY
    if not current_api_key: logger.critical("Failed to obtain MoMo API Key."); return False
    token_url = f"{MOMO_BASE_URL}/collection/token/"; auth_str = f"{MOMO_API_USER_ID}:{current_api_key}"; auth_header = base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization": f"Basic {auth_header}", "Ocp-Apim-Subscription-Key": MOMO_SUBSCRIPTION_KEY,}
    try:
        logger.info("Requesting MoMo Access Token..."); response = requests.post(token_url, headers=headers, timeout=15); response.raise_for_status()
        token_info = response.json(); momo_access_token = token_info.get("access_token"); expires_in = token_info.get("expires_in", 3500)
        momo_token_expires_at = time.time() + expires_in - 60
        if not momo_access_token: logger.error("Failed to retrieve MoMo access token: 'access_token' missing."); return False
        momo_headers = {
            "Authorization": f"Bearer {momo_access_token}", "X-Reference-Id": str(uuid.uuid4()),
            "X-Target-Environment": MOMO_TARGET_ENV, "Ocp-Apim-Subscription-Key": MOMO_SUBSCRIPTION_KEY,
            "Content-Type": "application/json",
        }
        logger.info("MoMo Access Token obtained successfully."); return True
    except requests.exceptions.RequestException as e: logger.error(f"Error requesting MoMo Access Token: {e}", exc_info=True); return False
    except Exception as e: logger.error(f"Unexpected error getting MoMo token: {e}", exc_info=True); return False

def ensure_momo_token() -> bool:
    """Checks if the token is valid and refreshes if necessary."""
    if time.time() >= momo_token_expires_at or not momo_access_token:
        logger.info("MoMo access token expired or needs refresh/fetch.")
        return get_momo_access_token()
    return True

def request_momo_payment(amount: float, currency: str, external_id: str, payer_number: str, payer_message: str, payee_note: str) -> Dict[str, Any]:
    """Initiates an MTN MoMo payment request."""
    if not ensure_momo_token(): return {"status": "failure", "error": "MoMo authentication failed."}
    request_url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay"; transaction_uuid = str(uuid.uuid4())
    current_headers = {**momo_headers, "X-Reference-Id": transaction_uuid}
    payload = {
        "amount": str(float(amount)), "currency": currency.lower(), "externalId": str(external_id),
        "payer": {"partyIdType": "MSISDN", "partyId": str(payer_number)},
        "payerMessage": str(payer_message), "payeeNote": str(payee_note),
    }
    try:
        logger.info(f"Requesting MoMo payment to {request_url} with ExtID: {external_id}, RefID: {transaction_uuid}")
        response = requests.post(request_url, json=payload, headers=current_headers, timeout=30)
        if response.status_code == 202: logger.info(f"MoMo payment request accepted (Ref: {transaction_uuid}). Awaiting confirmation."); return {"status": "pending", "transaction_ref": transaction_uuid, "message": "Awaiting user confirmation."}
        else:
            error_details = response.text; 
            try: error_details = response.json()
            except json.JSONDecodeError: pass
            logger.error(f"MoMo payment request failed (Status: {response.status_code}, Ref: {transaction_uuid}): {error_details}"); return {"status": "failure", "error": error_details}
    except requests.exceptions.RequestException as e: logger.error(f"Error requesting MoMo payment (Ref: {transaction_uuid}): {e}", exc_info=True); return {"status": "failure", "error": f"Network/API error: {e}"}
    except Exception as e: logger.error(f"Unexpected error in MoMo payment request (Ref: {transaction_uuid}): {e}", exc_info=True); return {"status": "failure", "error": "Unexpected server error."}

def check_momo_payment_status(transaction_ref: str) -> Dict[str, Any]:
    """Checks the status of an MTN MoMo payment."""
    if not ensure_momo_token(): return {"status": "failure", "error": "MoMo authentication failed."}
    status_url = f"{MOMO_BASE_URL}/collection/v1_0/requesttopay/{transaction_ref}"; current_headers = momo_headers
    try:
        logger.info(f"Checking MoMo payment status for Ref: {transaction_ref}"); response = requests.get(status_url, headers=current_headers, timeout=15); response.raise_for_status()
        payment_status_data = response.json(); logger.info(f"MoMo payment status for Ref {transaction_ref}: {payment_status_data.get('status')}")
        return {"status": "success", "payment_status": payment_status_data}
    except requests.exceptions.HTTPError as e:
         if e.response.status_code == 404: logger.warning(f"MoMo transaction ref '{transaction_ref}' not found."); return {"status": "not_found", "error": "Transaction reference not found."}
         else: error_details = e.response.text; 
         try: error_details = e.response.json()
         except json.JSONDecodeError: pass; logger.error(f"MoMo API error checking status (Ref {transaction_ref}, Status {e.response.status_code}): {error_details}"); return {"status": "failure", "error": error_details}
    except requests.exceptions.RequestException as e: logger.error(f"Error checking MoMo status (Ref {transaction_ref}): {e}", exc_info=True); return {"status": "failure", "error": f"Network/API error: {e}"}
    except Exception as e: logger.error(f"Unexpected error checking MoMo status (Ref {transaction_ref}): {e}", exc_info=True); return {"status": "failure", "error": "Unexpected server error."}


# --- Main Guard for Testing (Optional) ---
if __name__ == "__main__":
    print("Running example tests...")
    auth = Authentication()
    updatelists = Updatelists() # Need instance for helpers in Rec classes

    # Example: Test login (use a user known to exist and be verified)
    # Replace with an actual verified user email/name and password
    test_identifier = "bob.pointer@example.com" # Ensure this user exists and is verified
    test_password = "password456"
    login_result, status_code = auth.login_user(test_identifier, test_password)
    print(f"Login Result for {test_identifier} (Status {status_code}):", login_result)

    test_user_id = None
    # Corrected condition: check 'verified' key if present, or assume success if status is 200
    if login_result and login_result.get("verified", status_code == 200) and login_result.get("user_id"):
        test_user_id = login_result["user_id"]
    else:
        print(f"Login failed or user not suitable for testing ({login_result.get('message', 'Unknown login status')}), cannot proceed with user-specific tests.")
        # Optionally try to create a user here for testing if login fails reliably
        # ...

    # Example: Test fetching meals (runs regardless of login)
    meal_fetcher = GetAllMeals()
    all_meals_result = meal_fetcher.Fetch_All_Meals()
    if all_meals_result["success"]:
         print(f"\nFetched {len(all_meals_result['All_Meals'])} meals.")
         # print(json.dumps(all_meals_result['All_Meals'][:1], indent=2)) # Print first meal
    else:
         # FIXED: Removed colon
         print(f"\nFailed to fetch all meals: {all_meals_result.get('error')}")

    # Example: Test Recommendation V2 (only if login was successful)
    if test_user_id:
        print(f"\nTesting Meal Recommendation V2 for User ID: {test_user_id}")
        # Ensure user has metrics and preferences set up in the DB for meaningful results
        # Example: Add dummy preferences if needed for testing
        # pref_result = updatelists.add_user_preferences(test_user_id, 'weight loss', 'vegetarian', 'nuts', 'indian')
        # print("Preference update result:", pref_result)
        # Example: Add dummy metrics if needed for testing
        # metric_result = updatelists.add_user_metrics(test_user_id, '25-35', 80, 175, 200, 120, 80, 70, 'male', 'lightly active')
        # print("Metric update result:", metric_result)

        recommender = MealRecommendation2(test_user_id)
        recs = recommender.recommend_meals()
        if recs["success"]:
             print(f"Generated {len(recs['recommended_meals'])} recommendations for user {test_user_id}.")
             # print(json.dumps(recs['recommended_meals'][:1], indent=2)) # Print first recommendation
        else:
             # FIXED: Removed colon
             print(f"Failed to get recommendations for user {test_user_id}: {recs.get('error')}")
    else:
         print("\nSkipping recommendation test as login failed or user_id missing.")

    # FIXED: Removed trailing colon
    print("\nExample tests finished.")