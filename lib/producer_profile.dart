//cspell:disable
import 'dart:async';
import 'dart:convert';
import 'dart:io'; // For File handling

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter & SystemUiOverlayStyle
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/cache_config.dart'; // <<< IMPORT CacheConfig
import 'package:zinzi/user_cache.dart'; // <<< IMPORT UserCache
import 'package:flutter/foundation.dart';

// --- UI Constants ---
const Color primaryTeal = Color(0xFF00796B);
const Color lightTeal = Color(0xFFB2DFDB);
const Color faintLightTeal = Color(0xFFE0F2F1);
const Color darkTeal = Color(0xFF004D40);
const Color whiteColor = Colors.white;
const Color textOnTeal = Colors.white;
const Color textOnWhite = Color(0xFF212121);
const Color subtleText = Color(0xFF757575);
const Color cardBackground = Color(0xFFF1F8F8);
const Color errorColor = Color(0xFFD32F2F);
const Color starColor = Color(0xFFFFC107);
const Color dividerColor = Color(0xFFE0E0E0);
const Color textFieldFillColor = Color(0xFFF5F5F5);
const String placeholderImagePath = 'assets/images/placeholder_avatar.png'; // Ensure this asset exists

// --- Helper Functions ---
int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _parseIntNullable(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

double? _parseDoubleNullable(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String? _getStringSafe(dynamic value) {
  return value?.toString();
}

bool _parseBoolSafe(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  if (value is int) return value == 1;
  return false;
}

// --- Data Model for Producer Profile ---
class ProducerProfile {
  final int producerId;
  final String name;
  final String? email;
  final String? phoneNumber;
  final String? location;
  final String? image; // URL
  final bool isActive;
  final DateTime registrationDate;
  final DateTime? lastLogin;
  final String? producerType;
  final double? rating;
  final String? reviews;
  final String? userType;
  final bool? isEmailVerified;
  final List<Map<String, dynamic>>? stock;
  File? localImageFile;

  ProducerProfile({
    required this.producerId,
    required this.name,
    this.email,
    this.phoneNumber,
    this.location,
    this.image,
    required this.isActive,
    required this.registrationDate,
    this.lastLogin,
    this.producerType,
    this.rating,
    this.reviews,
    this.userType,
    this.isEmailVerified,
    this.stock,
    this.localImageFile,
  });

  Map<String, dynamic> toJson() {
    return {
      'producer_id': producerId,
      'name': name,
      'email': email,
      'phone_number': phoneNumber,
      'location': location,
      'image': image,
      'is_active': isActive,
      'registration_date': registrationDate.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
      'producer_type': producerType,
      'rating': rating,
      'reviews': reviews,
      'user_type': userType,
      'is_email_verified': isEmailVerified,
      'stock': stock,
    };
  }

  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'phone_number': phoneNumber,
      'location': location,
      'is_active': isActive,
      'stock': stock,
    }..removeWhere((key, value) => value == null);
  }

  factory ProducerProfile.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? parseStock(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) {
            return decoded.whereType<Map<String, dynamic>>().toList();
          }
        } catch (e) {
          debugPrint("[ProducerProfile] Error decoding stock JSON string: $e");
        }
      } else if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
      debugPrint("[ProducerProfile] Warning: Unexpected stock format: ${value.runtimeType}. Returning null.");
      return null;
    }

    DateTime? parseDate(String? dateString) {
      if (dateString == null || dateString.isEmpty) return null;
      try {
        return DateTime.parse(dateString);
      } catch (e) {
        debugPrint("[ProducerProfile] Error parsing date string '$dateString': $e");
        return null;
      }
    }

    return ProducerProfile(
      producerId: _parseInt(json['producer_id']),
      name: _getStringSafe(json['name']) ?? 'Unknown Producer',
      email: _getStringSafe(json['email']),
      phoneNumber: _getStringSafe(json['phone_number']),
      location: _getStringSafe(json['location']),
      image: _getStringSafe(json['image']),
      isActive: _parseBoolSafe(json['is_active']),
      registrationDate: parseDate(json['registration_date']) ?? DateTime.now(),
      lastLogin: parseDate(json['last_login']),
      producerType: _getStringSafe(json['producer_type']),
      rating: _parseDoubleNullable(json['rating']),
      reviews: _getStringSafe(json['reviews']),
      userType: _getStringSafe(json['user_type']),
      isEmailVerified: _parseBoolSafe(json['is_email_verified']),
      stock: parseStock(json['stock']),
    );
  }

  ProducerProfile copyWith({
    int? producerId,
    String? name,
    String? email,
    String? phoneNumber,
    String? location,
    String? image,
    bool? isActive,
    DateTime? registrationDate,
    ValueGetter<DateTime?>? lastLogin,
    String? producerType,
    ValueGetter<double?>? rating,
    ValueGetter<String?>? reviews,
    String? userType,
    bool? isEmailVerified,
    ValueGetter<List<Map<String, dynamic>>?>? stock,
    ValueGetter<File?>? localImageFile,
  }) {
    return ProducerProfile(
      producerId: producerId ?? this.producerId,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      location: location ?? this.location,
      image: image ?? this.image,
      isActive: isActive ?? this.isActive,
      registrationDate: registrationDate ?? this.registrationDate,
      lastLogin: lastLogin != null ? lastLogin() : this.lastLogin,
      producerType: producerType ?? this.producerType,
      rating: rating != null ? rating() : this.rating,
      reviews: reviews != null ? reviews() : this.reviews,
      userType: userType ?? this.userType,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      stock: stock != null ? stock() : this.stock,
      localImageFile: localImageFile != null ? localImageFile() : this.localImageFile,
    );
  }
}

