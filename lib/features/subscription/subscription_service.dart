import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService {
  static const String _baseUrlKey = 'API_BASE_URL';
  static const String _activePlanKey = 'active_subscription_plan';
  static const String _planExpiryKey = 'subscription_expiry_date';
  static const String _authTokenKey = 'auth_token';

  // Get base URL from environment variables
  String get _baseUrl {
    final url = dotenv.env[_baseUrlKey];
    if (url == null || url.isEmpty) {
      throw Exception('API base URL not configured');
    }
    return url.endsWith('/') ? url : '$url/';
  }

  // Get auth token from shared preferences
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  // Get headers with authentication
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Get available subscription plans
  Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    try {
      final response = await http.get(
        Uri.parse('${_baseUrl}api/subscriptions/plans'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        throw Exception('Failed to load subscription plans');
      }
    } catch (e) {
      throw Exception('Error fetching subscription plans: $e');
    }
  }

  // Get current user's subscription status
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${_baseUrl}api/subscriptions/status'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load subscription status');
      }
    } catch (e) {
      throw Exception('Error fetching subscription status: $e');
    }
  }

  // Subscribe to a plan
  Future<Map<String, dynamic>> subscribeToPlan({
    required int planId,
    required String paymentMethodId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${_baseUrl}api/subscriptions/subscribe'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'plan_id': planId,
          'payment_method_id': paymentMethodId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // Cache the subscription locally
        await _cacheSubscription(data);
        return data;
      } else {
        throw Exception('Failed to subscribe to plan');
      }
    } catch (e) {
      throw Exception('Error subscribing to plan: $e');
    }
  }

  // Cancel current subscription
  Future<bool> cancelSubscription() async {
    try {
      final response = await http.post(
        Uri.parse('${_baseUrl}api/subscriptions/cancel'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        // Clear cached subscription
        await _clearCachedSubscription();
        return true;
      } else {
        throw Exception('Failed to cancel subscription');
      }
    } catch (e) {
      throw Exception('Error canceling subscription: $e');
    }
  }

  // Check if user has an active subscription (local cache check)
  Future<bool> hasActiveSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final plan = prefs.getString(_activePlanKey);
    final expiryDateStr = prefs.getString(_planExpiryKey);
    
    if (plan == null || expiryDateStr == null) {
      return false;
    }
    
    try {
      final expiryDate = DateTime.parse(expiryDateStr);
      final now = DateTime.now();
      
      // Check if plan is expired
      if (now.isAfter(expiryDate)) {
        await _clearCachedSubscription();
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  // Cache subscription details locally
  Future<void> _cacheSubscription(Map<String, dynamic> subscription) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activePlanKey, subscription['plan']['name'] ?? '');
    
    if (subscription['end_date'] != null) {
      await prefs.setString(_planExpiryKey, subscription['end_date']);
    }
  }

  // Clear cached subscription
  Future<void> _clearCachedSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activePlanKey);
    await prefs.remove(_planExpiryKey);
  }
}
