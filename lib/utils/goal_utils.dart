/// Utility functions for working with user goals in the frontend.

/// Categorizes a user's goal string into one of the standard categories.
/// 
/// This mirrors the backend's _categorize_goal function to ensure consistent
/// categorization between frontend and backend.
/// 
/// Returns one of: 'weight_loss', 'muscle_gain', 'maintain', 'health_condition', 
/// or 'general_wellness'.
String categorizeGoal(String? goal) {
  if (goal == null || goal.isEmpty) {
    return 'general_wellness';
  }

  final goalLower = goal.toLowerCase();
  
  // Weight-related goals
  if (['lose weight', 'weight loss'].any((term) => goalLower.contains(term))) {
    return 'weight_loss';
  }
  if (['gain muscle', 'muscle gain'].any((term) => goalLower.contains(term))) {
    return 'muscle_gain';
  }
  if (['maintain', 'satiety'].any((term) => goalLower.contains(term))) {
    return 'maintain';
  }
  
  // Health conditions that might affect calculations
  final healthConditions = [
    'diabetes', 
    'hypertension', 
    'joint pain', 
    'postpartum', 
    'inflammation'
  ];
  
  if (healthConditions.any((condition) => goalLower.contains(condition))) {
    return 'health_condition';
  }
  
  return 'general_wellness';
}

/// Gets the display name for a goal category.
/// 
/// Returns a user-friendly display name for the given category.
String getGoalCategoryDisplayName(String category) {
  switch (category) {
    case 'weight_loss':
      return 'Weight Loss';
    case 'muscle_gain':
      return 'Muscle Gain';
    case 'maintain':
      return 'Maintain Weight';
    case 'health_condition':
      return 'Health Condition';
    case 'general_wellness':
    default:
      return 'General Wellness';
  }
}

/// Gets the calorie adjustment factor for a goal category.
/// 
/// Returns a multiplier to apply to TDEE based on the goal.
double getGoalAdjustmentFactor(String category) {
  switch (category) {
    case 'weight_loss':
      return -0.15;  // 15% reduction for weight loss
    case 'muscle_gain':
      return 0.15;   // 15% increase for muscle gain
    case 'maintain':
    case 'health_condition':
    case 'general_wellness':
    default:
      return 0.0;    // No adjustment for these categories
  }
}
