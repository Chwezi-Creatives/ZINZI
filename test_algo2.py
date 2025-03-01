import pyodbc
import logging
from typing import Optional, Dict, List

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