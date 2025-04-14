import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UserCache {
  static final UserCache instance = UserCache._internal();
  factory UserCache() => instance;
  UserCache._internal();

  Map<String, dynamic>? userDetails;
  DateTime? lastFetch;
  static const Duration cacheDuration = Duration(hours: 12);

  static const String _userCacheKey = 'user_details_cache';
  static const String _userCacheTimestampKey = 'user_details_cache_timestamp';

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userCacheKey);
    final timestampStr = prefs.getString(_userCacheTimestampKey);
    if (userJson != null && timestampStr != null) {
      try {
        userDetails = json.decode(userJson);
        lastFetch = DateTime.parse(timestampStr);
      } catch (_) {
        userDetails = null;
        lastFetch = null;
      }
    }
  }

  Future<void> saveToPrefs(Map<String, dynamic> details) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userCacheKey, json.encode(details));
    await prefs.setString(_userCacheTimestampKey, DateTime.now().toIso8601String());
    userDetails = details;
    lastFetch = DateTime.now();
  }

  bool get isFresh {
    if (userDetails == null || lastFetch == null) return false;
    return DateTime.now().difference(lastFetch!) < cacheDuration;
  }

  void clear() {
    userDetails = null;
    lastFetch = null;
  }
}