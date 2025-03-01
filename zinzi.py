#Cspell:disable
import os
import json
import random
import string
from datetime import datetime, timedelta
from dotenv import load_dotenv
import bcrypt
import pyodbc
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
import base64
import time
from typing import Dict, Any, Optional, List


# Load the .env file
load_dotenv()

# Access the API base URL
apibaseurl = os.getenv('OR1', 'https://default.url')
momocallbackurl=os.getenv('OR11', 'https://default.url')

# Database connection
def get_db_connection():
    connection_string = (
        "Driver={ODBC Driver 17 for SQL Server};"
        "Server=localhost\\SQLExpress;"
        "Database=ZANZA;"
        "Trusted_Connection=Yes;"
        "TrustServerCertificate=Yes;"
    )
    try:
        connection = pyodbc.connect(connection_string)
        return connection
    except pyodbc.Error as e:
        print(f"Error: {e}")
        return None

class Authentication:
    def signup_user(self, name, email, password):
        hashed_password = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
        verification_code = self.generate_verification_code()

        try:
            connection = get_db_connection()
            if connection is None:
                print("Error: Database connection failed.")
                return None

            cursor = connection.cursor()

            # Check for unique email
            email_query = "SELECT COUNT(*) FROM Users WHERE Email = ?"
            cursor.execute(email_query, (email,))
            if cursor.fetchone()[0] > 0:
                print("Error: Email is already registered.")
                return None

            # Check for unique name
            name_query = "SELECT COUNT(*) FROM Users WHERE Name = ?"  # Added name check
            cursor.execute(name_query, (name,))
            if cursor.fetchone()[0] > 0:
                print("Error: Name is already taken.") # More descriptive message
                return None             

            insert_query = """
                INSERT INTO Users (Name, Email, Password, Date_created, Is_verified)
                OUTPUT INSERTED.User_id
                VALUES (?, ?, ?, GETDATE(), 0)
            """
            cursor.execute(insert_query, (name, email, hashed_password))
            user_id = cursor.fetchone()[0]
            connection.commit()

            self.send_verification_email(email, verification_code)

            verification_query = """
                INSERT INTO Email_Verifications (User_id, Verification_code, Expires_at)
                VALUES (?, ?, DATEADD(MINUTE, 15, SYSDATETIMEOFFSET()))
            """
            cursor.execute(verification_query, (user_id, verification_code))
            connection.commit()

            print(f"User '{name}' registered successfully. Verification email sent to {email}.")
            return user_id

        except pyodbc.Error as e:
            # More detailed error handling for debugging
            print(f"Error during signup: {e}")
            print(f"SQLSTATE: {e.args[0]}")  # Provide SQLSTATE for better diagnostics
            if hasattr(e, 'message'): # Print the message if it exists
                print(f"Message: {e.message}")
            return None
        finally:
            if connection:
                connection.close()

    def generate_verification_code(self): # Example implementation
        import random
        import string
        return ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

    def send_verification_email(self, email, verification_code):
        # Your email sending logic here.  This is a placeholder.
        print(f"Sending verification email to {email} with code {verification_code}")
        # Use a library like smtplib or a service like SendGrid, Mailgun, etc.
        pass # Replace with your email sending code.

    def login_user(self, identifier, password):
        try:
            connection = get_db_connection()
            if connection is None:
                return {'message': 'Failed to connect to the database'}, 500

            cursor = connection.cursor()
            query = "SELECT User_id, Password, Is_verified FROM Users WHERE Name = ? OR Email = ?"
            cursor.execute(query, (identifier, identifier))
            result = cursor.fetchone()

            if not result:
                return {'message': 'Invalid credentials or account not verified'}, 401

            user_id, stored_hashed_password, verified = result

            if bcrypt.checkpw(password.encode(), stored_hashed_password.encode()):
                if not verified:
                    return {'message': 'Account not verified. Check your email for the verification code.'}, 403
                return {'message': 'Login successful', 'user_id': user_id}, 200
            else:
                return {'message': 'Invalid credentials or account not verified'}, 401
        except pyodbc.Error as e:
            print(f"Error during login: {e}")
            return {'message': 'Error during login'}, 500
        finally:
            if connection:
                connection.close()

#new improved email logic
    def send_verification_email(self, to_email, verification_code):
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None

        # Load existing credentials if available
        if os.path.exists('token.json'):
            try:
                creds = Credentials.from_authorized_user_file('token.json', SCOPES)
            except Exception as e:
                print(f"Error loading token.json: {e}")

        # Check and refresh credentials
        if creds:
            try:
                if creds.expired and creds.refresh_token:
                    creds.refresh(Request())
                elif creds.expiry and creds.expiry < datetime.now() + timedelta(minutes=10):
                    creds.refresh(Request())
            except Exception as e:
                print(f"Error refreshing token: {e}")
                creds = None

        # Prompt for new credentials if needed
        if not creds or not creds.valid:
            flow = InstalledAppFlow.from_client_secrets_file(
                'client_secret_769800441200-vlojtkiqv165kbumgmjsku2rbm97h217.apps.googleusercontent.com.json', SCOPES)
            creds = flow.run_local_server(port=8080)

        # Save new credentials to token.json
        with open('token.json', 'w') as token:
            token.write(creds.to_json())

        # Build Gmail API service
        service = build('gmail', 'v1', credentials=creds)

        subject = "Your ZINZI Verification Code"
        body = f"Your verification code is: {verification_code}\nPlease enter this code in the ZINZI app to verify your account."

        # Create and encode the email message
        message = MIMEText(body)
        message['to'] = to_email
        message['subject'] = subject
        raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()

        try:
            # Send the email
            send_message = service.users().messages().send(
                userId="me",
                body={'raw': raw_message}
            ).execute()

            print(f"Verification email sent to {to_email}. Message ID: {send_message['id']}")
        except Exception as e:
            print(f"Error sending email: {e}")

    def generate_verification_code(self):
        return ''.join(random.choices(string.digits, k=6))

    def verify_user_email(self, user_id, verification_code):
        try:
            connection = get_db_connection()
            if connection is None:
                return {'message': 'Failed to connect to the database'}, 500

            cursor = connection.cursor()

            # Check if the verification code exists and is not expired
            query = """
                SELECT Verification_code, Expires_at 
                FROM Email_Verifications 
                WHERE User_id = ? AND Verification_code = ? AND Expires_at > SYSDATETIMEOFFSET()
            """
            cursor.execute(query, (user_id, verification_code))
            result = cursor.fetchone()

            if not result:
                return {'message': 'Invalid or expired verification code'}, 400

            # Update the user's account to verified
            update_query = "UPDATE Users SET Is_verified = 1 WHERE User_id = ?"
            cursor.execute(update_query, (user_id,))
            connection.commit()

            # Remove the verification code after successful verification
            delete_query = "DELETE FROM Email_Verifications WHERE User_id = ?"
            cursor.execute(delete_query, (user_id,))
            connection.commit()

            return {'message': 'Email verification successful'}, 200
        except Exception as e:
            print(f"Error during email verification: {e}")
            return {'message': 'Error during email verification'}, 500
        finally:
            if connection:
                connection.close()




