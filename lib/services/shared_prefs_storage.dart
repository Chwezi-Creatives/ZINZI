import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

class SharedPrefsStorage implements StorageService {
  final SharedPreferences _prefs;
  static const String _keyUserId = 'user_id';
  static const String _keyUserType = 'user_type';

  SharedPrefsStorage(this._prefs);

  @override
  SharedPreferences get prefs => _prefs;

  @override
  String? get userId => _prefs.getString(_keyUserId);
  
  @override
  set userId(String? value) {
    if (value != null) {
      _prefs.setString(_keyUserId, value);
    } else {
      _prefs.remove(_keyUserId);
    }
  }

  @override
  String? get userType => _prefs.getString(_keyUserType);
  
  @override
  set userType(String? value) {
    if (value != null) {
      _prefs.setString(_keyUserType, value);
    } else {
      _prefs.remove(_keyUserType);
    }
  }

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<bool> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();
}
