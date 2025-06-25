# cspell:disable
import logging
from typing import Optional, Dict, List
from database import get_db_connection
from datetime import datetime, timedelta
from psycopg2.extras import RealDictCursor
import json
import hashlib

# Configure logging
logging.basicConfig(
    level="INFO",
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

class MealRecommendation4:
    _shared_cache = {
        'all_meals': None,
        'nutrition_data': {},
        'meal_ingredients': {},
        'last_update': datetime.now()
    }

    # Note: Removed DIETARY_PREFERENCE_MAPPINGS and CUISINE_PREFERENCE_MAPPINGS
    # as they are no longer needed with direct tag matching

    def __init__(self, user_id: int):
        self.user_id = user_id
        self._cache = {
            'filtered_meals': None,
            'last_update': datetime.now(),
            'user_data_hash': None
        }

        for cache_key in ['nutrition_data', 'meal_ingredients']:
            if cache_key not in self.__class__._shared_cache:
                self.__class__._shared_cache[cache_key] = {}

        logging.info(f"Initializing meal recommender for user {user_id}")
        
        try:
            connection = get_db_connection()
            if not connection:
                logging.error("Failed to establish database connection")
                self._set_defaults()
                return

            with connection:
                self.user_preferences, self.user_metrics = self._get_user_data(connection)
                self.daily_calorie_budget = self.calculate_daily_calorie_budget()

                if not self.__class__._shared_cache['nutrition_data']:
                    self._prefetch_nutrition_data(connection)
                
                if not self.__class__._shared_cache['all_meals']:
                    self.fetch_all_meals(connection)

            # Compute current user data hash after fetching data
            self._current_user_data_hash = self._get_user_data_hash()
            # Check if user data has changed; if not, keep previous hash
            # (This is to ensure that even if user data is the same, we verify for changes before recommending)
            # But since this is init, we set the hash after fetching data
            self._cache['user_data_hash'] = self._current_user_data_hash
            logging.info("Meal recommender initialized successfully")

        except Exception as e:
            logging.error(f"Error during initialization: {str(e)}")
            self._set_defaults()

    def _set_defaults(self):
        self.user_preferences = None
        self.user_metrics = None
        self.daily_calorie_budget = 2000
        logging.warning("Using default values due to initialization failure")

    def _get_user_data(self, connection) -> tuple:
        try:
            with connection.cursor() as cursor:
                query = """
                    SELECT 
                        up.goals, up.diet_type, up.food_restrictions, up.cuisine_preferences,
                        um.weight, um.height, um.cholesterol_level, um.sys_bp, um.dia_bp, 
                        um.pulse, um.age_range, um.sex, um.activity_level
                    FROM user_preferences up
                    JOIN user_metrics um ON up.user_id = um.user_id
                    WHERE up.user_id = %s
                """
                cursor.execute(query, (self.user_id,))
                result = cursor.fetchone()

                if not result:
                    logging.warning(f"No user data found for user_id {self.user_id}")
                    return None, None

                preferences = {
                    "goals": result[0].strip().lower() if result[0] else None,
                    "diet_type": result[1].strip().lower() if result[1] else None,
                    "food_restrictions": self._parse_list(result[2]),
                    "cuisine_preferences": self._parse_list(result[3]),
                }
                
                metrics = {
                    "weight": float(result[4]) if result[4] is not None else None,
                    "height": float(result[5]) if result[5] is not None else None,
                    "cholesterol_level": result[6],
                    "sys_bp": result[7],
                    "dia_bp": result[8],
                    "pulse": result[9],
                    "age_range": result[10],
                    "sex": result[11].strip().lower() if result[11] else "male",
                    "activity_level": result[12].strip().lower() if result[12] else "sedentary"
                }
                
                return preferences, metrics

        except Exception as e:
            logging.error(f"Error fetching user data: {str(e)}")
            return None, None

    def _parse_list(self, value):
        if not value:
            return []
        try:
            return [x.strip().lower() for x in value.split(",")]
        except:
            return []

    def _prefetch_nutrition_data(self, connection):
        try:
            logging.info("Prefetching nutrition data...")
            with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT 
                        produce_id, 
                        COALESCE(calories, 0)::float as calories,
                        COALESCE(carbohydrates, 0)::float as carbohydrates,
                        COALESCE(proteins, 0)::float as proteins,
                        COALESCE(fats, 0)::float as fats,
                        COALESCE(fiber, 0)::float as fiber,
                        COALESCE(sugar, 'Non') as sugar,
                        COALESCE(iron, 'Non') as iron,
                        COALESCE(vitamins, 'Non') as vitamins,
                        COALESCE(magnesium, 'Non') as magnesium,
                        COALESCE(calcium, 'Non') as calcium,
                        COALESCE(potassium, 'Non') as potassium,
                        COALESCE(cobalamin, 'Non') as cobalamin
                    FROM Produce
                """)
                
                count = 0
                for row in cursor:
                    self.__class__._shared_cache['nutrition_data'][row['produce_id']] = dict(row)
                    count += 1
                
                logging.info(f"Prefetched nutrition data for {count} ingredients")

        except Exception as e:
            logging.error(f"Error prefetching nutrition data: {str(e)}")

    def fetch_all_meals(self, connection=None) -> List[Dict]:
        try:
            now = datetime.now()
            if (self.__class__._shared_cache['all_meals'] and 
                (now - self.__class__._shared_cache['last_update']) < timedelta(hours=24)):
                logging.debug("Using cached meals data")
                return self.__class__._shared_cache['all_meals']

            logging.info("Fetching meals from database...")
            
            close_connection = False
            if not connection:
                connection = get_db_connection()
                close_connection = True
                if not connection:
                    return []

            try:
                with connection.cursor(cursor_factory=RealDictCursor) as cursor:
                    query = """
                        SELECT 
                            m.*,
                            string_agg(DISTINCT pr.produce_name, ', ') AS ingredients,
                            COALESCE(SUM(mi.produce_quantity_in_grams), 0) as total_weight,
                            jsonb_object_agg(
                                mi.produce_id, 
                                jsonb_build_object(
                                    'quantity', COALESCE(mi.produce_quantity_in_grams, 0),
                                    'name', pr.produce_name
                                )
                            ) as ingredients_detail
                        FROM meals m
                        LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
                        LEFT JOIN produce pr ON mi.produce_id = pr.produce_id
                        GROUP BY m.meal_id
                        ORDER BY m.meal_name
                    """
                    cursor.execute(query)
                    meals = []
                    error_count = 0

                    for row in cursor:
                        try:
                            meal = dict(row)
                            meal_id = meal['meal_id']
                            
                            ingredients = meal.pop('ingredients_detail', {})
                            self.__class__._shared_cache['meal_ingredients'][meal_id] = ingredients
                            
                            nutritional_info = self._calculate_meal_nutrition(meal_id, ingredients)
                            meal['Nutritional_Info'] = nutritional_info
                            meal['price'] = 10000
                            
                            meals.append(meal)
                        except Exception as e:
                            error_count += 1
                            logging.error(f"Error processing meal {meal.get('meal_id')}: {str(e)}")
                            continue

                    self.__class__._shared_cache['all_meals'] = meals
                    self.__class__._shared_cache['last_update'] = now
                    
                    logging.info(f"Loaded {len(meals)} meals ({error_count} errors)")
                    return meals

            finally:
                if close_connection and connection:
                    connection.close()

        except Exception as e:
            logging.error(f"Error fetching meals: {str(e)}")
            return []

    def _calculate_meal_nutrition(self, meal_id, ingredients) -> Dict:
        numerical_nutrition = {
            "calories": 0.0,
            "cholesterol": 0.0,
            "carbohydrates": 0.0,
            "proteins": 0.0,
            "fats": 0.0,
            "fiber": 0.0,
            "total_weight": 0.0
        }

        categorical_levels = {
            "iron": "Non",
            "vitamins": "Non",
            "magnesium": "Non",
            "calcium": "Non",
            "potassium": "Non",
            "cobalamin": "Non",
            "sugar": "Non"
        }

        for produce_id, data in ingredients.items():
            nutrition = self.__class__._shared_cache['nutrition_data'].get(produce_id)
            if not nutrition:
                continue

            quantity = float(data.get('quantity', 0))
            ratio = quantity / 100.0

            for nutrient in numerical_nutrition:
                if nutrient != "total_weight":
                    value = nutrition.get(nutrient, 0.0)
                    if isinstance(value, (int, float)):
                        numerical_nutrition[nutrient] += value * ratio

            numerical_nutrition["total_weight"] += quantity

            for nutrient in categorical_levels:
                current = categorical_levels[nutrient]
                new = nutrition.get(nutrient, "Non")
                level_order = {"Non": 0, "Low": 1, "Moderate": 2, "High": 3}
                if level_order.get(new, 0) > level_order.get(current, 0):
                    categorical_levels[nutrient] = new

        total_weight = numerical_nutrition["total_weight"]
        if total_weight > 0:
            for nutrient in ["calories", "cholesterol", "carbohydrates", "proteins", "fats", "fiber"]:
                numerical_nutrition[f"{nutrient}_per_gram"] = numerical_nutrition[nutrient] / total_weight

        level_scores = {"Non": 0, "Low": 1, "Moderate": 2, "High": 3}
        nutrient_score = sum(level_scores.get(categorical_levels[n], 0) 
                          for n in ["iron", "vitamins", "magnesium", "calcium", "potassium", "cobalamin"])

        return {**numerical_nutrition, **categorical_levels, "nutrient_score": nutrient_score}

    def _categorize_goal(self, goal: str) -> str:
        """Categorize the user's goal for calculation purposes."""
        goal = (goal or "").lower()
        
        # Weight-related goals
        if any(term in goal for term in ["lose weight", "weight loss"]):
            return "weight_loss"
        if any(term in goal for term in ["gain muscle", "muscle gain"]):
            return "muscle_gain"
        if "satiety" in goal:
            return "maintain"
            
        # Health conditions that might affect calculations in the future
        health_conditions = ["diabetes", "hypertension", "joint pain", "postpartum", "inflammation"]
        if any(condition in goal for condition in health_conditions):
            return "health_condition"
            
        return "general_wellness"

    def _get_goal_adjustment_factor(self, goal: str) -> float:
        """Get the calorie adjustment factor based on the goal category."""
        goal_category = self._categorize_goal(goal)
        
        adjustment_factors = {
            "weight_loss": -0.15,    # 15% reduction for weight loss
            "muscle_gain": 0.15,     # 15% increase for muscle gain
            "maintain": 0.0,         # No adjustment for maintenance/satiety
            "health_condition": 0.0,  # No adjustment by default for health conditions
            "general_wellness": 0.0   # No adjustment for general wellness
        }
        
        return adjustment_factors.get(goal_category, 0.0)

    def calculate_daily_calorie_budget(self) -> float:
        """
        Calculate the user's daily calorie budget based on their metrics and goals.
        
        Returns:
            float: The calculated daily calorie budget
        """
        if not self.user_metrics or not self.user_preferences:
            logging.warning("User metrics or preferences not found. Using default calorie budget.")
            return 2000

        # Get basic metrics with defaults
        weight = self.user_metrics.get("weight") or 70
        height = self.user_metrics.get("height") or 170
        age = int(self.user_metrics["age_range"].split("-")[0]) if self.user_metrics.get("age_range") else 30
        sex = (self.user_metrics.get("sex") or "male").lower()

        # Calculate BMR using Mifflin-St Jeor equation
        if sex == "male":
            bmr = 10 * weight + 6.25 * height - 5 * age + 5
        else:
            bmr = 10 * weight + 6.25 * height - 5 * age - 161

        # Apply activity factor
        activity_level = (self.user_metrics.get("activity_level") or "sedentary").lower()
        activity_factors = {
            "sedentary": 1.2,
            "lightly active": 1.375,
            "moderately active": 1.55,
            "very active": 1.725,
            "extra active": 1.9,
        }
        tdee = bmr * activity_factors.get(activity_level, 1.2)

        # Get goal from preferences
        goal = self.user_preferences.get("goals", "")
        
        # Get adjustment factor based on goal
        adjustment_percent = self._get_goal_adjustment_factor(goal)
        
        # Apply adjustment if needed
        if adjustment_percent != 0:
            tdee *= (1 + adjustment_percent)

        # Ensure minimum calorie threshold (never go below 1200 calories for safety)
        MINIMUM_CALORIES = 1200
        tdee = max(round(tdee, 1), MINIMUM_CALORIES)

        logging.info(
            f"Calculated TDEE: {tdee} calories | "
            f"Goal: {goal} | "
            f"Adjustment: {adjustment_percent*100}%"
        )

        return tdee

    def _has_user_data_changed(self):
        """Check if current user data differs from previously stored hash."""
        current_hash = self._get_user_data_hash()
        return current_hash != getattr(self, "_user_data_hash", None)

    def _get_user_data_hash(self):
        user_data = {
            'user_id': self.user_id,
            'user_preferences': self.user_preferences,
            'user_metrics': self.user_metrics,
            'diets': self.user_preferences.get('diet_type', '') if self.user_preferences else '',
            'cuisines': self.user_preferences.get('cuisine_preferences', []) if self.user_preferences else [],
            'allergies': self.user_preferences.get('food_restrictions', []) if self.user_preferences else []
        }
        return hashlib.md5(json.dumps(user_data, sort_keys=True).encode()).hexdigest()

    def _check_user_data_for_recommendation(self):
        """Return True if user data has changed, else False."""
        changed = self._has_user_data_changed()
        if changed:
            # Update stored hash
            self._user_data_hash = self._get_user_data_hash()
        return changed

    def recommend_meals(self) -> List[Dict]:
        now = datetime.now()
        cache_key = f"recommendations_{self.user_id}"
        
        # Always refresh user data from database before checking cache
        try:
            connection = get_db_connection()
            if connection:
                with connection:
                    # Fetch fresh user data
                    fresh_prefs, fresh_metrics = self._get_user_data(connection)
                    if fresh_prefs and fresh_metrics:
                        self.user_preferences = fresh_prefs
                        self.user_metrics = fresh_metrics
                        self.daily_calorie_budget = self.calculate_daily_calorie_budget()
                        # Update the hash after refreshing data
                        self._current_user_data_hash = self._get_user_data_hash()
        except Exception as e:
            logging.error(f"Error refreshing user data: {str(e)}")
        
        user_data_hash = self._get_user_data_hash()

        # Check cache with fresh user data hash
        previous_cached_hash = None
        if cache_key in self.__class__._shared_cache:
            _, _, previous_cached_hash = self.__class__._shared_cache[cache_key]
        
        if previous_cached_hash == user_data_hash:
            # User data hasn't changed; return cached recommendations
            if cache_key in self.__class__._shared_cache:
                cache_time, cached_recommendations, _ = self.__class__._shared_cache[cache_key]
                if now - cache_time < timedelta(hours=1):
                    logging.info(f"Using cached recommendations for user {self.user_id}")
                    return cached_recommendations
        else:
            # User data has changed; log the change
            logging.info(f"User data changed for user {self.user_id}, regenerating recommendations")
        
        logging.info(f"Generating new recommendations for user {self.user_id}")
        recommendations = self._generate_recommendations()
        self.__class__._shared_cache[cache_key] = (now, recommendations, user_data_hash)
        return recommendations

    def _get_max_meal_calories(self, meal_type: str) -> float:
        """
        Get the maximum allowed calories for a specific meal type based on the user's daily budget.
        These are slightly higher than the target calories to allow for some flexibility.
        """
        if not hasattr(self, 'daily_calorie_budget') or not self.daily_calorie_budget:
            # Fallback values if daily calorie budget isn't set
            return {
                "breakfast": 800,
                "lunch": 1000,
                "dinner": 1000,
                "snack": 300,
            }.get(meal_type.lower(), 1000)
            
        return {
            "breakfast": self.daily_calorie_budget * 0.30,  # 30% of daily budget (higher than target for filtering)
            "lunch": self.daily_calorie_budget * 0.40,      # 40% of daily budget
            "dinner": self.daily_calorie_budget * 0.40,     # 40% of daily budget
            "snack": self.daily_calorie_budget * 0.15,      # 15% of daily budget
        }.get(meal_type.lower(), self.daily_calorie_budget * 0.3)

        
    def _is_meal_within_calorie_budget(self, meal: Dict, meal_type: str) -> bool:
        """Check if a meal's calories are within the user's budget for its meal type."""
        try:
            meal_calories = meal["Nutritional_Info"].get("calories", 0)
            if not meal_calories:
                return True  # Can't determine, so don't filter out
                
            max_calories = self._get_max_meal_calories(meal_type)
            return float(meal_calories) <= max_calories
            
        except (KeyError, ValueError, TypeError) as e:
            logging.warning(f"Error checking meal calories for {meal.get('meal_id')}: {e}")
            return True  # Don't filter out on error

    def _generate_recommendations(self) -> List[Dict]:
        def log_remaining(meals_list, filter_name, filter_value=None, is_fallback=False):
            count = len(meals_list)
            log_msg = f"After {filter_name}"
            if filter_value is not None:
                log_msg += f" (value: {filter_value})"
            if is_fallback:
                log_msg = "[FALLBACK] " + log_msg
            log_msg += f": {count} meals remaining"
            logging.info(log_msg)
            if count == 0:
                warning_msg = f"No meals remaining after {filter_name}"
                if filter_value is not None:
                    warning_msg += f" with value: {filter_value}"
                if not is_fallback:
                    logging.warning(warning_msg)
            return meals_list

        try:
            # Before generating, check if user data has changed
            if not self._check_user_data_for_recommendation():
                # Data unchanged, can return cached recommendations if any
                cache_entry = self.__class__._shared_cache.get(f"recommendations_{self.user_id}")
                if cache_entry:
                    _, cached_recommendations, _ = cache_entry
                    return cached_recommendations or []
            
            # Initial fetch of all meals
            meals = self.fetch_all_meals()
            if not meals:
                logging.error("No meals found in the database")
                return []

            # Start with all meals
            filtered_meals = meals.copy()
        
            applied_filters = []
            filters = [
                ("allergy-based", 
                 lambda m: self._match_allergies(m),
                 lambda: ", ".join(self.user_preferences.get('food_restrictions', [])) 
                        if self.user_preferences and 'food_restrictions' in self.user_preferences else None,
                 True,  # Strict (safety first)
                 0),    # Never relax allergy filters
                
                ("diet-based", 
                 lambda m: self._match_diet(m),
                 lambda: self.user_preferences.get('diet_type') 
                        if self.user_preferences and 'diet_type' in self.user_preferences else None,
                 True,  # Strict (dietary requirements are important)
                 1),    # Only relax after trying everything else
                 
                ("calorie budget",
                 lambda m: self._is_meal_within_calorie_budget(m, self._determine_meal_type(m)),
                 lambda: f"Max calories per meal type: {self.daily_calorie_budget}",
                 False,  # Can be relaxed if needed
                 3),     # Medium priority for relaxation
                
                ("cuisine-based", 
                 lambda m: self._match_cuisine(m),
                 lambda: ", ".join(self.user_preferences.get('cuisine_preferences', [])) 
                        if self.user_preferences and 'cuisine_preferences' in self.user_preferences else None,
                 False,  # Can be relaxed
                 4),     # Lower priority - can relax cuisine preferences
                
                ("goal-based", 
                 lambda m: self._match_goal(m),
                 lambda: self.user_preferences.get('goals') 
                        if self.user_preferences and 'goals' in self.user_preferences else None,
                 True,  # Can be relaxed
                 5)      # Lowest priority - goals are more flexible
            ]
            
            for filter_name, filter_func, get_value_func, _, _ in filters:
                filter_value = get_value_func()
                logging.info(f"Applying {filter_name} filter with value: {filter_value}")
                
                # Special handling for calorie filter which needs meal type
                if filter_name == "calorie budget":
                    # Apply calorie filter separately for each meal type
                    filtered_by_calories = []
                    for meal in filtered_meals:
                        meal_type = self._determine_meal_type(meal)
                        if filter_func(meal):
                            filtered_by_calories.append(meal)
                    filtered_meals = filtered_by_calories
                else:
                    filtered_meals = [m for m in filtered_meals if filter_func(m)]
                
                filtered_meals = log_remaining(filtered_meals, filter_name, filter_value, False)
                
                if not filtered_meals:
                    logging.warning(f"No meals remaining after applying {filter_name} filter with value: {filter_value}")
                    return []  # Return empty list if no meals match the filters
            
            # If we have no meals after applying all filters, return empty list
            if not filtered_meals:
                logging.error("No meals match the current filters. Please adjust your preferences.")
                return []

            # Prepare final recommendations with serving sizes
            final_recommendations = []
            for meal in filtered_meals:
                try:
                    meal_type = self._determine_meal_type(meal)
                    serving_size = self.calculate_serving_size(meal, meal_type)
                    meal = meal.copy()  # Avoid modifying the original meal
                    meal["recommended_serving_size"] = serving_size
                    final_recommendations.append(meal)
                except Exception as e:
                    logging.error(f"Error processing meal {meal.get('meal_id', 'unknown')}: {str(e)}")
                    continue

            logging.info(f"Generated {len(final_recommendations)} final recommendations")
            return final_recommendations

        except Exception as e:
            logging.error(f"Error generating meal recommendations: {str(e)}", exc_info=True)
            return []



    def calculate_serving_size(self, meal, meal_type: str) -> float:
        try:
            if not meal or not meal.get("meal_id"):
                return 0

            calorie_density = self.calculate_calorie_density(meal)
            if calorie_density <= 0:
                return 0

            daily_calories = self.daily_calorie_budget or 2000
            target_calories = {
                "breakfast": daily_calories * 0.25,
                "lunch": daily_calories * 0.35,
                "dinner": daily_calories * 0.40,
                "snack": daily_calories * 0.10
            }.get(meal_type.lower(), daily_calories * 0.25)

            try:
                serving_size = float(target_calories) / float(calorie_density)
            except ZeroDivisionError:
                logging.warning(f"Zero division error in serving size calculation for meal {meal.get('meal_id')}")
                return 0

            actual_total_weight = meal["Nutritional_Info"].get("total_weight", 0)
            serving_size = min(serving_size, float(actual_total_weight))

            return round(serving_size, -1)

        except Exception as e:
            logging.error(f"Error calculating serving size: {e}")
            return 0

    def calculate_calorie_density(self, meal) -> float:
        try:
            total_calories = float(meal["Nutritional_Info"].get("calories", 0))
            total_weight = float(meal["Nutritional_Info"].get("total_weight", 1))
            calorie_density = total_calories / total_weight if total_weight > 0 else 0
            return round(calorie_density, 1)
        except Exception as e:
            logging.error(f"Failed to calculate calorie density: {e}")
            return 0.0

    async def calculate_meal_calories(self, meal_id: str) -> Dict:
        try:
            ingredients = self.__class__._shared_cache['meal_ingredients'].get(meal_id, {})
            if not ingredients:
                logging.warning(f"No ingredients found for meal {meal_id}")
                return {"error": "No ingredients found"}

            nutritional_values = {
                "calories": 0.0,
                "carbohydrates": 0.0,
                "proteins": 0.0,
                "fats": 0.0,
                "fiber": 0.0,
                "sugar": "Non"
            }
            
            categorical_nutrients = ["sugar", "iron", "vitamins", "magnesium", "calcium", "potassium", "cobalamin"]
            total_weight = 0

            for produce_id, data in ingredients.items():
                nutrition = self.__class__._shared_cache['nutrition_data'].get(produce_id)
                if not nutrition:
                    continue
                
                quantity = float(data.get('quantity', 0))
                ratio = quantity / 100.0
                
                for nutrient in nutritional_values:
                    if nutrient in categorical_nutrients:
                        current_level = nutritional_values.get(nutrient, "Non")
                        new_level = nutrition.get(nutrient, "Non")
                        level_order = {"Non": 0, "Low": 1, "Moderate": 2, "High": 3}
                        if level_order.get(new_level, 0) > level_order.get(current_level, 0):
                            nutritional_values[nutrient] = new_level
                        continue
                    
                    try:
                        if nutrient in nutrition:
                            nutritional_values[nutrient] += float(nutrition.get(nutrient, 0)) * ratio
                    except (ValueError, TypeError):
                        continue
                
                total_weight += quantity

            if nutritional_values["calories"] == 0:
                logging.error(f"Zero calories calculated for {meal_id}")

            return {
                "calories": nutritional_values["calories"],
                "nutritional_info": nutritional_values,
                "serving_size": total_weight,
                "meal_id": meal_id
            }

        except Exception as e:
            logging.error(f"Error calculating meal calories: {e}")
            return {"error": str(e)}

    def _determine_meal_type(self, meal: Dict) -> str:
        calories = meal.get("Nutritional_Info", {}).get("calories", 0)
        if calories < 200:
            return "snack"
        elif calories < 300:
            return "breakfast"
        else:
            return "lunch"

    def _match_goal(self, meal: Dict) -> int:
        """
        Match user's goals with meal's goals using direct tag matching.
        Returns 1 if there's a match, 0 otherwise.
        
        Handles various goal types including:
        - Weight-related goals (weight loss, muscle gain)
        - Health conditions (diabetes, hypertension, etc.)
        - General wellness goals (energy, sleep, etc.)
        """
        if not self.user_preferences or not meal:
            return 0
            
        # Get user goals as a set of lowercase strings
        user_goals = self.user_preferences.get("goals") or []
        if isinstance(user_goals, str):
            user_goals = [g.strip().lower() for g in user_goals.split(',') if g.strip()]
        elif isinstance(user_goals, list):
            user_goals = [str(g).strip().lower() for g in user_goals if g and str(g).strip()]
        else:
            user_goals = []
            
        # If no user goals specified, don't filter on goals
        if not user_goals:
            return 1
            
        # If meal has no goals, don't filter it out (be permissive)
        meal_goals = meal.get("goal") or ""
        if isinstance(meal_goals, str):
            meal_goals = [g.strip().lower() for g in meal_goals.split(',') if g.strip()]
        elif isinstance(meal_goals, list):
            meal_goals = [str(g).strip().lower() for g in meal_goals if g and str(g).strip()]
        else:
            meal_goals = []
            
        if not meal_goals:
            logging.debug(f"Meal {meal.get('meal_id', 'unknown')} has no goals specified")
            return 1
            
        # Check for any match between user goals and meal goals
        user_goals_set = set(user_goals)
        meal_goals_set = set(meal_goals)
        
        # Special handling for specific goal patterns
        for meal_goal in meal_goals:
            # General fitness goals match any specific goal
            if any(term in meal_goal for term in ['improve overall fitness', 'general wellness']):
                return 1
                
            # Sustainable eating matches most health-related goals
            if 'build sustainable eating habits' in meal_goal:
                return 1  # Match all goals as sustainable eating is generally good
                
            # Special case: Satiety - exclude for weight loss, include for others
            if 'satiety' in meal_goal:
                if any(goal in ['lose weight', 'weight loss'] for goal in user_goals):
                    return 0
                return 1
                
            # Special case: Energy-boosting meals for energy goals
            if 'energy' in meal_goal and any('energy' in goal for goal in user_goals):
                return 1
                
            # Special case: Anti-inflammatory meals for joint pain/inflammation
            if any(term in meal_goal for term in ['anti-inflammatory', 'reduce inflammation']) and \
               any(term in ' '.join(user_goals) for term in ['joint pain', 'inflammation']):
                return 1
        
        # Check for direct matches
        if user_goals_set & meal_goals_set:
            return 1
            
        # Check for partial matches with special handling for different goal types
        for user_goal in user_goals:
            for meal_goal in meal_goals:
                # For weight-related terms, be more strict
                if any(term in user_goal for term in ['weight', 'lose', 'gain', 'bmi', 'fat']):
                    # Require at least one full word match
                    user_words = set(user_goal.split())
                    meal_words = set(meal_goal.split())
                    if user_words & meal_words:
                        return 1
                # For health conditions, be more permissive
                elif any(term in user_goal for term in ['diabetes', 'hypertension', 'joint pain', 'inflammation']):
                    if any(term in meal_goal for term in ['healthy', 'balanced', 'nutrient-dense']):
                        return 1
                    if 'diabetes' in user_goal and 'low glycemic' in meal_goal:
                        return 1
                    if 'hypertension' in user_goal and 'low sodium' in meal_goal:
                        return 1
                # For general wellness goals, be more permissive
                elif any(term in user_goal for term in ['energy', 'sleep', 'immune', 'skin', 'hair', 'detox', 'cleanse']):
                    if any(term in meal_goal for term in ['healthy', 'nutrient-dense', 'balanced']):
                        return 1
                # Default: any partial match is sufficient
                elif user_goal in meal_goal or meal_goal in user_goal:
                    return 1
        
        # Log why the meal was excluded
        logging.debug(
            f"Excluding meal {meal.get('meal_id', 'unknown')} - "
            f"meal goals ({', '.join(meal_goals)}) do not match user goals ({', '.join(user_goals)})"
        )
        return 0

    def _match_diet(self, meal: Dict) -> int:
        """
        Match user's diet preferences with meal's dietary tags using direct tag matching.
        Returns 1 if the meal matches the user's diet preferences, 0 otherwise.
        """
        if not self.user_preferences or not meal:
            return 0
            
        # Get user's diet preferences as a list of lowercase strings
        user_diets = self.user_preferences.get("diet_type") or []
        if isinstance(user_diets, str):
            user_diets = [d.strip().lower() for d in user_diets.split(',') if d.strip()]
        elif isinstance(user_diets, list):
            user_diets = [str(d).strip().lower() for d in user_diets if d and str(d).strip()]
        else:
            user_diets = []
            
        # If no user diet preferences specified, don't filter on diet
        if not user_diets:
            return 1
            
        # If 'omnivore' or 'all' is in user diets, include all meals
        if any(d in ['omnivore', 'all'] for d in user_diets):
            return 1
            
        # Get meal's diet tags as a list of lowercase strings
        meal_diets = meal.get("dietary_preference") or meal.get("diet_type") or ""
        if isinstance(meal_diets, str):
            meal_diets = [d.strip().lower() for d in meal_diets.split(',') if d.strip()]
        elif isinstance(meal_diets, list):
            meal_diets = [str(d).strip().lower() for d in meal_diets if d and str(d).strip()]
        else:
            meal_diets = []
            
        # If meal has no diet tags, log a warning and be conservative by excluding it
        if not meal_diets:
            logging.warning(f"Meal {meal.get('meal_id', 'unknown')} has no diet information. Filtering out for safety.")
            return 0
            
        # Check for any overlap between user's diets and meal's diets
        # Using set intersection for efficient lookup
        user_diets_set = set(user_diets)
        meal_diets_set = set(meal_diets)
        
        # If there's any overlap, include the meal
        if user_diets_set & meal_diets_set:
            return 1
            
        # Log why the meal was excluded
        logging.debug(
            f"Excluding meal {meal.get('meal_id', 'unknown')} - "
            f"meal diets ({', '.join(meal_diets)}) do not match user diets ({', '.join(user_diets)})"
        )
        return 0
            
        # Create a clean string of all meal diets for easier checking
        meal_diets_str = ' '.join(meal_diets).lower()
        
        # For vegan/vegetarian, be very strict with diet types
        if user_diet == 'vegan':
            # List of terms that would make a meal incompatible for vegans
            incompatible_terms = [
                # Animal products
                'meat', 'poultry', 'fish', 'seafood', 'animal', 'game', 'gelatin',
                'rennet', 'lard', 'tallow', 'carmine', 'shellac', 'confectioner\'s glaze',
                'omega-3', 'epa', 'dha', 'fish oil', 'cod liver oil', 'krill oil',
                # Dairy and eggs
                'dairy', 'milk', 'cheese', 'butter', 'yogurt', 'cream', 'eggs', 'egg',
                'whey', 'casein', 'lactose', 'ghee', 'mayonnaise', 'custard', 'ice cream', 
                'gelato', 'pudding', 'flan', 'custard', 'batter', 'meringue', 'albumen',
                # Other animal products
                'honey', 'royal jelly', 'propolis', 'beeswax', 'collagen', 'elastin',
                'keratin', 'lactalbumin', 'lactoferrin', 'lactoglobulin', 'lactulose',
                'lanolin', 'lecithin', 'oleic acid', 'pepsin', 'vitamin d3', 'cholecalciferol'
            ]
            
            # Check for any non-vegan terms in the meal's diet info
            for term in incompatible_terms:
                if term in meal_diets_str:
                    logging.warning(f"Excluding meal {meal.get('meal_id', 'unknown')} - diet type contains non-vegan term: {term}")
                    return 0
                    
        elif user_diet == 'vegetarian':
            # For vegetarians, exclude meat, poultry, fish, seafood, and their derivatives
            incompatible_terms = [
                'meat', 'poultry', 'fish', 'seafood', 'animal', 'game', 'gelatin',
                'rennet', 'lard', 'tallow', 'carmine', 'shellac', 'confectioner\'s glaze',
                'fish oil', 'cod liver oil', 'krill oil', 'omega-3', 'epa', 'dha',
                'anchovy', 'bacon', 'beef', 'bison', 'buffalo', 'calf', 'caribou',
                'carp', 'chicken', 'clam', 'crab', 'crayfish', 'eel', 'elk', 'fowl',
                'frog', 'goose', 'grouse', 'guinea fowl', 'haddock', 'halibut', 'ham',
                'hare', 'herring', 'lamb', 'liver', 'lobster', 'mackerel', 'mussel',
                'octopus', 'oyster', 'partridge', 'pheasant', 'pork', 'quail', 'rabbit',
                'salmon', 'sardine', 'scallop', 'shrimp', 'snail', 'snake', 'squid',
                'trout', 'tuna', 'turtle', 'veal', 'venison', 'wild boar', 'worcestershire sauce'
            ]
            
            # Check for any non-vegetarian terms in the meal's diet info
            for term in incompatible_terms:
                if term in meal_diets_str:
                    logging.warning(f"Excluding meal {meal.get('meal_id', 'unknown')} - diet type contains non-vegetarian term: {term}")
                    return 0
        
        # For omnivore (including 'all' which was normalized to 'omnivore'), 
        # accept any meal that doesn't explicitly conflict with the diet
        if user_diet in ['omnivore', 'all']:
            # Only exclude meals that are explicitly marked as incompatible with omnivore diet
            non_omnivore_terms = [
                'vegan', 'vegetarian', 'keto', 'paleo', 'mediterranean',
                'dairy-free', 'gluten-free', 'nut-free', 'soy-free', 'lactose-free'
            ]
            
            # Check if the meal is explicitly marked with any non-omnivore diet
            if any(term in meal_diets_str for term in non_omnivore_terms):
                logging.info(f"Excluding meal {meal.get('meal_id', 'unknown')} - marked as incompatible with omnivore diet")
                return 0
            return 1
        else:
            # For other diet types, use the existing matching logic
            meal_matched = False
            for diet in meal_diets:
                # Check for direct match
                if diet in compatible_diets:
                    meal_matched = True
                    break
                    
                # Check for partial matches (case-insensitive)
                if any(diet in cd.lower() or cd.lower() in diet for cd in compatible_diets):
                    meal_matched = True
                    break
            
            # If no match found, log why the meal was excluded
            if not meal_matched:
                logging.info(f"Excluding meal {meal.get('meal_id', 'unknown')} - diet type '{', '.join(meal_diets)}' "
                            f"does not match user's {user_diet} diet")
                return 0
                
            return 1

    def _match_allergies(self, meal: Dict) -> int:
        """
        Match user's food restrictions with meal's allergy tags using direct tag matching.
        Returns 1 if the meal is safe for the user's restrictions, 0 otherwise.
        """
        if not self.user_preferences or not meal:
            return 0
            
        # Get user's food restrictions as a list of lowercase strings
        user_restrictions = self.user_preferences.get("food_restrictions") or []
        if isinstance(user_restrictions, str):
            user_restrictions = [r.strip().lower() for r in user_restrictions.split(',') if r.strip()]
        elif isinstance(user_restrictions, list):
            user_restrictions = [str(r).strip().lower() for r in user_restrictions if r and str(r).strip()]
        else:
            user_restrictions = []
            
        # If no user restrictions, allow the meal
        if not user_restrictions:
            return 1
            
        # Get meal's allergy tags as a list of lowercase strings
        meal_allergies = meal.get("allergies") or ""
        if isinstance(meal_allergies, str):
            meal_allergies = [a.strip().lower() for a in meal_allergies.split(',') if a.strip()]
        elif isinstance(meal_allergies, list):
            meal_allergies = [str(a).strip().lower() for a in meal_allergies if a and str(a).strip()]
        else:
            meal_allergies = []
            
        # If meal has no allergy info, be safe and filter it out if there are any restrictions
        if not meal_allergies and user_restrictions:
            logging.warning(f"Meal {meal.get('meal_id', 'unknown')} has no allergy information. Filtering out for safety.")
            return 0
            
        # Check for any overlap between user's restrictions and meal's allergies
        # Using set intersection for efficient lookup
        user_restrictions_set = set(user_restrictions)
        meal_allergies_set = set(meal_allergies)
        
        # If there's any overlap, the meal is not safe
        if user_restrictions_set & meal_allergies_set:
            conflicting = user_restrictions_set & meal_allergies_set
            logging.info(
                f"Excluding meal {meal.get('meal_id', 'unknown')} - "
                f"contains allergens that conflict with user's restrictions: {', '.join(conflicting)}"
            )
            return 0
            
        return 1

    def _match_cuisine(self, meal: Dict) -> int:
        """
        Match user's cuisine preferences with meal's cuisine tags using direct tag matching.
        Returns 1 if the meal matches any of the user's cuisine preferences, 0 otherwise.
        If user has no cuisine preferences, all meals are allowed.
        """
        if not self.user_preferences or not meal:
            return 0
            
        # Get user's cuisine preferences as a list of lowercase strings
        user_cuisines = self.user_preferences.get("cuisine_preferences") or []
        if isinstance(user_cuisines, str):
            user_cuisines = [c.strip().lower() for c in user_cuisines.split(',') if c.strip()]
        elif isinstance(user_cuisines, list):
            user_cuisines = [str(c).strip().lower() for c in user_cuisines if c and str(c).strip()]
        else:
            user_cuisines = []
            
        # If no user cuisine preferences, allow all meals
        if not user_cuisines:
            return 1
            
        # Get meal's cuisine tags as a list of lowercase strings
        meal_cuisines = meal.get("cuisine_type") or ""
        if isinstance(meal_cuisines, str):
            meal_cuisines = [c.strip().lower() for c in meal_cuisines.split(',') if c.strip()]
        elif isinstance(meal_cuisines, list):
            meal_cuisines = [str(c).strip().lower() for c in meal_cuisines if c and str(c).strip()]
        else:
            meal_cuisines = []
            
        # If meal has no cuisine tags, filter it out (be conservative)
        if not meal_cuisines:
            logging.debug(f"Meal {meal.get('meal_id', 'unknown')} has no cuisine information. Filtering out.")
            return 0
            
        # Check for any overlap between user's cuisine preferences and meal's cuisines
        # Using set intersection for efficient lookup
        user_cuisines_set = set(user_cuisines)
        meal_cuisines_set = set(meal_cuisines)
        
        # If there's any overlap, include the meal
        if user_cuisines_set & meal_cuisines_set:
            return 1
            
        # Log why the meal was excluded
        logging.debug(
            f"Excluding meal {meal.get('meal_id', 'unknown')} - "
            f"meal cuisines ({', '.join(meal_cuisines)}) do not match user preferences ({', '.join(user_cuisines)})"
        )
        return 0

        return 1 if any(cuisine in meal_cuisine for cuisine in compatible_cuisines) else 0

if __name__ == "__main__":
    logging.info("Starting meal recommendation service...")
    user_id = 1
    try:
        meal_recommender = MealRecommendation4(user_id)
        recommendations = meal_recommender.recommend_meals()
        logging.info(f"Generated {len(recommendations)} recommendations")
    except Exception as e:
        logging.error(f"Failed to generate recommendations: {str(e)}")