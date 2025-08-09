//cspell:disable
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const String _userIdKey = 'user_id';
  static const String _userTypeKey = 'user_type';

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to get user ID as string first, fall back to int for backward compatibility
    return prefs.getString(_userIdKey) ?? 
           prefs.getInt(_userIdKey)?.toString();
  }

  Future<String?> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userTypeKey);
  }

  Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
  }

  Future<void> saveUserType(String userType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userTypeKey, userType);
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userTypeKey);
  }
}