// --- API Service for Producer Profile ---
class ProducerProfileApiService {
  static final String _apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://your-api.example.com';

  static Future<String?> _getProducerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('producer_id') ?? prefs.getInt('producer_id')?.toString();
  }

  static dynamic _handleApiResponse(dynamic responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded.containsKey('data')) {
        return decoded['data'];
      }
      if (decoded is List || decoded is Map) {
        return decoded;
      }
      debugPrint("[ProducerProfileApiService] API response format warning: Decoded type is ${decoded.runtimeType}");
      return null;
    } catch (e) {
      debugPrint("[ProducerProfileApiService] API response JSON decoding error: $e");
      return null;
    }
  }

  static Future<Map<String, String>> _getReadHeaders({bool requiresAuth = false}) async {
    Map<String, String> headers = {'Accept': 'application/json'};
    if (requiresAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        debugPrint("[ProducerProfileApiService] Warning: Auth required for read but no access token found.");
      }
    }
    return headers;
  }

  static Future<Map<String, String>> _getWriteHeaders({bool requiresAuth = true}) async {
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (requiresAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        debugPrint("[ProducerProfileApiService] Warning: Auth required but no access token found.");
      }
    }
    return headers;
  }

  static Future<ProducerProfile> fetchProducerProfile() async {
    final producerId = await _getProducerId();
    if (producerId == null) {
      debugPrint('[ProducerProfileApiService] No producer ID found.');
      throw Exception('Producer session expired or not logged in. Please log in again.');
    }
    final Uri uri = Uri.parse('$_apibaseurl/rr/rproducers/$producerId');
    debugPrint("[ProducerProfileApiService] Fetching profile: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        Map<String, dynamic>? profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception('API response list item is not a valid map.');
          }
        } else if (handledData is Map<String, dynamic>) {
          if (handledData.containsKey('producer_id')) {
            profileMap = handledData;
          } else {
            throw Exception('API response map missing expected keys for profile. Body: ${response.body}');
          }
        }
        if (profileMap == null) {
          throw Exception('Producer profile not found or invalid format. Body: ${response.body}');
        }
        return ProducerProfile.fromJson(profileMap);
      } else {
        throw Exception('Failed to fetch producer profile (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('[ProducerProfileApiService] Profile fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateProducerStatus(int producerId, bool isActive) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId/status');
    debugPrint("[ProducerProfileApiService] Updating status for $producerId to $isActive at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: await _getWriteHeaders(),
        body: jsonEncode({'is_active': isActive}),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("[ProducerProfileApiService] Exception updating status: $e");
      return false;
    }
  }

  static Future<bool> updateProducerProfileFields(int producerId, {Map<String, dynamic>? changedFields}) async {
    if (changedFields == null || changedFields.isEmpty) {
      debugPrint("[ProducerProfileApiService] No fields to update");
      return true; // No changes to make
    }
    
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId');
    
    // Filter out null values from the changed fields
    final payload = Map<String, dynamic>.from(changedFields)
      ..removeWhere((key, value) => value == null);
    
    debugPrint("[ProducerProfileApiService] Updating profile fields for $producerId at $uri. Payload: ${jsonEncode(payload)}");
    try {
      final response = await http.patch(
        uri, 
        headers: await _getWriteHeaders(), 
        body: jsonEncode(payload),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("[ProducerProfileApiService] Exception updating profile fields: $e");
      return false;
    }
  }

  static Future<String?> updateProducerProfileImage(int producerId, File imageFile) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId/image');
    debugPrint("[ProducerProfileApiService] Uploading profile image for $producerId to $uri");
    try {
      var request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _getWriteHeaders());
      request.files.add(await http.MultipartFile.fromPath('profile_image', imageFile.path));
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final newImageUrl = responseData['imageUrl'] ?? responseData['image'];
        debugPrint("[ProducerProfileApiService] Image upload successful. New URL: $newImageUrl");
        return newImageUrl;
      } else {
        debugPrint("[ProducerProfileApiService] Error uploading image: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("[ProducerProfileApiService] Exception uploading image: $e");
      return null;
    }
  }
    /// Preload producer profile cache
  static Future<void> preloadCacheForSplash() async {
    debugPrint('[Splash][ProducerProfile] Starting profile cache preload...');
    final stopwatch = Stopwatch()..start();
    try {
      await fetchProducerProfile(); // This will use its own caching if implemented inside
      debugPrint('[Splash][ProducerProfile] Profile cache preloaded in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[Splash][ProducerProfile] Profile preload error: $e');
    }
  }
}

