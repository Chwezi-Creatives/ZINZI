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
                SELECT Goals, Diet_type, Food_restrictions, Cuisine_preferences
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
                SELECT Weight, Height, Cholesterol_level, Sys_bp, Dia_bp, Pulse, Age_range, Sex, Activity_level
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
                    "activity_level": result[8].strip().lower() if result[8] else "sedentary"
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
            return 2000  # Default calorie budget # Mifflin-St Jeor equation for BMR and TDEE calculation

        weight = self.user_metrics["weight"]
        height = self.user_metrics["height"]
        age = int(self.user_metrics["age_range"].split("-")[0])
        sex = self.user_metrics["sex"]

        if sex == "male":
            bmr = 10 * weight + 6.25 * height - 5 * age + 5
        else:
            bmr = 10 * weight + 6.25 * height - 5 * age - 161

        activity_level = self.user_metrics.get("activity_level", "sedentary")
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

        return round(tdee, 1)  # Round to 1 decimal place

    def fetch_all_meals(self) -> Optional[List[Dict]]:
        """Fetch all meals from the database with calorie calculations and aggregated ingredients."""
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
                    STRING_AGG(pr.Produce_name, ', ') AS Ingredients  -- Aggregated ingredients
                FROM Meals m
                LEFT JOIN Meal_ingredients mi ON m.Meal_id = mi.Meal_id
                LEFT JOIN Produce pr ON mi.Produce_id = pr.Produce_id
                GROUP BY 
                    m.Meal_id, m.Meal_name, m.Meal_category, 
                    m.Recipe, m.Recipe_link, m.Image_link,
                    m.Goal, m.Dietary_preference, m.Allergies, 
                    m.Disease_management, m.Cuisine_preferences, 
                    m.Skill_level, m.Prep_time,
                    m.Meal_description
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

            # Add nutritional info for each meal
            for meal in meals:
                meal["Nutritional_Info"] = self.calculate_nutritional_info(meal)

            return meals

        except pyodbc.Error as e:
            logging.error(f"Error fetching meals: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def calculate_nutritional_info(self, meal) -> Dict[str, float]:
        """Calculate total nutritional info percentages for a meal based on meal grams."""
        ingredients = meal.get("Ingredients", "").split(", ") if meal.get("Ingredients") else []
        total_nutrition = {
            "calories": 0,  # Total calories in the meal
            "cholesterol": 0,
            "carbohydrates": 0,
            "proteins": 0,
            "fats": 0,
            "fiber": 0,
            "sugars": 0,
            "total_weight": 0  # Total weight in grams
        }

        for ingredient in ingredients:
            nutrition_data = self.fetch_nutrition_data(ingredient.strip().lower())
            if nutrition_data:
                ingredient_weight = nutrition_data["unit_grams"]  # Weight of the specific unit
                # Calculate nutrient totals based on actual grams used
                total_nutrition["calories"] += nutrition_data["calories"] * (ingredient_weight / 100)
                total_nutrition["cholesterol"] += nutrition_data["cholesterol"] * (ingredient_weight / 100)
                total_nutrition["carbohydrates"] += nutrition_data["carbohydrates"] * (ingredient_weight / 100)
                total_nutrition["proteins"] += nutrition_data["proteins"] * (ingredient_weight / 100)
                total_nutrition["fats"] += nutrition_data["fats"] * (ingredient_weight / 100)
                total_nutrition["fiber"] += nutrition_data["fiber"] * (ingredient_weight / 100)
                total_nutrition["sugars"] += nutrition_data["sugars"] * (ingredient_weight / 100)
                total_nutrition["total_weight"] += ingredient_weight  # Track the total weight of all ingredients

        # Calculate percentages for each nutrient based on total weight
        for nutrient in total_nutrition.keys():
            if nutrient != "total_weight":
                total_nutrition[nutrient] = round(
                    (total_nutrition[nutrient] / total_nutrition["total_weight"]) * 100 if total_nutrition["total_weight"] > 0 else 0,
                    1  # Round to 1 decimal place
                )

        # Round total_weight and calories to 1 decimal place
        total_nutrition["total_weight"] = round(total_nutrition["total_weight"], 1)
        total_nutrition["calories"] = round(total_nutrition["calories"], 1)

        return total_nutrition

    def fetch_nutrition_data(self, ingredient) -> Optional[Dict]:
        """Fetch nutritional data for a specific ingredient from the Produce table."""
        connection = get_db_connection()
        if connection is None:
            logging.error("Database connection failed.")
            return None

        try:
            cursor = connection.cursor()
            query = """
                SELECT 
                    Calories, 
                    Unit_grams, 
                    Cholesterol, 
                    Carbohydrates, 
                    Proteins, 
                    Fats, 
                    Fiber, 
                    Sugars 
                FROM Produce 
                WHERE Produce_name = ?
            """
            cursor.execute(query, (ingredient,))
            result = cursor.fetchone()
            if result:
                return {
                    "calories": result[0],
                    "unit_grams": result[1],
                    "cholesterol": result[2],
                    "carbohydrates": result[3],
                    "proteins": result[4],
                    "fats": result[5],
                    "fiber": result[6],
                    "sugars": result[7]
                }
            else:
                logging.warning(f"No nutritional data found for ingredient: {ingredient}")
                return None

        except pyodbc.Error as e:
            logging.error(f"Error fetching nutritional data for {ingredient}: {e}")
            return None
        finally:
            if connection:
                connection.close()

    def calculate_calorie_density(self, meal) -> float:
        """Calculate the calorie density (calories per gram) of a meal."""
        total_calories = meal["Nutritional_Info"].get("calories", 0)
        total_weight = meal["Nutritional_Info"].get("total_weight", 1)  # Avoid division by zero

        # Calculate calorie density
        calorie_density = total_calories / total_weight if total_weight > 0 else 0
        return round(calorie_density, 1)  # Round to 1 decimal place

    def calculate_serving_size(self, meal, meal_type: str) -> float:
        """Calculate the serving size (in grams) for a meal based on the user's calorie budget and meal type."""
        calorie_density = self.calculate_calorie_density(meal)
        if calorie_density <= 0:
            return 0

        # Adjust calorie budget based on meal type
        meal_type_calorie_contribution = {
            "breakfast": 0.25,
            "lunch": 0.35,
            "dinner": 0.35,
            "snack": 0.05,
        }.get(meal_type.lower(), 0.25)  # Default to 25% if meal type is unknown

        adjusted_calorie_budget = self.daily_calorie_budget * meal_type_calorie_contribution

        # Calculate serving size to fit within the adjusted calorie budget
        serving_size = adjusted_calorie_budget / calorie_density
        return round(serving_size, 1)  # Round to 1 decimal place

    def filter_meals(self) -> List[Dict]:
        """Filter meals based on user preferences, metrics, and calorie budget."""
        meals = self.fetch_all_meals()
        if not meals:
            return []

        filtered_meals = []
        for meal in meals:
            # Determine meal type (default to "lunch" if not specified)
            meal_type = meal.get("meal_category", "lunch").lower()

            # Calorie budget filter
            serving_size = self.calculate_serving_size(meal, meal_type)
            if serving_size > 0:
                meal["amount_to_serve"] = round(serving_size, 1)  # Round to 1 decimal place

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
user_id = 138
meal_recommender2 = MealRecommendation2(user_id)
recommendations = meal_recommender2.recommend_meals()
print(recommendations)