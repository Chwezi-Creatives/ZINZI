import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyUserId = 'user_id';
  static const String _keyUserType = 'user_type';
  
  final SharedPreferences _prefs;
  
  StorageService._(this._prefs);
  
  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService._(prefs);
  }
  
  // Getter for SharedPreferences instance
  SharedPreferences get prefs => _prefs;
  
  // User ID management
  String? get userId => _prefs.getString(_keyUserId);
  set userId(String? value) {
    if (value != null) {
      _prefs.setString(_keyUserId, value);
    } else {
      _prefs.remove(_keyUserId);
    }
  }
  
  // User type management
  String? get userType => _prefs.getString(_keyUserType);
  set userType(String? value) {
    if (value != null) {
      _prefs.setString(_keyUserType, value);
    } else {
      _prefs.remove(_keyUserType);
    }
  }
  
  // Clear all stored data
  Future<bool> clear() => _prefs.clear();
}