// --- Producer Profile Tab Widget ---
class ProducerProfileTab extends StatefulWidget {
  const ProducerProfileTab({super.key});

  @override
  State<ProducerProfileTab> createState() => _ProducerProfileTabState();
}

class _ProducerProfileTabState extends State<ProducerProfileTab> with AutomaticKeepAliveClientMixin {
  ProducerProfile? _profile;
  bool _isLoadingProfile = true;
  String _profileFetchError = '';
  bool _isEditingProfile = false;
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  late TextEditingController _profileLocationController;
  bool _isLoadingLocation = false;
  bool _isUploadingProfileImage = false;
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();

  ProducerProfile? _profileCache;
  DateTime? _profileCacheTimestamp;
  Timer? _refreshTimer; // For auto-refresh if needed, not implemented in original

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _profileNameController = TextEditingController();
    _profilePhoneController = TextEditingController();
    _profileLocationController = TextEditingController();
    _initializeProducerProfile();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _profileLocationController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeProducerProfile({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true;
        _profileFetchError = '';
      });
    }

    if (!forceRefresh) {
      await _loadProfileCacheFromPrefs();
    } else {
      _profileCache = null;
      _profileCacheTimestamp = null;
    }

    bool shouldFetchFresh = true;
    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) < CacheConfig.profileCacheDuration;

      if (cacheIsValid && !forceRefresh) {
        debugPrint("ProducerProfileTab: Displaying valid cached profile.");
        setState(() {
          _profile = _profileCache;
          if (_profile != null) _updateControllersFromProfile(_profile!);
          _isLoadingProfile = false;
        });
        shouldFetchFresh = false;
      } else {
        debugPrint("ProducerProfileTab: Cached profile ${forceRefresh ? 'ignored' : 'expired'}, will fetch fresh.");
        setState(() {
          _profile = _profileCache; 
          if (_profile != null) _updateControllersFromProfile(_profile!);
        });
      }
    }

    if (shouldFetchFresh && mounted) {
      await _fetchProducerProfileAndUpdate();
    } else if (mounted && !shouldFetchFresh && _isLoadingProfile) {
      setState(() => _isLoadingProfile = false);
    }
  }


  Future<void> _fetchProducerProfileAndUpdate() async {
    try {
      final profile = await ProducerProfileApiService.fetchProducerProfile();
      if (mounted) {
        await _saveProfileCacheToPrefs(profile, DateTime.now());
        setState(() {
          _profile = profile;
          _updateControllersFromProfile(profile);
          _isLoadingProfile = false;
          _profileFetchError = '';
        });
      }
    } catch (error) {
      debugPrint("[ProducerProfileTab] Error fetching profile: $error");
      if (mounted) {
        final errorMsg = 'Failed to load profile. Please check your connection.';
        setState(() {
          _profileFetchError = errorMsg;
          _isLoadingProfile = false;
          if (_profile == null) _showErrorSnackBar('Error loading profile data.');
          else _showInfoSnackbar("Couldn't update profile, showing last known data.");
        });
      }
    }
  }

  Future<void> _loadProfileCacheFromPrefs() async {
    final cachedJson = await UserCache.getData('producer_profile');
    final timestampStr = await UserCache.getData('producer_profile_cache_timestamp');
    if (cachedJson is Map<String, dynamic>) {
      try {
        _profileCache = ProducerProfile.fromJson(cachedJson);
      } catch (e) {
        _profileCache = null;
        await UserCache.removeData('producer_profile');
        await UserCache.removeData('producer_profile_cache_timestamp');
      }
    }
    if (timestampStr is String) {
      _profileCacheTimestamp = DateTime.tryParse(timestampStr);
    }
  }

  Future<void> _saveProfileCacheToPrefs(ProducerProfile profile, DateTime timestamp) async {
    await UserCache.saveData('producer_profile', profile.toJson());
    await UserCache.saveData('producer_profile_cache_timestamp', timestamp.toIso8601String());
    _profileCache = profile;
    _profileCacheTimestamp = timestamp;
  }

  void _updateControllersFromProfile(ProducerProfile profile) {
    _profileNameController.text = profile.name;
    _profilePhoneController.text = profile.phoneNumber ?? '';
    _profileLocationController.text = profile.location ?? '';
  }

  void _handleEditProfile() {
    if (_profile == null || !mounted) return;
    setState(() {
      _isEditingProfile = true;
      _updateControllersFromProfile(_profile!);
      _profile!.localImageFile = null;
    });
  }

  Future<void> _saveProfileChanges() async {
    if (_profile == null || !mounted || !_isEditingProfile) return;
    if (!(_profileFormKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar('Please fix errors in the profile form.');
      return;
    }
    _showLoadingSnackbar('Saving profile...');
    setState(() => _isUploadingProfileImage = true);

    try {
      String? finalImageUrl = _profile!.image;
      
      // Handle image upload if a new image was selected
      if (_profile!.localImageFile != null) {
        final newImageUrl = await ProducerProfileApiService.updateProducerProfileImage(
          _profile!.producerId, 
          _profile!.localImageFile!,
        );
        if (newImageUrl != null) {
          finalImageUrl = newImageUrl;
        } else {
          _showInfoSnackbar('Image upload failed. Old image retained.');
        }
      }

      // Get current values from form fields
      final String newName = _profileNameController.text.trim();
      final String? newPhone = _profilePhoneController.text.trim().isEmpty 
          ? null 
          : _profilePhoneController.text.trim();
      final String? newLocation = _profileLocationController.text.trim().isEmpty 
          ? null 
          : _profileLocationController.text.trim();

      // Only include fields that have changed
      final Map<String, dynamic> changedFields = {};
      
      if (newName != _profile!.name) {
        changedFields['name'] = newName;
      }
      
      if (newPhone != _profile!.phoneNumber) {
        changedFields['phone_number'] = newPhone;
      }
      
      if (newLocation != _profile!.location) {
        changedFields['location'] = newLocation;
      }

      bool textUpdateSuccess = true;
      
      // Only make the API call if there are changes
      if (changedFields.isNotEmpty) {
        textUpdateSuccess = await ProducerProfileApiService.updateProducerProfileFields(
          _profile!.producerId,
          changedFields: changedFields,
        );
      }

      if (mounted) {
        setState(() => _isUploadingProfileImage = false);
        _dismissLoadingSnackbar();
        
        if (textUpdateSuccess) {
          // Update local state with new values
          setState(() {
            _profile = _profile!.copyWith(
              name: newName,
              phoneNumber: newPhone ?? _profile!.phoneNumber,
              location: newLocation ?? _profile!.location,
              image: finalImageUrl,
              localImageFile: () => null,
            );
            _isEditingProfile = false;
          });
          
          _showSuccessSnackbar('Profile updated.');
          await _initializeProducerProfile(forceRefresh: true);
        } else {
          _showErrorSnackBar('Failed to save profile text changes.');
        }
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");
      if (mounted) {
        setState(() => _isUploadingProfileImage = false);
        _dismissLoadingSnackbar();
        _showErrorSnackBar('An error occurred: $e');
      }
    }
  }

  void _cancelProfileEdit() {
    if (!mounted) return;
    setState(() {
      _isEditingProfile = false;
      if (_profile != null) {
        _updateControllersFromProfile(_profile!);
        _profile!.localImageFile = null;
      }
      _profileFormKey.currentState?.reset();
    });
  }

  Future<void> _handleToggleActiveStatus(bool newStatus) async {
    if (_profile == null || !mounted || _isEditingProfile) return;
    final originalStatus = _profile!.isActive;
    setState(() => _profile = _profile!.copyWith(isActive: newStatus));
    _showLoadingSnackbar('Updating status...');
    try {
      bool success = await ProducerProfileApiService.updateProducerStatus(_profile!.producerId, newStatus);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Status updated.');
          if (_profile != null) await _saveProfileCacheToPrefs(_profile!, DateTime.now());
        } else {
          setState(() => _profile = _profile!.copyWith(isActive: originalStatus));
          _showErrorSnackBar('Failed to update status.');
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() => _profile = _profile!.copyWith(isActive: originalStatus));
        _showErrorSnackBar('Error updating status: $e');
      }
    }
  }

  Future<void> _pickAndSetProfileImage() async {
    if (!_isEditingProfile || !mounted) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null && mounted) {
        setState(() => _profile = _profile?.copyWith(localImageFile: () => File(pickedFile.path)));
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar("Could not pick image: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isEditingProfile || !mounted) return;
    setState(() => _isLoadingLocation = true);
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled.');
      
      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied.');
      }
      
      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15)
      );
      
      // Prepare coordinates string
      final coords = '(${position.latitude}, ${position.longitude})';
      String displayAddress = coords; // Default to just coordinates
      
      try {
        // Try to get human-readable address
        final apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1';
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final address = data['address'] as Map<String, dynamic>?;
          
          if (address != null) {
            // Build a clean address string from available components
            final parts = <String>[];
            
            // Add specific address components in order of specificity
            if (address['name'] != null && address['name'].toString().isNotEmpty) {
              parts.add(address['name'].toString().trim());
            }
            if (address['road'] != null && address['road'].toString().isNotEmpty) {
              parts.add(address['road'].toString().trim());
            }
            if (address['neighbourhood'] != null && address['neighbourhood'].toString().isNotEmpty) {
              parts.add(address['neighbourhood'].toString().trim());
            }
            if (address['suburb'] != null && address['suburb'].toString().isNotEmpty) {
              parts.add(address['suburb'].toString().trim());
            }
            if (address['city'] != null && address['city'].toString().isNotEmpty) {
              parts.add(address['city'].toString().trim());
            } else if (address['town'] != null && address['town'].toString().isNotEmpty) {
              parts.add(address['town'].toString().trim());
            } else if (address['village'] != null && address['village'].toString().isNotEmpty) {
              parts.add(address['village'].toString().trim());
            }
            if (address['state'] != null && address['state'].toString().isNotEmpty) {
              parts.add(address['state'].toString().trim());
            }
            if (address['country'] != null && address['country'].toString().isNotEmpty) {
              parts.add(address['country'].toString().trim());
            }
            
            // Join parts with comma and space, remove any double spaces
            String addressString = parts.join(', ').replaceAll(RegExp(r'\s+'), ' ').trim();
            
            // If we have any address parts, use them with coordinates
            if (addressString.isNotEmpty) {
              displayAddress = '$addressString $coords';
            } else {
              // Fallback to display_name if address components are empty
              displayAddress = '${data['display_name'] ?? ''} $coords'.trim();
            }
          } else {
            // Fallback to display_name if address object is null
            displayAddress = '${data['display_name'] ?? ''} $coords'.trim();
          }
        } else {
          _showInfoSnackbar('Could not fetch readable address. Using coordinates only.');
        }
      } catch (e) {
        debugPrint('Reverse geocoding failed: $e');
        _showInfoSnackbar('Using coordinates only. Could not fetch readable address.');
      }
      
      // Update the UI with the formatted address
      if (mounted) {
        setState(() => _profileLocationController.text = displayAddress);
        _showSuccessSnackbar('Location Acquired!');
      }
    } on TimeoutException {
      _showErrorSnackBar('Getting location timed out.');
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _showErrorSnackBar(String message) => _showSnackbar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackbar(String message) => _showSnackbar(message, isError: false);
  void _showInfoSnackbar(String message) => _showSnackbar(message, isError: false, durationSeconds: 2);
  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..removeCurrentSnackBar()..showSnackBar(SnackBar(
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
        const SizedBox(width: 15),
        Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]),
      backgroundColor: Colors.black.withOpacity(0.8), duration: const Duration(minutes: 1),
      behavior: SnackBarBehavior.floating, margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
    ));
  }
  void _dismissLoadingSnackbar() { if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar(); }
  void _showSnackbar(String message, {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: isError ? whiteColor : textOnTeal), textAlign: TextAlign.center),
      backgroundColor: isError ? errorColor.withOpacity(0.9) : primaryTeal.withOpacity(0.9),
      duration: Duration(seconds: durationSeconds), behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)), elevation: 2.0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Important for AutomaticKeepAliveClientMixin
    if (_isLoadingProfile && _profile == null) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_profileFetchError.isNotEmpty && _profile == null) {
      return _buildProfileErrorView();
    }
    if (_profile != null) {
      return _isEditingProfile
          ? _buildProfileEditView(_profile!)
          : _buildProfileDisplayView(_profile!);
    }
    return _buildEmptyState('Profile Unavailable', 'Could not load profile details.', icon: Icons.person_off_outlined);
  }

  Widget _buildProfileErrorView() {
    return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Card(
      color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(25.0), child: Column(
        mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_off_outlined, color: errorColor, size: 48),
          const SizedBox(height: 16),
          const Text("Error Loading Profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textOnWhite)),
          const SizedBox(height: 8),
          Text(_profileFetchError.isNotEmpty ? _profileFetchError : "Could not load profile.", style: const TextStyle(color: subtleText, fontSize: 14), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => _initializeProducerProfile(forceRefresh: true),
          ),
        ],
      )),
    )));
  }

  Widget _buildProfileDisplayView(ProducerProfile profile) {
    final dateFormat = DateFormat('MMM d, yyyy, hh:mm a');
    final profileAvatarImage = (profile.image != null && profile.image!.isNotEmpty)
        ? CachedNetworkImageProvider(profile.image!)
        : const AssetImage(placeholderImagePath) as ImageProvider;

    return RefreshIndicator(
      onRefresh: () => _initializeProducerProfile(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            elevation: 2.0, color: cardBackground.withOpacity(0.95), margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0), child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 45, backgroundColor: lightTeal.withOpacity(0.5), backgroundImage: profileAvatarImage,
                  onBackgroundImageError: (_, __) => debugPrint('Error loading profile network image'),
                  child: profileAvatarImage is AssetImage ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                ),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkTeal)),
                  if (profile.producerType != null && profile.producerType!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2.0), child: Row(children: [
                       Text(profile.producerType!, style: const TextStyle(fontSize: 14, color: subtleText)),
                       if(profile.isEmailVerified != null)...[
                          const SizedBox(width: 8),
                          Icon(Icons.verified, size: 14, color: profile.isEmailVerified! ? Colors.green : Colors.grey),
                          const SizedBox(width:4),
                          Text(profile.isEmailVerified! ? 'Verified' : 'Not Verified', style: TextStyle(fontSize: 12, color: profile.isEmailVerified! ? Colors.green : Colors.grey, fontWeight: FontWeight.w500)),
                       ]
                    ])),
                  if (profile.rating != null && profile.rating! > 0)
                    Padding(padding: const EdgeInsets.only(top: 8.0), child: Row(children: [
                      const Icon(Icons.star_rounded, color: starColor, size: 18),
                      const SizedBox(width: 4),
                      Text(profile.rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textOnWhite)),
                      if (profile.reviews != null && profile.reviews!.isNotEmpty && profile.reviews!.toLowerCase() != 'none') ...[
                        const SizedBox(width: 6),
                        Text('(${profile.reviews} reviews)', style: const TextStyle(fontSize: 12, color: subtleText)),
                      ],
                    ])),
                ])),
              ],
            )),
          ),
          Card(
            elevation: 1, margin: const EdgeInsets.only(bottom: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: SwitchListTile(
              value: profile.isActive, onChanged: _isEditingProfile ? null : _handleToggleActiveStatus,
              title: const Text('Active Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: darkTeal)),
              subtitle: Text(profile.isActive ? 'Visible to customers' : 'Not currently visible', style: const TextStyle(fontSize: 13, color: subtleText)),
              secondary: Icon(profile.isActive ? Icons.check_circle_outline_rounded : Icons.power_settings_new_outlined, color: profile.isActive ? Colors.green.shade600 : Colors.orange.shade700, size: 28),
              activeColor: primaryTeal, inactiveThumbColor: Colors.grey.shade400, inactiveTrackColor: Colors.grey.shade200, contentPadding: EdgeInsets.zero,
            )),
          ),
          _buildProfileSectionCard(title: 'Contact & Details', icon: Icons.info_outline_rounded, children: [
            _buildDetailItem(Icons.email_outlined, 'Email', profile.email),
            _buildDetailItem(Icons.phone_outlined, 'Phone', profile.phoneNumber),
            _buildDetailItem(Icons.location_on_outlined, 'Location', profile.location),
            _buildDetailItem(Icons.calendar_today_rounded, 'Registered', dateFormat.format(profile.registrationDate)),
            if (profile.lastLogin != null) _buildDetailItem(Icons.access_time_rounded, 'Last Login', dateFormat.format(profile.lastLogin!)),
             if (profile.isEmailVerified != null) _buildDetailItem(Icons.verified_outlined, 'Email Verified', profile.isEmailVerified! ? 'Yes':'No'),
            _buildDetailItem(Icons.person_outline_rounded, 'User Type', profile.userType),
            _buildDetailItem(Icons.category_outlined, 'Producer Type', profile.producerType),

          ]),
          // Edit Profile Button (Only if not editing)
           if (!_isEditingProfile)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: textOnTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleEditProfile,
                ),
              ),
            ),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }

  Widget _buildProfileEditView(ProducerProfile profile) {
    ImageProvider displayImage;
    if (profile.localImageFile != null) displayImage = FileImage(profile.localImageFile!);
    else if (profile.image != null && profile.image!.isNotEmpty) displayImage = CachedNetworkImageProvider(profile.image!);
    else displayImage = const AssetImage(placeholderImagePath);

    return Form(
      key: _profileFormKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Center(child: Stack(alignment: Alignment.bottomRight, children: [
            CircleAvatar(
              radius: 60, backgroundColor: lightTeal.withOpacity(0.3), backgroundImage: displayImage,
              onBackgroundImageError: (_, __) {}, 
              child: _isUploadingProfileImage ? const CircularProgressIndicator(color: primaryTeal) : null,
            ),
            Material(color: primaryTeal, shape: const CircleBorder(), elevation: 2, child: InkWell(
              customBorder: const CircleBorder(), onTap: _pickAndSetProfileImage,
              child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.camera_alt, color: whiteColor, size: 20)),
            )),
          ])),
          const SizedBox(height: 24),
          // Read-only email field
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text('Email', style: TextStyle(fontSize: 12, color: subtleText)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined, size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          profile.email ?? 'No email provided',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                      if (profile.isEmailVerified ?? false)
                        const Icon(Icons.verified, size: 16, color: Colors.green)
                      else
                        const Icon(Icons.error_outline, size: 16, color: Colors.orange),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildEditableItem(_profileNameController, 'Producer Name *', Icons.person_outline_rounded, 
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
          // Read-only phone field
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text('Phone Number', style: TextStyle(fontSize: 12, color: subtleText)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          profile.phoneNumber?.isNotEmpty == true 
                              ? profile.phoneNumber! 
                              : 'No phone number provided',
                          style: TextStyle(
                            fontSize: 14, 
                            color: profile.phoneNumber?.isNotEmpty == true 
                                ? Colors.black87 
                                : Colors.grey,
                            fontStyle: profile.phoneNumber?.isNotEmpty == true 
                                ? FontStyle.normal 
                                : FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildEditableItem(_profileLocationController, 'Location / Service Area', Icons.location_on_outlined, maxLines: 2),
          Padding(padding: const EdgeInsets.only(top: 4.0, left: 40), child: TextButton.icon(
            onPressed: _isLoadingLocation ? null : _getCurrentLocation,
            icon: _isLoadingLocation ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 18),
            label: Text(_isLoadingLocation ? 'Fetching...' : 'Get Current Location'),
            style: TextButton.styleFrom(foregroundColor: primaryTeal, textStyle: const TextStyle(fontSize: 13)),
          )),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _cancelProfileEdit, child: const Text('Cancel', style: TextStyle(color: subtleText)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: _isUploadingProfileImage ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: whiteColor)) : const Icon(Icons.save_outlined, size: 18),
              label: Text(_isUploadingProfileImage ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: _isUploadingProfileImage ? null : _saveProfileChanges,
            ),
          ]),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildProfileSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
        elevation: 1.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        color: whiteColor.withOpacity(0.9), margin: const EdgeInsets.only(bottom: 16),
        child: Padding(padding: const EdgeInsets.all(12.0), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: primaryTeal, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal))
            ]),
            const Divider(height: 16, thickness: 0.8, color: dividerColor),
            ...children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 4.0), child: child)),
          ],
        )));
  }

  Widget _buildDetailItem(IconData icon, String label, String? value) {
    final displayValue = (value == null || value.trim().isEmpty) ? 'Not provided' : value;
    final displayColor = (value == null || value.trim().isEmpty) ? subtleText.withOpacity(0.7) : subtleText;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, color: textOnWhite, fontSize: 13))),
        Expanded(child: Text(displayValue, style: TextStyle(color: displayColor, fontSize: 13), softWrap: true)),
      ],
    ));
  }

  Widget _buildEditableItem(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text, String? Function(String?)? validator}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, size: 18, color: primaryTeal.withOpacity(0.9)),
        prefixIconConstraints: const BoxConstraints(minWidth: 36), isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
        labelStyle: const TextStyle(color: subtleText, fontSize: 13), floatingLabelStyle: const TextStyle(color: primaryTeal),
        errorStyle: const TextStyle(fontSize: 11, color: errorColor),
      ),
      style: const TextStyle(color: textOnWhite, fontSize: 13), maxLines: maxLines, keyboardType: keyboardType,
      validator: validator, autovalidateMode: AutovalidateMode.onUserInteraction,
    ));
  }
  
  Widget _buildEmptyState(String title, String subtitle, {required IconData icon}) {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: subtleText.withOpacity(0.5)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textOnWhite), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: subtleText), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.grey[700], elevation: 0),
          onPressed: () => _initializeProducerProfile(forceRefresh: true), // Specific refresh for profile
        ),
      ],
    )));
  }
}


