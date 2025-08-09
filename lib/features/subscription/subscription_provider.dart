import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'subscription_service.dart';

class SubscriptionProvider with ChangeNotifier {
  final SubscriptionService _subscriptionService = SubscriptionService();
  
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _subscriptionStatus;
  List<Map<String, dynamic>> _plans = [];
  
  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get subscriptionStatus => _subscriptionStatus;
  List<Map<String, dynamic>> get plans => _plans;
  
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
    _setLoading(true);
    try {
      _subscriptionStatus = await _subscriptionService.getSubscriptionStatus();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading subscription status: $e');
    } finally {
      _setLoading(false);
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
    required String paymentMethodId,
  }) async {
    _setLoading(true);
    try {
      await _subscriptionService.subscribeToPlan(
        planId: planId,
        paymentMethodId: paymentMethodId,
      );
      
      // Refresh subscription status after successful subscription
      await loadSubscriptionStatus();
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error subscribing to plan: $e');
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
  
  // Check if user has an active subscription (local cache check)
  Future<bool> checkLocalSubscriptionStatus() async {
    return await _subscriptionService.hasActiveSubscription();
  }
  
  // Helper method to update loading state
  void _setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
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
