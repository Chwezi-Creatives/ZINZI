import pyodbc
from datetime import datetime
from database import get_db_connection  # Import the connection function
import logging
import bcrypt

# Configure logging for error reporting
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Database:
    def __init__(self):
        self.conn = get_db_connection()  # Connect to the database
        if self.conn is not None:
            self.cursor = self.conn.cursor()
        else:
            raise Exception("Failed to connect to the database.")

    def close(self):
        if hasattr(self, 'cursor'):
            self.cursor.close()
        if hasattr(self, 'conn'):
            self.conn.close()

# Utility function to check required fields
def check_required_fields(data, required_fields):
    missing_fields = [field for field in required_fields if not data.get(field)]
    if missing_fields:
        raise ValueError(f"Missing required fields: {', '.join(missing_fields)}")

# Serialize/deserialize helper functions for lists
def serialize_list(data_list):
    return ','.join(data_list) if isinstance(data_list, list) else ''

def deserialize_list(data_string):
    return data_string.split(',') if data_string else []

# CRUD operations for Users
class Users:
    def __init__(self, db):
        self.db = db

    def hash_password(self, password):
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt())

    def create_user(self, user_data):
        try:
            check_required_fields(user_data, ['Name', 'Password', 'Email'])
            existing_email_sql = "SELECT COUNT(*) FROM Users WHERE Email = ?"
            self.db.cursor.execute(existing_email_sql, (user_data['Email'],))
            email_count = self.db.cursor.fetchone()[0]

            if email_count > 0:
                raise ValueError("A user with this email already exists.")

            hashed_password = self.hash_password(user_data['Password'])
            user_type = user_data.get('User_Type', 'user')

            sql = """
                INSERT INTO Users (Name, Email, Hashed_Password, Is_Email_Verified, User_Type, Is_Active,
                Rating, Phone_Number, Registration_Date, Location, Added_By, Added_By_Type, Last_Login)
                OUTPUT INSERTED.User_id
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                user_data['Name'], user_data['Email'], hashed_password,
                user_data.get('Is_Email_Verified', 0), user_type,
                user_data.get('Is_Active', 1), user_data.get('Rating', 0),
                user_data.get('Phone_Number'), datetime.now(),
                user_data.get('Location'), user_data.get('Added_By', 0),
                user_data.get('Added_By_Type', user_type), datetime.now()
            ))
            user_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created user with ID: {user_id} and User Type: {user_type}")
            return {"UserId": user_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating user: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating user: {e}")
            raise ValueError(str(e))

    def list_users(self, user_id=None):
        try:
            sql = "SELECT * FROM Users"
            parameters = []

            if user_id:
                sql += " WHERE User_id=?"
                parameters.append(user_id)

            self.db.cursor.execute(sql, parameters)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing users: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing users: {e}")
            raise ValueError(str(e))

    def login_user(self, identifier, password):
        try:
            connection = get_db_connection()
            cursor = connection.cursor()
            query = "SELECT User_id, Hashed_Password, User_Type FROM Users WHERE Name = ? OR Email = ?"
            cursor.execute(query, (identifier, identifier))
            result = cursor.fetchone()

            if not result:
                return {'message': 'Invalid credentials or account not found.'}, 401

            user_id, stored_hashed_password, user_type = result

            if bcrypt.checkpw(password.encode(), stored_hashed_password.encode()):
                return {'message': 'Login successful', 'user_id': user_id, 'user_type': user_type}, 200
            else:
                return {'message': 'Invalid credentials.'}, 401
        except pyodbc.Error as e:
            logger.error(f"Error during login: {e}")
            return {'message': 'Error during login'}, 500
        finally:
            if connection:
                connection.close()

    # CRUD operations for Metrics
    def create_metric(self, metric_data):
        try:
            check_required_fields(metric_data, ['User_id', 'Weight', 'Height', 'Cholesterol_level', 'Sys_bp', 'Dia_bp', 'Pulse'])
            sql = """
                INSERT INTO User_metrics (User_id, Age_range, Weight, Height, Cholesterol_level,
                Sys_bp, Dia_bp, Pulse, Recorded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                metric_data['User_id'], metric_data['Age_range'], metric_data['Weight'], metric_data['Height'],
                metric_data['Cholesterol_level'], metric_data['Sys_bp'], metric_data['Dia_bp'],
                metric_data['Pulse'], datetime.now()
            ))
            self.db.conn.commit()
            return {"MetricId": self.db.cursor.execute("SELECT SCOPE_IDENTITY()").fetchval()}
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating metric: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating metric: {e}")
            raise ValueError(str(e))

    def update_metric(self, metric_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE User_metrics SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Metric_id=?"
            parameters.append(metric_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating metric (ID: {metric_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating metric (ID: {metric_id}): {e}")
            raise ValueError(str(e))

    def list_metrics(self, user_id=None):
        try:
            sql = "SELECT * FROM User_metrics"
            parameters = []

            if user_id:
                sql += " WHERE User_id=?"
                parameters.append(user_id)

            self.db.cursor.execute(sql, parameters)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing metrics: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing metrics: {e}")
            raise ValueError(str(e))

    # CRUD operations for Metrics History
    def create_metric_history(self, metric_history_data):
        try:
            check_required_fields(metric_history_data, ['User_id', 'Weight'])
            sql = """
                INSERT INTO Metrics_history (User_id, Weight, Logged_at) VALUES (?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                metric_history_data['User_id'], metric_history_data['Weight'], datetime.now()
            ))
            self.db.conn.commit()
            return {"MetricHistoryId": self.db.cursor.execute("SELECT SCOPE_IDENTITY()").fetchval()}
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating metric history: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating metric history: {e}")
            raise ValueError(str(e))

    def update_metric_history(self, log_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Metrics_history SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Log_id=?"
            parameters.append(log_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating metric history (Log ID: {log_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating metric history (Log ID: {log_id}): {e}")
            raise ValueError(str(e))

    def list_metric_history(self, user_id=None):
        try:
            sql = "SELECT * FROM Metrics_history"
            parameters = []

            if user_id:
                sql += " WHERE User_id=?"
                parameters.append(user_id)

            self.db.cursor.execute(sql, parameters)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing metric history: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing metric history: {e}")
            raise ValueError(str(e))

    def create_preference(self, preference_data):
        try:
            check_required_fields(preference_data, ['User_id', 'Goals', 'Diet_type'])
            sql = """
                INSERT INTO User_preferences (User_id, Goals, Diet_type, Food_restrictions, Cuisine_preferences)
                OUTPUT INSERTED.Preference_id
                VALUES (?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                preference_data['User_id'], preference_data['Goals'],
                preference_data['Diet_type'], preference_data.get('Food_restrictions', None),
                preference_data.get('Cuisine_preferences', None)
            ))
            self.db.conn.commit()
            return {"PreferenceId": self.db.cursor.fetchone()[0]}
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating preference: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating preference: {e}")
            raise ValueError(str(e))

    def update_preference(self, preference_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE UserPreferences SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Preference_id=?"
            parameters.append(preference_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating preference (ID: {preference_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating preference (ID: {preference_id}): {e}")
            raise ValueError(str(e))

    def list_preferences(self, user_id=None):
        try:
            sql = "SELECT * FROM User_preferences"
            parameters = []

            if user_id:
                sql += " WHERE User_id=?"
                parameters.append(user_id)

            self.db.cursor.execute(sql, parameters)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing preferences: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing preferences: {e}")
            raise ValueError(str(e))

# CRUD operations for Chefs
class Chefs:
    def __init__(self, db):
        self.db = db
        logger.info("Chefs class initialized.")

    def hash_password(self, password):
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt())

    def create_chef(self, chef_data):
        try:
            check_required_fields(chef_data, ['Name', 'Password'])
            equipment = serialize_list(chef_data.get('Equipment', []))
            availability = serialize_list(chef_data.get('Availability', []))
            languages = serialize_list(chef_data.get('Languages', []))
            specialties = serialize_list(chef_data.get('Specialties', []))
            certifications = serialize_list(chef_data.get('Certifications', []))

            hashed_password = self.hash_password(chef_data['Password'])
            user_type = chef_data.get('User_Type', 'chef')

            sql = """
                INSERT INTO Chefs (Name, Image, Email, Hashed_Password, Is_Email_Verified, User_Type,
                Chef_Type, Is_Active, Rating, Price, Phone_Number, Experience, ServiceRadius,
                ResponseTime, MinNotice, Punctuality, TeamSize, Equipment, Bio, Availability,
                Languages, Specialties, Certifications, SampleMenu, Reviews,
                Registration_Date, Location, Added_By, Added_By_Type, Last_Login)
                OUTPUT INSERTED.ChefID
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            logger.debug(f"Executing SQL for creating chef: {chef_data}")

            self.db.cursor.execute(sql, (
                chef_data.get('Name'), chef_data.get('Image'), chef_data.get('Email'),
                hashed_password, chef_data.get('Is_Email_Verified', 0), user_type,
                chef_data.get('Chef_Type', 'Individual'), chef_data.get('Is_Active', 1),
                chef_data.get('Rating', 0), chef_data.get('Price'), chef_data.get('Phone_Number'),
                chef_data.get('Experience'), chef_data.get('ServiceRadius'),
                chef_data.get('ResponseTime'), chef_data.get('MinNotice'),
                chef_data.get('Punctuality', 0), chef_data.get('TeamSize'), equipment,
                chef_data.get('Bio'), availability, languages, specialties, certifications,
                chef_data.get('SampleMenu'), chef_data.get('Reviews'), datetime.now(),
                chef_data.get('Location'), chef_data.get('Added_By', 0),
                chef_data.get('Added_By_Type', user_type), datetime.now()
            ))
            chef_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created chef with ID: {chef_id} and User Type: {user_type}")
            return {"ChefID": chef_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating chef: {sql_error.args}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating chef: {e}")
            raise ValueError(str(e))

    def list_chefs(self, chef_id=None):
        try:
            if chef_id is not None:
                sql = "SELECT * FROM Chefs WHERE ChefID = ?"
                logger.debug(f"Listing chef with ID: {chef_id}")
                self.db.cursor.execute(sql, chef_id)
            else:
                sql = "SELECT * FROM Chefs"
                logger.debug("Listing all chefs.")
                self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            results = [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
            logger.info(f"Fetched {len(results)} chefs.")
            return results
        
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing chefs: {sql_error.args}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing chefs: {e}")
            raise ValueError(str(e))

    def update_chef(self, chef_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Chefs SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE ChefID=?"
            parameters.append(chef_id)

            logger.debug(f"Executing SQL for updating chef ID {chef_id}: {parameters}")
            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
            logger.info(f"Updated chef with ID: {chef_id}")

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating chef (ID: {chef_id}): {sql_error.args}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating chef (ID: {chef_id}): {e}")
            raise ValueError(str(e))

    def login_user(self, identifier, password):
        try:
            connection = get_db_connection()
            cursor = connection.cursor()
            query = "SELECT ChefID, Hashed_Password, User_Type FROM Chefs WHERE Name = ? OR Email = ?"
            cursor.execute(query, (identifier, identifier))
            result = cursor.fetchone()

            if not result:
                logger.warning(f"Invalid credentials provided for identifier: {identifier}")
                return {'message': 'Invalid credentials or account not found.'}, 401

            chef_id, stored_hashed_password, user_type = result

            if bcrypt.checkpw(password.encode(), stored_hashed_password.encode()):
                logger.info(f"Login successful for user: {identifier} (ID: {chef_id})")
                return {'message': 'Login successful', 'chef_id': chef_id, 'user_type': user_type}, 200
            else:
                logger.warning(f"Invalid password for user: {identifier}.")
                return {'message': 'Invalid credentials.'}, 401
            
        except pyodbc.Error as e:
            logger.error(f"Error during login for user: {identifier}. Error: {e.args}")
            return {'message': 'Error during login'}, 500
        except Exception as e:
            logger.error(f"Unexpected error during login for user: {identifier}. Error: {e}")
            return {'message': 'Error during login'}, 500
        finally:
            if connection:
                connection.close()

# CRUD operations for Producers
class Producers:
    def __init__(self, db):
        self.db = db

    def hash_password(self, password):
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt())

    def create_producer(self, producer_data):
        try:
            check_required_fields(producer_data, ['Name', 'Password', 'Email'])

            existing_email_sql = "SELECT COUNT(*) FROM Producers WHERE Email = ?"
            self.db.cursor.execute(existing_email_sql, (producer_data['Email'],))
            email_count = self.db.cursor.fetchone()[0]

            if email_count > 0:
                raise ValueError("A producer with this email already exists.")

            hashed_password = self.hash_password(producer_data['Password'])
            user_type = producer_data.get('User_Type', 'Producer')

            sql = """
                INSERT INTO Producers (Name, Image, Email, Hashed_Password, Is_Email_Verified, User_Type,
                Producer_Type, Is_Active, Rating, Phone_Number, Registration_Date,
                Location, Added_By, Added_By_Type, Last_Login) OUTPUT INSERTED.Producer_Id
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                producer_data['Name'], producer_data.get('Image'), producer_data['Email'],
                hashed_password, producer_data.get('Is_Email_Verified', 0), user_type,
                producer_data.get('Producer_Type', 'Individual'), producer_data.get('Is_Active', 1),
                producer_data.get('Rating', 0), producer_data.get('Phone_Number'),
                datetime.now(), producer_data.get('Location'), producer_data.get('Added_By', 0),
                producer_data.get('Added_By_Type', user_type), datetime.now()
            ))
            producer_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created producer with ID: {producer_id} and User Type: {user_type}")
            return {"ProducerID": producer_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating producer: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating producer: {e}")
            raise ValueError(str(e))

    def list_producers(self, producer_id=None):
        try:
            if producer_id:
                sql = "SELECT * FROM Producers WHERE Producer_Id = ?"
                self.db.cursor.execute(sql, [producer_id])
            else:
                sql = "SELECT * FROM Producers"
                self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            results = self.db.cursor.fetchall()
            if producer_id and not results:
                raise ValueError(f"No producer found with ID: {producer_id}")

            return [dict(zip(columns, row)) for row in results]

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing producers: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing producers: {e}")
            raise ValueError(str(e))

    def update_producer(self, producer_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Producers SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Producer_Id=?"
            parameters.append(producer_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating producer (ID: {producer_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating producer (ID: {producer_id}): {e}")
            raise ValueError(str(e))

    def login_user(self, identifier, password):
        try:
            connection = get_db_connection()
            cursor = connection.cursor()
            query = "SELECT Producer_Id, Hashed_Password, User_Type FROM Producers WHERE Name = ? OR Email = ?"
            cursor.execute(query, (identifier, identifier))
            result = cursor.fetchone()

            if not result:
                return {'message': 'Invalid credentials or account not found.'}, 401

            producer_id, stored_hashed_password, user_type = result

            if bcrypt.checkpw(password.encode(), stored_hashed_password.encode()):
                return {'message': 'Login successful', 'producer_id': producer_id, 'user_type': user_type}, 200
            else:
                return {'message': 'Invalid credentials.'}, 401
        except pyodbc.Error as e:
            logger.error(f"Error during login: {e}")
            return {'message': 'Error during login'}, 500
        finally:
            if connection:
                connection.close()

# CRUD operations for Stakeholders
class Stakeholders:
    def __init__(self, db):
        self.db = db

    def hash_password(self, password):
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt())

    def create_stakeholder(self, stakeholder_data):
        try:
            check_required_fields(stakeholder_data, ['Name', 'Password', 'Email', 'Full_Name'])

            existing_email_sql = "SELECT COUNT(*) FROM Stakeholders WHERE Email = ?"
            self.db.cursor.execute(existing_email_sql, (stakeholder_data['Email'],))
            email_count = self.db.cursor.fetchone()[0]

            if email_count > 0:
                raise ValueError("A stakeholder with this email already exists.")

            hashed_password = self.hash_password(stakeholder_data['Password'])
            user_type = stakeholder_data.get('User_Type', 'stakeholder')

            sql = """
                INSERT INTO Stakeholders (Name, Full_Name, Image, Email, Hashed_Password,
                Is_Email_Verified, User_Type, Is_Active, Rating, Phone_Number,
                Registration_Date, Location, Added_By, Added_By_Type, Last_Login)
                OUTPUT INSERTED.Stakeholder_Id
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                stakeholder_data['Name'], stakeholder_data['Full_Name'], stakeholder_data.get('Image'),
                stakeholder_data['Email'], hashed_password, stakeholder_data.get('Is_Email_Verified', 0),
                user_type, stakeholder_data.get('Is_Active', 1), stakeholder_data.get('Rating', 0),
                stakeholder_data.get('Phone_Number'), datetime.now(), stakeholder_data.get('Location'),
                stakeholder_data.get('Added_By', '0'), stakeholder_data.get('Added_By_Type', user_type),
                datetime.now()
            ))
            stakeholder_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created stakeholder with ID: {stakeholder_id} and User Type: {user_type}")
            return {"StakeholderID": stakeholder_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating stakeholder: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating stakeholder: {e}")
            raise ValueError(str(e))

    def list_stakeholders(self):
        try:
            sql = "SELECT * FROM Stakeholders"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing stakeholders: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing stakeholders: {e}")
            raise ValueError(str(e))

    def update_stakeholder(self, stakeholder_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Stakeholders SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Stakeholder_Id=?"
            parameters.append(stakeholder_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating stakeholder (ID: {stakeholder_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating stakeholder (ID: {stakeholder_id}): {e}")
            raise ValueError(str(e))

    def login_user(self, identifier, password):
        try:
            connection = get_db_connection()
            cursor = connection.cursor()
            query = "SELECT Stakeholder_Id, Hashed_Password, User_Type FROM Stakeholders WHERE Name = ? OR Email = ?"
            cursor.execute(query, (identifier, identifier))
            result = cursor.fetchone()

            if not result:
                return {'message': 'Invalid credentials or account not found.'}, 401

            stakeholder_id, stored_hashed_password, user_type = result

            if bcrypt.checkpw(password.encode(), stored_hashed_password.encode()):
                return {'message': 'Login successful', 'stakeholder_id': stakeholder_id, 'user_type': user_type}, 200
            else:
                return {'message': 'Invalid credentials.'}, 401
        except pyodbc.Error as e:
            logger.error(f"Error during login: {e}")
            return {'message': 'Error during login'}, 500
        finally:
            if connection:
                connection.close()

# CRUD operations for Herbals
class Herbals:
    def __init__(self, db):
        self.db = db

    def create_herbal(self, herbal_data):
        try:
            check_required_fields(herbal_data, ['herbal_name', 'description', 'unit', 'price'])

            user_type = herbal_data.get('User_Type', 'herbal')

            sql = """
                INSERT INTO Herbals (herbal_name, description, unit, price, image_url, date_added,
                added_by, added_by_type, User_type) OUTPUT INSERTED.HerbalID
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                herbal_data['herbal_name'], herbal_data['description'], herbal_data['unit'],
                herbal_data['price'], herbal_data.get('image_url'), datetime.now(),
                herbal_data.get('added_by'), herbal_data.get('added_by_type', user_type), user_type
            ))
            herbal_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created herbal with ID: {herbal_id} and User Type: {user_type}")
            return {"HerbalID": herbal_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating herbal: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating herbal: {e}")
            raise ValueError(str(e))

    def update_herbal(self, herbal_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Herbals SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE herbal_id=?"
            parameters.append(herbal_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating herbal (ID: {herbal_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating herbal (ID: {herbal_id}): {e}")
            raise ValueError(str(e))

    def list_herbals(self):
        try:
            sql = "SELECT * FROM Herbals"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing herbals: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing herbals: {e}")
            raise ValueError(str(e))

# CRUD operations for Meals
class Meals:
    def __init__(self, db):
        self.db = db

    def create_meal(self, meal_data):
        try:
            check_required_fields(meal_data, ['Meal_name', 'Meal_category', 'Ingredients'])

            user_type = meal_data.get('User_Type', 'meal')

            sql = """
                INSERT INTO Meals (Meal_name, Meal_category, Ingredients,
                Complementary_dishes, Recipe, Recipe_link, Image_link,
                Goal, Dietary_preference, Allergies, Disease_management,
                Cuisine_preferences, Skill_level, Prep_time, meal_description,
                date_added, date_last_edited, added_by, added_by_type, User_type)
                OUTPUT INSERTED.MealID VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                meal_data['Meal_name'], meal_data['Meal_category'], meal_data['Ingredients'],
                meal_data.get('Complementary_dishes'), meal_data.get('Recipe'), meal_data.get('Recipe_link'),
                meal_data.get('Image_link'), meal_data.get('Goal'), meal_data.get('Dietary_preference'),
                meal_data.get('Allergies'), meal_data.get('Disease_management'),
                meal_data.get('Cuisine_preferences'), meal_data.get('Skill_level'),
                meal_data.get('Prep_time'), meal_data.get('meal_description'),
                datetime.now(), datetime.now(), meal_data.get('added_by'),
                meal_data.get('added_by_type', user_type), user_type
            ))
            meal_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created meal with ID: {meal_id} and User Type: {user_type}")
            return {"MealID": meal_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating meal: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating meal: {e}")
            raise ValueError(str(e))

    def update_meal(self, meal_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Meals SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Meal_id=?"
            parameters.append(meal_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating meal (ID: {meal_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating meal (ID: {meal_id}): {e}")
            raise ValueError(str(e))

    def list_meals(self):
        try:
            sql = "SELECT * FROM Meals"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing meals: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing meals: {e}")
            raise ValueError(str(e))

# CRUD operations for Produce
class Produce:
    def __init__(self, db):
        self.db = db

    def create_produce(self, produce_data):
        try:
            check_required_fields(produce_data, ['Produce_name', 'Unit_grams', 'Calories'])

            user_type = produce_data.get('User_Type', 'produce')

            sql = """
                INSERT INTO Produce (Produce_name, Unit_grams, Calories, Cholesterol,
                Carbohydrates, Proteins, Fats, Fiber, Sugars, Meal_type,
                Source, Nutritional_info, date_added, date_last_edited,
                added_by, added_by_type, User_type) OUTPUT INSERTED.ProduceID
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                produce_data['Produce_name'], produce_data['Unit_grams'], produce_data['Calories'],
                produce_data.get('Cholesterol', None), produce_data.get('Carbohydrates', None),
                produce_data.get('Proteins', None), produce_data.get('Fats', None),
                produce_data.get('Fiber', None), produce_data.get('Sugars', None),
                produce_data.get('Meal_type', None), produce_data.get('Source', None),
                produce_data.get('Nutritional_info', None), datetime.now(), datetime.now(),
                produce_data.get('added_by'), produce_data.get('added_by_type', user_type), user_type
            ))
            produce_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created produce with ID: {produce_id} and User Type: {user_type}")
            return {"ProduceID": produce_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating produce: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating produce: {e}")
            raise ValueError(str(e))

    def update_produce(self, produce_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Produce SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Produce_id=?"
            parameters.append(produce_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating produce (ID: {produce_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating produce (ID: {produce_id}): {e}")
            raise ValueError(str(e))

    def list_produce(self):
        try:
            sql = "SELECT * FROM Produce"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing produce: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing produce: {e}")
            raise ValueError(str(e))

# CRUD operations for Gadgets
class Gadgets:
    def __init__(self, db):
        self.db = db

    def create_gadget(self, gadget_data):
        try:
            check_required_fields(gadget_data, ['gadget_name', 'description'])

            user_type = gadget_data.get('User_Type', 'gadget')

            sql = """
                INSERT INTO Gadgets (gadget_name, description, brand, model,
                price, image_url, date_added, added_by, added_by_type, User_type)
                OUTPUT INSERTED.GadgetID
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                gadget_data['gadget_name'], gadget_data['description'],
                gadget_data.get('brand', None), gadget_data.get('model', None),
                gadget_data['price'], gadget_data.get('image_url', None),
                datetime.now(), gadget_data.get('added_by'), gadget_data.get('added_by_type', user_type), user_type
            ))
            gadget_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created gadget with ID: {gadget_id} and User Type: {user_type}")
            return {"GadgetID": gadget_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating gadget: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating gadget: {e}")
            raise ValueError(str(e))

    def update_gadget(self, gadget_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Gadgets SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE gadget_id=?"
            parameters.append(gadget_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating gadget (ID: {gadget_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating gadget (ID: {gadget_id}): {e}")
            raise ValueError(str(e))

    def list_gadgets(self):
        try:
            sql = "SELECT * FROM Gadgets"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing gadgets: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing gadgets: {e}")
            raise ValueError(str(e))

# CRUD operations for Spices
class Spices:
    def __init__(self, db):
        self.db = db

    def create_spice(self, spice_data):
        try:
            check_required_fields(spice_data, ['spice_name', 'description'])

            user_type = spice_data.get('User_Type', 'spice')

            sql = """
                INSERT INTO Spices (spice_name, description, unit, price,
                image_url, date_added, added_by, added_by_type, User_type)
                OUTPUT INSERTED.SpiceID
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                spice_data['spice_name'], spice_data['description'],
                spice_data.get('unit', None), spice_data['price'],
                spice_data.get('image_url', None), datetime.now(),
                spice_data['added_by'], spice_data.get('added_by_type', user_type), user_type
            ))
            spice_id = self.db.cursor.fetchone()[0]
            self.db.conn.commit()
            logger.info(f"Created spice with ID: {spice_id} and User Type: {user_type}")
            return {"SpiceID": spice_id, "UserType": user_type}

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating spice: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating spice: {e}")
            raise ValueError(str(e))

    def update_spice(self, spice_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Spices SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE spice_id=?"
            parameters.append(spice_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating spice (ID: {spice_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating spice (ID: {spice_id}): {e}")
            raise ValueError(str(e))

    def list_spices(self):
        try:
            sql = "SELECT * FROM Spices"
            self.db.cursor.execute(sql)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing spices: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing spices: {e}")
            raise ValueError(str(e))

# CRUD operations for Orders
# CRUD operations for Orders
import pyodbc
import logging

logger = logging.getLogger(__name__)

class Orders:
    def __init__(self, db):
        self.db = db

    def create_order(self, user_id, order_type, product_id=None, chef_id=None, producer_id=None, 
                     delivery_address=None, order_status="Pending", total_price=0, 
                     notes=None, payment_status="Pending", payment_mode=None, 
                     amount_paid=0, transaction_id=None, quantity=1):
        try:
            # Validate required fields
            if not user_id:
                raise ValueError("user_id is required")
            if not order_type:
                raise ValueError("order_type is required")

            # Validate order_type
            allowed_order_types = {'supplement', 'herbal', 'gadget', 'spice', 'produce', 'meal'}
            if order_type.lower() not in allowed_order_types:
                raise ValueError(f"Invalid order_type: {order_type}. Allowed values are {allowed_order_types}.")

            # Validate order_status
            allowed_order_statuses = {'cancelled', 'delivered', 'shipped', 'preparing', 'confirmed', 'pending'}
            if order_status.lower() not in allowed_order_statuses:
                raise ValueError(f"Invalid order_status: {order_status}. Allowed values are {allowed_order_statuses}.")

            # Validate payment_status
            allowed_payment_statuses = {'failed', 'refunded', 'paid', 'pending'}
            if payment_status.lower() not in allowed_payment_statuses:
                raise ValueError(f"Invalid payment_status: {payment_status}. Allowed values are {allowed_payment_statuses}.")

            # Validate payment_mode
            allowed_payment_modes = {'cash', 'momo', 'mobile money', 'Airtel Card', 'paypal', 'stripe', 'debit card', 'credit card'}
            if payment_mode and payment_mode.lower() not in allowed_payment_modes:
                raise ValueError(f"Invalid payment_mode: {payment_mode}. Allowed values are {allowed_payment_modes}.")

            # Set default values for optional fields
            delivery_address = delivery_address or "Not specified"
            notes = notes or "No special instructions"
            payment_mode = payment_mode or "cash"

            # Normalize case for constrained columns
            order_type = order_type.lower()
            order_status = order_status.lower()
            payment_status = payment_status.lower()
            payment_mode = payment_mode.lower()

            # Insert the order into the database using OUTPUT clause
            sql = """
                INSERT INTO Orders (
                    user_id, order_type, product_id, chef_id, producer_id, 
                    order_date, delivery_address, order_status, total_price, 
                    notes, payment_status, payment_mode, 
                    amount_paid, transaction_id, quantity
                )
                OUTPUT INSERTED.order_id
                VALUES (?, ?, ?, ?, ?, GETDATE(), ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            parameters = [
                user_id, order_type, product_id, chef_id, producer_id, 
                delivery_address, order_status, total_price, 
                notes, payment_status, payment_mode, 
                amount_paid, transaction_id, quantity
            ]

            result = self.db.cursor.execute(sql, parameters)
            order_id = result.fetchone()[0]  # Retrieve the generated order_id
            self.db.conn.commit()

            logger.info(f"Order successfully created with order_id: {order_id}")
            return {
                "message": "Order(s) created successfully",
                "orders": [
                    {
                        "message": "Order created successfully",
                        "order_id": order_id,
                        "success": True
                    }
                ],
                "success": True
            }

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating order: {sql_error}")
            return {
                "message": "Error creating order",
                "orders": [
                    {
                        "message": "Failed to create order",
                        "order_id": None,
                        "success": False
                    }
                ],
                "success": False
            }
        except Exception as e:
            logger.error(f"Error creating order: {str(e)}", exc_info=True)
            return {
                "message": "Error creating order",
                "orders": [
                    {
                        "message": "Failed to create order",
                        "order_id": None,
                        "success": False
                    }
                ],
                "success": False
            }

    def read_orders(self, order_id=None, chef_id=None, producer_id=None, user_id=None):
        try:
            # Define SQL query with CTE for meal details and ingredient aggregation
            sql = """
                WITH MealDetails AS (
                    SELECT 
                        m.Meal_id,
                        m.Meal_name,
                        COALESCE(
                            (SELECT STRING_AGG(p.Produce_name, ', ') 
                             FROM Meal_Ingredients i
                             JOIN Produce p ON i.Produce_ID = p.Produce_ID
                             WHERE i.Meal_id = m.Meal_id), 
                            ''
                        ) AS Ingredients
                    FROM Meals m
                )
                SELECT 
                    o.order_id,
                    o.user_id,
                    o.order_type,
                    o.product_id,
                    o.chef_id,
                    o.producer_id,
                    o.order_date,
                    o.delivery_address,
                    o.order_status,
                    o.total_price,
                    o.notes,
                    o.payment_status,
                    o.payment_mode,
                    o.amount_paid,
                    o.transaction_id,
                    o.quantity,
                    md.Meal_name AS meal_name,
                    md.Ingredients AS ingredients,
                    p.Name AS producer_name, -- Correct column name from Producers table
                    c.Name AS chef_name      -- Correct column name from Chefs table
                FROM Orders o
                LEFT JOIN MealDetails md ON o.product_id = md.Meal_id
                LEFT JOIN Producers p ON o.producer_id = p.Producer_Id -- Correct column name from Producers table
                LEFT JOIN Chefs c ON o.chef_id = c.ChefID             -- Correct column name from Chefs table
                WHERE 1=1
            """
            parameters = []

            # Add filters based on provided arguments
            if order_id:
                sql += " AND o.order_id=?"
                parameters.append(order_id)
            if chef_id:
                sql += " AND o.chef_id=?"
                parameters.append(chef_id)
            if producer_id:
                sql += " AND o.producer_id=?"
                parameters.append(producer_id)
            if user_id:
                sql += " AND o.user_id=?"
                parameters.append(user_id)

            # Execute the query
            self.db.cursor.execute(sql, parameters)

            # Check if results are returned
            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            # Convert results into a list of dictionaries
            columns = [column[0] for column in self.db.cursor.description]
            results = [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]

            # Log the retrieved orders
            logger.info(f"Retrieved {len(results)} orders")
            return results

        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while reading orders: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error reading orders: {str(e)}", exc_info=True)
            raise ValueError(str(e))

# CRUD operations for Metrics History
class MetricsHistory:
    def __init__(self, db):
        self.db = db

    def create_metric_history(self, metric_history_data):
        try:
            check_required_fields(metric_history_data, ['User_id', 'Weight'])
            sql = """
                INSERT INTO Metrics_history (User_id, Weight, Logged_at) VALUES (?, ?, ?)
            """
            self.db.cursor.execute(sql, (
                metric_history_data['User_id'], metric_history_data['Weight'], datetime.now()
            ))
            self.db.conn.commit()
            return {"MetricHistoryId": self.db.cursor.execute("SELECT SCOPE_IDENTITY()").fetchval()}
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while creating metric history: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error creating metric history: {e}")
            raise ValueError(str(e))

    def update_metric_history(self, log_id, updates):
        try:
            if not updates:
                raise ValueError("At least one field must be provided for updates.")

            sql = "UPDATE Metrics_history SET "
            set_statements = []
            parameters = []

            for key, value in updates.items():
                set_statements.append(f"{key}=?")
                parameters.append(value)

            sql += ", ".join(set_statements)
            sql += " WHERE Log_id=?"
            parameters.append(log_id)

            self.db.cursor.execute(sql, parameters)
            self.db.conn.commit()
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while updating metric history (Log ID: {log_id}): {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error updating metric history (Log ID: {log_id}): {e}")
            raise ValueError(str(e))

    def list_metric_history(self, user_id=None):
        try:
            sql = "SELECT * FROM Metrics_history"
            parameters = []

            if user_id:
                sql += " WHERE User_id=?"
                parameters.append(user_id)

            self.db.cursor.execute(sql, parameters)

            if self.db.cursor.description is None:
                raise ValueError("No results returned from the database query.")

            columns = [column[0] for column in self.db.cursor.description]
            return [dict(zip(columns, row)) for row in self.db.cursor.fetchall()]
        except pyodbc.Error as sql_error:
            logger.error(f"SQL error while listing metric history: {sql_error}")
            raise ValueError(f"Database error: {sql_error}")
        except Exception as e:
            logger.error(f"Error listing metric history: {e}")
            raise ValueError(str(e))

# Usage example (for testing)
if __name__ == "__main__":
    db = Database()
    try:
        users = Users(db)
        created_user_response = users.create_user({
            'Name': 'Alice', 
            'Password': 'password123', 
            'Email': 'alice@example.com'
        })
        print(f"Created User Response: {created_user_response}")

        login_response = users.login_user('alice@example.com', 'password123')
        print(f"Login Response: {login_response}")

        # Create a metric for the user
        metric_response = users.create_metric({
            'User_id': created_user_response['UserId'],
            'Age_range': '26-35',
            'Weight': 70,
            'Height': 170,
            'Cholesterol_level': 190,
            'Sys_bp': 120,
            'Dia_bp': 80,
            'Pulse': 70
        })
        print(f"Created Metric Response: {metric_response}")

        # Create a metric history for the user
        metric_history_response = users.create_metric_history({
            'User_id': created_user_response['UserId'],
            'Weight': 68
        })
        print(f"Created Metric History Response: {metric_history_response}")

        # List all metrics for the user
        all_metrics = users.list_metrics(user_id=created_user_response['UserId'])
        print("All Metrics:", all_metrics)

        # List all metric history for the user
        all_metric_history = users.list_metric_history(user_id=created_user_response['UserId'])
        print("All Metric History:", all_metric_history)

        # Create user preferences
        preference_response = users.create_preference({
            'User_id': created_user_response['UserId'],
            'Goals': 'Weight Loss',
            'Diet_type': 'Vegan',
            'Food_restrictions': 'Nuts',
            'Cuisine_preferences': 'Asian'
        })
        print(f"Created Preference Response: {preference_response}")

        # Update the user's preferences
        users.update_preference(preference_response['PreferenceId'], {'Goals': 'Muscle Gain'})

        # List preferences for the user
        all_preferences = users.list_preferences(user_id=created_user_response['UserId'])
        print("All Preferences:", all_preferences)

    except ValueError as ve:
        print(f"ValueError: {ve}")
    except Exception as ex:
        print(f"Unexpected error: {ex}")
    finally:
        db.close()