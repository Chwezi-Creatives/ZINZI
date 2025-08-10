import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MealPlan {
  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final int chefId;
  final List<Map<String, dynamic>> meals;

  MealPlan({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.chefId,
    required this.meals,
  });

  factory MealPlan.fromJson(Map<String, dynamic> json) {
    return MealPlan(
      id: json['id'],
      name: json['name'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      chefId: json['chef_id'],
      meals: List<Map<String, dynamic>>.from(json['meals'] ?? []),
    );
  }
}

class SubscriptionPlan {
  final int id;
  final String name;
  final double price;
  final String billingCycle;
  final List<String> features;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.billingCycle,
    this.features = const [],
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    // Helper to parse price from any type
    double parsePrice(dynamic price) {
      if (price == null) return 0.0;
      if (price is num) return price.toDouble();
      if (price is String) {
        return double.tryParse(price) ?? 0.0;
      }
      return 0.0;
    }

    // Parse features from JSON
    List<String> parseFeatures(dynamic features) {
      if (features == null) return [];
      if (features is List) {
        return features.map((e) => e.toString()).toList();
      }
      if (features is String) {
        try {
          final parsed = jsonDecode(features) as List;
          return parsed.map((e) => e.toString()).toList();
        } catch (e) {
          return [features.toString()];
        }
      }
      return [];
    }

    return SubscriptionPlan(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Unnamed Plan',
      price: parsePrice(json['price']),
      billingCycle: json['billing_cycle']?.toString() ?? 'monthly',
      features: parseFeatures(json['features']),
    );
  }
}

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
  Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    try {
      final response = await http.get(
        Uri.parse('${_baseUrl}api/plans'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map<SubscriptionPlan>(
          (plan) => SubscriptionPlan.fromJson(plan)
        ).toList();
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Failed to load subscription plans';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Error fetching subscription plans: $e');
    }
  }

  // Get all subscriptions (admin only)
  Future<List<Map<String, dynamic>>> getAllSubscriptions() async {
    try {
      print('📡 [SubscriptionService] Fetching all subscriptions...');
      final response = await http.get(
        Uri.parse('${_baseUrl}api/admin/subscriptions'),
        headers: await _getHeaders(),
      );

      print('📥 [SubscriptionService] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        print('📊 [SubscriptionService] Response data keys: ${responseData.keys}');
        
        if (responseData.containsKey('subscriptions')) {
          final List<dynamic> subscriptions = responseData['subscriptions'];
          print('✅ [SubscriptionService] Found ${subscriptions.length} subscriptions');
          return List<Map<String, dynamic>>.from(subscriptions);
        } else if (responseData is List) {
          print('⚠️ [SubscriptionService] Response is a list, converting to list of maps');
          return List<Map<String, dynamic>>.from(
            (responseData as List).map((item) => item as Map<String, dynamic>)
          );
        } else {
          print('⚠️ [SubscriptionService] Unexpected response format, returning empty list');
          return [];
        }
      } else {
        final error = 'Failed to load subscriptions: ${response.statusCode}\n${response.body}';
        print('❌ [SubscriptionService] $error');
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      print('❌ [SubscriptionService] Error in getAllSubscriptions: $e');
      print('📝 Stack trace: $stackTrace');
      throw Exception('Error fetching subscriptions: $e');
    }
  }

  // Update subscription status (admin only)
  Future<Map<String, dynamic>> updateSubscriptionStatus({
    required String subscriptionId,
    required String status,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${_baseUrl}api/admin/subscriptions/$subscriptionId/status'),
        headers: await _getHeaders(),
        body: jsonEncode({'status': status.toLowerCase()}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Failed to update subscription status';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Error updating subscription status: $e');
    }
  }

  // Get current user's subscription status
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final userId = await _getUserId();
      final response = await http.get(
        Uri.parse('${_baseUrl}api/subscriptions/status?user_id=$userId'),
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
    String? paymentTransactionId,
    String? paymentMethod,
    String? phoneNumber,
  }) async {
    try {
      final userId = await _getUserId();
      final body = <String, dynamic>{
        'user_id': userId,
        'plan_id': planId,
      };
      
      if (paymentTransactionId != null) {
        body['payment_transaction_id'] = paymentTransactionId;
      }
      
      if (paymentMethod != null) {
        body['payment_method'] = paymentMethod;
      }
      
      if (phoneNumber != null) {
        // Ensure phone number is in the correct format (remove +256 if present and add it)
        String formattedPhone = phoneNumber.trim();
        if (formattedPhone.startsWith('+256')) {
          formattedPhone = formattedPhone.substring(4);
        } else if (formattedPhone.startsWith('0')) {
          formattedPhone = formattedPhone.substring(1);
        }
        body['phone_number'] = formattedPhone;
      }
      
      debugPrint('📡 Sending subscription request to: ${_baseUrl}api/subscriptions');
      debugPrint('📦 Request body: $body');
      
      final response = await http.post(
        Uri.parse('${_baseUrl}api/subscriptions'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📦 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Subscription successful. Response data: $data');
        // Cache the subscription locally
        await _cacheSubscription(data);
        return data;
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Failed to subscribe to plan';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Error subscribing to plan: $e');
    }
  }

  // Cancel current subscription
  Future<bool> cancelSubscription() async {
    try {
      final userId = await _getUserId();
      final response = await http.post(
        Uri.parse('${_baseUrl}api/subscriptions/cancel'),
        headers: await _getHeaders(),
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        // Clear cached subscription
        await _clearCachedSubscription();
        return true;
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Failed to cancel subscription';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Error canceling subscription: $e');
    }
  }
  
  // Create a new meal plan
  Future<MealPlan> createMealPlan({
    required int subscriptionId,
    required int chefId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> meals,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${_baseUrl}api/meal-plans'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'subscription_id': subscriptionId,
          'chef_id': chefId,
          'name': name,
          'start_date': _formatDate(startDate),
          'end_date': _formatDate(endDate),
          'meals': meals,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return MealPlan.fromJson(jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body)['detail'] ?? 'Failed to create meal plan';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Error creating meal plan: $e');
    }
  }
  
  // Get meal plans for a chef
  Future<List<MealPlan>> getChefMealPlans({
    required int chefId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, String>{};
      if (status != null) params['status'] = status;
      if (startDate != null) params['start_date'] = _formatDate(startDate);
      if (endDate != null) params['end_date'] = _formatDate(endDate);

      final uri = Uri.parse('${_baseUrl}api/chefs/$chefId/meal-plans')
          .replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map<MealPlan>((plan) => MealPlan.fromJson(plan)).toList();
      } else {
        throw Exception('Failed to load chef meal plans');
      }
    } catch (e) {
      throw Exception('Error fetching chef meal plans: $e');
    }
  }
  
  // Helper to format date for API
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
  
  // Helper to get user ID from shared preferences
  Future<int> _getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try all possible user ID keys and types
      final keysToCheck = [
        'user_id',
        'chef_user_id',
        'producer_id',
        'stakeholder_id',
      ];
      
      // First try to get as int
      for (final key in keysToCheck) {
        final dynamic value = prefs.get(key);
        
        if (value == null) continue;
        
        // Handle case where value is already an int
        if (value is int) {
          return value;
        }
        
        // Handle case where value is a string that can be parsed as int
        if (value is String) {
          final parsedId = int.tryParse(value);
          if (parsedId != null) {
            return parsedId;
          }
        }
        
        // Handle case where value is a double (can happen with some storage backends)
        if (value is double) {
          return value.toInt();
        }
      }
      
      // If we get here, no valid user ID was found
      throw Exception('User not authenticated or invalid user ID format. Checked keys: $keysToCheck');
    } catch (e) {
      // Add more context to the error
      debugPrint('Error in _getUserId: $e');
      rethrow;
    }
  }

  // Check if user has an active subscription
  Future<bool> hasActiveSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check our subscription flag first (fast path)
      final hasActiveFlag = prefs.getBool('has_active_subscription') ?? false;
      if (!hasActiveFlag) {
        return false;
      }
      
      // Check if we have an end date
      final expiryDateStr = prefs.getString(_planExpiryKey);
      if (expiryDateStr != null) {
        final expiryDate = DateTime.parse(expiryDateStr);
        if (expiryDate.isBefore(DateTime.now())) {
          // Subscription has expired
          await prefs.setBool('has_active_subscription', false);
          return false;
        }
        return true;
      }
      
      // If we don't have an end date, check with the server
      final status = await getSubscriptionStatus();
      final isActive = status['is_active'] == true;
      
      // Update our local cache
      await prefs.setBool('has_active_subscription', isActive);
      if (status['end_date'] != null) {
        await prefs.setString(_planExpiryKey, status['end_date'].toString());
      }
      
      return isActive;
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
      return false;
    }
  }

  // Cache subscription details locally
  Future<void> _cacheSubscription(Map<String, dynamic> subscription) async {
    try {
      debugPrint('💾 Caching subscription data: $subscription');
      final prefs = await SharedPreferences.getInstance();
      
      String? endDate;
      
      // Get end date from subscription
      endDate = subscription['end_date']?.toString();
      
      // No need to cache plan name if we don't have it - we'll get it when loading subscription status
      // The important part is that the subscription was successful
      
      debugPrint('📅 End date to cache: $endDate');
      
      // Store a flag that we have an active subscription
      await prefs.setBool('has_active_subscription', true);
      
      if (endDate != null && endDate.isNotEmpty) {
        await prefs.setString(_planExpiryKey, endDate);
      }
      
      debugPrint('✅ Successfully cached subscription data');
    } catch (e) {
      debugPrint('❌ Error caching subscription: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      // Don't rethrow - failing to cache shouldn't fail the subscription
    }
  }

  // Clear cached subscription
  Future<void> _clearCachedSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activePlanKey);
    await prefs.remove(_planExpiryKey);
  }
}
