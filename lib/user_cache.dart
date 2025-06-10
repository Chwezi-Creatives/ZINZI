//cspell:disable
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UserCache {
  // --- User-specific cache methods ---
  
  /// Saves data with a user-specific key
  static Future<void> saveUserData(String baseKey, dynamic data, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserSpecificKey(baseKey, userId: userId);
    await prefs.setString(userKey, jsonEncode(data));
  }

  /// Retrieves data using a user-specific key
  static Future<dynamic> getUserData(String baseKey, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserSpecificKey(baseKey, userId: userId);
    final jsonString = prefs.getString(userKey);
    
    // Fallback to non-user-specific key for backward compatibility
    if (jsonString == null) {
      final legacyData = await getData(baseKey);
      if (legacyData != null) {
        // Migrate old data to user-specific key
        await saveUserData(baseKey, legacyData, userId: userId);
        return legacyData;
      }
      return null;
    }
    
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
  }

  /// Removes data using a user-specific key
  static Future<void> removeUserData(String baseKey, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _getUserSpecificKey(baseKey, userId: userId);
    await prefs.remove(userKey);
  }

  // --- Legacy methods (kept for backward compatibility) ---
  
  static Future<void> saveData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<dynamic> getData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(key);
    if (jsonString != null) {
      try {
        return jsonDecode(jsonString);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  static Future<void> removeData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Clears all data for the current user
  static Future<void> clearUserData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // Find all keys that belong to this user
    final userKeys = keys.where((key) => key.endsWith('_$userId'));
    
    // Remove all user-specific keys
    for (final key in userKeys) {
      await prefs.remove(key);
    }
    
    // Also clear any legacy non-user-specific caches that might contain user data
    await Future.wait([
      prefs.remove('order_history_cache'),
      prefs.remove('order_history_cache_ts'),
      prefs.remove('user_profile'),
      prefs.remove('user_profile_ts'),
    ]);
  }

  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  
  // --- Private helper methods ---
  
  static Future<String> _getUserSpecificKey(String baseKey, {String? userId}) async {
    if (userId == null) {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('user_id');
      if (currentUserId == null) {
        return baseKey; // Fallback to non-user-specific key if no user ID
      }
      return '${baseKey}_$currentUserId';
    }
    return '${baseKey}_$userId';
  }
}