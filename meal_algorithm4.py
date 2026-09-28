# cspell:disable
import logging
from typing import Optional, Dict, List, Tuple, Any, AsyncGenerator
from database import get_db, get_database_pool
from datetime import datetime, timedelta
import asyncpg
import json
import hashlib
import random
import math
import re
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(
    level="INFO",
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Create module-level logger
logger = logging.getLogger(__name__)

class MealRecommendation4:
    _shared_cache = {
        'all_meals': None,
        'nutrition_data': {},
        'meal_ingredients': {},
        'last_update': datetime.now()
    }

    def __init__(self, user_id: int, db_pool: Optional[asyncpg.Pool] = None):
        """
        Initialize the meal recommendation system.
        
        Args:
            user_id: The ID of the user to make recommendations for
            db_pool: Optional database connection pool. If not provided, will use the global pool.
        """
        self.user_id = user_id
        self._cache = {
            'filtered_meals': None,
            'last_update': datetime.now(),
            'user_data_hash': None
        }
        self.user_preferences = None
        self.user_metrics = None
        self.daily_calorie_budget = 2000
        self._current_user_data_hash = None
        
        # Set the database pool (use provided pool or get the global one)
        if db_pool is not None:
            self._db_pool = db_pool
        else:
            self._db_pool = get_database_pool()

        # Initialize cache
        for cache_key in ['nutrition_data', 'meal_ingredients']:
            if cache_key not in self.__class__._shared_cache:
                self.__class__._shared_cache[cache_key] = {}

    async def initialize(self):
        """
        Async initialization method to be called after instantiation.
        This method should be called before any other methods that require database access.
        """
        logger.info(f"Initializing meal recommender for user {self.user_id}")
        
        if not self._db_pool:
            logger.error("Database pool not available")
            self._set_defaults()
            return
            
        async with self._db_pool.acquire() as connection:
            try:
                # Load user data
                self.user_preferences, self.user_metrics = await self._get_user_data(connection)
                if not self.user_preferences or not self.user_metrics:
                    logger.warning("Failed to load user data, using defaults")
                    self._set_defaults()
                    return
                    
                self.daily_calorie_budget = self.calculate_daily_calorie_budget()

                # Prefetch data if needed
                if not self.__class__._shared_cache['nutrition_data']:
                    await self._prefetch_nutrition_data(connection)
                
                if not self.__class__._shared_cache['all_meals']:
                    await self.fetch_all_meals(connection)

                # Update cache and hashes
                self._current_user_data_hash = self._get_user_data_hash()
                self._cache['user_data_hash'] = self._current_user_data_hash
                logger.info("Meal recommender initialized successfully")
                
            except Exception as e:
                logger.error(f"Error during initialization: {str(e)}")
                self._set_defaults()
                raise

    def _set_defaults(self):
        self.user_preferences = None
        self.user_metrics = None
        self.daily_calorie_budget = 2000
        logging.warning("Using default values due to initialization failure")

    async def _get_user_data(self, connection: asyncpg.Connection) -> tuple[Optional[Dict], Optional[Dict]]:
        try:
            # First, try to get data with a JOIN
            query_join = """
                SELECT 
                    up.goals, up.diet_type, up.food_restrictions, up.cuisine_preferences,
                    um.weight, um.height, um.cholesterol_level, um.sys_bp, um.dia_bp, 
                    um.pulse, um.age_range, um.sex, um.activity_level
                FROM user_preferences up
                LEFT JOIN user_metrics um ON up.user_id = um.user_id
                WHERE up.user_id = $1
            """
            result = await connection.fetchrow(query_join, self.user_id)

            if not result:
                logging.warning(f"No user preferences found for user_id {self.user_id}")
                return None, None

            # Check if we have metrics from the JOIN
            if result.get('weight') is None:
                logging.warning(f"No user metrics found for user_id {self.user_id}, fetching separately or using defaults.")
                query_metrics = """
                    SELECT weight, height, age_range, sex, activity_level 
                    FROM user_metrics 
                    WHERE user_id = $1
                """
                metrics_result = await connection.fetchrow(query_metrics, self.user_id)
            else:
                metrics_result = result

            # Handle case where metrics_result is None (no metrics found)
            if not metrics_result:
                logging.warning(f"No metrics found for user_id {self.user_id}, using defaults")
                metrics_result = {}

            preferences = {
                "goals": result.get("goals"),
                "diet_type": result.get("diet_type"),
                "food_restrictions": result.get("food_restrictions"),
                "cuisine_preferences": result.get("cuisine_preferences"),
            }
            
            # Safely extract and convert metrics with proper type checking
            def safe_get_float(data, key, default=0.0):
                if not data:
                    return default
                value = data.get(key)
                try:
                    return float(value) if value is not None else default
                except (ValueError, TypeError):
                    return default
                    
            def safe_get_str(data, key, default=""):
                if not data:
                    return default
                value = data.get(key)
                if value is None:
                    return default
                try:
                    return str(value).strip().lower()
                except (AttributeError, TypeError):
                    return default.lower()
            
            metrics = {
                "weight": safe_get_float(metrics_result, "weight", 70.0),
                "height": safe_get_float(metrics_result, "height", 170.0),
                "age_range": safe_get_str(metrics_result, "age_range", "30-40"),
                "sex": safe_get_str(metrics_result, "sex", "male"),
                "activity_level": safe_get_str(metrics_result, "activity_level", "sedentary")
            }
            
            return preferences, metrics

        except Exception as e:
            logging.error(f"Error fetching user data: {str(e)}")
            return None, None

    def _parse_tags(self, value: Optional[str]) -> set:
        """Helper function to parse comma-separated string into a set of lowercase tags."""
        if not value or not isinstance(value, str):
            return set()
        return {tag.strip().lower() for tag in value.split(',') if tag.strip()}

    async def _prefetch_nutrition_data(self, connection: asyncpg.Connection):
        try:
            logger.info("Prefetching nutrition data...")
            
            # Clear existing cache
            self.__class__._shared_cache['nutrition_data'] = {}
            
            rows = await connection.fetch("""
                SELECT 
                    produce_id, 
                    COALESCE(calories, 0)::float as calories,
                    COALESCE(carbohydrates, 0)::float as carbohydrates,
                    COALESCE(proteins, 0)::float as proteins,
                    COALESCE(fats, 0)::float as fats,
                    COALESCE(fiber, 0)::float as fiber,
                    COALESCE(NULLIF(sugar, ''), 'Non') as sugar,
                    COALESCE(NULLIF(iron, ''), 'Non') as iron,
                    COALESCE(NULLIF(vitamins, ''), 'Non') as vitamins,
                    COALESCE(NULLIF(magnesium, ''), 'Non') as magnesium,
                    COALESCE(NULLIF(calcium, ''), 'Non') as calcium,
                    COALESCE(NULLIF(potassium, ''), 'Non') as potassium,
                    COALESCE(NULLIF(cobalamin, ''), 'Non') as cobalamin
                FROM Produce
            """)
            
            count = 0
            for row in rows:
                self.__class__._shared_cache['nutrition_data'][row['produce_id']] = dict(row)
                count += 1
            
            logger.info(f"Prefetched nutrition data for {count} ingredients")

        except Exception as e:
            logger.error(f"Error prefetching nutrition data: {str(e)}")


    async def fetch_all_meals(self, connection: Optional[asyncpg.Connection] = None) -> List[Dict]:
        """
        Fetch all meals from the database.
        
        Args:
            connection: Optional database connection. If not provided, will use the pool.
            
        Returns:
            List of meal dictionaries with their details
        """
        try:
            now = datetime.now()
            if (self.__class__._shared_cache['all_meals'] and 
                (now - self.__class__._shared_cache['last_update']) < timedelta(hours=24)):
                logger.debug("Using cached meals data")
                return self.__class__._shared_cache['all_meals']

            logger.info("Fetching meals from database...")
            
            async def _fetch_meals(conn: asyncpg.Connection) -> List[Dict]:
                query = """
                    SELECT 
                        m.*,
                        string_agg(DISTINCT pr.produce_name, ', ') AS ingredients,
                        COALESCE(SUM(mi.produce_quantity_in_grams), 0) as total_weight,
                        COALESCE(
                            jsonb_object_agg(
                                mi.produce_id, 
                                jsonb_build_object(
                                    'quantity', COALESCE(mi.produce_quantity_in_grams, 0),
                                    'name', pr.produce_name
                                )
                            ) FILTER (WHERE mi.produce_id IS NOT NULL),
                            '{}'::jsonb
                        ) as ingredients_detail
                    FROM meals m
                    LEFT JOIN meal_ingredients mi ON m.meal_id = mi.meal_id
                    LEFT JOIN produce pr ON mi.produce_id = pr.produce_id
                    GROUP BY m.meal_id
                    ORDER BY m.meal_name
                """
                
                rows = await conn.fetch(query)
                meals = []
                error_count = 0

                for row in rows:
                    try:
                        meal = dict(row)
                        meal_id = meal['meal_id']
                        
                        # Handle ingredients detail (already JSON from the query)
                        ingredients = meal.pop('ingredients_detail', {})
                        if isinstance(ingredients, str) and ingredients:
                            import json
                            ingredients = json.loads(ingredients)
                        
                        self.__class__._shared_cache['meal_ingredients'][meal_id] = ingredients
                        
                        nutritional_info = self._calculate_meal_nutrition(meal_id, ingredients)
                        meal['Nutritional_Info'] = nutritional_info
                        
                        meals.append(meal)
                    except Exception as e:
                        error_count += 1
                        logger.error(f"Error processing meal {meal.get('meal_id')}: {str(e)}")
                        continue
                
                return meals, error_count
            
            if connection:
                # Use the provided connection
                meals, error_count = await _fetch_meals(connection)
            else:
                # Get a new connection from the pool
                if not self._db_pool:
                    logger.error("Database pool not available")
                    return []
                    
                async with self._db_pool.acquire() as conn:
                    meals, error_count = await _fetch_meals(conn)
            
            # Update cache
            self.__class__._shared_cache['all_meals'] = meals
            self.__class__._shared_cache['last_update'] = now
            
            logger.info(f"Loaded {len(meals)} meals ({error_count} errors)")
            return meals

        except Exception as e:
            logger.error(f"Error fetching meals: {str(e)}", exc_info=True)
            return []

    def _calculate_meal_nutrition(self, meal_id, ingredients) -> Dict:
        # ... (This function is unchanged)
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

    # ... (Other functions like calculate_daily_calorie_budget, _has_user_data_changed, etc. are okay and remain here)
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
        """
        if not self.user_metrics or not self.user_preferences:
            logging.warning("User metrics or preferences not found. Using default calorie budget.")
            return 2000

        weight = self.user_metrics.get("weight", 70)
        height = self.user_metrics.get("height", 170)
        age = int(self.user_metrics.get("age_range", "30-40").split("-")[0])
        sex = self.user_metrics.get("sex", "male").lower()
        activity_level = self.user_metrics.get("activity_level", "sedentary").lower()

        if sex == "male":
            bmr = 10 * weight + 6.25 * height - 5 * age + 5
        else:
            bmr = 10 * weight + 6.25 * height - 5 * age - 161

        activity_factors = {
            "sedentary": 1.2, "lightly active": 1.375, "moderately active": 1.55,
            "very active": 1.725, "extra active": 1.9,
        }
        tdee = bmr * activity_factors.get(activity_level, 1.2)

        goal = self.user_preferences.get("goals", "")
        adjustment_percent = self._get_goal_adjustment_factor(goal)
        tdee *= (1 + adjustment_percent)

        MINIMUM_CALORIES = 1200
        tdee = max(round(tdee, 1), MINIMUM_CALORIES)

        logging.info(f"Calculated TDEE: {tdee} calories | Goal: {goal} | Adjustment: {adjustment_percent*100:.1f}%")
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
        }
        return hashlib.md5(json.dumps(user_data, sort_keys=True, default=str).encode()).hexdigest()

    def _check_user_data_for_recommendation(self):
        """Return True if user data has changed, else False."""
        changed = self._has_user_data_changed()
        if changed:
            self._user_data_hash = self._get_user_data_hash()
        return changed
        
    def _generate_recommendations(self) -> List[Dict]:
        # ... (This function is mostly unchanged, but I've updated it to use the new matching functions)
        def log_remaining(meals_list, filter_name, filter_value=None):
            count = len(meals_list)
            log_msg = f"After {filter_name} filter (value: {filter_value}): {count} meals remaining"
            logger.info(log_msg)
            return meals_list

        try:
            all_meals = self.fetch_all_meals()
            if not all_meals:
                logger.error("No meals found in the database.")
                return []
            
            if not self.user_preferences:
                logger.warning("No user preferences found. Cannot generate recommendations.")
                return []

            filtered_meals = all_meals.copy()

            # Apply Allergy Filter
            filtered_meals = [m for m in filtered_meals if self._match_allergies(m)]
            log_remaining(filtered_meals, "allergy-based", self.user_preferences.get('food_restrictions'))
            if not filtered_meals: return []

            # Apply Diet Filter
            filtered_meals = [m for m in filtered_meals if self._match_diet(m)]
            log_remaining(filtered_meals, "diet-based", self.user_preferences.get('diet_type'))
            if not filtered_meals: return []

            # Apply Calorie Filter
            filtered_meals = [m for m in filtered_meals if self._is_meal_within_calorie_budget(m, self._determine_meal_type(m))]
            log_remaining(filtered_meals, "calorie budget", f"Max calories per meal type: {self.daily_calorie_budget}")
            if not filtered_meals: return []
            
            # Apply Cuisine Filter
            filtered_meals = [m for m in filtered_meals if self._match_cuisine(m)]
            log_remaining(filtered_meals, "cuisine-based", self.user_preferences.get('cuisine_preferences'))
            if not filtered_meals: return []

            # Apply Goal Filter
            filtered_meals = [m for m in filtered_meals if self._match_goal(m)]
            log_remaining(filtered_meals, "goal-based", self.user_preferences.get('goals'))
            if not filtered_meals: return []

            final_recommendations = []
            for meal in filtered_meals:
                meal_copy = meal.copy()
                meal_type = self._determine_meal_type(meal_copy)
                meal_copy["recommended_serving_size"] = self.calculate_serving_size(meal_copy, meal_type)
                final_recommendations.append(meal_copy)

            logging.info(f"Generated {len(final_recommendations)} final recommendations")
            return final_recommendations

        except Exception as e:
            logging.error(f"Error generating meal recommendations: {str(e)}", exc_info=True)
            return []
    
    # ... (Other functions like recommend_meals, calculate_serving_size, etc., are okay)
    def recommend_meals(self) -> List[Dict]:
        now = datetime.now()
        cache_key = f"recommendations_{self.user_id}"
        
        try:
            connection = get_db()
            if connection:
                with connection:
                    fresh_prefs, fresh_metrics = self._get_user_data(connection)
                    if fresh_prefs:
                        self.user_preferences = fresh_prefs
                        self.user_metrics = fresh_metrics
                        self.daily_calorie_budget = self.calculate_daily_calorie_budget()
                        self._current_user_data_hash = self._get_user_data_hash()
        except Exception as e:
            logging.error(f"Error refreshing user data: {str(e)}")
        
        user_data_hash = self._get_user_data_hash()

        if cache_key in self.__class__._shared_cache:
            cache_time, cached_recs, cached_hash = self.__class__._shared_cache[cache_key]
            if cached_hash == user_data_hash and (now - cache_time < timedelta(hours=1)):
                logging.info(f"Using cached recommendations for user {self.user_id}")
                return cached_recs
        
        logging.info(f"User data changed for user {self.user_id} or cache expired, regenerating recommendations")
        recommendations = self._generate_recommendations()
        self.__class__._shared_cache[cache_key] = (now, recommendations, user_data_hash)
        return recommendations

    def _get_max_meal_calories(self, meal_type: str) -> float:
        # ... (This function is unchanged)
        if not hasattr(self, 'daily_calorie_budget') or not self.daily_calorie_budget:
            return 1000 # Fallback
            
        return {
            "breakfast": self.daily_calorie_budget * 0.30,
            "lunch": self.daily_calorie_budget * 0.40,
            "dinner": self.daily_calorie_budget * 0.40,
            "snack": self.daily_calorie_budget * 0.15,
        }.get(meal_type.lower(), self.daily_calorie_budget * 0.3)

    def _is_meal_within_calorie_budget(self, meal: Dict, meal_type: str) -> bool:
        # ... (This function is unchanged)
        try:
            meal_calories = meal["Nutritional_Info"].get("calories", 0)
            if not meal_calories: return True
            max_calories = self._get_max_meal_calories(meal_type)
            return float(meal_calories) <= max_calories
        except (KeyError, ValueError, TypeError):
            return True

    def calculate_serving_size(self, meal, meal_type: str) -> float:
        # ... (This function is unchanged)
        try:
            if not meal or not meal.get("meal_id"): return 0
            calorie_density = self.calculate_calorie_density(meal)
            if calorie_density <= 0: return 0
            daily_calories = self.daily_calorie_budget or 2000
            target_calories = {
                "breakfast": daily_calories * 0.25, "lunch": daily_calories * 0.35,
                "dinner": daily_calories * 0.40, "snack": daily_calories * 0.10
            }.get(meal_type.lower(), daily_calories * 0.25)
            serving_size = min(
                float(target_calories) / float(calorie_density),
                float(meal["Nutritional_Info"].get("total_weight", 0))
            )
            return round(serving_size, -1)
        except (ZeroDivisionError, KeyError, ValueError, TypeError) as e:
            logger.error(f"Error calculating serving size for meal {meal.get('meal_id')}: {e}")
            return 0

    def calculate_calorie_density(self, meal) -> float:
        # ... (This function is unchanged)
        try:
            total_calories = float(meal["Nutritional_Info"].get("calories", 0))
            total_weight = float(meal["Nutritional_Info"].get("total_weight", 1))
            return round(total_calories / total_weight, 1) if total_weight > 0 else 0.0
        except (KeyError, ValueError, TypeError) as e:
            logger.error(f"Failed to calculate calorie density: {e}")
            return 0.0

    async def calculate_meal_calories(self, meal_id: str) -> Dict:
        # ... (This function is unchanged)
        pass # Placeholder for the existing async function

    def _determine_meal_type(self, meal: Dict) -> str:
        # ... (This function is unchanged)
        calories = meal.get("Nutritional_Info", {}).get("calories", 0)
        if calories < 200: return "snack"
        elif calories < 300: return "breakfast"
        else: return "lunch"
    
    # ===================================================================
    # START OF CORRECTED AND SIMPLIFIED MATCHING LOGIC
    # ===================================================================

    def _match_allergies(self, meal: Dict) -> int:
        """
        Checks if a meal contains any of the user's specified food restrictions.
        Returns 1 if the meal is SAFE, 0 if it CONFLICTS.
        """
        if not self.user_preferences: return 1 # Be permissive
        
        user_restrictions = self._parse_tags(self.user_preferences.get("food_restrictions"))
        if not user_restrictions or "no allergies" in user_restrictions:
            return 1 # User has no restrictions, all meals are safe.

        meal_allergens = self._parse_tags(meal.get("allergies"))
        if not meal_allergens:
            return 1 # Meal has no allergens, it's safe.
        
        # A conflict exists if there is any overlap between the two sets.
        if user_restrictions.intersection(meal_allergens):
            logging.debug(f"Excluding meal {meal.get('meal_id')} due to allergy conflict: {user_restrictions.intersection(meal_allergens)}")
            return 0 # CONFLICT
        
        return 1 # SAFE

    def _match_diet(self, meal: Dict) -> int:
        """
        Checks if a meal's diet type matches the user's preference.
        Returns 1 for a MATCH, 0 for NO MATCH.
        """
        if not self.user_preferences: return 1 # Be permissive
        
        user_diets = self._parse_tags(self.user_preferences.get("diet_type"))
        if not user_diets or "omnivore" in user_diets or "all" in user_diets:
            return 1 # User has no specific diet preference, allow all meals.

        meal_diets = self._parse_tags(meal.get("dietary_preference"))
        if not meal_diets:
            return 1 # Meal has no specific diet, so don't exclude it.
            
        # A match exists if there is any overlap.
        if user_diets.intersection(meal_diets):
            return 1 # MATCH
            
        return 0 # NO MATCH

    def _match_cuisine(self, meal: Dict) -> int:
        """
        Checks if a meal's cuisine matches the user's preference.
        Returns 1 for a MATCH, 0 for NO MATCH.
        """
        if not self.user_preferences: return 1 # Be permissive
        
        user_cuisines = self._parse_tags(self.user_preferences.get("cuisine_preferences"))
        if not user_cuisines or "any" in user_cuisines:
            return 1 # User wants any cuisine, allow all meals.
        
        # Note: The meal's cuisine field is named 'cuisine_preferences' in the DB query alias.
        meal_cuisines = self._parse_tags(meal.get("cuisine_type"))
        if not meal_cuisines:
            return 0 # Meal has no cuisine tag, so it cannot match a specific preference.

        # A match exists if there is any overlap.
        if user_cuisines.intersection(meal_cuisines):
            return 1 # MATCH
            
        return 0 # NO MATCH

    def _match_goal(self, meal: Dict) -> int:
        """
        Checks if a meal's goals match the user's specified goals.
        Returns 1 for a MATCH, 0 for NO MATCH.
        """
        if not self.user_preferences: return 1 # Be permissive
        
        user_goals = self._parse_tags(self.user_preferences.get("goals"))
        if not user_goals:
            return 1 # User specified no goals, so all meals are fine.
        
        meal_goals = self._parse_tags(meal.get("goal"))
        if not meal_goals:
            return 1 # Meal isn't for a specific goal, don't exclude it by default.
            
        # A match exists if there is any overlap between user's goals and meal's goals.
        if user_goals.intersection(meal_goals):
            return 1 # MATCH
        
        logging.debug(f"Excluding meal {meal.get('meal_id')} because its goals {meal_goals} do not match user goals {user_goals}")
        return 0 # NO MATCH

    # ===================================================================
    # END OF CORRECTED AND SIMPLIFIED MATCHING LOGIC
    # ===================================================================

async def main():
    logging.info("Starting meal recommendation service...")
    user_id = 206  # Testing with the user from the example
    try:
        meal_recommender = MealRecommendation4(user_id)
        recommendations = meal_recommender.recommend_meals()
        logging.info(f"Generated {len(recommendations)} recommendations for user {user_id}")
        for rec in recommendations:
            print(f"- {rec['meal_name']} (ID: {rec['meal_id']})")
    except Exception as e:
        logger.error(f"Failed to generate recommendations: {str(e)}")