// --- Wrapper App for ProducerProfileTab ---
class ProducerProfileApp extends StatelessWidget {
  const ProducerProfileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Producer Profile',
      theme: ThemeData(
        primaryColor: primaryTeal,
        scaffoldBackgroundColor: Colors.grey[100],
        colorScheme: ColorScheme.fromSwatch().copyWith(secondary: lightTeal, error: errorColor, primary: primaryTeal),
         appBarTheme: const AppBarTheme(
            backgroundColor: primaryTeal,
            elevation: 2.0,
            iconTheme: IconThemeData(color: textOnTeal),
            titleTextStyle: TextStyle(color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18), systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: CardTheme(
            elevation: 1.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
            color: whiteColor.withOpacity(0.9),
            margin: const EdgeInsets.only(bottom: 16)
        ),
        inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
            labelStyle: const TextStyle(color: subtleText, fontSize: 13),
            floatingLabelStyle: const TextStyle(color: primaryTeal),
             errorStyle: const TextStyle(fontSize: 11, color: errorColor),
             contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
             isDense: true,

        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryTeal,
                foregroundColor: textOnTeal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                 textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)
            )
        ),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor: primaryTeal,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)
            )
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryTeal),
         snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
            elevation: 2.0,
            contentTextStyle: const TextStyle(color: Colors.white),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: textOnTeal),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Producer Profile Section'),
        ),
        body: const ProducerProfileTab(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}