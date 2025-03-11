import pyodbc
from datetime import datetime

class Database:
    def __init__(self, server, database, username, password):
        self.connection_string = f'DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}'
        self.conn = pyodbc.connect(self.connection_string)
        self.cursor = self.conn.cursor()

    def close(self):
        self.cursor.close()
        self.conn.close()

# CRUD operations for Users
class Users:
    def __init__(self, db):
        self.db = db
        
    def create_user(self, user_data):
        sql = """
            INSERT INTO Users (Username, Password, Email, Date_created, Salt, Is_verified)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            user_data.get('Username'),
            user_data.get('Password'),
            user_data.get('Email'),
            user_data.get('Date created', datetime.now()),
            user_data.get('Salt', None),
            user_data.get('Is verified', 1)
        ))
        self.db.conn.commit()

    def read_users(self):
        sql = "SELECT * FROM Users"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_user(self, user_id, updates):
        sql = "UPDATE Users SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE User_id=?"
        parameters.append(user_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_user(self, user_id):
        sql = "DELETE FROM Users WHERE User_id=?"
        self.db.cursor.execute(sql, user_id)
        self.db.conn.commit()


# CRUD operations for Chefs
class Chefs:
    def __init__(self, db):
        self.db = db
    
    def create_chef(self, chef_data):
        sql = """
            INSERT INTO Chefs (Image, Name, Price, Rating, Location, Experience, [Service Radius],
                [Response Time], [MinNotice], Punctuality, TeamSize, Equipment, Bio, Availability,
                Languages, Specialties, Certifications, SampleMenu, Reviews, [is active],
                registration_date, added_by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            chef_data.get('Image'),
            chef_data.get('Name'),
            chef_data.get('Price'),
            chef_data.get('Rating'),
            chef_data.get('Location'),
            chef_data.get('Experience'),
            chef_data.get('Service Radius'),
            chef_data.get('Response Time'),
            chef_data.get('MinNotice'),
            chef_data.get('Punctuality'),
            chef_data.get('TeamSize'),
            chef_data.get('Equipment'),
            chef_data.get('Bio'),
            chef_data.get('Availability'),
            chef_data.get('Languages'),
            chef_data.get('Specialties'),
            chef_data.get('Certifications'),
            chef_data.get('SampleMenu'),
            chef_data.get('Reviews'),
            chef_data.get('is active', 1),
            chef_data.get('registration_date', datetime.now()),
            chef_data.get('added_by'),
            chef_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_chefs(self):
        sql = "SELECT * FROM Chefs"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_chef(self, chef_id, updates):
        sql = "UPDATE Chefs SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE ChefID=?"
        parameters.append(chef_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_chef(self, chef_id):
        sql = "DELETE FROM Chefs WHERE ChefID=?"
        self.db.cursor.execute(sql, chef_id)
        self.db.conn.commit()


# CRUD operations for Herbals
class Herbals:
    def __init__(self, db):
        self.db = db

    def create_herbal(self, herbal_data):
        sql = """
            INSERT INTO Herbals (herbal name, description, unit, price, image_url, date added, added_by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            herbal_data.get('herbal name'),
            herbal_data.get('description'),
            herbal_data.get('unit'),
            herbal_data.get('price'),
            herbal_data.get('image_url'),
            herbal_data.get('date added', datetime.now()),
            herbal_data.get('added_by'),
            herbal_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_herbals(self):
        sql = "SELECT * FROM Herbals"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_herbal(self, herbal_id, updates):
        sql = "UPDATE Herbals SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE herbal id=?"
        parameters.append(herbal_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_herbal(self, herbal_id):
        sql = "DELETE FROM Herbals WHERE herbal id=?"
        self.db.cursor.execute(sql, herbal_id)
        self.db.conn.commit()


# CRUD operations for Meals
class Meals:
    def __init__(self, db):
        self.db = db

    def create_meal(self, meal_data):
        sql = """
            INSERT INTO Meals (Meal_name, Meal_category, Ingredients, Complementary_dishes, Recipe, Recipe_link,
                Image_link, Goal, Dietary_preference, Allergies, Disease management,
                Cuisine preferences, Skill level, Prep_time, meal_description, date added, date last edited, added_by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            meal_data.get('Meal name'),
            meal_data.get('Meal_category'),
            meal_data.get('Ingredients'),
            meal_data.get('Complementary_dishes'),
            meal_data.get('Recipe'),
            meal_data.get('Recipe_link'),
            meal_data.get('Image_link'),
            meal_data.get('Goal'),
            meal_data.get('Dietary_preference'),
            meal_data.get('Allergies'),
            meal_data.get('Disease management'),
            meal_data.get('Cuisine preferences'),
            meal_data.get('Skill level'),
            meal_data.get('Prep_time'),
            meal_data.get('meal_description'),
            meal_data.get('date added', datetime.now()),
            meal_data.get('date last edited', datetime.now()),
            meal_data.get('added_by'),
            meal_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_meals(self):
        sql = "SELECT * FROM Meals"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_meal(self, meal_id, updates):
        sql = "UPDATE Meals SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE [Meal id]=?"
        parameters.append(meal_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_meal(self, meal_id):
        sql = "DELETE FROM Meals WHERE [Meal id]=?"
        self.db.cursor.execute(sql, meal_id)
        self.db.conn.commit()


# CRUD operations for Produce
class Produce:
    def __init__(self, db):
        self.db = db

    def create_produce(self, produce_data):
        sql = """
            INSERT INTO Produce (Produce name, Unit_grams, Calories, Cholesterol, Carbohydrates, Proteins, Fats, fiber, sugars,
            Meal_type, Source, Nutritional info, date added, date last edited, added by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            produce_data.get('Produce name'),
            produce_data.get('Unit_grams'),
            produce_data.get('Calories'),
            produce_data.get('Cholesterol'),
            produce_data.get('Carbohydrates'),
            produce_data.get('Proteins'),
            produce_data.get('Fats'),
            produce_data.get('fiber'),
            produce_data.get('sugars'),
            produce_data.get('Meal_type'),
            produce_data.get('Source'),
            produce_data.get('Nutritional info'),
            produce_data.get('date added', datetime.now()),
            produce_data.get('date last edited', datetime.now()),
            produce_data.get('added by'),
            produce_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_produce(self):
        sql = "SELECT * FROM Produce"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_produce(self, produce_id, updates):
        sql = "UPDATE Produce SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE [Produce ID]=?"
        parameters.append(produce_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_produce(self, produce_id):
        sql = "DELETE FROM Produce WHERE [Produce ID]=?"
        self.db.cursor.execute(sql, produce_id)
        self.db.conn.commit()


# CRUD operations for Producers
class Producers:
    def __init__(self, db):
        self.db = db

    def create_producer(self, producer_data):
        sql = """
            INSERT INTO Producers (producer_name, address, phone_number, email, registration_date, producer_type, last_login, rating, added_by, [is active], added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            producer_data.get('producer_name'),
            producer_data.get('address'),
            producer_data.get('phone_number'),
            producer_data.get('email'),
            producer_data.get('registration_date', datetime.now()),
            producer_data.get('producer_type'),
            producer_data.get('last_login', None),
            producer_data.get('rating', None),
            producer_data.get('added_by'),
            producer_data.get('is active', 1),
            producer_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_producers(self):
        sql = "SELECT * FROM Producers"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_producer(self, producer_id, updates):
        sql = "UPDATE Producers SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE producer_id=?"
        parameters.append(producer_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_producer(self, producer_id):
        sql = "DELETE FROM Producers WHERE producer_id=?"
        self.db.cursor.execute(sql, producer_id)
        self.db.conn.commit()


# CRUD operations for Gadgets
class Gadgets:
    def __init__(self, db):
        self.db = db

    def create_gadget(self, gadget_data):
        sql = """
            INSERT INTO Gadgets (gadget_name, description, brand, model, price, image_url, date added, added by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            gadget_data.get('gadget_name'),
            gadget_data.get('description'),
            gadget_data.get('brand'),
            gadget_data.get('model'),
            gadget_data.get('price'),
            gadget_data.get('image_url'),
            gadget_data.get('date added', datetime.now()),
            gadget_data.get('added by'),
            gadget_data.get('added_by_type', 'default')
        ))
        self.db.conn.commit()

    def read_gadgets(self):
        sql = "SELECT * FROM Gadgets"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_gadget(self, gadget_id, updates):
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

    def delete_gadget(self, gadget_id):
        sql = "DELETE FROM Gadgets WHERE gadget_id=?"
        self.db.cursor.execute(sql, gadget_id)
        self.db.conn.commit()


# CRUD operations for Spices
class Spices:
    def __init__(self, db):
        self.db = db

    def create_spice(self, spice_data):
        sql = """
            INSERT INTO Spices (spice_name, description, unit, price, image_url, date added, added by, added_by_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            spice_data.get('spice_name'),
            spice_data.get('description'),
            spice_data.get('unit'),
            spice_data.get('price'),
            spice_data.get('image_url'),
            spice_data.get('date added', datetime.now()),
            spice_data.get('added by'),
            spice_data.get('added_by_type', 'default'),
        ))
        self.db.conn.commit()

    def read_spices(self):
        sql = "SELECT * FROM Spices"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_spice(self, spice_id, updates):
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

    def delete_spice(self, spice_id):
        sql = "DELETE FROM Spices WHERE spice_id=?"
        self.db.cursor.execute(sql, spice_id)
        self.db.conn.commit()


# CRUD operations for Stakeholders
class Stakeholders:
    def __init__(self, db):
        self.db = db

    def create_stakeholder(self, stakeholder_data):
        sql = """
            INSERT INTO Stakeholders (username, email, password_hash, full name, last_login)
            VALUES (?, ?, ?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            stakeholder_data.get('username'),
            stakeholder_data.get('email'),
            stakeholder_data.get('password_hash'),
            stakeholder_data.get('full name'),
            stakeholder_data.get('last_login', None)
        ))
        self.db.conn.commit()

    def read_stakeholders(self):
        sql = "SELECT * FROM Stakeholders"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_stakeholder(self, stakeholder_id, updates):
        sql = "UPDATE Stakeholders SET "
        set_statements = []
        parameters = []

        for key, value in updates.items():
            set_statements.append(f"{key}=?")
            parameters.append(value)

        sql += ", ".join(set_statements)
        sql += " WHERE stakeholder id=?"
        parameters.append(stakeholder_id)

        self.db.cursor.execute(sql, parameters)
        self.db.conn.commit()

    def delete_stakeholder(self, stakeholder_id):
        sql = "DELETE FROM Stakeholders WHERE stakeholder id=?"
        self.db.cursor.execute(sql, stakeholder_id)
        self.db.conn.commit()


# CRUD operations for Orders (Read-only)
class Orders:
    def __init__(self, db):
        self.db = db

    def read_orders(self):
        sql = "SELECT * FROM Orders"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()


# Read-only operations for Email Verifications
class EmailVerifications:
    def __init__(self, db):
        self.db = db

    def read_verifications(self):
        sql = "SELECT * FROM [Email Verifications]"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()


# CRUD operations for Metrics History
class MetricsHistory:
    def __init__(self, db):
        self.db = db

    def create_metric(self, metric_data):
        sql = """
            INSERT INTO Metrics_history (User id, Weight, Logged_at)
            VALUES (?, ?, ?)
        """
        self.db.cursor.execute(sql, (
            metric_data.get('User id'),
            metric_data.get('Weight'),
            metric_data.get('Logged_at', datetime.now())
        ))
        self.db.conn.commit()

    def read_metrics(self):
        sql = "SELECT * FROM Metrics_history"
        self.db.cursor.execute(sql)
        return self.db.cursor.fetchall()

    def update_metric(self, log_id, updates):
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

    def delete_metric(self, log_id):
        sql = "DELETE FROM Metrics_history WHERE Log_id=?"
        self.db.cursor.execute(sql, log_id)
        self.db.conn.commit()


# Usage example with your database
if __name__ == "__main__":
    db = Database(server='your_server', database='your_database', username='your_username', password='your_password')

    users = Users(db)
    chefs = Chefs(db)
    herbals = Herbals(db)
    meals = Meals(db)
    produce = Produce(db)
    producers = Producers(db)
    gadgets = Gadgets(db)
    spices = Spices(db)
    stakeholders = Stakeholders(db)
    email_verifications = EmailVerifications(db)
    metrics_history = MetricsHistory(db)
    orders = Orders(db)

    # Example: Creating a new user
    new_user = {
        'Username': 'john_doe',
        'Password': 'password123',
        'Email': 'john@example.com',
    }
    users.create_user(new_user)

    # Example: Creating a new chef
    new_chef = {
        'Image': 'chef_image_url',
        'Name': 'Chef Example',
        'Price': 100.00,
        'Rating': 4.5,
        'Location': 'New York'
    }
    chefs.create_chef(new_chef)

    # Reading all users
    all_users = users.read_users()
    for user in all_users:
        print(user)

    # Reading chefs
    all_chefs = chefs.read_chefs()
    for chef in all_chefs:
        print(chef)

    # Reading orders (read-only)
    all_orders = orders.read_orders()
    for order in all_orders:
        print(order)

    # Reading email verifications
    all_verifications = email_verifications.read_verifications()
    for verification in all_verifications:
        print(verification)

    db.close()