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
    level=logging.INFO,
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

            self._cache['user_data_hash'] = self._get_user_data_hash()
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
        if goals == "weight loss":
            tdee -= 500
        elif goals == "muscle gain":
            tdee += 500

        return round(tdee, 1)

    def filter_meals(self) -> List[Dict]:
        try:
            user_data_hash = self._get_user_data_hash()
            now = datetime.now()
            cache_age = now - self._cache['last_update']
            
            if (self._cache['filtered_meals'] is not None and 
                cache_age < timedelta(hours=1) and 
                self._cache.get('user_data_hash') == user_data_hash):
                logging.info("Using cached filtered meals for user")
                return self._cache['filtered_meals']
            elif self._cache.get('user_data_hash') != user_data_hash:
                logging.info("User data changed, invalidating filtered meals cache")
            
            meals = self.fetch_all_meals()
            if not meals:
                logging.warning("No meals found in database")
                return []

            meals = list(meals)

            if self.user_preferences and self.user_preferences.get("diet_type"):
                diet_type = self.user_preferences["diet_type"].lower()
                if diet_type:
                    original_count = len(meals)
                    meals = [m for m in meals if 
                        m and m.get("dietary_preference") and 
                        diet_type in m["dietary_preference"].lower()]
                    logging.info(f"After diet_type filter ({diet_type}): {len(meals)} meals")

            if self.user_preferences and self.user_preferences.get("food_restrictions"):
                restrictions = self.user_preferences["food_restrictions"]
                if restrictions:
                    for restriction in restrictions:
                        if restriction:
                            original_count = len(meals)
                            meals = [m for m in meals if 
                                m and restriction.lower() not in (m.get("ingredients", "") or "").lower()]
                            logging.info(f"After restriction filter ({restriction}): {len(meals)} meals")

            if self.user_preferences and self.user_preferences.get("cuisine_preferences"):
                prefs = self.user_preferences["cuisine_preferences"]
                if prefs:
                    original_count = len(meals)
                    meals = [m for m in meals if 
                        m and any(pref.lower() in (m.get("cuisine_preferences", "") or "").lower() 
                                for pref in prefs)]
                    logging.info(f"After cuisine preferences filter: {len(meals)} meals")

            if self.user_metrics:
                min_nutrient_score = self._calculate_min_nutrient_score()
                original_count = len(meals)
                meals = [m for m in meals if 
                    m and m.get("Nutritional_Info") and 
                    m["Nutritional_Info"].get("nutrient_score", 0) >= min_nutrient_score]
                logging.info(f"After nutrient score filter (min score {min_nutrient_score}): {len(meals)} meals")

            if self.daily_calorie_budget is not None:
                original_count = len(meals)
                meals = [m for m in meals if 
                    m and m.get("Nutritional_Info") and 
                    m["Nutritional_Info"].get("calories", 0) <= self.daily_calorie_budget]
                logging.info(f"After calorie budget filter: {len(meals)} meals")

            if meals:
                meals.sort(key=lambda m: (
                    self._match_goal(m or {}),
                    self._match_diet(m or {}),
                    self._match_allergies(m or {}),
                    self._match_disease(m or {}),
                    self._match_cuisine(m or {}),
                    (m.get("Nutritional_Info") or {}).get("nutrient_score", 0)
                ), reverse=True)
            
            self._cache['filtered_meals'] = meals
            self._cache['last_update'] = now
            self._cache['user_data_hash'] = user_data_hash

            return meals

        except Exception as e:
            logging.error(f"Error filtering meals: {e}")
            return []

    def _calculate_min_nutrient_score(self) -> int:
        min_score = 0
        if self.user_metrics.get("health_conditions"):
            for condition in self.user_metrics["health_conditions"]:
                if condition == "anemia":
                    min_score += 5
                elif condition == "osteoporosis":
                    min_score += 4
                elif condition == "hypertension":
                    min_score += 3
                elif condition == "diabetes":
                    min_score += 2
        return min_score

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

    def recommend_meals(self) -> List[Dict]:
        now = datetime.now()
        cache_key = f"recommendations_{self.user_id}"
        user_data_hash = self._get_user_data_hash()
        
        if cache_key in self.__class__._shared_cache:
            cache_time, cached_recommendations, cached_user_hash = self.__class__._shared_cache[cache_key]
            if now - cache_time < timedelta(hours=1) and cached_user_hash == user_data_hash:
                logging.info(f"Using cached recommendations for user {self.user_id}")
                return cached_recommendations
            elif cached_user_hash != user_data_hash:
                logging.info(f"User data changed for user {self.user_id}, regenerating recommendations")
        
        logging.info(f"Generating new recommendations for user {self.user_id}")
        recommendations = self._generate_recommendations()
        
        self.__class__._shared_cache[cache_key] = (now, recommendations, user_data_hash)
        
        return recommendations

    def _generate_recommendations(self) -> List[Dict]:
        try:
            meals = self.filter_meals()
            if not meals:
                return []

            final_recommendations = []
            for meal in meals:
                meal_type = self._determine_meal_type(meal)
                serving_size = self.calculate_serving_size(meal, meal_type)
                meal["recommended_serving_size"] = serving_size
                final_recommendations.append(meal)

            return final_recommendations

        except Exception as e:
            logging.error(f"Error generating meal recommendations: {e}")
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
                return {"error": "Meal not found"}

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
        elif calories > 500:
            return "dinner"
        else:
            return "lunch"

    def _match_goal(self, meal: Dict) -> int:
        meal_goal = meal.get("goal")
        user_goal = self.user_preferences.get("goals") if self.user_preferences else None
        return 1 if meal_goal and user_goal and meal_goal.lower() == user_goal.lower() else 0

    def _match_diet(self, meal: Dict) -> int:
        meal_diet = meal.get("diet_type")
        user_diet = self.user_preferences.get("diet_type") if self.user_preferences else None
        return 1 if meal_diet and user_diet and meal_diet.lower() == user_diet.lower() else 0

    def _match_allergies(self, meal: Dict) -> int:
        meal_allergies = meal.get("allergies", "")
        user_restrictions = self.user_preferences.get("food_restrictions", []) if self.user_preferences else []
        return 1 if not any(allergy in meal_allergies.lower() for allergy in user_restrictions) else 0

    def _match_cuisine(self, meal: Dict) -> int:
        meal_cuisine = meal.get("cuisine")
        user_cuisines = self.user_preferences.get("cuisine_preferences", []) if self.user_preferences else []
        return 1 if meal_cuisine and any(cuisine.lower() == meal_cuisine.lower() for cuisine in user_cuisines) else 0

    def _match_disease(self, meal: Dict) -> int:
        return 1 if meal.get("disease_management") == self.user_metrics.get("health_conditions") else 0

if __name__ == "__main__":
    logging.info("Starting meal recommendation service...")
    user_id = 1
    try:
        meal_recommender = MealRecommendation4(user_id)
        recommendations = meal_recommender.recommend_meals()
        logging.info(f"Generated {len(recommendations)} recommendations")
    except Exception as e:
        logging.error(f"Failed to generate recommendations: {str(e)}")