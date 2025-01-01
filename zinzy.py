#Cspell:disable
import os
import random
import string
from datetime import datetime
import bcrypt
import pyodbc
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from email.mime.text import MIMEText
import base64
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
import paypalrestsdk
import logging


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
            query = "SELECT COUNT(*) FROM Users WHERE Email = ?"
            cursor.execute(query, (email,))
            if cursor.fetchone()[0] > 0:
                print("Error: Email is already registered.")
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
            print(f"Error during signup: {e}")
            return None
        finally:
            if connection:
                connection.close()

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

    def send_verification_email(self, to_email, verification_code):
        # OAuth 2.0 flow to get credentials
        SCOPES = ['https://www.googleapis.com/auth/gmail.send']
        creds = None

        # Check if token.json exists to load the stored credentials
        if os.path.exists('token.json'):
            try:
                creds = Credentials.from_authorized_user_file('token.json', SCOPES)
            except AttributeError:
                # If from_authorized_user_file is not available, use from_authorized_user_info
                with open('token.json', 'r') as token:
                    creds_info = json.load(token)
                creds = Credentials.from_authorized_user_info(creds_info, SCOPES)

        # If there are no valid credentials, the user must log in again
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                # Load credentials from client_secret file
                flow = InstalledAppFlow.from_client_secrets_file(
                    'client_secret_769800441200-vlojtkiqv165kbumgmjsku2rbm97h217.apps.googleusercontent.com.json', SCOPES)
                creds = flow.run_local_server(port=8080)

            # Save the credentials for the next run
            with open('token.json', 'w') as token:
                token.write(creds.to_json())

        # Build the Gmail API service
        service = build('gmail', 'v1', credentials=creds)

        subject = "Your zinzi Verification Code"
        body = f"Your verification code is: {verification_code}\nPlease enter this code in the zinzi app to verify your account."

        # Create the email message
        message = MIMEText(body)
        message['to'] = to_email
        message['subject'] = subject

        # Encode the message
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


    # Verifying the verification code
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
        except pyodbc.Error as e:
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


    #log metrics
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

    

# 5. Meal Recommendation Logic
class MealRecommendation:
    def __init__(self, user_id):
        self.user_id = user_id
        self.weight = self.get_user_weight()
        self.cholesterol_level = self.get_user_cholesterol_level()
        self.dietary_preferences = self.get_user_dietary_preferences()

    def get_user_weight(self):
        try:
            connection = get_db_connection()
            if connection is None:
                return None
            cursor = connection.cursor()
            query = "SELECT Weight FROM User_metrics WHERE User_id = ?"
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()
            connection.close()
            if result:
                return result[0]
            else:
                print(f"No weight data found for user {self.user_id}.")
                return None
        except pyodbc.Error as e:
            print(f"Error fetching weight: {e}")
            return None

    def get_user_cholesterol_level(self):
        try:
            connection = get_db_connection()
            if connection is None:
                return None
            cursor = connection.cursor()
            query = "SELECT Cholestrol_level FROM User_metrics WHERE User_id = ?"
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()
            connection.close()
            if result:
                return result[0]
            else:
                print(f"No cholesterol data found for user {self.user_id}.")
                return None
        except pyodbc.Error as e:
            print(f"Error fetching cholesterol level: {e}")
            return None

    def get_user_dietary_preferences(self):
        try:
            connection = get_db_connection()
            if connection is None:
                return []
            cursor = connection.cursor()
            query = "SELECT Diet_type FROM User_preferences WHERE User_id = ?"
            cursor.execute(query, (self.user_id,))
            result = cursor.fetchone()
            connection.close()
            if result:
                return result[0].split(",")
            else:
                print(f"No dietary preferences found for user {self.user_id}.")
                return []
        except pyodbc.Error as e:
            print(f"Error fetching dietary preferences: {e}")
            return []

    def recommend_meals(self):
        connection = get_db_connection()
        if connection is None:
            return []
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM Meal_data")
        columns = [column[0] for column in cursor.description]
        meal_data = [dict(zip(columns, row)) for row in cursor.fetchall()]

        recommended_meals = [meal for meal in meal_data if self.is_meal_suitable(meal)]
        connection.close()
        return recommended_meals

    def is_meal_suitable(self, meal):
        if meal['MealType'] not in self.dietary_preferences:
            return False

        if meal['Calories'] > (self.weight * 30):
            return False

        if meal['Cholesterol_content'] > self.cholesterol_level:
            return False

        return True



# Set up PayPal SDK with your credentials (client_id and secret)
paypalrestsdk.configure({
    'mode': 'sandbox',  # or 'live' for production
    'client_id': 'AfzJI5McbstkRODEO9C_DtEgmP7lRf0K49OFKXhi3Xo6W5HSVO77JTNnwWJI2ndjz0fcAg9oWObiT5nb',
    'client_secret': 'YOELDAPDBWEEWxEuAofCbcWH5XvKLYtcp_TFsL_b-XQPdR0G04IDiEkSuNmZTPRF-ItPjKOPnp12i-u_FJ'
})

# Function to create a payment
def create_payment(amount, currency="USD", return_url="http://localhost:5000/rr/execute", cancel_url="http://localhost:5000/rr/cancel"):
    payment = paypalrestsdk.Payment({
        "intent": "sale",
        "payer": {
            "payment_method": "paypal"
        },
        "transactions": [{
            "amount": {
                "total": str(amount),
                "currency": currency
            },
            "description": "Payment for ZINZI health service"
        }],
        "redirect_urls": {
            "return_url": return_url,
            "cancel_url": cancel_url
        }
    })

    if payment.create():
        for link in payment.links:
            if link.rel == "approval_url":
                approval_url = link.href
                return approval_url
    else:
        logging.error(payment.error)
        return None

# Function to execute a payment after user approval
def execute_payment(payment_id, payer_id):
    payment = paypalrestsdk.Payment.find(payment_id)

    if payment.execute({"payer_id": payer_id}):
        return {"status": "success", "payment": payment}
    else:
        logging.error(payment.error)
        return {"status": "failure", "error": payment.error}

# Function to handle cancellation
def handle_payment_cancellation():
    return {"status": "failure", "message": "Payment was cancelled."}

