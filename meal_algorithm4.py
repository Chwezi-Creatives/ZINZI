#cspell:disable
import logging
from typing import Optional, Dict, List
from database import get_db_connection
from datetime import datetime, timedelta
from psycopg2.extras import RealDictCursor
import json
import hashlib

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# Database connection is now handled by database.py


class MealRecommendation4:
    # Class-level cache for shared data across instances
    _shared_cache = {
        'all_meals': None,  # Cache for all meals from database
        'nutrition_data': {},  # Cache for nutrition data
        'last_update': datetime.now()
    }
    
    def __init__(self, user_id: int):
        self.user_id = user_id
        # Instance-specific cache
        self._cache = {
            'filtered_meals': None,  # Cache for filtered meals for this user
            'last_update': datetime.now(),
            'user_data_hash': None  # Will be set after user data is loaded
        }
        # Initialize nutrition cache if missing
        if 'nutrition_data' not in self.__class__._shared_cache:
            self.__class__._shared_cache['nutrition_data'] = {}
        # Fetch user data immediately
        self.user_preferences = self.get_user_preferences()
        self.user_metrics = self.get_user_metrics()
        self.daily_calorie_budget = self.calculate_daily_calorie_budget()
        
        # Set initial user data hash after loading user data
        self._cache['user_data_hash'] = self._get_user_data_hash()

    def get_user_preferences(self) -> Optional[Dict]:
        """Fetch user preferences from the database."""
        try:
            connection = get_db_connection()
            if connection is None:
                logging.error("Database connection failed.")
                return None

            cursor = connection.cursor()
            query = """
                SELECT goals, diet_type, food_restrictions, cuisine_preferences
                FROM user_preferences
                WHERE user_id = %s
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

        except Exception as e:
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
                SELECT weight, height, cholesterol_level, sys_bp, dia_bp, pulse, age_range, sex, activity_level
                FROM user_metrics
                WHERE user_id = %s
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

        except Exception as e:
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

    def fetch_all_meals(self) -> List[Dict]:
        """Fetch all meals from the database with calorie calculations and aggregated ingredients.
        Uses class-level shared cache to improve performance across instances.
        Meal data is cached for 24 hours since ingredients rarely change."""
        try:
            # Check class-level shared cache first
            now = datetime.now()
            cache_age = now - self.__class__._shared_cache['last_update']
            
            # Return cached data if it's less than 24 hours old (ingredients rarely change)
            if self.__class__._shared_cache['all_meals'] is not None and cache_age < timedelta(hours=24):
                logging.info("Using cached meals data")
                return self.__class__._shared_cache['all_meals']

            logging.info("Fetching meals from database (cache expired or empty)")
            connection = get_db_connection()
            if not connection:
                return []

            with connection.cursor() as cursor:
                # Optimized query with JOINs and indexes
                query = """
                    SELECT 
                        m.*,
                        string_agg(DISTINCT pr.produce_name, ', ') AS ingredients,
                        COALESCE(SUM(mi.produce_quantity_in_grams), 0) as total_weight
                    FROM meals m
                    LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
                    LEFT JOIN produce pr ON mi.produce_id = pr.produce_id
                    GROUP BY m.meal_id
                    ORDER BY m.meal_name
                """
                cursor.execute(query)
                results = cursor.fetchall()

                meals = []
                for row in results:
                    meal = dict(zip([col.name for col in cursor.description], row))
                    meal["ingredients"] = meal["ingredients"] if meal["ingredients"] else ""
                    meal["total_weight"] = meal["total_weight"] or 0
                    meal["price"] = 10000  # Add price field
                    meals.append(meal)

                # Calculate nutritional info for each meal
                for meal in meals:
                    nutritional_info = self.calculate_nutritional_info(meal)
                    meal["Nutritional_Info"] = nutritional_info

                # Update the class-level shared cache
                self.__class__._shared_cache['all_meals'] = meals
                self.__class__._shared_cache['last_update'] = now
                logging.info(f"Updated shared meals cache with {len(meals)} meals")

                return meals

        except Exception as e:
            logging.error(f"Error fetching meals: {e}")
            return []

    def calculate_nutritional_info(self, meal) -> Dict[str, float]:
        """Calculate total nutritional info percentages for a meal based on meal grams.
        Also calculate nutrient scores based on categorical levels."""
        try:
            if not meal or not isinstance(meal, dict):
                return {}

            # Initialize numerical nutritional values
            numerical_nutrition = {
                "calories": 0,  # Total calories in the meal
                "cholesterol": 0,
                "carbohydrates": 0,
                "proteins": 0,
                "fats": 0,
                "fiber": 0,
                "total_weight": 0  # Total weight in grams
            }

            # Initialize categorical nutrient levels
            categorical_levels = {
                "iron": "Non",
                "vitamins": "Non",
                "magnesium": "Non",
                "calcium": "Non",
                "potassium": "Non",
                "cobalamin": "Non",
                "sugar": "Non"
            }

            # Get meal ID safely
            meal_id = meal.get("meal_id")
            if not meal_id:
                return {**numerical_nutrition, **categorical_levels, "nutrient_score": 0}

            # Fetch ingredients for the meal
            connection = get_db_connection()
            if not connection:
                logging.error("Database connection failed.")
                return {**numerical_nutrition, **categorical_levels, "nutrient_score": 0}

            ingredients = []
            try:
                with connection.cursor() as cursor:
                    cursor.execute("""
                        SELECT produce_id, COALESCE(produce_quantity_in_grams, 0.0)
                        FROM meal_ingredients
                        WHERE meal_id = %s
                    """, (meal_id,))
                    ingredients = cursor.fetchall()
            except Exception as e:
                logging.error(f"Error fetching meal ingredients for meal {meal_id}: {e}")
                return {**numerical_nutrition, **categorical_levels, "nutrient_score": 0}
            finally:
                if connection:
                    connection.close()

            if not ingredients:
                logging.warning(f"No ingredients found for meal {meal_id}.")
                return {**numerical_nutrition, **categorical_levels, "nutrient_score": 0}

            # Aggregate nutritional values from ingredients
            for (produce_id, quantity) in ingredients:
                nutrition = self.fetch_nutrition_data(produce_id)
                if not nutrition:
                    logging.error(f"Missing nutrition data for produce {produce_id}")
                    continue

                # Calculate ratio based on 100g serving size in nutrition data
                # Ensure quantity is float for calculation and handle potential Decimal type
                try:
                    ratio = float(quantity) / 100.0
                except (TypeError, ValueError) as e:
                    logging.warning(f"Error converting quantity {quantity} to float: {e}")
                    # Try explicit string conversion first in case it's a Decimal
                    try:
                        ratio = float(str(quantity)) / 100.0
                    except Exception:
                        ratio = 0.0

                # Aggregate numerical values
                for nutrient in numerical_nutrition:
                    if nutrient != "total_weight": # total_weight is the sum of ingredient quantities
                         # Ensure nutrition value is float before calculation, only for numerical fields
                         nutrient_value = nutrition.get(nutrient, 0.0)
                         # Skip categorical string values in numerical calculations
                         if isinstance(nutrient_value, str) and nutrient_value in ['Non', 'Low', 'Moderate', 'High']:
                             logging.info(f"Skipping categorical value '{nutrient_value}' for {nutrient} in numerical calculation")
                             continue
                         # Explicitly check if the nutrient is expected to be numerical and not None
                         if nutrient in ["calories", "cholesterol", "carbohydrates", "proteins", "fats", "fiber"] and nutrient_value is not None and isinstance(nutrient_value, (int, float, str)) and (isinstance(nutrient_value, str) and nutrient_value.replace('.', '', 1).isdigit() or isinstance(nutrient_value, (int, float))):
                             numerical_nutrition[nutrient] += float(nutrient_value) * float(ratio)
                         else:
                             logging.warning(f"Skipping non-numerical or None nutrient {nutrient} with value {nutrient_value} for produce {produce_id}")

                # Aggregate total weight
                numerical_nutrition["total_weight"] += quantity

                # Aggregate categorical levels (take the highest level if multiple ingredients have the same nutrient)
                for nutrient in categorical_levels:
                    ingredient_level = nutrition.get(nutrient, "None")
                    current_level = categorical_levels[nutrient]
                    # Simple logic: if ingredient has a higher level than current, update
                    # Assuming levels are ordered: Non < Low < Moderate < High
                    level_order = {"Non": 0, "Low": 1, "Moderate": 2, "High": 3}
                    if level_order.get(ingredient_level, 0) > level_order.get(current_level, 0):
                         categorical_levels[nutrient] = ingredient_level

            # Calculate nutritional percentages
            if numerical_nutrition["total_weight"] > 0:
                # Ensure all values are floats before division and check for None values
                total_weight_float = float(numerical_nutrition["total_weight"])
                
                # Process each numerical nutrient, checking for None values
                numerical_nutrients = ["calories", "cholesterol", "carbohydrates", "proteins", "fats", "fiber"]
                for nutrient in numerical_nutrients:
                    value = numerical_nutrition.get(nutrient)
                    if value is None or not isinstance(value, (int, float, str)) or (isinstance(value, str) and not value.replace('.', '', 1).isdigit()):
                        logging.warning(f"Skipping non-numerical or None value for {nutrient}: {value}")
                        numerical_nutrition[f"{nutrient}_per_gram"] = 0.0
                    else:
                        numerical_nutrition[f"{nutrient}_per_gram"] = float(value) / total_weight_float

            # Combine numerical and categorical values
            total_nutrition = {**numerical_nutrition, **categorical_levels}

            # Calculate nutrient score
            nutrient_levels = {
                "Low": 1,
                "Moderate": 2,
                "High": 3,
                "Non": 0
            }
            total_nutrition["nutrient_score"] = (
                nutrient_levels.get(total_nutrition["iron"], 0) +
                nutrient_levels.get(total_nutrition["vitamins"], 0) +
                nutrient_levels.get(total_nutrition["magnesium"], 0) +
                nutrient_levels.get(total_nutrition["calcium"], 0) +
                nutrient_levels.get(total_nutrition["potassium"], 0) +
                nutrient_levels.get(total_nutrition["cobalamin"], 0) +
                nutrient_levels.get(total_nutrition["sugar"], 0)
            )

            return total_nutrition

        except Exception as e:
            logging.error(f"Error in calculate_nutritional_info for meal {meal_id}: {e}")
            return {**numerical_nutrition, **categorical_levels, "nutrient_score": 0}

    def calculate_calorie_density(self, meal) -> float:
        """Calculate the calorie density (calories per gram) of a meal."""
        try:
            total_calories = float(meal["Nutritional_Info"].get("calories", 0))
            total_weight = float(meal["Nutritional_Info"].get("total_weight", 1))  # Avoid division by zero

            # Calculate calorie density with explicit float conversion
            calorie_density = total_calories / total_weight if total_weight > 0 else 0
            return round(calorie_density, 1)  # Round to 1 decimal place
        except (TypeError, ValueError) as e:
            logging.warning(f"Error in calorie density calculation: {e}")
            # Try explicit string conversion in case of Decimal values
            try:
                total_calories = float(str(meal["Nutritional_Info"].get("calories", 0)))
                total_weight = float(str(meal["Nutritional_Info"].get("total_weight", 1)))
                calorie_density = total_calories / total_weight if total_weight > 0 else 0
                return round(calorie_density, 1)
            except Exception as inner_e:
                logging.error(f"Failed to calculate calorie density: {inner_e}")
                return 0.0

    def calculate_serving_size(self, meal, meal_type: str) -> float:
        """Calculate the serving size (in grams) for a meal based on the user's calorie budget and meal type.
        Also consider the actual produce quantities used in the meal."""
        try:
            if not meal or not meal.get("meal_id"):
                return 0

            # Get calorie density safely
            calorie_density = self.calculate_calorie_density(meal)
            if calorie_density <= 0:
                return 0

            # Calculate target calories based on meal type
            daily_calories = self.daily_calorie_budget or 2000  # Default to 2000 if not set
            target_calories = {
                "breakfast": daily_calories * 0.25,
                "lunch": daily_calories * 0.35,
                "dinner": daily_calories * 0.40,
                "snack": daily_calories * 0.10
            }.get(meal_type.lower(), daily_calories * 0.25)  # Default to breakfast if type is unknown

            # Calculate serving size with safe division
            try:
                # Ensure both values are converted to float to prevent decimal.Decimal type mismatch
                serving_size = float(target_calories) / float(calorie_density)
            except ZeroDivisionError:
                logging.warning(f"Zero division error in serving size calculation for meal {meal.get('meal_id')}")
                return 0
            except TypeError as e:
                logging.error(f"Type error in serving size calculation: {e}")
                # Explicitly convert any potential Decimal values
                try:
                    serving_size = float(target_calories) / float(calorie_density)
                except Exception as inner_e:
                    logging.error(f"Failed to convert values for calculation: {inner_e}")
                    return 0

            # Get actual meal weight safely
            try:
                connection = get_db_connection()
                if not connection:
                    return serving_size

                with connection.cursor() as cursor:
                    cursor.execute("""
                        SELECT COALESCE(SUM(produce_quantity_in_grams), 0) as total_weight
                        FROM meal_ingredients
                        WHERE meal_id = %s
                    """, (meal.get("meal_id"),))
                    result = cursor.fetchone()
                    if result:
                        actual_total_weight = float(result[0] or 0)
                        serving_size = min(serving_size, actual_total_weight)

            except Exception as e:
                logging.error(f"Error getting meal weight: {e}")
            finally:
                if connection:
                    connection.close()

            # Round to nearest 10 grams
            return round(serving_size, -1)

        except Exception as e:
            logging.error(f"Error calculating serving size: {e}")
            return 0

    def calculate_meal_calories(self, meal_id: str) -> Dict:
        """
        Calculate calories and nutritional information for a specific meal.
        
        Args:
            meal_id: ID of the meal to calculate calories for
            
        Returns:
            Dictionary containing:
            - calories: Total calories in the meal
            - nutritional_info: Full nutritional information
            - serving_size: Recommended serving size in grams
            - meal_name: Name of the meal
        """
        try:
            connection = get_db_connection()
            if not connection:
                return {"error": "Database connection failed"}

            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT mi.produce_id, mi.produce_quantity_in_grams
                    FROM meal_ingredients mi
                    WHERE mi.meal_id = %s
                """, (meal_id,))
                ingredients = cursor.fetchall()

            total_weight = 0
            nutritional_values = {
                "calories": 0.0,
                "carbohydrates": 0.0,
                "proteins": 0.0,
                "fats": 0.0,
                "fiber": 0.0,
                # Sugar is now a categorical value, not numerical
                "sugar": "Non"
            }
            
            # Define which nutrients are categorical vs numerical
            categorical_nutrients = ["sugar", "iron", "vitamins", "magnesium", "calcium", "potassium", "cobalamin"]

            for (produce_id, quantity) in ingredients:
                nutrition = self.fetch_nutrition_data(produce_id)
                if not nutrition:
                    logging.error(f"Missing nutrition data for {produce_id}")
                    continue
                
                ratio = float(quantity) / 100.0
                for nutrient in nutritional_values:
                    # Get nutrient value with default based on type
                    nutrient_value = nutrition.get(nutrient, 0 if nutrient not in categorical_nutrients else "Non")
                    
                    # Handle categorical nutrients differently
                    if nutrient in categorical_nutrients:
                        # For categorical nutrients, take the highest level
                        if nutrient_value in ["Low", "Moderate", "High"]:
                            current_level = nutritional_values[nutrient]
                            level_order = {"Non": 0, "Low": 1, "Moderate": 2, "High": 3}
                            if level_order.get(nutrient_value, 0) > level_order.get(current_level, 0):
                                nutritional_values[nutrient] = nutrient_value
                        continue
                    
                    # For numerical nutrients, perform calculations
                    try:
                        nutritional_values[nutrient] += float(nutrient_value) * float(ratio)
                    except (ValueError, TypeError) as e:
                        logging.warning(f"Error converting {nutrient} value '{nutrient_value}' to float: {e}")
                        # Skip this nutrient if conversion fails
                total_weight += quantity

            if nutritional_values["calories"] == 0:
                logging.error(f"Zero calories calculated for {meal_id}")

            return {
                "calories": nutritional_values["calories"],
                "nutritional_info": nutritional_values,
                "serving_size": total_weight,
                "meal_id": meal_id,
                "meal_name": ""  # Name retrieval removed for brevity
            }

        except Exception as e:
            logging.error(f"Error calculating meal calories: {e}")
            return {"error": str(e)}

    def filter_meals(self) -> List[Dict]:
        """Filter meals based on user preferences, metrics, and nutrient scores.
        Uses instance-level cache to improve performance for repeated requests.
        Cache is invalidated when user preferences or metrics change."""
        try:
            # Check if user data has changed since last cache update
            user_data_hash = self._get_user_data_hash()
            
            # Check instance cache first
            now = datetime.now()
            cache_age = now - self._cache['last_update']
            
            # Return cached filtered meals if available, less than 1 hour old, and user data hasn't changed
            if (self._cache['filtered_meals'] is not None and 
                cache_age < timedelta(hours=1) and 
                self._cache.get('user_data_hash') == user_data_hash):
                logging.info("Using cached filtered meals for user")
                return self._cache['filtered_meals']
            elif self._cache.get('user_data_hash') != user_data_hash:
                logging.info("User data changed, invalidating filtered meals cache")
            
            # Get all meals with their nutritional info from the shared cache
            meals = self.fetch_all_meals()
            if not meals:
                logging.warning("No meals found in database")
                return []

            logging.info(f"Found {len(meals)} meals initially")
            logging.info(f"User preferences: {self.user_preferences}")
            logging.info(f"User metrics: {self.user_metrics}")
            logging.info(f"Daily calorie budget: {self.daily_calorie_budget}")

            # Create a copy of the meals list to avoid modifying the shared cache
            meals = list(meals)  # Make a shallow copy

            # Filter by dietary preference
            if self.user_preferences and self.user_preferences.get("diet_type"):
                diet_type = self.user_preferences["diet_type"].lower()
                if diet_type:
                    original_count = len(meals)
                    meals = [m for m in meals if 
                        m and m.get("dietary_preference") and 
                        diet_type in m["dietary_preference"].lower()]
                    logging.info(f"After diet_type filter ({diet_type}): {len(meals)} meals (removed {original_count - len(meals)})")

            # Filter by food restrictions
            if self.user_preferences and self.user_preferences.get("food_restrictions"):
                restrictions = self.user_preferences["food_restrictions"]
                if restrictions:
                    for restriction in restrictions:
                        if restriction:
                            original_count = len(meals)
                            meals = [m for m in meals if 
                                m and restriction.lower() not in (m.get("ingredients", "") or "").lower()]
                            logging.info(f"After restriction filter ({restriction}): {len(meals)} meals (removed {original_count - len(meals)})")

            # Filter by cuisine preferences
            if self.user_preferences and self.user_preferences.get("cuisine_preferences"):
                prefs = self.user_preferences["cuisine_preferences"]
                if prefs:
                    original_count = len(meals)
                    meals = [m for m in meals if 
                        m and any(pref.lower() in (m.get("cuisine_preferences", "") or "").lower() 
                                for pref in prefs)]
                    logging.info(f"After cuisine preferences filter: {len(meals)} meals (removed {original_count - len(meals)})")

            # Filter by nutrient requirements
            if self.user_metrics:
                min_nutrient_score = self._calculate_min_nutrient_score()
                original_count = len(meals)
                meals = [m for m in meals if 
                    m and m.get("Nutritional_Info") and 
                    m["Nutritional_Info"].get("nutrient_score", 0) >= min_nutrient_score]
                logging.info(f"After nutrient score filter (min score {min_nutrient_score}): {len(meals)} meals (removed {original_count - len(meals)})")

            # Filter by calorie budget
            if self.daily_calorie_budget is not None:
                original_count = len(meals)
                meals = [m for m in meals if 
                    m and m.get("Nutritional_Info") and 
                    m["Nutritional_Info"].get("calories", 0) <= self.daily_calorie_budget]
                logging.info(f"After calorie budget filter (budget {self.daily_calorie_budget}): {len(meals)} meals (removed {original_count - len(meals)})")

            # Sort by relevance (matching preferences and nutrient score)
            if meals:
                logging.info(f"Final meal count before sorting: {len(meals)}")
                meals.sort(key=lambda m: (
                    self._match_goal(m or {}),
                    self._match_diet(m or {}),
                    self._match_allergies(m or {}),
                    self._match_disease(m or {}),
                    self._match_cuisine(m or {}),
                    (m.get("Nutritional_Info") or {}).get("nutrient_score", 0)
                ), reverse=True)
                logging.info(f"Final sorted meal count: {len(meals)}")
            
            # Cache the filtered results for this user
            self._cache['filtered_meals'] = meals
            self._cache['last_update'] = now
            self._cache['user_data_hash'] = user_data_hash

            return meals

        except Exception as e:
            logging.error(f"Error filtering meals: {e}")
            return []

    def _calculate_min_nutrient_score(self) -> int:
        """Calculate minimum nutrient score based on user's health metrics."""
        min_score = 0
        
        # Increase score requirement for specific health conditions
        if self.user_metrics.get("health_conditions"):
            for condition in self.user_metrics["health_conditions"]:
                if condition == "anemia":
                    min_score += 5  # Need higher iron score
                elif condition == "osteoporosis":
                    min_score += 4  # Need higher calcium score
                elif condition == "hypertension":
                    min_score += 3  # Need higher potassium score
                elif condition == "diabetes":
                    min_score += 2  # Need lower sugar score
        
        return min_score

    def _get_cached_meals(self):
        """Cache meal recommendations for 1 hour.
        This method is kept for backward compatibility but uses the new caching system.
        Note: Cache is invalidated when user preferences or metrics change."""
        # Check if we have cached recommendations
        now = datetime.now()
        cache_key = f"recommendations_{self.user_id}"
        
        # Check if user preferences or metrics have changed since last cache
        user_data_hash = self._get_user_data_hash()
        
        # Check in the class-level shared cache
        if cache_key in self.__class__._shared_cache:
            cache_time, cached_recommendations, cached_user_hash = self.__class__._shared_cache[cache_key]
            # Only use cache if it's fresh AND user data hasn't changed
            if now - cache_time < timedelta(hours=1) and cached_user_hash == user_data_hash:
                logging.info(f"Using cached recommendations from _get_cached_meals for user {self.user_id}")
                return cached_recommendations
            else:
                if cached_user_hash != user_data_hash:
                    logging.info(f"User data changed for user {self.user_id}, invalidating recommendation cache")
                    
        # If we get here, we need to regenerate the cache
        return None
        
    def _get_user_data_hash(self):
        """Generate a hash of user data that affects meal recommendations."""
        user_data = {
            'user_id': self.user_id,
            'user_preferences': self.user_preferences,
            'user_metrics': self.user_metrics,
            # Source all dietary info from preferences
            'diets': self.user_preferences.get('diet_type', '') if self.user_preferences else '',
            'cuisines': self.user_preferences.get('cuisine_preferences', []) if self.user_preferences else [],
            'allergies': self.user_preferences.get('food_restrictions', []) if self.user_preferences else []
        }
        return hashlib.md5(json.dumps(user_data, sort_keys=True).encode()).hexdigest()

    def recommend_meals(self) -> List[Dict]:
        """Generate meal recommendations based on user data and nutrient scores.
        Uses cached data when available to improve performance.
        Cache is invalidated when user preferences or metrics change."""
        # Check if we have cached recommendations
        now = datetime.now()
        cache_key = f"recommendations_{self.user_id}"
        
        # Get user data hash to check if preferences have changed
        user_data_hash = self._get_user_data_hash()
        
        # Store recommendations in the class-level cache with user-specific key
        if cache_key in self.__class__._shared_cache:
            cache_time, cached_recommendations, cached_user_hash = self.__class__._shared_cache[cache_key]
            # Only use cache if it's fresh AND user data hasn't changed
            if now - cache_time < timedelta(hours=1) and cached_user_hash == user_data_hash:
                logging.info(f"Using cached recommendations for user {self.user_id}")
                return cached_recommendations
            elif cached_user_hash != user_data_hash:
                logging.info(f"User data changed for user {self.user_id}, regenerating recommendations")
        
        # Generate new recommendations
        logging.info(f"Generating new recommendations for user {self.user_id}")
        recommendations = self._generate_recommendations()
        
        # Cache the recommendations with the current user data hash
        self.__class__._shared_cache[cache_key] = (now, recommendations, user_data_hash)
        
        return recommendations

    def _generate_recommendations(self) -> List[Dict]:
        """Generate meal recommendations."""
        try:
            # Get filtered meals
            meals = self.filter_meals()
            if not meals:
                return []

            # Use all filtered meals initially
            recommended_meals = meals

            # Add additional recommendations based on user metrics
            if self.user_metrics:
                # Add meals that address specific nutrient deficiencies
                nutrient_deficiencies = self._identify_nutrient_deficiencies()
                for deficiency in nutrient_deficiencies:
                    # Find meals that are high in the deficient nutrient
                    high_nutrient_meals = self._find_high_nutrient_meals(deficiency)
                    if high_nutrient_meals:
                        recommended_meals.extend(high_nutrient_meals[:2])  # Add top 2 meals

            # Create balanced meal combinations
            balanced_meals = self._create_balanced_combinations(recommended_meals)

            # Fallback if balanced_meals is empty
            meals_to_process = balanced_meals if balanced_meals else recommended_meals

            # Remove duplicates
            unique_meals = []
            seen_meals = set()
            for meal in meals_to_process:
                meal_id = meal.get("meal_id")
                if meal_id and meal_id not in seen_meals:
                    unique_meals.append(meal)
                    seen_meals.add(meal_id)

            # Add meal recommendations with serving sizes
            final_recommendations = []
            for meal in unique_meals:
                meal_type = self._determine_meal_type(meal)
                serving_size = self.calculate_serving_size(meal, meal_type)
                meal["recommended_serving_size"] = serving_size
                final_recommendations.append(meal)

            return final_recommendations

        except Exception as e:
            logging.error(f"Error generating meal recommendations: {e}")
            return []

    def _create_balanced_combinations(self, meals: List[Dict]) -> List[Dict]:
        """Create balanced meal combinations based on nutrient scores."""
        balanced_meals = []
        
        # Group meals by their nutrient profiles
        nutrient_categories = {
            "iron": [],
            "calcium": [],
            "potassium": [],
            "vitamins": [],
            "magnesium": [],
            "cobalamin": [],
            "sugar": []
        }
        
        for meal in meals:
            nutrition = meal.get("Nutritional_Info", {})
            for nutrient in nutrient_categories.keys():
                level = nutrition.get(nutrient, "None")
                if level == "High":
                    nutrient_categories[nutrient].append(meal)
        
        # Create combinations that balance different nutrients
        for i in range(len(meals)):
            meal = meals[i]
            # Find complementary meals that balance different nutrients
            complementary_meals = []
            for nutrient in nutrient_categories.keys():
                if meal.get("Nutritional_Info", {}).get(nutrient, "None") != "High":
                    complementary_meals.extend(nutrient_categories[nutrient])
            
            if complementary_meals:
                # Sort by nutrient score and add top complementary meal
                complementary_meals.sort(
                    key=lambda m: m.get("Nutritional_Info", {}).get("nutrient_score", 0),
                    reverse=True
                )
                balanced_meals.append(complementary_meals[0])
        
        return balanced_meals

    def _identify_nutrient_deficiencies(self) -> List[str]:
        """Identify nutrient deficiencies based on user metrics."""
        deficiencies = []
        
        # Check for iron deficiency
        iron_level = self.user_metrics.get("iron_level")
        if iron_level is not None and iron_level < 10:
            deficiencies.append("iron")
        
        # Check for calcium deficiency
        calcium_level = self.user_metrics.get("calcium_level")
        if calcium_level is not None and calcium_level < 10:
            deficiencies.append("calcium")
        
        # Check for potassium deficiency
        potassium_level = self.user_metrics.get("potassium_level")
        if potassium_level is not None and potassium_level < 10:
            deficiencies.append("potassium")
        
        # Check for vitamin deficiency
        vitamins_level = self.user_metrics.get("vitamins_level")
        if vitamins_level is not None and vitamins_level < 10:
            deficiencies.append("vitamins")
        
        # Check for magnesium deficiency
        magnesium_level = self.user_metrics.get("magnesium_level")
        if magnesium_level is not None and magnesium_level < 10:
            deficiencies.append("magnesium")
        
        # Check for cobalamin deficiency
        cobalamin_level = self.user_metrics.get("cobalamin_level")
        if cobalamin_level is not None and cobalamin_level < 10:
            deficiencies.append("cobalamin")
        
        return deficiencies

    def _find_high_nutrient_meals(self, nutrient: str) -> List[Dict]:
        """Find meals that are high in a specific nutrient."""
        high_nutrient_meals = []
        
        # Get all meals with their nutritional info
        meals = self.fetch_all_meals()
        if not meals:
            return []
        
        # Filter meals by nutrient level
        for meal in meals:
            nutrition = meal.get("Nutritional_Info", {})
            if nutrition.get(nutrient, "None") == "High":
                high_nutrient_meals.append(meal)
        
        return high_nutrient_meals

    def _determine_meal_type(self, meal: Dict) -> str:
        """Determine the meal type (breakfast, lunch, dinner, snack) based on the meal's nutritional info."""
        meal_type = "lunch"  # Default to lunch
        
        # Check for breakfast
        if meal.get("Nutritional_Info", {}).get("calories", 0) < 300:
            meal_type = "breakfast"
        
        # Check for dinner
        elif meal.get("Nutritional_Info", {}).get("calories", 0) > 500:
            meal_type = "dinner"
        
        # Check for snack
        elif meal.get("Nutritional_Info", {}).get("calories", 0) < 200:
            meal_type = "snack"
        
        return meal_type

    def _match_goal(self, meal: Dict) -> int:
        """Match the meal's goal with the user's goal."""
        match = 0
        
        # Get the meal's goal and user's goal
        meal_goal = meal.get("goal")
        user_goal = self.user_preferences.get("goals") if self.user_preferences else None
        
        # Check if both goals exist and match
        if meal_goal and user_goal and meal_goal.lower() == user_goal.lower():
            match = 1
        
        return match

    def _match_diet(self, meal: Dict) -> int:
        """Match the meal's diet with the user's diet."""
        match = 0
        
        # Get the meal's diet and user's diet
        meal_diet = meal.get("diet_type")
        user_diet = self.user_preferences.get("diet_type") if self.user_preferences else None
        
        # Check if both diets exist and match
        if meal_diet and user_diet and meal_diet.lower() == user_diet.lower():
            match = 1
        
        return match

    def _match_allergies(self, meal: Dict) -> int:
        """Match the meal's allergies with the user's allergies."""
        match = 0
        
        # Get meal allergies and user restrictions
        meal_allergies = meal.get("allergies", "")
        user_restrictions = self.user_preferences.get("food_restrictions", []) if self.user_preferences else []
        
        # Check if the meal's allergies match the user's allergies
        if not any(allergy in meal_allergies.lower() for allergy in user_restrictions):
            match = 1
        
        return match

    def _match_cuisine(self, meal: Dict) -> int:
        """Match the meal's cuisine with the user's cuisine preferences."""
        match = 0
        
        # Get meal cuisine and user preferences
        meal_cuisine = meal.get("cuisine")
        user_cuisines = self.user_preferences.get("cuisine_preferences", []) if self.user_preferences else []
        
        # Check if the meal's cuisine matches the user's cuisine preferences
        if meal_cuisine and any(cuisine.lower() == meal_cuisine.lower() for cuisine in user_cuisines):
            match = 1
        
        return match

    def fetch_nutrition_data(self, ingredient) -> Optional[Dict]:
        """Fetch nutritional data for a specific ingredient from the Produce table.
        Uses class-level shared cache to improve performance across instances.
        Nutrition data is cached indefinitely since ingredient nutritional values rarely change."""
        # Check class-level shared cache first
        cached = self.__class__._shared_cache['nutrition_data'].get(ingredient)
        if cached:
            return cached

        # Database fallback with fresh connection
        connection = get_db_connection()
        try:
            # Use RealDictCursor to fetch results as dictionaries
            with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT 
                        COALESCE(calories::text, '0.0') as calories,
                        COALESCE(carbohydrates::text, '0.0') as carbohydrates,
                        COALESCE(proteins::text, '0.0') as proteins,
                        COALESCE(fats::text, '0.0') as fats,
                        COALESCE(fiber::text, '0.0') as fiber,
                        COALESCE(sugar::text, 'Non') as sugar,
                        COALESCE(iron::text, 'Non') as iron,
                        COALESCE(vitamins::text, 'Non') as vitamins,
                        COALESCE(magnesium::text, 'Non') as magnesium,
                        COALESCE(calcium::text, 'Non') as calcium,
                        COALESCE(potassium::text, 'Non') as potassium,
                        COALESCE(cobalamin::text, 'Non') as cobalamin
                    FROM Produce
                    WHERE produce_id = %s
                """, (ingredient.strip(),))
                
                if result := cursor.fetchone():
                    # Attempt to convert numeric fields to float, handling potential errors
                    nutrition_data = {
                        "calories": float(result['calories']) if result['calories'] and result['calories'].replace('.', '', 1).isdigit() else 0.0,
                        "carbohydrates": float(result['carbohydrates']) if result['carbohydrates'] and result['carbohydrates'].replace('.', '', 1).isdigit() else 0.0,
                        "proteins": float(result['proteins']) if result['proteins'] and result['proteins'].replace('.', '', 1).isdigit() else 0.0,
                        "fats": float(result['fats']) if result['fats'] and result['fats'].replace('.', '', 1).isdigit() else 0.0,
                        "fiber": float(result['fiber']) if result['fiber'] and result['fiber'].replace('.', '', 1).isdigit() else 0.0,
                        "sugar": result['sugar'],  # Treat sugar as categorical
                        "iron": result['iron'],
                        "vitamins": result['vitamins'],
                        "magnesium": result['magnesium'],
                        "calcium": result['calcium'],
                        "potassium": result['potassium'],
                        "cobalamin": result['cobalamin']
                    }

                    # Update the class-level shared cache
                    self.__class__._shared_cache['nutrition_data'][ingredient] = nutrition_data
                    return nutrition_data
                else:
                    logging.warning(f"No nutrition data found for ingredient {ingredient}")
                    return None

        except Exception as e:
            logging.error(f"Error fetching nutrition data: {e}")
            return None
        finally:
            if connection:
                connection.close()


    def _bulk_fetch_nutrition_data(self, meal_ids: List[int]) -> Dict[int, Dict]:
        """Fetch nutritional data for multiple meals in bulk."""
        try:
            # Check cache first
            cached_data = {}
            for meal_id in meal_ids:
                if meal_id in self._cache['nutrition_data']:
                    cached_data[meal_id] = self._cache['nutrition_data'][meal_id]

            # Only fetch uncached data
            uncached_ids = [meal_id for meal_id in meal_ids if meal_id not in cached_data]
            if not uncached_ids:
                return cached_data

            connection = get_db_connection()
            if not connection:
                return cached_data

            with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                # Get all ingredients for the uncached meals
                cursor.execute("""
                    SELECT mi.meal_id, mi.produce_id, mi.produce_quantity_in_grams
                    FROM meal_ingredients mi
                    WHERE mi.meal_id IN %s
                """, (tuple(uncached_ids),))
                ingredients = cursor.fetchall()

                # Group ingredients by meal
                meal_ingredients = {}
                for meal_id, produce_id, quantity in ingredients:
                    if meal_id not in meal_ingredients:
                        meal_ingredients[meal_id] = []
                    meal_ingredients[meal_id].append((produce_id, quantity or 0))  # Handle null quantity

                # Get nutritional data for all ingredients
                # First, fetch numerical nutritional data
                cursor.execute("""
                    SELECT produce_id, 
                           COALESCE(calories::integer, 0) as calories,
                           COALESCE(cholesterol::integer, 0) as cholesterol,
                           COALESCE(carbohydrates::integer, 0) as carbohydrates,
                           COALESCE(proteins::integer, 0) as proteins,
                           COALESCE(fats::integer, 0) as fats,
                           COALESCE(fiber::integer, 0) as fiber,
                           COALESCE(sugar::integer, 0) as sugar
                    FROM produce
                    WHERE produce_id IN %s
                """, (tuple(set(produce_id for meal_id in meal_ingredients for produce_id, _ in meal_ingredients[meal_id])),))
                numerical_data = cursor.fetchall()

                # Then, fetch categorical nutritional data
                cursor.execute("""
                    SELECT produce_id, 
                           COALESCE(iron::text, 'None') as iron,
                           COALESCE(vitamins::text, 'None') as vitamins,
                           COALESCE(magnesium::text, 'None') as magnesium,
                           COALESCE(calcium::text, 'None') as calcium,
                           COALESCE(potassium::text, 'None') as potassium,
                           COALESCE(cobalamin::text, 'None') as cobalamin
                    FROM produce
                    WHERE produce_id IN %s
                """, (tuple(set(produce_id for meal_id in meal_ingredients for produce_id, _ in meal_ingredients[meal_id])),))
                categorical_data = cursor.fetchall()

                # Create nutritional info for each meal
                result = cached_data  # Start with cached data
                for meal_id, ingredients in meal_ingredients.items():
                    # Initialize numerical and categorical dictionaries
                    numerical_nutrition = {
                        "calories": 0,
                        "cholesterol": 0,
                        "carbohydrates": 0,
                        "proteins": 0,
                        "fats": 0,
                        "fiber": 0,
                        "sugar": 0,
                    }
                    categorical_levels = {
                        "iron": "None",
                        "vitamins": "None",
                        "magnesium": "None",
                        "calcium": "None",
                        "potassium": "None",
                        "cobalamin": "None",
                    }
                    nutrient_score = 0

                    # Process numerical nutritional data
                    for data in numerical_data:
                        if data["produce_id"] in [i[0] for i in ingredients]:
                            quantity = next(i[1] for i in ingredients if i[0] == data["produce_id"])
                            for nutrient, value in data.items():
                                if nutrient != "produce_id" and value is not None:
                                    numerical_nutrition[nutrient] += float(value) * (quantity / 100)

                    # Process categorical nutritional data
                    for data in categorical_data:
                        if data["produce_id"] in [i[0] for i in ingredients]:
                            for nutrient, value in data.items():
                                if nutrient != "produce_id" and value and value != "None":
                                    categorical_levels[nutrient] = value

                    if numerical_nutrition["total_weight"] > 0:
                        numerical_nutrition["calories_per_gram"] = numerical_nutrition["calories"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["cholesterol_per_gram"] = numerical_nutrition["cholesterol"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["carbohydrates_per_gram"] = numerical_nutrition["carbohydrates"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["proteins_per_gram"] = numerical_nutrition["proteins"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["fats_per_gram"] = numerical_nutrition["fats"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["fiber_per_gram"] = numerical_nutrition["fiber"] / numerical_nutrition["total_weight"]
                        numerical_nutrition["sugar_per_gram"] = numerical_nutrition["sugar"] / numerical_nutrition["total_weight"]

                    # Combine numerical and categorical values
                    total_nutrition = {**numerical_nutrition, **categorical_levels}

                    # Calculate nutrient score
                    nutrient_levels = {
                        "Low": 1,
                        "Moderate": 2,
                        "High": 3,
                        "None": 0
                    }
                    total_nutrition["nutrient_score"] = (
                        nutrient_levels.get(total_nutrition["iron"], 0) +
                        nutrient_levels.get(total_nutrition["vitamins"], 0) +
                        nutrient_levels.get(total_nutrition["magnesium"], 0) +
                        nutrient_levels.get(total_nutrition["calcium"], 0) +
                        nutrient_levels.get(total_nutrition["potassium"], 0) +
                        nutrient_levels.get(total_nutrition["cobalamin"], 0)
                    )

                    result[meal_id] = total_nutrition

            return result

        except Exception as e:
            import traceback
            error_msg = f"Error in bulk fetch nutrition data: {e}\n" \
                       f"Line: {traceback.extract_tb(e.__traceback__)[-1].lineno}\n" \
                       f"Traceback: {traceback.format_exc()}"
            logging.error(error_msg)
            return {}
                        
    def _match_disease(self, meal: Dict) -> int:
        """Match the meal's disease management with the user's disease management."""
        match = 0

        # Check if the meal's disease management matches the user's disease management
        if meal.get("disease_management") == self.user_metrics.get("health_conditions"):
            match = 1
    
        return match

# Example usage
#user_id = 138
#meal_recommender2 = MealRecommendation4(user_id)
#recommendations = meal_recommender2.recommend_meals()
#print(recommendations)