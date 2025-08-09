import pyodbc
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