class Updatelists:
    def __init__(self):
        pass

    # Add or update user metrics
    def add_user_metrics(self, user_id, age_range, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, sex, activity_level):
        try:
            # Convert all inputs to float (except sex and activity_level)
            weight, height, cholesterol_level, sys_bp, dia_bp, pulse = map(float, [weight, height, cholesterol_level, sys_bp, dia_bp, pulse])
        except ValueError as e:
            print(f"ValueError: {e} - Ensure all numeric values are correctly passed.")
            return {"error": f"Invalid input: {e}", "success": False}

        # Calculate metrics
        bmi = self.calculate_bmi(weight, height)
        bmi_category = self.calculate_bmi_category(bmi)
        ideal_weight = self.calculate_ideal_weight(height, sex)
        bmr = self.calculate_bmr(weight, height, age_range, sex)
        daily_calories = self.calculate_daily_calories(bmr, activity_level)

        try:
            connection = get_db_connection()
            if connection is None:
                return {"error": "Database connection failed", "success": False}

            cursor = connection.cursor()
            query = "SELECT COUNT(*) FROM User_metrics WHERE User_id = ?"
            cursor.execute(query, (user_id,))
            if cursor.fetchone()[0] > 0:
                update_query = """
                    UPDATE User_metrics
                    SET Weight = ?, Height = ?, Cholestrol_level = ?, Sys_bp = ?, Dia_bp = ?, Pulse = ?, Age_range = ?, Sex = ?, Activity_level = ?, 
                        BMI = ?, BMI_category = ?, Ideal_weight = ?, BMR = ?, Daily_calories = ?, Recorded_at = GETDATE()
                    WHERE User_id = ?
                """
                cursor.execute(update_query, (weight, height, cholesterol_level, sys_bp, dia_bp, pulse, age_range, sex, activity_level,
                                              bmi, bmi_category, ideal_weight, bmr, daily_calories, user_id))
                message = f"Updated metrics for user ID {user_id}."
            else:
                insert_query = """
                    INSERT INTO User_metrics (User_id, Weight, Height, Cholestrol_level, Sys_bp, Dia_bp, Pulse, Age_range, Sex, Activity_level, 
                                              BMI, BMI_category, Ideal_weight, BMR, Daily_calories, Recorded_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
                """
                cursor.execute(insert_query, (user_id, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, age_range, sex, activity_level,
                                              bmi, bmi_category, ideal_weight, bmr, daily_calories))
                message = f"Added metrics for user ID {user_id}."
            connection.commit()
            # Log the metrics in history
            self.log_user_metrics(user_id, weight)
            return {"message": message, "success": True}
        except pyodbc.Error as e:
            return {"error": f"Error updating metrics: {e}", "success": False}
        finally:
            if connection:
                connection.close()

    def get_user_metrics(self, user_id):
        """
        Fetch user metrics from the database.

        Args:
            user_id: The ID of the user.

        Returns:
            A dictionary containing the user's metrics 
            or an error message if the query fails.
        """
        try:
            connection = get_db_connection()
            if connection is None:
                return {"error": "Database connection failed", "success": False}

            cursor = connection.cursor()
            query = """
                SELECT Weight, Height, Cholestrol_level, Sys_bp, Dia_bp, Pulse, 
                       Age_range, BMI, BMI_category, Ideal_weight, BMR, 
                       Daily_calories, Recorded_at, Sex
                FROM User_metrics
                WHERE User_id = ?
            """
            cursor.execute(query, (user_id,))
            result = cursor.fetchone()

            if result:
                recorded_at = result[12]
                iso_format = recorded_at.isoformat()
                return {
                    'weight': result[0],
                    'height': result[1],
                    'cholesterol_level': result[2],
                    'sys_bp': result[3],
                    'dia_bp': result[4],
                    'pulse': result[5],
                    'age_range': result[6],
                    'bmi': result[7],
                    'bmi_category': result[8],
                    'ideal_weight': result[9],
                    'bmr': result[10],
                    'daily_calories': result[11],
                    'recorded_at': iso_format,
                    'sex': result[13]
                }
            else:
                return {"message": f"No metrics found for user ID {user_id}.", "success": False}

        except pyodbc.Error as e:
            return {"error": f"Error fetching metrics: {e}", "success": False}

        finally:
            if connection:
                connection.close()

    # Fetch user preferences
    def fetch_user_preferences(self, user_id):
        try:
            connection = get_db_connection()
            if connection is None:
                return {"error": "Failed to connect to the database", "success": False}

            cursor = connection.cursor()
            query = "SELECT User_id, Goals, Diet_type, Food_restrictions FROM User_preferences WHERE User_id = ?"
            cursor.execute(query, (user_id,))
            result = cursor.fetchone()
            if result:
                return {
                    'user_id': result[0],
                    'goals': result[1],
                    'diet_type': result[2],
                    'food_restrictions': result[3]
                }
            else:
                return {"message": f"No preferences found for user ID {user_id}.", "success": False}
        except pyodbc.Error as e:
            return {"error": f"Error fetching user preferences: {e}", "success": False}
        finally:
            if connection:
                connection.close()

    # Add or update user preferences
    def add_user_preferences(self, user_id, goals, diet_type, food_restrictions):
        try:
            connection = get_db_connection()
            if connection is None:
                return {"error": "Failed to connect to the database", "success": False}

            cursor = connection.cursor()
            query = "SELECT COUNT(*) FROM User_preferences WHERE User_id = ?"
            cursor.execute(query, (user_id,))
            if cursor.fetchone()[0] > 0:
                update_query = """
                    UPDATE User_preferences
                    SET Goals = ?, Diet_type = ?, Food_restrictions = ?
                    WHERE User_id = ?
                """
                cursor.execute(update_query, (goals, diet_type, food_restrictions, user_id))
                connection.commit()
                return {"message": f"Updated preferences for user ID {user_id}.", "success": True}
            else:
                insert_query = """
                    INSERT INTO User_preferences (User_id, Goals, Diet_type, Food_restrictions)
                    VALUES (?, ?, ?, ?)
                """
                cursor.execute(insert_query, (user_id, goals, diet_type, food_restrictions))
                connection.commit()
                return {"message": f"Added preferences for user ID {user_id}.", "success": True}
        except pyodbc.Error as e:
            return {"error": f"Error updating preferences: {e}", "success": False}
        finally:
            if connection:
                connection.close()

    # Supporting calculation methods
    def calculate_bmi(self, weight, height):
        height_in_meters = height / 100
        return weight / (height_in_meters ** 2)

    def calculate_bmi_category(self, bmi):
        if bmi < 18.5:
            return 'Underweight'
        elif 18.5 <= bmi < 24.9:
            return 'Normal weight'
        elif 25 <= bmi < 29.9:
            return 'Overweight'
        else:
            return 'Obesity'

    def calculate_ideal_weight(self, height, sex):
        if sex == 'Male':
            return 50 + 0.91 * (height - 152)
        else:
            return 45.5 + 0.91 * (height - 152)

    def calculate_bmr(self, weight, height, age_range, sex):
        age = self.convert_age_range_to_age(age_range)
        if sex == 'Male':
            return 10 * weight + 6.25 * height - 5 * age + 5
        else:
            return 10 * weight + 6.25 * height - 5 * age - 161

    def calculate_daily_calories(self, bmr, activity_level):
        activity_multiplier = {
            'Sedentary': 1.2,
            'Lightly active': 1.375,
            'Moderately active': 1.55,
            'Very active': 1.725,
            'Extremely active': 1.9
        }
        return bmr * activity_multiplier.get(activity_level, 1.2)

    def convert_age_range_to_age(self, age_range):
        try:
            age_min, age_max = map(int, age_range.split('-'))
            return (age_min + age_max) // 2
        except ValueError:
            print(f"Error: Invalid age range format {age_range}")
            return 30

    # Log metrics
    def log_user_metrics(self, user_id, weight):
        try:
            connection = get_db_connection()
            if connection is None:
                return {"success": False, "message": "Failed to log metrics: Database connection failed."}

            cursor = connection.cursor()
            insert_query = """
                INSERT INTO Metrics_history (User_id, Weight, Logged_at)
                VALUES (?, ?, CONVERT(VARCHAR(30), GETDATE(), 127))
            """
            cursor.execute(insert_query, (user_id, weight))
            connection.commit()

            return {"success": True, "message": "Metrics logged successfully."}
        except pyodbc.Error as e:
            return {"success": False, "message": f"Error logging metrics: {e}"}
        finally:
            if connection:
                connection.close()

