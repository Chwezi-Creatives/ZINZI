import unittest
from meal_algorithm4 import MealRecommendation4

class TestMealFiltering(unittest.TestCase):    
    def test_match_goal(self):
        """Test goal matching with direct tag comparison"""
        # Setup test meal
        test_meal = {
            "goal": "weight loss, muscle gain",
            "dietary_preference": "high-protein, low-carb",
            "allergies": "dairy, gluten",
            "cuisine_type": "italian, mediterranean"
        }
        
        # Initialize with test preferences
        recommender = MealRecommendation4(1)
        recommender.user_preferences = {
            "goals": "weight loss",
            "diet_type": "high-protein",
            "food_restrictions": ["dairy", "gluten"],
            "cuisine_preferences": ["italian", "mediterranean"]
        }
        
        # Test goal matching
        self.assertEqual(recommender._match_goal(test_meal), 1)
        
        # Test non-matching goal
        recommender.user_preferences["goals"] = "maintenance"
        self.assertEqual(recommender._match_goal(test_meal), 0)
    
    def test_match_diet(self):
        """Test diet matching with direct tag comparison"""
        test_meal = {
            "dietary_preference": "high-protein, low-carb",
            "ingredients": ["chicken", "broccoli", "olive oil"]
        }
        
        recommender = MealRecommendation4(1)
        recommender.user_preferences = {
            "diet_type": "high-protein",
            "food_restrictions": []
        }
        
        # Test direct match
        self.assertEqual(recommender._match_diet(test_meal), 1)
        
        # Test non-matching diet
        recommender.user_preferences["diet_type"] = "vegan"
        self.assertEqual(recommender._match_diet(test_meal), 0)
    
    def test_match_allergies(self):
        """Test allergy filtering with direct tag comparison"""
        test_meal = {
            "allergies": "dairy, gluten",
            "ingredients": ["chicken", "broccoli"]
        }
        
        recommender = MealRecommendation4(1)
        recommender.user_preferences = {
            "food_restrictions": ["dairy", "nuts"]
        }
        
        # Test with matching allergy (should return 0 to exclude)
        self.assertEqual(recommender._match_allergies(test_meal), 0)
        
        # Test with no matching allergies
        test_meal["allergies"] = "soy, eggs"
        self.assertEqual(recommender._match_allergies(test_meal), 1)
    
    def test_match_cuisine(self):
        """Test cuisine preference matching with direct tag comparison"""
        test_meal = {
            "cuisine_type": "italian, mediterranean"
        }
        
        recommender = MealRecommendation4(1)
        recommender.user_preferences = {
            "cuisine_preferences": ["italian", "french"]
        }
        
        # Test with matching cuisine
        self.assertEqual(recommender._match_cuisine(test_meal), 1)
        
        # Test with no matching cuisine
        recommender.user_preferences["cuisine_preferences"] = ["chinese", "japanese"]
        self.assertEqual(recommender._match_cuisine(test_meal), 0)

if __name__ == "__main__":
    unittest.main()
