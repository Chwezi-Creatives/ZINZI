import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A utility class for caching user-related data using SharedPreferences.
class UserCache {
  static const String _cachePrefix = 'user_cache_';
  static const String _mealsCacheKey = '${_cachePrefix}cached_meals';
  static const String _mealsCacheTimestampKey = '${_cachePrefix}cached_meals_timestamp';
  
  final SharedPreferences _prefs;
  
  UserCache(this._prefs);
  
  /// Saves meals to cache with current timestamp
  Future<bool> cacheMeals(List<Map<String, dynamic>> meals) async {
    try {
      final now = DateTime.now().toIso8601String();
      final mealsJson = meals.map((meal) => jsonEncode(meal)).toList();
      
      await _prefs.setStringList(_mealsCacheKey, mealsJson);
      await _prefs.setString(_mealsCacheTimestampKey, now);
      return true;
    } catch (e) {
      debugPrint('Error caching meals: $e');
      return false;
    }
  }
  
  /// Retrieves cached meals if they exist and aren't expired
  List<Map<String, dynamic>>? getCachedMeals({Duration maxAge = const Duration(hours: 1)}) {
    try {
      final timestampStr = _prefs.getString(_mealsCacheTimestampKey);
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > maxAge) {
        // Cache is expired
        return null;
      }
      
      final mealsJson = _prefs.getStringList(_mealsCacheKey);
      if (mealsJson == null || mealsJson.isEmpty) return null;
      
      return mealsJson
          .map((json) => Map<String, dynamic>.from(jsonDecode(json)))
          .toList();
    } catch (e) {
      debugPrint('Error getting cached meals: $e');
      return null;
    }
  }
  
  /// Clears all cached meals
  Future<bool> clearMealCache() async {
    try {
      await _prefs.remove(_mealsCacheKey);
      await _prefs.remove(_mealsCacheTimestampKey);
      return true;
    } catch (e) {
      debugPrint('Error clearing meal cache: $e');
      return false;
    }
  }
  
  /// Saves user preferences
  Future<bool> savePreference<T>(String key, T value) async {
    try {
      final cacheKey = '${_cachePrefix}pref_$key';
      
      if (value is String) {
        return await _prefs.setString(cacheKey, value);
      } else if (value is int) {
        return await _prefs.setInt(cacheKey, value);
      } else if (value is double) {
        return await _prefs.setDouble(cacheKey, value);
      } else if (value is bool) {
        return await _prefs.setBool(cacheKey, value);
      } else if (value is List<String>) {
        return await _prefs.setStringList(cacheKey, value);
      }
      
      return false;
    } catch (e) {
      debugPrint('Error saving preference: $e');
      return false;
    }
  }
  
  /// Retrieves a user preference
  T? getPreference<T>(String key, {T? defaultValue}) {
    try {
      final cacheKey = '${_cachePrefix}pref_$key';
      
      if (T == String) {
        return _prefs.getString(cacheKey) as T? ?? defaultValue;
      } else if (T == int) {
        return _prefs.getInt(cacheKey) as T? ?? defaultValue;
      } else if (T == double) {
        return _prefs.getDouble(cacheKey) as T? ?? defaultValue;
      } else if (T == bool) {
        return _prefs.getBool(cacheKey) as T? ?? defaultValue;
      } else if (T == List<String>) {
        return _prefs.getStringList(cacheKey) as T? ?? defaultValue;
      }
      
      return defaultValue;
    } catch (e) {
      debugPrint('Error getting preference: $e');
      return defaultValue;
    }
  }
}