# Retrieve metrics history
    def get_metrics_history(self, user_id):
        try:
            connection = get_db_connection()
            if connection is None:
                return {"error": "Database connection failed", "success": False}

            cursor = connection.cursor()
            query = """
                SELECT Weight, Logged_at
                FROM Metrics_history
                WHERE User_id = ?
                ORDER BY Logged_at ASC
            """
            cursor.execute(query, (user_id,))
            results = cursor.fetchall()
            return [{"weight": row[0], "logged_at": row[1].isoformat()} for row in results]
        except pyodbc.Error as e:
            return {"error": f"Error fetching metrics history: {e}", "success": False}
        finally:
            if connection:
                connection.close()

    #adding chefs
    def add_chef(self, data):
        """Inserts chef data into the database."""
        try:
            conn = get_db_connection() # Assuming you have get_db_connection() defined
            cursor = conn.cursor()

            languages_string = ', '.join(data['languages'])
            print(f"Languages List: {data['languages']}")
            print(f"Languages String: {languages_string}")
            print(f"Languages String (repr): {repr(languages_string)}")

            for language in data['languages']:
                if not isinstance(language, str):
                    print(f"Non-string language found: {language}, type: {type(language)}")

            cursor.execute('''
                INSERT INTO Chefs (
                    Image,
                    Name, Price, 
                    Location, Experience,
                    ResponseTime, MinNotice,
                    TeamSize, Equipment, Bio,
                    Availability, Languages, Specialties,
                    Certifications, SampleMenu
                    -- temporarily commenting out this Rating, ServiceRadius, Punctuality, Reviews
                )
                -- temporarily commenting out this VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        data['image'],
        data['name'], data['price'], 
        data['location'], data['experience'],
        data['response_time'], data['min_notice'],
        data['team_size'], ','.join(data['equipment']), data['bio'], 
        ', '.join(data['availability']),
        languages_string,
        ', '.join(data['specialties']),
        ', '.join(data['certifications']),
        ', '.join(data['sample_menu'])
        # temporarily commenting out this line data['rating'], data['service_radius'], data['punctuality'], str(data['reviews']) #commented out for now
    ))

            # Commit the transaction
            conn.commit()
            return True
        except Exception as e:
            import traceback
            print(f"Error occurred while adding chef: {e}")
            print(traceback.format_exc())
            return False
        finally:
            cursor.close()
            conn.close()

#fetching chefs
    def get_chefs(self):
        try:
            conn = get_db_connection()
            cursor = conn.cursor()

            cursor.execute('SELECT * FROM Chefs')
        
            columns = [column[0] for column in cursor.description]
            chefs = []
            for row in cursor.fetchall():
                chef = dict(zip(columns, row))
            
            # Deserialize array fields back to lists if necessary
                chef['Languages'] = chef['Languages'].split(', ') if chef['Languages'] else []
                chef['Specialties'] = chef['Specialties'].split(', ') if chef['Specialties'] else []
                chef['Certifications'] = chef['Certifications'].split(', ') if chef['Certifications'] else []
                chef['SampleMenu'] = chef['SampleMenu'].split(', ') if chef['SampleMenu'] else []
                chef['Availability'] = chef['Availability'].split(', ') if chef['Availability'] else []
                chef['Equipment'] = chef['Equipment'].split(',') if chef['Equipment'] else []
            # You can include deserialization for other fields as necessary
            
            # Return all fields as is
                chefs.append(chef)

            return chefs
        except Exception as e:
            print("Error occurred while retrieving chefs:", str(e))
            return []
        finally:
            cursor.close()
            conn.close()


    # Add product to catalog
    def add_product_to_catalog(self, product_name, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, meal_id=None):
        try:
            connection = get_db_connection()
            if connection is None:
                return
            cursor = connection.cursor()

            insert_query = """
                INSERT INTO Product_catalog 
                (Product_name, Calories, Cholestrol_content, Protein_content, Carbohydrate_content, Fat_content, Nutrition_details, Meal_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
            cursor.execute(insert_query, (product_name, calories, cholesterol_content, protein_content, carbohydrate_content, fat_content, nutrition_details, meal_id))
            connection.commit()
            print(f"Product '{product_name}' added successfully to the catalog.")
        except pyodbc.Error as e:
            print(f"Error adding product: {e}")
        finally:
            if connection:
                connection.close()


    # Update meal data
    def update_meal_data(self, meal_id, meal_name, products):
        """
        Update meal data in the database based on contributions from products.
        """
        try:
            # Calculate total contribution of all products
            total_calories, total_cholesterol, total_protein, total_carbs, total_fat = self.calculate_nutritional_contributions(products)

            # Update meal data in the database
            connection = get_db_connection()
            if connection is None:
                return
            cursor = connection.cursor()

            update_query = """
                UPDATE Meal_data 
                SET MealName = ?, Calories = ?, Cholesterol_content = ?, Protein_content = ?, Carbohydrate_content = ?, Fat_content = ?, Nutrition_details = ?
                WHERE Meal_id = ?
            """
            cursor.execute(update_query, (meal_name, total_calories, total_cholesterol, total_protein, total_carbs, total_fat, "Updated nutritional details based on product contribution", meal_id))
            connection.commit()
            print(f"Meal with ID {meal_id} updated successfully.")
        except pyodbc.Error as e:
            print(f"Error updating meal data: {e}")

    # Add meal data
    def add_meal_data(self, meal_name, products, user_id):
        """
        Add new meal data to the database based on contributions from products.
        """
        try:
            # Calculate total contribution of all products
            total_calories, total_cholesterol, total_protein, total_carbs, total_fat = self.calculate_nutritional_contributions(products)

            # Add new meal data to the database
            connection = get_db_connection()
            if connection is None:
                return
            cursor = connection.cursor()

            insert_query = """
                INSERT INTO Meal_data 
                (MealName, Calories, Cholesterol_content, Protein_content, Carbohydrate_content, Fat_content, Nutrition_details, User_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
            cursor.execute(insert_query, (meal_name, total_calories, total_cholesterol, total_protein, total_carbs, total_fat, "Nutritional details calculated based on product contribution", user_id))
            connection.commit()
            print(f"New meal '{meal_name}' added successfully.")
        except pyodbc.Error as e:
            print(f"Error adding new meal data: {e}")
        finally:
            if connection:
                connection.close()

    # Calculate nutritional contributions
    def calculate_nutritional_contributions(self, products):
        """
        Calculate the total nutritional values for a meal based on product contributions.
        """
        total_calories = 0
        total_cholesterol = 0
        total_protein = 0
        total_carbs = 0
        total_fat = 0

        for product in products:
            percentage_contribution = product['PercentageContribution'] / 100.0
            total_calories += product['Calories'] * percentage_contribution
            total_cholesterol += product['Cholestrol_content'] * percentage_contribution
            total_protein += product['Protein_content'] * percentage_contribution
            total_carbs += product['Carbohydrate_content'] * percentage_contribution
            total_fat += product['Fat_content'] * percentage_contribution

        return total_calories, total_cholesterol, total_protein, total_carbs, total_fat
        

'''import pyodbc
import logging
from typing import List, Dict

def get_db_connection():
    try:
        conn = pyodbc.connect('DRIVER={SQL Server};SERVER=server;DATABASE=db;Trusted_Connection=yes;')
        return conn
    except pyodbc.Error as e:
        logging.error(f"Database connection failed: {e}")
        return None

class MealRecommendation:
    def __init__(self, user_id: str):
        self.user_id = user_id
        self.user_data = self.get_user_data()

    def get_user_data(self) -> Dict:
        try:
            connection = get_db_connection()
            if not connection:
                return None
            cursor = connection.cursor()
            query = """
            SELECT um.Weight, um.Cholesterol_level, up.Diet_type, up.Goal, up.allergies,
                   up.disease_management, up.cuisine_preferences, up.cooking_skill_level,
                   up.prep_time, up.calorie_limit
            FROM User_metrics um
            JOIN User_preferences up ON um.User_id = up.User_id
            WHERE um.User_id = ?
            """
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()
            connection.close()
            if result:
                return {
                    "weight": result[0],
                    "cholesterol_level": result[1],
                    "dietary_preferences": result[2].split(",") if result[2] else [],
                    "goal": result[3],
                    "allergies": result[4].split(",") if result[4] else [],
                    "disease_management": result[5].split(",") if result[5] else [],
                    "cuisine_preferences": result[6].split(",") if result[6] else [],
                    "cooking_skill_level": result[7],
                    "prep_time": result[8],
                    "calorie_limit": result[9]
                }
            logging.warning(f"No data for user {self.user_id}")
            return None
        except pyodbc.Error as e:
            logging.error(f"Error fetching user data: {e}")
            return None

    def recommend_meals(self) -> List[Dict]:
        if not self.user_data:
            return []
        
        user_data = self.user_data
        dietary_prefs = user_data["dietary_preferences"]
        goal = user_data["goal"]
        weight = user_data["weight"]
        calorie_limit = user_data["calorie_limit"]

        # Adjust calorie limit with weight (simple approximation: 15 kcal/kg base)
        base_calories = weight * 15 if weight else calorie_limit
        if goal == "Lose Weight":
            effective_calorie_limit = base_calories * 0.85
        elif goal == "Gain Weight":
            effective_calorie_limit = base_calories * 1.15
        else:
            effective_calorie_limit = base_calories

        connection = get_db_connection()
        if not connection:
            return []
        cursor = connection.cursor()

        placeholders = ",".join(["?"] * len(dietary_prefs))
        meal_query = f"""
        SELECT Meal_id, Meal_name, Ingredients, Allergies, Disease_management,
               Cuisine_preferences, Skill_level, Prep_time
        FROM Meal
        WHERE Dietary_preference IN ({placeholders}) AND Goal = ? AND Skill_level = ? AND Prep_time = ?
        """
        cursor.execute(meal_query, dietary_prefs + [goal, user_data["cooking_skill_level"], user_data["prep_time"]])
        meals = cursor.fetchall()

        produce_ids = set()
        for meal in meals:
            if meal[2]:
                produce_ids.update(pid.strip() for pid in meal[2].split(","))

        produce_dict = {}
        if produce_ids:
            produce_query = f"""
            SELECT Produce_id, Produce_name, Calories, Proteins, Carbohydrates, Fats
            FROM Produce
            WHERE Produce_id IN ({','.join(['?' for _ in produce_ids])})
            """
            cursor.execute(produce_query, list(produce_ids))
            produce_data = cursor.fetchall()
            produce_dict = {row[0]: row[1:] for row in produce_data}

        recommendations = []
        for meal in meals:
            meal_id, meal_name, ingredients_str, allergies_str, disease_mgmt_str, cuisine_str, skill, prep = meal
            ingredients = [pid.strip() for pid in ingredients_str.split(",")] if ingredients_str else []
            allergies = [a.strip() for a in allergies_str.split(",")] if allergies_str else []
            disease_mgmt = [dm.strip() for dm in disease_mgmt_str.split(",")] if disease_mgmt_str else []
            cuisines = [c.strip() for c in cuisine_str.split(",")] if cuisine_str else []

            if any(allergy in allergies for allergy in user_data["allergies"]):
                continue
            if user_data["disease_management"] and not any(dm in disease_mgmt for dm in user_data["disease_management"]):
                continue
            if user_data["cuisine_preferences"] and not any(c in user_data["cuisine_preferences"] for c in cuisines):
                continue

            total_calories = total_proteins = total_carbs = total_fats = 0
            ingredient_details = []
            for pid in ingredients:
                if pid in produce_dict:
                    name, cal, prot, carb, fat = produce_dict[pid]
                    total_calories += cal
                    total_proteins += prot
                    total_carbs += carb
                    total_fats += fat
                    ingredient_details.append({"Produce": name, "Calories": cal, "Proteins": prot, "Carbohydrates": carb, "Fats": fat})
                else:
                    logging.warning(f"Produce_id {pid} not found for meal {meal_name}")

            # Check nutritional balance (e.g., protein > 10% of calories, assuming 4 kcal/g)
            protein_calories = total_proteins * 4
            if total_calories > 0 and protein_calories / total_calories < 0.1:
                continue

            if (goal == "Lose Weight" and total_calories <= effective_calorie_limit) or \
               (goal == "Gain Weight" and total_calories >= effective_calorie_limit) or \
               (goal == "Maintain Weight" and abs(total_calories - effective_calorie_limit) <= 100):
                recommendations.append({
                    "Meal Name": meal_name,
                    "Ingredients": ingredient_details,
                    "Nutrition": {"Calories": total_calories, "Proteins": total_proteins, "Carbohydrates": total_carbs, "Fats": total_fats}
                })

        connection.close()
        return recommendations'''


# Database connection
def get_db_connection():
    connection_string = (
        "Driver={ODBC Driver 17 for SQL Server};"
        "Server=localhost\\SQLExpress;"
        "Database=ZANZA;"
        "Trusted_Connection=Yes;"
        "TrustServerCertificate=Yes;"
    )
    try:
        connection = pyodbc.connect(connection_string)
        return connection
    except pyodbc.Error as e:
        print(f"Error: {e}")
        return None

#a test meal recommendation algorithm version 1
class MealRecommendation1:
    def __init__(self, user_id):
        self.user_id = user_id
        self.user_preferences = self.get_user_preferences()
        self.user_metrics = self.get_user_metrics()

    def get_user_preferences(self):
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = "SELECT Goals, Diet_type, Food_restrictions, Cuisine_preferences FROM User_preferences WHERE User_id = ?"
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()
            
            if result:
                return {
                    "goals": result[0],
                    "diet_type": result[1],
                    "food_restrictions": result[2].split(",") if result[2] else [],
                    "cuisine_preferences": result[3].split(",") if result[3] else []
                }
            else:
                logging.warning(f"No preferences found for user_id {self.user_id}.")
                return None
                
        except pyodbc.Error as e:
            logging.error(f"Error fetching user preferences: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def get_user_metrics(self):
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = """
                SELECT Weight, Height, Cholesterol_level, Sys_bp, Dia_bp, Pulse, Age_range, Sex
                FROM User_metrics
                WHERE User_id = ?
            """
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()

            if result:
                return {
                    "weight": result[0],
                    "height": result[1],
                    "cholesterol_level": result[2],
                    "sys_bp": result[3],
                    "dia_bp": result[4],
                    "pulse": result[5],
                    "age_range": result[6],
                    "sex": result[7]
                }
            else:
                logging.warning(f"No metrics found for user_id {self.user_id}.")
                return None

        except pyodbc.Error as e:
            logging.error(f"Error fetching user metrics: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def fetch_all_meals(self):
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            # Your previous SQL query to fetch all meal details
            sql_query = """ 
            WITH MealDetails AS ( 
                SELECT 
                    m.Meal_id,
                    m.Meal_name,
                    m.Meal_category,
                    m.Recipe,
                    m.Recipe_link,
                    m.Image_link,
                    m.Goal,
                    m.Dietary_preference,
                    m.Allergies,
                    m.Disease_management,
                    m.Cuisine_preferences,
                    m.Skill_level,
                    m.Prep_time,
                    m.Meal_description
                FROM Meals m
            )
            SELECT 
                md.*,
                (SELECT STRING_AGG(p.Produce_name, ', ') 
                 FROM Meal_ingredients i
                 JOIN Produce p ON i.Produce_id = p.Produce_id
                 WHERE i.Meal_id = md.Meal_id) AS Ingredients
            FROM MealDetails md;
            """
            cursor.execute(sql_query)
            results = cursor.fetchall()

            columns = [column[0] for column in cursor.description]

            meal_recommendations = []
            for row in results:
                row_dict = dict(zip(columns, row))
                meal_recommendations.append(row_dict)
            
            return meal_recommendations

        except pyodbc.Error as e:
            logging.error(f"Error fetching meals: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def filter_meals(self):
        meals = self.fetch_all_meals()
        if not meals:
            return []
        
        filtered_meals = []
        diet_type = self.user_preferences['diet_type']
        food_restrictions = self.user_preferences['food_restrictions']
        cuisine_preferences = self.user_preferences['cuisine_preferences']

        for meal in meals:
            if diet_type not in meal['Dietary_preference'].split(", "):
                continue
            
            if any(allergen in meal['Allergies'].split(", ") for allergen in food_restrictions):
                continue

            if not any(cuisine in meal['Cuisine_preferences'].split(", ") for cuisine in cuisine_preferences):
                continue

            # Calculate calories
            meal['Calories'] = self.calculate_calories(meal)
            filtered_meals.append(meal)
        
        return filtered_meals

    def calculate_calories(self, meal):
        total_calories = 0
        ingredients = meal['Ingredients'].split(", ")
        try:
            for ingredient in ingredients:
                calorie_count = self.fetch_calorie_count(ingredient.strip())
                total_calories += calorie_count
        except Exception as e:
            logging.error(f"Error calculating calories for meal ID {meal['Meal_id']}: {e}")
        return total_calories

    def fetch_calorie_count(self, ingredient_name):
        try:
            connection = get_db_connection()
            cursor = connection.cursor()
            query = "SELECT Calories FROM Produce WHERE Produce_name = ?"
            cursor.execute(query, (ingredient_name,))
            result = cursor.fetchone()
            return result[0] if result else 0
        except Exception as e:
            logging.error(f"Error fetching calorie count for ingredient {ingredient_name}: {e}")
            return 0
        finally:
            if connection:
                connection.close()

    def recommend_meals(self):
        if not self.user_preferences or not self.user_metrics:
            return {"error": "User preferences or metrics not found."}
        
        recommended_meals = self.filter_meals()
        return {"recommended_meals": recommended_meals, "success": True}

# Example usage:
# user_id = 138  # User ID to fetch recommendations for
# meal_recommender = MealRecommendation(user_id)
# recommendations = meal_recommender.recommend_meals()
# print(recommendations)



# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# Database connection
def get_db_connection():
    connection_string = (
        "Driver={ODBC Driver 17 for SQL Server};"
        "Server=localhost\\SQLExpress;"
        "Database=ZANZA;"
        "Trusted_Connection=Yes;"
        "TrustServerCertificate=Yes;"
    )
    try:
        connection = pyodbc.connect(connection_string)
        return connection
    except pyodbc.Error as e:
        print(f"Error: {e}")
        return None

#a more accomodative, more robust recommendation algorithm version 2
class MealRecommendation2:
    def __init__(self, user_id: int):
        self.user_id = user_id
        self.user_preferences = self.get_user_preferences()
        self.user_metrics = self.get_user_metrics()
        self.daily_calorie_budget = self.calculate_daily_calorie_budget()

    def get_user_preferences(self) -> Optional[Dict]:
        """Fetch user preferences from the database."""
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = """
                SELECT Goals, Diet_type, Food_restrictions, Cuisine_preferences, Activity_level
                FROM User_preferences
                WHERE User_id = ?
            """
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()

            if result:
                return {
                    "goals": result[0].strip().lower() if result[0] else None,
                    "diet_type": result[1].strip().lower() if result[1] else None,
                    "food_restrictions": [x.strip().lower() for x in result[2].split(",")] if result[2] else [],
                    "cuisine_preferences": [x.strip().lower() for x in result[3].split(",")] if result[3] else [],
                    "activity_level": result[4].strip().lower() if result[4] else "sedentary",
                }
            else:
                logging.warning(f"No preferences found for user_id {self.user_id}.")
                return None

        except pyodbc.Error as e:
            logging.error(f"Error fetching user preferences: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def get_user_metrics(self) -> Optional[Dict]:
        """Fetch user health metrics from the database."""
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = """
                SELECT Weight, Height, Cholesterol_level, Sys_bp, Dia_bp, Pulse, Age_range, Sex
                FROM User_metrics
                WHERE User_id = ?
            """
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()

            if result:
                return {
                    "weight": result[0],  # in kg
                    "height": result[1],  # in cm
                    "cholesterol_level": result[2],
                    "sys_bp": result[3],
                    "dia_bp": result[4],
                    "pulse": result[5],
                    "age_range": result[6],
                    "sex": result[7].strip().lower() if result[7] else "male",
                }
            else:
                logging.warning(f"No metrics found for user_id {self.user_id}.")
                return None

        except pyodbc.Error as e:
            logging.error(f"Error fetching user metrics: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def calculate_daily_calorie_budget(self) -> float:
        """Calculate the user's daily calorie budget based on TDEE and health goals."""
        if not self.user_metrics or not self.user_preferences:
            logging.warning("User metrics or preferences not found. Using default calorie budget.")
            return 2000  # Default calorie budget

        weight = self.user_metrics["weight"]
        height = self.user_metrics["height"]
        age = int(self.user_metrics["age_range"].split("-")[0])
        sex = self.user_metrics["sex"]

        if sex == "male":
            bmr = 10 * weight + 6.25 * height - 5 * age + 5
        else:
            bmr = 10 * weight + 6.25 * height - 5 * age - 161

        activity_level = self.user_preferences.get("activity_level", "sedentary")
        activity_factors = {
            "sedentary": 1.2,
            "lightly active": 1.375,
            "moderately active": 1.55,
            "very active": 1.725,
            "extra active": 1.9,
        }
        tdee = bmr * activity_factors.get(activity_level, 1.2)

        goals = self.user_preferences.get("goals")
        if goals == "weight loss":
            tdee -= 500
        elif goals == "muscle gain":
            tdee += 500

        return tdee

    def fetch_all_meals(self) -> Optional[List[Dict]]:
        """Fetch all meals from the database with calorie calculations."""
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = """
                SELECT 
                    m.Meal_id,
                    m.Meal_name,
                    m.Meal_category,
                    m.Recipe,
                    m.Recipe_link,
                    m.Image_link,
                    m.Goal,
                    m.Dietary_preference,
                    m.Allergies,
                    m.Disease_management,
                    m.Cuisine_preferences,
                    m.Skill_level,
                    m.Prep_time,
                    m.Meal_description,
                    p.Calories,  -- Calories per unit
                    p.Unit_grams  -- Unit weight in grams
                FROM Meals m
                LEFT JOIN Meal_ingredients mi ON m.Meal_id = mi.Meal_id
                LEFT JOIN Produce p ON mi.Produce_id = p.Produce_id
            """
            cursor.execute(query)
            results = cursor.fetchall()

            columns = [column[0] for column in cursor.description]
            meals = [dict(zip(columns, row)) for row in results]

            # Strip and lowercase all string fields in meals
            for meal in meals:
                for key, value in meal.items():
                    if isinstance(value, str):
                        meal[key] = value.strip().lower()

            return meals

        except pyodbc.Error as e:
            logging.error(f"Error fetching meals: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def calculate_calorie_density(self, meal) -> float:
        """Calculate the calorie density (calories per gram) of a meal."""
        total_calorie_density = 0
        total_units = 0
        ingredients = meal["Ingredients"].split(", ") if meal["Ingredients"] else []

        for ingredient in ingredients:
            ingredient = ingredient.strip().lower()
            calorie_data = self.fetch_calorie_data(ingredient)
            if calorie_data:
                calories_per_unit = calorie_data["calories"]
                unit_grams = calorie_data["unit_grams"]

                # Calculate calories per gram for the ingredient
                calories_per_gram = calories_per_unit / unit_grams
                total_calorie_density += calories_per_gram
                total_units += 1  # Count the ingredient

        # Calculate average calorie density for the meal
        return total_calorie_density / total_units if total_units else 0

    def fetch_calorie_data(self, ingredient) -> Optional[Dict]:
        """Fetch calorie data for a specific ingredient from the Produce table."""
        # Implementation to fetch data from the Produce table based on the ingredient
        # Example implementation; modify this to fit your actual DB schema
        connection = get_db_connection()
        if connection is None:
            logging.error("Database connection failed.")
            return None

        try:
            cursor = connection.cursor()
            query = "SELECT Calories, Unit_grams FROM Produce WHERE Ingredient = ?"
            cursor.execute(query, (ingredient,))
            result = cursor.fetchone()
            if result:
                return {"calories": result[0], "unit_grams": result[1]}
            else:
                logging.warning(f"No data found for ingredient: {ingredient}")
                return None

        except pyodbc.Error as e:
            logging.error(f"Error fetching calorie data for {ingredient}: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def calculate_serving_size(self, meal) -> float:
        """Calculate the serving size (in grams) for a meal based on the user's calorie budget."""
        calorie_density = self.calculate_calorie_density(meal)
        if calorie_density <= 0:
            return 0

        # Calculate serving size to fit within the user's daily calorie budget
        serving_size = self.daily_calorie_budget / calorie_density
        return serving_size

    def filter_meals(self) -> List[Dict]:
        """Filter meals based on user preferences, metrics, and calorie budget."""
        meals = self.fetch_all_meals()
        if not meals:
            return []

        filtered_meals = []
        for meal in meals:
            # Calorie budget filter
            serving_size = self.calculate_serving_size(meal)
            if serving_size > 0:
                meal["amount_to_serve"] = round(serving_size, 2)

                # Only keep meals within the calorie budget
                total_calories = serving_size * self.calculate_calorie_density(meal)
                if total_calories <= self.daily_calorie_budget:
                    filtered_meals.append(meal)

        return filtered_meals

    def recommend_meals(self) -> Dict:
        """Generate meal recommendations based on user data."""
        if not self.user_preferences or not self.user_metrics:
            logging.warning("User preferences or metrics not found. Using default recommendations.")
            return {"error": "User preferences or metrics not found.", "success": False}

        recommended_meals = self.filter_meals()
        return {"recommended_meals": recommended_meals, "success": True}

# Example usage
#if __name__ == "__main__":
    #user_id = 138
    #meal_recommender = MealRecommendation2(user_id)
    #recommendations = meal_recommender.recommend_meals()
    #print(recommendations)

class GetAllMeals:
    def Fetch_All_Meals(self):
        """
        Fetch all meals from the database and explicitly include all columns from the CTE.
        """
        print("Fetching meals...")
        try:
            connection = get_db_connection()
            if connection is None:
                print("Database connection failed.")
                return {"error": "Database connection failed", "success": False}

            print("Database connection established.")
            cursor = connection.cursor()

            # Define the SQL query
            sql_query = """ 
            WITH MealDetails AS ( 
                SELECT 
                    m.Meal_id,
                    m.Meal_name,
                    m.Meal_category,
                    m.Recipe,
                    m.Recipe_link,
                    m.Image_link,
                    m.Goal,
                    m.Dietary_preference,
                    m.Allergies,
                    m.Disease_management,
                    m.Cuisine_preferences,
                    m.Skill_level,
                    m.Prep_time,
                    m.Meal_description
                FROM Meals m
            )
            SELECT 
                md.*,
                (SELECT STRING_AGG(p.Produce_name, ', ') 
                 FROM Meal_ingredients i
                 JOIN Produce p ON i.Produce_id = p.Produce_id
                 WHERE i.Meal_id = md.Meal_id) AS Ingredients,
                (SELECT STRING_AGG(mc.Meal_name, ', ') 
                 FROM Meal_complementaries mc_link
                 JOIN Meals mc ON mc_link.Complementary_Dish_id = mc.Meal_id
                 WHERE mc_link.Meal_id = md.Meal_id) AS Complementary_dishes
            FROM MealDetails md;
            """

            print("Executing SQL query...")
            cursor.execute(sql_query)

            print("Query executed. Fetching results...")
            results = cursor.fetchall()

            # Get column names from the cursor description
            columns = [column[0] for column in cursor.description]

            print("Results fetched. Processing results...")
            meal_recommendations = []
            for row in results:
                # Create a dictionary mapping column names to row values
                row_dict = dict(zip(columns, row))

                # Explicitly include all columns from the CTE
                meal = {
                    "Meal_id": row_dict["Meal_id"],
                    "Meal_name": row_dict["Meal_name"],
                    "Meal_category": row_dict["Meal_category"],
                    "Recipe": row_dict["Recipe"],
                    "Recipe_link": row_dict["Recipe_link"],
                    "Image_link": row_dict["Image_link"],
                    "Goal": row_dict["Goal"],
                    "Dietary_preference": row_dict["Dietary_preference"],
                    "Allergies": row_dict["Allergies"],
                    "Disease_management": row_dict["Disease_management"],
                    "Cuisine_preferences": row_dict["Cuisine_preferences"],
                    "Skill_level": row_dict["Skill_level"],
                    "Prep_time": row_dict["Prep_time"],
                    "Meal_description": row_dict["Meal_description"],
                    "Ingredients": row_dict["Ingredients"],
                    "Complementary_dishes": row_dict["Complementary_dishes"]
                }

                # Clean up ingredients if they exist
                if meal["Ingredients"]:
                    meal["Ingredients"] = meal["Ingredients"].replace('"', '').strip()

                # Clean up complementaries if they exist
                if meal["Complementary_dishes"]:
                    meal["Complementary_dishes"] = meal["Complementary_dishes"].replace('"', '').strip()

                # Append the meal dictionary to the meal recommendations
                meal_recommendations.append(meal)

            print("Results processed. Returning meal recommendations...")
            return {"All_Meals": meal_recommendations, "success": True}

        except pyodbc.Error as e:
            print(f"Error fetching meal recommendations: {e}")
            return {"error": f"Error fetching meal recommendations: {e}", "success": False}
        finally:
            if connection:
                print("Closing database connection...")
                connection.close()
                print("Database connection closed.")




#meal_fetcher = GetAllMeals()
#meal_recommendations = meal_fetcher.Fetch_All_Meals()
#print(meal_recommendations)

#payment methds
# Set up PayPal SDK with your credentials (client_id and secret)

def configure_paypal(mode, client_id, client_secret):
    """
    Configures the PayPal SDK with the provided credentials.
    """
    paypalrestsdk.configure({
        'mode': mode,
        'client_id': client_id,
        'client_secret': client_secret
    })



def create_payment_paypal(amount, description):
    """
    Creates a PayPal payment object with the specified amount and description.

    Args:
        amount: The amount of the payment.
        description: A description of the payment.

    Returns:
        A dictionary containing the approval URL if successful, or an error message otherwise.
    """
    try:
        payment = paypalrestsdk.Payment({
            "intent": "sale",
            "payer": {"payment_method": "paypal"},
            "transactions": [{
                "amount": {"total": str(amount), "currency": "USD"},
                "description": description
            }],
            "redirect_urls": {
                "return_url": f"{apibaseurl}/rr/execute",
                "cancel_url": f"{apibaseurl}/rr/cancel"
            }
        })

        if payment.create():
            for link in payment.links:
                if link.rel == "approval_url":
                    return {"approval_url": link.href}
        else:
            logging.error(payment.error)
            return {"error": "Payment creation failed"}
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return {"error": "An unexpected error occurred"}


def execute_payment(payment_id, payer_id):
    """
    Executes a PayPal payment using the provided payment ID and payer ID.

    Args:
        payment_id: The ID of the PayPal payment.
        payer_id: The ID of the payer who authorized the payment.

    Returns:
        A dictionary containing the payment status and details if successful, or an error message otherwise.
    """
    try:
        payment = paypalrestsdk.Payment.find(payment_id)
        if payment.execute({"payer_id": payer_id}):
            return {"status": "success", "payment": payment.to_dict()}
        else:
            logging.error(payment.error)
            return {"status": "failure", "error": payment.error}
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return {"status": "failure", "error": "An unexpected error occurred"}


def handle_payment_cancellation():
    """
    Returns a message indicating payment cancellation.
    """
    return {"status": "failure", "message": "Payment was cancelled."}


# Stripe
def configure_stripe(secret_key):
    """
    Configures Stripe with the provided secret key.
    """
    stripe.api_key = secret_key


def create_stripe_payment(amount, description="Payment for ZINZI Health Service", currency="usd"):
    """
    Creates a Stripe payment intent with the specified amount and description.

    Args:
        amount: The amount of the payment.
        description: A description of the payment.
        currency: The currency of the payment (default is USD).

    Returns:
        A dictionary containing the client secret if successful, or an error message otherwise.
    """
    try:
        if amount <= 0:
            return {"status": "failure", "error": "Amount must be greater than zero"}

        payment_intent = stripe.PaymentIntent.create(
            amount=int(amount),  # Convert to cents if required
            currency=currency,
            description=description
        )
        return {"status": "success", "client_secret": payment_intent.client_secret}
    except stripe.error.StripeError as e:
        logging.error(f"Stripe error: {e}")
        return {"status": "failure", "error": e.user_message}
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return {"status": "failure", "error": "An unexpected error occurred"}


def execute_stripe_payment(payment_intent_id, payment_method_id):
    """
    Executes a Stripe payment using the provided payment intent ID and payment method ID.

    Args:
        payment_intent_id: The ID of the payment intent.
        payment_method_id: The ID of the payment method to use.

    Returns:
        A dictionary containing the payment status and details if successful, or an error message otherwise.
    """
    try:
        payment_intent = stripe.PaymentIntent.confirm(
            payment_intent_id,
            payment_method=payment_method_id
        )
        if payment_intent.status == 'succeeded':
            return {"status": "success", "payment": payment_intent}
        else:
            return {"status": "failure", "message": "Payment not completed"}
    except stripe.error.StripeError as e:
        logging.error(f"Stripe error: {e}")
        return {"status": "failure", "error": e.user_message}
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return {"status": "failure", "error": "An unexpected error occurred"}


def handle_stripe_payment_cancellation():
    """
    Returns a message indicating payment cancellation.
    """
    return {"status": "failure", "message": "Payment was cancelled."}



# Load MoMo environment variables (ensure these are set in your environment or .env file)
X_REFERENCE_ID = os.getenv("X_REFERENCE_ID")
API_KEY = os.getenv("MOMO_API_KEY")
SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")
API_BASE_URL = os.getenv("API_BASE_URL11")  # Your callback URL

# Initialize MoMo base URL and headers
momo_base_url = os.getenv("MOMO")
momo_headers = {}
access_token = ""
token_expires_at = 0

# Configure logging
logging.basicConfig(level=logging.INFO)


def get_access_token(x_reference_id: str, api_key: str) -> str:
    """
    Retrieve an access token for authentication in MoMo API requests.
    """
    url = f"{momo_base_url}/collection/token/"
    auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()

    headers = {
        "Authorization": f"Basic {auth_header}",
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
    }

    logging.info("----- Access Token Request -----")
    logging.info(f"URL: {url}")
    logging.info(f"Headers: {headers}")

    response = requests.post(url, headers=headers)

    logging.info("----- Access Token Response -----")
    logging.info(f"Status Code: {response.status_code}")
    logging.info(f"Response Text: {response.text}")

    if response.status_code == 200:
        token_info = response.json()
        logging.info("Access token retrieved successfully!")
        return token_info["access_token"], time.time() + token_info["expires_in"]
    else:
        logging.error("Failed to retrieve access token.")
        response.raise_for_status()


def refresh_access_token() -> None:
    """Refresh the access token before it expires."""
    global access_token, token_expires_at

    if time.time() >= token_expires_at:  # Check if token needs to be refreshed
        access_token, token_expires_at = get_access_token(X_REFERENCE_ID, API_KEY)
        momo_headers["Authorization"] = f"Bearer {access_token}"


def configure_momo() -> Dict[str, Any]:
    """Configure the MoMo API with the required headers."""
    global momo_headers

    # Get initial access token
    global access_token, token_expires_at
    access_token, token_expires_at = get_access_token(X_REFERENCE_ID, API_KEY)

    momo_headers = {
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
        "Authorization": f"Bearer {access_token}",
    }

    logging.info("MoMo API configured successfully.")
    return {"status": "success", "message": "MoMo API configured successfully."}


def bc_authorize(scope: str = "payments") -> Dict[str, Any]:
    """Claims consent from the account holder for the requested scopes."""
    try:
        refresh_access_token()  # Ensure token is valid before making the request

        logging.info("Requesting authorization for MoMo consent...")
        payload = {
            "scope": scope,
            "callbackUrl": momocallbackurl,  # Send the callback URL
        }

        headers = {**momo_headers, "X-Target-Environment": "sandbox"}

        response = requests.post(
            f"{momo_base_url}/collection/v1_0/bc-authorize",
            json=payload,
            headers=headers,
        )

        if response.status_code == 200:
            auth_req_id = response.json().get("auth_req_id")
            logging.info(f"Authorization successful. Auth Request ID: {auth_req_id}")
            return {"status": "success", "auth_req_id": auth_req_id}
        else:
            logging.error(f"Authorization failed: {response.json()}")
            return {"status": "failure", "error": response.json()}
    except Exception as e:
        logging.error(f"Unexpected error during bc_authorize: {e}")
        return {"status": "failure", "error": "An unexpected error occurred"}


def request_momo_payment(amount: float, currency: str, external_id: str, payer_number: str, payer_message: str, payee_note: str) -> Dict[str, Any]:
    """Initiates an MTN MoMo payment request."""
    try:
        refresh_access_token()  # Ensure token is valid before making the request

        logging.info(f"Initiating MoMo payment: amount={amount}, currency={currency}, external_id={external_id}, payer_number={payer_number}, payer_message={payer_message}, payee_note={payee_note}")

        payload = {
            "amount": str(amount),
            "currency": currency,
            "externalId": external_id,
            "payer": {
                "partyIdType": "MSISDN",
                "partyId": payer_number,
            },
            "payerMessage": payer_message,
            "payeeNote": payee_note,
            "callbackUrl": momocallbackurl,  # Send the callback URL
        }

        headers = {**momo_headers, "X-Target-Environment": "sandbox"}

        logging.info("----- Request Details -----")
        logging.info(f"URL: {momo_base_url}/collection/v1_0/requesttopay")
        logging.info(f"Headers: {headers}")
        logging.info(f"Payload: {payload}")

        response = requests.post(
            f"{momo_base_url}/collection/v1_0/requesttopay",
            json=payload,
            headers=headers,
        )

        # Log the raw response details
        logging.info("----- Response Details -----")
        logging.info(f"Status Code: {response.status_code}")
        logging.info(f"Headers: {response.headers}")
        logging.info(f"Body: {response.text}")

        if response.status_code == 202:
            transaction_ref = response.headers.get("X-Reference-Id")
            logging.info(f"Payment request successful. Transaction Reference: {transaction_ref}")
            return {"status": "success", "transaction_ref": transaction_ref}
        else:
            try:
                # Log the JSON error response
                error_response = response.json()
                logging.error(f"Payment request failed: {error_response}")
                return {"status": "failure", "error": error_response}
            except ValueError:
                # Log non-JSON error response
                logging.error(f"Non-JSON error response: {response.text}")
                return {"status": "failure", "error": "Non-JSON response received"}
    except Exception as e:
        logging.error(f"Unexpected error during request_momo_payment: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}


def check_momo_payment_status(transaction_ref: str) -> Dict[str, Any]:
    """Checks the status of an MTN MoMo payment using its transaction reference."""
    try:
        refresh_access_token()  # Ensure token is valid before making the request

        logging.info(f"Checking payment status for transaction_ref: {transaction_ref}")
        headers = {**momo_headers, "X-Target-Environment": "sandbox"}

        response = requests.get(
            f"{momo_base_url}/collection/v1_0/requesttopay/{transaction_ref}",
            headers=headers,
        )

        if response.status_code == 200:
            payment_status = response.json()
            logging.info(f"Payment status retrieved successfully: {json.dumps(payment_status)}")
            return {"status": "success", "payment_status": payment_status}
        else:
            logging.error(f"Failed to retrieve payment status: {response.json()}")
            return {"status": "failure", "error": response.json()}
    except Exception as e:
        logging.error(f"Unexpected error during check_momo_payment_status: {e}")
        return {"status": "failure", "error": "An unexpected error occurred"}


# Initialize MoMo configuration
configure_momo()
