import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'subscription_service.dart' show SubscriptionService, SubscriptionPlan, MealPlan;

class SubscriptionProvider with ChangeNotifier {
  final SubscriptionService _subscriptionService = SubscriptionService();
  
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _subscriptionStatus;
  List<SubscriptionPlan> _plans = [];
  List<MealPlan> _chefMealPlans = [];
  
  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get subscriptionStatus => _subscriptionStatus;
  List<SubscriptionPlan> get plans => _plans;
  List<MealPlan> get chefMealPlans => _chefMealPlans;
  
  // Check if user has an active subscription
  bool get hasActiveSubscription {
    if (_subscriptionStatus == null) return false;
    return _subscriptionStatus!['has_active_plan'] == true;
  }
  
  // Get current plan name if available
  String? get currentPlanName {
    if (_subscriptionStatus == null || _subscriptionStatus!['current_plan'] == null) {
      return null;
    }
    return _subscriptionStatus!['current_plan']['plan']['name'];
  }
  
  // Load subscription status from the server
  Future<void> loadSubscriptionStatus() async {
    // Skip if already loading
    if (_isLoading) return;
    
    _setLoading(true);
    try {
      _subscriptionStatus = await _subscriptionService.getSubscriptionStatus();
      _error = null;
      // Schedule the notification for the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isLoading) {
          _setLoading(false);
        }
      });
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading subscription status: $e');
      // Schedule the notification for the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isLoading) {
          _setLoading(false);
        }
      });
    }
  }
  
  // Load available subscription plans
  Future<void> loadSubscriptionPlans() async {
    _setLoading(true);
    try {
      _plans = await _subscriptionService.getSubscriptionPlans();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading subscription plans: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  // Subscribe to a plan
  Future<bool> subscribeToPlan({
    required int planId,
    String? paymentTransactionId,
    String? paymentMethod,
    String? phoneNumber,
  }) async {
    _setLoading(true);
    _error = null;
    
    try {
      debugPrint('🔄 Attempting to subscribe to plan $planId');
      debugPrint('💳 Payment method: $paymentMethod');
      debugPrint('📱 Phone number: $phoneNumber');
      
      final result = await _subscriptionService.subscribeToPlan(
        planId: planId,
        paymentTransactionId: paymentTransactionId,
        paymentMethod: paymentMethod,
        phoneNumber: phoneNumber,
      );
      
      debugPrint('✅ Subscription successful. Result: $result');
      
      // Refresh subscription status after successful subscription
      await loadSubscriptionStatus();
      return true;
      
    } catch (e, stackTrace) {
      _error = e.toString();
      debugPrint('❌ Error subscribing to plan: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Try to extract a more user-friendly error message
      if (e.toString().contains('NoSuchMethodError')) {
        _error = 'Error processing subscription. Please try again.';
      }
      
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  // Cancel current subscription
  Future<bool> cancelSubscription() async {
    _setLoading(true);
    try {
      final success = await _subscriptionService.cancelSubscription();
      if (success) {
        // Refresh subscription status after cancellation
        await loadSubscriptionStatus();
      }
      _error = null;
      return success;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error canceling subscription: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  // Create a new meal plan
  Future<bool> createMealPlan({
    required int subscriptionId,
    required int chefId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> meals,
  }) async {
    _setLoading(true);
    try {
      await _subscriptionService.createMealPlan(
        subscriptionId: subscriptionId,
        chefId: chefId,
        name: name,
        startDate: startDate,
        endDate: endDate,
        meals: meals,
      );
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error creating meal plan: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  // Load meal plans for a chef
  Future<void> loadChefMealPlans({
    required int chefId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _setLoading(true);
    try {
      _chefMealPlans = await _subscriptionService.getChefMealPlans(
        chefId: chefId,
        status: status,
        startDate: startDate,
        endDate: endDate,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading chef meal plans: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  // Check if user has an active subscription (local cache check)
  Future<bool> checkLocalSubscriptionStatus() async {
    return await _subscriptionService.hasActiveSubscription();
  }
  
  // Helper method to update loading state
  void _setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      // Use Timer.run to ensure we're not in the middle of a build
      Timer.run(() {
        if (hasListeners) {
          notifyListeners();
        }
      });
    }
  }
  
  // Clear any errors
  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }
}
