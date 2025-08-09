import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class PaymentService {
  static const String _activePlanKey = 'active_payment_plan';
  static const String _planExpiryKey = 'plan_expiry_date';
  
  // Check if user has an active payment plan
  static Future<bool> hasActivePlan() async {
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
        // Clear expired plan
        await prefs.remove(_activePlanKey);
        await prefs.remove(_planExpiryKey);
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('Error checking plan status: $e');
      return false;
    }
  }
  
  // Get the current active plan type
  static Future<String?> getActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activePlanKey);
  }
  
  // Set a new payment plan for the user
  static Future<bool> setActivePlan(String planType, {int durationInDays = 14}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryDate = DateTime.now().add(Duration(days: durationInDays));
      
      await prefs.setString(_activePlanKey, planType);
      await prefs.setString(_planExpiryKey, expiryDate.toIso8601String());
      
      return true;
    } catch (e) {
      debugPrint('Error setting payment plan: $e');
      return false;
    }
  }
  
  // Clear the active plan (for logout or admin actions)
  static Future<void> clearActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activePlanKey);
    await prefs.remove(_planExpiryKey);
  }
  
  // Get plan expiration date
  static Future<DateTime?> getPlanExpiryDate() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryDateStr = prefs.getString(_planExpiryKey);
    
    if (expiryDateStr == null) return null;
    
    try {
      return DateTime.parse(expiryDateStr);
    } catch (e) {
      debugPrint('Error parsing expiry date: $e');
      return null;
    }
  }
}