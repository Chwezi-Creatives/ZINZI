import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MealService {
  final String baseUrl;
  final http.Client client;
  final SharedPreferences prefs;

  MealService({
    required this.baseUrl,
    required this.client,
    required this.prefs,
  });

  /// Fetches all available meals from the API
  Future<List<Map<String, dynamic>>> getMeals({int page = 1, int perPage = 10}) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/meals?page=$page&per_page=$perPage'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to load meals: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch meals: $e');
    }
  }

  /// Gets the authentication headers with token
  Future<Map<String, String>> _getHeaders() async {
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Saves the selected meals to the user's meal plan
  Future<bool> saveMealPlan({
    required int subscriptionId,
    required List<String> mealIds,
    String? chefId,
  }) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/subscriptions/$subscriptionId/meals'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'meal_ids': mealIds,
          if (chefId != null) 'chef_id': chefId,
        }),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      throw Exception('Failed to save meal plan: $e');
    }
  }

  /// Gets the list of available chefs
  Future<List<Map<String, dynamic>>> getChefs() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/chefs'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to load chefs: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch chefs: $e');
    }
  }
}
