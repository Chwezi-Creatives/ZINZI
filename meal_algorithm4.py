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

    # Define robust dietary preference mappings
    DIETARY_PREFERENCE_MAPPINGS = {
        'vegan': [
            'vegan', 'plant-based', 'dairy-free', 'lactose-free', 'egg-free',
            'honey-free', 'animal-free', 'cruelty-free', 'nut-free', 'soy-free',
            'gluten-free', 'low-sodium', 'diabetes-friendly', 'low-sugar',
            'hohfap', 'organic', 'vegetable-based'
        ],
        'vegetarian': [
            'vegetarian', 'lacto-vegetarian', 'ovo-vegetarian', 'lacto-ovo-vegetarian',
            'dairy', 'eggs', 'honey', 'plant-based', 'nut-free', 'soy-free',
            'gluten-free', 'low-sodium', 'diabetes-friendly', 'low-sugar',
            'hohfap', 'organic', 'vegetable-based', 'dairy products', 'egg products'
        ],
        'keto': [
            'keto', 'dairy-free', 'lactose-free', 'nut-free', 'soy-free',
            'gluten-free', 'low-sugar', 'diabetes-friendly', 'high-protein',
            'organic', 'omnivore'
        ],
        'paleo': [
            'paleo', 'gluten-free', 'dairy-free', 'lactose-free', 'nut-free',
            'soy-free', 'low-sugar', 'high-protein', 'organic', 'omnivore'
        ],
        'mediterranean': [
            'mediterranean', 'pescatarian', 'primarily plant-based with occasional meats',
            'dairy-free', 'lactose-free', 'nut-free', 'low-sodium',
            'diabetes-friendly', 'low-sugar', 'low-fat', 'organic', 'omnivore'
        ],
        'omnivore': [
            'omnivore', 'halal', 'kosher', 'vegetarian', 'pescatarian',
            'primarily plant-based with occasional meats', 'high-protein',
            'low-fat', 'dairy-free', 'lactose-free', 'nut-free', 'soy-free',
            'gluten-free', 'low-sodium', 'diabetes-friendly', 'low-sugar',
            'hohfap', 'organic', 'dairy', 'eggs'
        ]
    }

    # Define robust cuisine preference mappings
    CUISINE_PREFERENCE_MAPPINGS = {
        'indian': ['indian'],
        'american': ['american'],
        'british': ['british'],
        'korean': ['korean'],
        'thai': ['thai'],
        'chinese': ['chinese'],
        'mediterranean': ['mediterranean'],
        'japanese': ['japanese'],
        'vietnamese': ['vietnamese'],
        'rest of africa': ['rest of africa'],
        'east african': ['east african'],
        'west african': ['west african'],
        'mexican': ['mexican'],
        'middle eastern': ['middle eastern'],
        'italian': ['italian'],
        'french': ['french'],
        'german': ['german'],
        'brazilian': ['brazilian'],
        'caribbean': ['caribbean'],
        'spanish': ['spanish'],
        'greek': ['greek'],
        'african': ['rest of africa', 'east african', 'west african'],
        'all': [
            'indian', 'american', 'british', 'korean', 'thai', 'chinese',
            'mediterranean', 'japanese', 'vietnamese', 'rest of africa',
            'east african', 'west african', 'mexican', 'middle eastern',
            'italian', 'french', 'german', 'brazilian', 'caribbean',
            'spanish', 'greek'
        ]
    }

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

    def calculate_daily_calorie_budget(self) -> float:
        if not self.user_metrics or not self.user_preferences:
            logging.warning("User metrics or preferences not found. Using default calorie budget.")
            return 2000

        weight = self.user_metrics["weight"] or 70
        height = self.user_metrics["height"] or 170
        age = int(self.user_metrics["age_range"].split("-")[0]) if self.user_metrics["age_range"] else 30
        sex = self.user_metrics["sex"] or "male"

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
    
        # Define adjustment percentages (can be customized as needed)
        ADJUSTMENT_MULTIPLIERS = {
            "weight loss": 0.15,  # 15% reduction for weight loss
            "muscle gain": 0.20,  # 20% increase for muscle gain
            "maintenance": 0.0    # No adjustment for maintenance
        }
    
        # Get the appropriate multiplier based on goal
        adjustment_percent = ADJUSTMENT_MULTIPLIERS.get(goals, 0.0)
    
        # Apply the adjustment
        if goals == "weight loss":
            tdee *= (1 - adjustment_percent)  # Reduce calories for weight loss
        elif goals == "muscle gain":
            tdee *= (1 + adjustment_percent)  # Increase calories for muscle gain
    
        # Ensure minimum calorie threshold (e.g., never go below 1200 calories for safety)
        MINIMUM_CALORIES = 1200
        tdee = max(round(tdee, 1), MINIMUM_CALORIES)
    
        logging.info(f"Adjusted TDEE for {goals}: {tdee} calories (using {adjustment_percent*100}% {'reduction' if goals == 'weight loss' else 'increase' if goals == 'muscle gain' else 'no adjustment'})")
    
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

    # Class-level goal mappings
    GOAL_MAPPINGS = {
        "weight loss": [
            "lose weight", "weight loss", "weight management",
            "fat loss", "reduce body fat",
            "bmi reduction", "reduce bmi",
            "postpartum weight management", "postpartum",
            "control chronic conditions", "chronic disease management",
            "diabetes management", "hypertension management",
            "detox", "cleanse", "detox and cleanse",
            "improve metabolic health", "metabolic health",
            "improved skin", "skin improvement",
            "improve overall fitness",
            "build sustainable eating habits"
        ],
        "muscle gain": [
            "gain muscle", "build muscle", "muscle building",
            "hypertrophy", "increase muscle mass",
            "achieve specific body composition goals", "body recomposition",
            "enhance athletic performance", "improve performance",
            "sports nutrition", "strength training",
            "recover from nutritional deficiencies", "nutrition recovery",
            "protein intake", "increase protein",
            "boost energy levels", "increase energy",
            "improved sleep quality", "better sleep", "recovery sleep",
            "satiety"
        ],
        "maintain weight": [
            "maintain current weight", "weight maintenance",
            "sustain current weight", "weight stability",
            "build sustainable eating habits", "sustainable diet",
            "healthy eating", "balanced nutrition",
            "improve overall fitness", "general fitness",
            "wellness", "holistic health",
            "boost energy levels", "sustain energy",
            "enhance metabolic health", "metabolic health",
            "achieve a healthier bmi", "healthy bmi",
            "manage stress through nutrition", "stress management",
            "improved sleep quality", "better sleep",
            "control chronic conditions", "chronic disease management",
            "improved eye health", "eye health",
            "general health", "overall health",
            "reduce inflammation",
            "improved skin"
        ]
    }
    
    def _match_goal(self, meal: Dict) -> int:
        meal_goal = (meal.get("goal") or "").strip().lower()
        user_goal = (self.user_preferences.get("goals") or "").strip().lower() if self.user_preferences else None
        
        if not meal_goal or not user_goal:
            return 0
            
        # Normalize goals for comparison
        meal_goals = [g.strip().lower() for g in str(meal_goal).split(',') if g.strip()]
        user_goal = str(user_goal).strip().lower()
        
        # If no valid meal goals or no user goal, don't filter on it
        if not meal_goals or not user_goal:
            return 1
            
        # Check if user's goal has a mapping
        if user_goal in self.GOAL_MAPPINGS:
            goal_variations = self.GOAL_MAPPINGS[user_goal]
            
            # Check if any of the meal's goals match the user's goal variations
            for mg in meal_goals:
                # Check for exact matches
                if mg in goal_variations:
                    return 1
                    
                # Check for partial matches in case of longer descriptions
                if any(gv in mg for gv in goal_variations):
                    return 1
            
            # Handle conflicting terms based on goal type
            conflicting_terms = []
            
            # Define conflicts based on primary goal categories
            if 'loss' in user_goal or 'lose' in user_goal:
                # For weight loss, avoid muscle gain related terms
                conflicting_terms.extend(['gain muscle', 'bulk', 'hypertrophy', 'mass gain', 'weight gain'])
                # Also check for any weight gain terms in the meal's goals
                if any('gain' in mg and 'weight' in mg for mg in meal_goals):
                    return 0
                    
            elif 'gain' in user_goal and 'muscle' in user_goal:
                # For muscle gain, avoid weight loss terms
                conflicting_terms.extend(['lose weight', 'fat loss', 'weight loss', 'reduce', 'weight reduction'])
            
            # Check for conflicts in any of the meal's goals
            for mg in meal_goals:
                if any(conflict in mg for conflict in conflicting_terms):
                    logging.debug(f"Excluding meal due to conflicting goal: {mg} for user goal: {user_goal}")
                    return 0
            
            # For maintenance, be more permissive but still check for strong conflicts
            if 'maintain' in user_goal:
                strong_conflicts = ['lose weight', 'weight loss', 'gain muscle', 'bulk', 'weight gain']
                if any(any(conflict in mg for conflict in strong_conflicts) for mg in meal_goals):
                    return 0
                    
        return 0
            
        # Check for partial matches within variations
        for variation in goal_variations:
            # Split variations into words for more precise matching
            variation_words = set(word.strip() for word in variation.split() if len(word) > 2)
            for mg in meal_goals:
                meal_words = set(word.strip() for word in mg.split() if len(word) > 2)
                variation_words = set(word.strip() for word in variation.split() if len(word) > 2)
                meal_words = set(word.strip() for word in meal_goal.split() if len(word) > 2)
                
                # Check for word overlaps (at least one meaningful word in common)
                if variation_words & meal_words:
                    # For weight-related terms, be more strict
                    if any(term in variation for term in ['weight', 'lose', 'gain', 'bmi', 'fat']):
                        # Require at least two matching words or exact phrase match
                        if (len(variation_words & meal_words) >= 2 or 
                            variation in meal_goal or 
                            meal_goal in variation):
                            return 1
                    else:
                        # For other terms, single word match is sufficient
                        return 1
                        
            # Special handling for overlaps between goals
            if 'improve overall fitness' in meal_goal:
                # This is a valid overlap for all goals
                return 1
                
            if 'build sustainable eating habits' in meal_goal:
                # Valid for weight loss (portion control) and maintenance
                if 'loss' in user_goal or 'maintain' in user_goal:
                    return 1
                    
            if 'satiety' in meal_goal:
                # Exclude satiety meals for weight loss goals
                if 'loss' in user_goal or 'lose' in user_goal:
                    return 0
                # For other goals (muscle gain, maintenance), allow satiety meals
                return 1
                
            # No matches found in this mapping
            return 0
            
        # Fallback to exact matching if no explicit mapping exists
        return 1 if meal_goal == user_goal else 0

    def _match_diet(self, meal: Dict) -> int:
        # Get user's diet preference (if any)
        user_diet = (self.user_preferences.get("diet_type") or "").strip().lower() if self.user_preferences else ""
        
        # If no user diet preference, or if diet is 'omnivore' or 'all', don't filter on diet
        if not user_diet or user_diet in ['omnivore', 'all']:
            return 1
            
        # Get meal's diet preferences as a list, handling both string and list inputs
        meal_diets = meal.get("dietary_preference") or meal.get("diet_type") or ""
        
        # Check meal ingredients if available (for strict diets like vegan/vegetarian)
        ingredients = (meal.get("ingredients") or "").lower()
        
        # For vegan/vegetarian diets, we need to be extremely strict
        if user_diet in ['vegan', 'vegetarian']:
            # Comprehensive list of non-vegan/vegetarian ingredients and terms to check for
            non_vegan_terms = [
                # Meats
                'beef', 'pork', 'chicken', 'turkey', 'duck', 'goose', 'quail', 'pheasant',
                'lamb', 'mutton', 'veal', 'venison', 'bison', 'buffalo', 'rabbit', 'game',
                'bacon', 'ham', 'sausage', 'pepperoni', 'salami', 'prosciutto', 'pancetta',
                'chorizo', 'pastrami', 'bologna', 'bratwurst', 'frankfurter', 'hot dog',
                'steak', 'roast', 'chop', 'cutlet', 'fillet', 'tenderloin', 'ribs', 'wings',
                'ground beef', 'ground turkey', 'ground chicken', 'minced meat',
                'organ meat', 'liver', 'kidney', 'heart', 'tongue', 'brain', 'sweetbreads',
                'gelatin', 'collagen', 'lard', 'tallow', 'suet', 'dripping',
                
                # Fish and seafood
                'fish', 'seafood', 'salmon', 'tuna', 'cod', 'haddock', 'halibut', 'tilapia',
                'trout', 'mackerel', 'sardine', 'anchovy', 'herring', 'sardine', 'sprat',
                'shrimp', 'prawn', 'lobster', 'crab', 'crayfish', 'langoustine',
                'scallop', 'clam', 'mussel', 'oyster', 'octopus', 'squid', 'cuttlefish',
                'eel', 'caviar', 'roe', 'fish eggs', 'surimi', 'fish sauce', 'shrimp paste',
                'oyster sauce', 'fish oil', 'cod liver oil', 'krill oil',
                
                # Dairy and eggs
                'milk', 'cheese', 'butter', 'yogurt', 'yoghurt', 'cream', 'sour cream',
                'creme fraiche', 'buttermilk', 'whey', 'casein', 'lactose', 'lactate',
                'ghee', 'clarified butter', 'curd', 'paneer', 'quark', 'kefir',
                'eggs', 'egg whites', 'egg yolks', 'albumen', 'ovalbumin', 'mayo', 'mayonnaise',
                'custard', 'ice cream', 'gelato', 'pudding', 'flan',
                
                # Other animal products
                'honey', 'royal jelly', 'propolis', 'beeswax', 'shellac', 'confectioner\'s glaze',
                'carmine', 'cochineal', 'carminic acid', 'guarana',
                'rennet', 'animal rennet', 'pepsin', 'trypsin',
                'vitamin d3', 'cholecalciferol', 'l-cysteine', 'cysteine',
                'omega-3', 'epa', 'dha', 'fish oil', 'cod liver oil', 'krill oil',
                
                # Common non-vegan additives
                'e120', 'e441', 'e542', 'e631', 'e901', 'e904', 'e913', 'e920', 'e921', 'e966',
                
                # General terms that might indicate non-vegan
                'meat', 'poultry', 'seafood', 'fish', 'dairy', 'animal', 'animal-derived',
                'animal based', 'animal product', 'animal by-product'
            ]
            
            # Additional terms specific to vegetarian (but not vegan) that we want to flag
            if user_diet == 'vegan':
                non_vegan_terms.extend([
                    'dairy', 'milk', 'cheese', 'butter', 'yogurt', 'cream', 'eggs', 'honey',
                    'whey', 'casein', 'lactose', 'ghee', 'rennet'
                ])
            
            # Clean up the ingredients string for better matching
            ingredients = ' ' + ingredients.replace(',', ' ').replace('.', ' ').lower() + ' '
            
            # Check for any non-vegan terms in the ingredients
            for term in non_vegan_terms:
                if f' {term} ' in ingredients:
                    logging.warning(f"Excluding meal {meal.get('meal_id', 'unknown')} - contains non-{user_diet} ingredient: {term}")
                    return 0
        
        # If meal has no diet info, log a warning but don't exclude it (ingredients are our primary check)
        if not meal_diets:
            logging.warning(f"Meal {meal.get('meal_id', 'unknown')} has no diet information. Relying on ingredient check only.")
            return 1
            
        # Convert to list if it's a string (handling both comma-separated and space-separated)
        if isinstance(meal_diets, str):
            # First try splitting by comma, if that doesn't work, try space
            if ',' in meal_diets:
                meal_diets = [d.strip().lower() for d in meal_diets.split(',') if d.strip()]
            else:
                meal_diets = [d.strip().lower() for d in meal_diets.split() if d.strip()]
        elif not isinstance(meal_diets, list):
            meal_diets = [str(meal_diets).lower()]
        else:
            meal_diets = [str(d).lower().strip() for d in meal_diets if d and str(d).strip()]
        
        # If no valid diet types found in meal, log a warning but don't exclude it
        if not meal_diets:
            logging.warning(f"Meal {meal.get('meal_id', 'unknown')} has empty diet information. Relying on ingredient check only.")
            return 1
            
        # Get compatible diets for user's diet type
        compatible_diets = self.DIETARY_PREFERENCE_MAPPINGS.get(user_diet, [])
        if not compatible_diets:
            compatible_diets = [user_diet]
            
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
        # Handle case where user_preferences is None or food_restrictions is None/empty
        if not self.user_preferences or not self.user_preferences.get("food_restrictions"):
            return 1  # No restrictions specified, allow all meals
            
        # Get user's food restrictions (allergies)
        user_restrictions = [r.strip().lower() for r in self.user_preferences["food_restrictions"] if r and str(r).strip()]
        
        # If no valid user restrictions, allow the meal
        if not user_restrictions:
            return 1
            
        # Get meal's allergy information as a list, handling both string and list inputs
        meal_allergies = meal.get("allergies") or ""
        if isinstance(meal_allergies, str):
            meal_allergies = [a.strip().lower() for a in meal_allergies.split(',') if a.strip()]
        else:
            meal_allergies = [str(a).strip().lower() for a in meal_allergies if a and str(a).strip()]
        
        # If meal has no allergy info, be safe and filter it out if there are any restrictions
        if not meal_allergies and user_restrictions:
            logging.warning(f"Meal {meal.get('meal_id', 'unknown')} has no allergy information. Filtering out for safety.")
            return 0
            
        # Define the robust allergy mapping
        ALLERGY_MAPPING = {
            'nut-free': ['peanut allergy', 'tree nut allergy'],
            'dairy-free': ['dairy allergy'],
            'gluten-free': ['gluten allergy'],
            'none': []
        }
        
        # Check each user restriction against the meal's allergies
        for restriction in user_restrictions:
            # Skip empty or invalid restrictions
            if not restriction:
                continue
                
            # Get the allergies to exclude based on the restriction
            allergies_to_exclude = ALLERGY_MAPPING.get(restriction.lower(), [])
            
            # If the restriction is 'none', no allergies to exclude
            if restriction.lower() == 'none':
                continue
                
            # If no allergies to exclude for this restriction, skip
            if not allergies_to_exclude:
                continue
                
            # Check if any of the meal's allergies match the exclusions
            for meal_allergy in meal_allergies:
                if any(excluded in meal_allergy for excluded in allergies_to_exclude):
                    logging.info(f"Excluding meal {meal.get('meal_id', 'unknown')} - contains {meal_allergy} "
                                 f"which conflicts with user's {restriction} restriction")
                    return 0
                    
        return 1

    def _match_cuisine(self, meal: Dict) -> int:
        """
        Enhanced cuisine matching using robust mappings.
        Returns 1 (include) if:
        - No user cuisine preferences are specified (empty list, None, or empty string)
        - The meal's cuisine matches any of the user's cuisine preferences
        """
        # Handle case where user_preferences is None or cuisine_preferences is None/empty
        if not self.user_preferences or not self.user_preferences.get("cuisine_preferences"):
            return 1  # No cuisine preferences specified, allow all meals
            
        # Get user's cuisine preferences, filtering out any empty or invalid values
        user_cuisines = [c.strip().lower() for c in self.user_preferences["cuisine_preferences"] 
                        if c and str(c).strip()]
        
        # If no valid user cuisine preferences, allow all meals
        if not user_cuisines:
            return 1
            
        # Get meal's cuisine information
        meal_cuisine = (meal.get("cuisine_preferences") or "").strip().lower()
        
        # If meal has no cuisine specified, filter it out (be conservative)
        if not meal_cuisine:
            return 0

        # Get all compatible cuisines for user preferences
        compatible_cuisines = set()
        for pref in user_cuisines:
            compatible_cuisines.update(self.CUISINE_PREFERENCE_MAPPINGS.get(pref.lower(), [pref.lower()]))

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