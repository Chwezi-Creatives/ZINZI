import 'dart:io';
import 'package:flutter/material.dart';
import 'widgets/custom_group_container.dart';
// import 'dart:math'; // Unused import for min function
import 'dart:async'; // Import for TimeoutException
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
// import 'notifications/fcm_service.dart'; // Removed duplicate, one below is fine
import 'package:zinzi2/onlymeals.dart';
// import 'package:zinzi2/blogview.dart'; // Not used directly here
// import 'package:zinzi2/cart.dart' as cart; // Not used directly here
// import 'package:zinzi2/onboard.dart'; // Not used directly here
import 'package:zinzi2/signup_or_Login.dart';
// import 'package:zinzi2/splash.dart'; // Replaced with LandingPage for logout
// import 'package:zinzi2/useranalytics.dart'; // Not used directly here
// import 'social.dart'; // Not used directly here
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinzi2/user_cache.dart'; // Import UserCache
import 'package:zinzi2/notifications/fcm_service.dart'; // Import FCMService
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/cache_config.dart'; // Import CacheConfig
import 'package:shimmer/shimmer.dart'; // For loading effect
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter/services.dart'; // For input formatters

// --- Re-add Color Constants (or import from a shared file) ---
// Imgur configuration
String imgurClientID = dotenv.env['IMGUR_CLIENT_ID'] ?? '';

const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Clean background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary =
    kColorPrimaryDark; // Use Dark Teal for primary text
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface =
    kColorTextPrimary; // Adjusted for Surface background
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
const Color kSubtleTextColor = Color(0xFF616161); // From user_metrics
const Color kErrorColor = Color(0xFFD32F2F); // From user_metrics
// Shimmer Colors
final Color kShimmerBaseColor = Colors.grey.shade300;
final Color kShimmerHighlightColor = Colors.grey.shade100;
// --- End Color Constants ---

// Use environment variable for API base URL
final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url';

class ProfilePage extends StatefulWidget {
  // Use const constructor
  const ProfilePage({super.key});

  /// Preload the user profile cache for splash screen (no UI, no context needed)
  static Future<void> preloadCacheForSplash() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = await UserCache.getData('user_details_cache');
    final cachedTimestampMillis = prefs.getInt('user_details_cache_timestamp');
    final now = DateTime.now();
    bool cacheValid = false;
    if (cachedData != null &&
        cachedTimestampMillis != null &&
        now.difference(
                DateTime.fromMillisecondsSinceEpoch(cachedTimestampMillis)) <
            CacheConfig.profileCacheDuration) {
      cacheValid = true;
    }
    if (!cacheValid) {
      try {
        final apiBaseUrlForPreload = dotenv.env[
                'API_BASE_URL'] ?? // Use a different var name to avoid confusion if needed
            dotenv.env['API_BASE_URL-intranet'] ??
            'https://default.url';
        int? userId = prefs.getInt('user_id');
        if (userId != null) {
          final response = await http
              .get(Uri.parse(
                  '$apiBaseUrlForPreload/rr/rusers/$userId')) // Assuming /rr/rusers endpoint
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            Map<String, dynamic>? userMap =
                _parseUserResponseStatic(responseData);
            if (userMap != null && userMap['user_id'] != null) {
              // Ensure correct keys for cache
              final cacheUserMap = {
                'name': userMap['name'] ?? '',
                'email': userMap['email'] ?? '',
                'user_id': userMap['user_id']?.toString() ?? '',
                ...userMap // preserve other keys as well
              };
              await UserCache.saveData('user_details_cache', cacheUserMap);
              await prefs.setInt('user_details_cache_timestamp',
                  DateTime.now().millisecondsSinceEpoch);
              print('[Splash][Profile] preload cache updated.');
            } else {
              print(
                  '[Splash][Profile] preload skipped: Failed to parse user data from response.');
            }
          } else {
            print(
                '[Splash][Profile] preload skipped: API error ${response.statusCode}');
          }
        } else {
          print('[Splash][Profile] preload skipped: No user ID found.');
        }
      } catch (e) {
        print('[Splash][Profile] preload error: $e');
      }
    } else {
      print('[Splash][Profile] preload skipped: Cache still valid.');
    }
  }

  // Static parser for preloadCacheForSplash
  static Map<String, dynamic>? _parseUserResponseStatic(dynamic responseData) {
    Map<String, dynamic>? userMap;
    if (responseData is Map<String, dynamic>) {
      // Handle single user object directly or nested under 'data'
      if (responseData.containsKey('data') && responseData['data'] is Map) {
        userMap = Map<String, dynamic>.from(responseData['data']);
      } else if (!responseData.containsKey('message') &&
          responseData.containsKey('user_id')) {
        // Check for user_id to assume it's the user object
        userMap = responseData;
      }
    } else if (responseData is List &&
        responseData.isNotEmpty &&
        responseData[0] is Map) {
      // Handle if API unexpectedly returns a list for a specific ID
      userMap = Map<String, dynamic>.from(responseData[0]);
    }
    return userMap;
  }

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  // --- Location Fetching State ---
  bool _isFetchingLocation = false;
  int _locationHintDots = 0;
  Timer? _locationHintTimer;

  // --- User Identification ---
  int? _userId;
  String? _userType;

  // --- Data Holding Maps ---
  Map<String, dynamic> _userDetails = {};
  Map<String, dynamic> _userMetrics = {};
  Map<String, dynamic> _userPreferences = {};

  // --- Loading and Error States ---
  bool _isLoadingUserDetails = true;
  bool _isLoadingMetrics = true;
  bool _isLoadingPreferences = true;
  bool _isLoading = true; // Overall initial loading
  String _fetchError = '';

  // --- Image State ---
  String? _profileImagePath;
  String? _profileImageUrl;
  final ImagePicker _picker = ImagePicker();

  // --- Section Editing State ---
  bool _isEditingUserDetails = false;
  bool _isEditingMetrics = false;
  bool _isEditingPreferences = false;

  // --- Controllers for User Details Editing ---
  final TextEditingController _userDetailsNameController =
      TextEditingController();
  final TextEditingController _userDetailsEmailController =
      TextEditingController();
  final TextEditingController _userDetailsPhoneController =
      TextEditingController();
  final TextEditingController _userDetailsLocationController =
      TextEditingController();

  // --- State Variables & Controllers for Metrics Editing ---
  String? _selectedAgeRange;
  final List<String> _ageRanges = [
    '5-10',
    '10-17',
    '18-25',
    '26-35',
    '36-45',
    '46-55',
    '56-65',
    '66+'
  ];
  String? _selectedSex;
  final List<String> _sexs = ['Male', 'Female'];
  String? _selectedActivityLevel;
  final List<String> _activityLevels = [
    'Sedentary',
    'Lightly Active',
    'Moderately Active',
    'Very Active'
  ];
  double _weightKg = 0;
  String _weightUnit = 'kg';
  final TextEditingController _weightController = TextEditingController();
  List<bool> _weightSelection = [true, false];
  double _heightCm = 0;
  String _heightUnit = 'cm';
  final TextEditingController _heightCmController = TextEditingController();
  final TextEditingController _heightFeetController = TextEditingController();
  final TextEditingController _heightInchesController = TextEditingController();
  List<bool> _heightSelection = [true, false];

  // --- State Variables & Controllers for Preferences Editing ---
  String? _selectedGoal;
  final List<String> _goalsOptions = [
    'Weight Loss',
    'Muscle Gain',
    'Maintain Weight'
  ];
  String? _selectedDietType;
  final List<String> _dietTypeOptions = [
    'Vegan',
    'Keto',
    'Paleo',
    'Mediterranean',
    'Omnivore'
  ];
  String? _selectedFoodRestriction;
  final List<String> _foodRestrictionsOptions = [
    'Gluten-Free',
    'Dairy-Free',
    'Nut-Free',
    'None'
  ];
  
  // Cuisine preferences
  List<String> _selectedCuisines = [];
  final List<String> _cuisineOptions = [
    'African',
    'East frican',
    'American',
    'Asian',
    'Chinese',
    'French',
    'Indian',
    'Italian',
    'Japanese',
    'Mediterranean',
    'Mexican',
    'Thai',
    'Other'
  ];

  // --- Animation ---
  late final AnimationController _refreshIconController;

  // --- Initialization ---
  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _initializeProfile();

    // Add listeners to update internal backend values (kg, cm) when text changes
    _weightController.addListener(_onWeightInputChanged);
    _heightCmController.addListener(_onHeightCmInputChanged);
    _heightFeetController.addListener(_onHeightFtInInputChanged);
    _heightInchesController.addListener(_onHeightFtInInputChanged);
  }

  // --- Disposal ---
  @override
  void dispose() {
    _refreshIconController.dispose();
    // Dispose all text controllers
    _userDetailsNameController.dispose();
    _userDetailsEmailController.dispose();
    _userDetailsPhoneController.dispose();
    _userDetailsLocationController.dispose();
    // Dispose metric controllers
    _weightController.dispose();
    _heightCmController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    // Dispose location hint timer if active
    _locationHintTimer?.cancel();
    super.dispose();
  }

  // --- Refresh Animation Control ---
  void _startRefreshAnimation() {
    if (!_refreshIconController.isAnimating) {
      _refreshIconController.repeat();
    }
  }

  void _stopRefreshAnimation() {
    if (_refreshIconController.isAnimating) {
      _refreshIconController.stop();
      _refreshIconController.reset();
    }
  }

  // --- Profile Initialization and Data Fetching ---
  Future<void> _initializeProfile() async {
    setState(() => _isLoading = true);
    await _loadUserIdAndType();
    await _loadImageFromPrefs(); // Load local image path first

    if (_userId != null) {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = await UserCache.getData('user_details_cache');
      final cachedTimestampMillis =
          prefs.getInt('user_details_cache_timestamp');
      final now = DateTime.now();

      bool isUserDetailsCacheComplete(Map<String, dynamic>? data) {
        if (data == null) return false;
        final requiredKeys = ['name', 'email', 'user_id'];
        for (final key in requiredKeys) {
          if (data[key] == null || data[key].toString().trim().isEmpty) {
            return false;
          }
        }
        return true;
      }

      bool isCacheValid = cachedData != null &&
          cachedTimestampMillis != null &&
          now.difference(
                  DateTime.fromMillisecondsSinceEpoch(cachedTimestampMillis)) <
              CacheConfig.profileCacheDuration;

      if (isCacheValid && isUserDetailsCacheComplete(cachedData)) {
        print("[Profile] Using cached user details.");
        _updateStateWithUserDetails(cachedData!);
        setState(() {
          _isLoading = false;
          _isLoadingUserDetails = false;
        });
        // Fetch metrics and preferences in the background if details are from cache
        _fetchMetrics();
        _fetchPreferences();
      } else {
        print(
            "[Profile] Cache incomplete or invalid. Fetching fresh user details.");
        await _fetchData(); // Fetches all details, metrics, prefs
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _fetchError = 'User not logged in.';
        });
        _showErrorSnackBar('User not logged in.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const SignUpOrLoginPage()),
              (Route<dynamic> route) => false,
            );
          }
        });
      }
    }
  }

  Future<void> _loadUserIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
    final userIdStr = prefs.getString('user_id');
    _userId =
        userIdStr != null ? int.tryParse(userIdStr) : prefs.getInt('user_id');
    _userType = prefs.getString('user_type');
    print("Loaded User ID: $_userId, User Type: $_userType");
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _userDetails.isEmpty;
      _fetchError = '';
      _isLoadingUserDetails = true;
      _isLoadingMetrics = true;
      _isLoadingPreferences = true;
    });
    _startRefreshAnimation();

    try {
      await Future.wait([
        _fetchUserDetails(),
        _fetchMetrics(forceRefresh: true),
        _fetchPreferences(forceRefresh: true),
      ]);
    } catch (e) {
      if (mounted) {
        print("Error during concurrent data fetch: $e");
        setState(() {
          _fetchError = "Failed to load profile data. Please try again.";
          _isLoadingUserDetails = false;
          _isLoadingMetrics = false;
          _isLoadingPreferences = false;
        });
        _showErrorSnackBar(_fetchError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _stopRefreshAnimation();
      }
    }
  }

  // --- Specific Data Fetchers ---

  Future<void> _fetchUserDetails() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingUserDetails = false);
      return;
    }
    final url = '$apiBaseUrl/rr/rusers/$_userId';
    print('[Profile] API fetch: Fetching user details... from URL: $url');
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("User Details Response: ${response.statusCode} - ${response.body}");
      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        Map<String, dynamic>? userMap = _parseUserResponse(responseData);
        if (userMap != null) {
          final cacheUserMap = {
            'name': userMap['name'] ?? '',
            'email': userMap['email'] ?? '',
            'user_id': userMap['user_id']?.toString() ?? '',
            ...userMap
          };
          _updateStateWithUserDetails(userMap);
          await UserCache.saveData('user_details_cache', cacheUserMap);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_details_cache_timestamp',
              DateTime.now().millisecondsSinceEpoch);
        } else {
          print(
              'Failed to parse user details from API response: $responseData');
          _userDetails = {}; // Clear or set to default on parse failure
        }
      } else {
        print('Failed to fetch user details. Status: ${response.statusCode}');
        _userDetails = {}; // Clear or set to default on API error
        if (response.statusCode == 401 || response.statusCode == 403) {
          _fetchError = "Unauthorized. Please log in again.";
          _logout(); // Or redirect to login
        }
      }
    } on TimeoutException {
      print("Timeout fetching user details.");
      if (mounted) _userDetails = {};
    } catch (error) {
      print("Error fetching user details: $error");
      if (mounted) _userDetails = {};
    } finally {
      if (mounted) setState(() => _isLoadingUserDetails = false);
    }
  }

  Map<String, dynamic>? _parseUserResponse(dynamic responseData) {
    return ProfilePage._parseUserResponseStatic(responseData);
  }

  void _updateStateWithUserDetails(Map<String, dynamic> userData) {
    if (!mounted) return;
    setState(() {
      _userDetails = {
        'User_Id': userData['user_id']?.toString() ?? 'N/A',
        'Name': userData['name'] ?? 'N/A',
        'Email': userData['email'] ?? 'N/A',
        'Phone_Number': userData['phone_number'] ?? 'N/A',
        'Location': userData['location'] ?? 'N/A',
        'Registration_Date': userData['registration_date'] ?? 'N/A',
        'image': userData['image'],
      };
      _profileImageUrl = _userDetails['image']; // This comes from API

      if (!_isEditingUserDetails) {
        _userDetailsNameController.text = _userDetails['Name'] ?? '';
        _userDetailsEmailController.text = _userDetails['Email'] ?? '';
        _userDetailsPhoneController.text = _userDetails['Phone_Number'] ?? '';
        _userDetailsLocationController.text = _userDetails['Location'] ?? '';
      }
    });
  }
  // *** END OF CORRECTED _updateStateWithUserDetails ***

  // *** START OF RECONSTRUCTED/MISSING METHODS ***
  Future<void> _fetchMetrics({bool forceRefresh = false}) async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingMetrics = false);
      return;
    }
    if (mounted) setState(() => _isLoadingMetrics = true);

    final prefs = await SharedPreferences.getInstance();
    final cachedMetrics = await UserCache.getData('user_metrics_cache');
    final cachedTimestamp = prefs.getInt('user_metrics_cache_timestamp');
    final now = DateTime.now();

    if (!forceRefresh &&
        cachedMetrics != null &&
        cachedTimestamp != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(cachedTimestamp)) <
            CacheConfig.metricsCacheDuration) {
      print("Using cached metrics data");
      print(
          "Metrics Data Structure (from cache): ${json.encode(cachedMetrics)}");
      _updateStateWithMetrics(cachedMetrics);
      if (mounted) setState(() => _isLoadingMetrics = false);
      return;
    }

    print('[Profile] API fetch: Fetching user metrics...');
    final url = '$apiBaseUrl/rr/metrics/$_userId';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print(
            "Metrics Data Structure (from API): ${json.encode(responseData)}");

        // Extract metrics from response - handle the nested 'metrics' array structure
        Map<String, dynamic> metricsMap = {};
        if (responseData.containsKey('metrics') &&
            responseData['metrics'] is List &&
            responseData['metrics'].isNotEmpty) {
          // Get the first metrics entry from the array
          metricsMap = Map<String, dynamic>.from(responseData['metrics'][0]);
          print("Extracted metrics: ${json.encode(metricsMap)}");
          _updateStateWithMetrics(metricsMap);
          await UserCache.saveData('user_metrics_cache', metricsMap);
          await prefs.setInt(
              'user_metrics_cache_timestamp', now.millisecondsSinceEpoch);
        } else if (responseData.containsKey('data')) {
          metricsMap = Map<String, dynamic>.from(responseData['data']);
          _updateStateWithMetrics(metricsMap);
          await UserCache.saveData('user_metrics_cache', metricsMap);
          await prefs.setInt(
              'user_metrics_cache_timestamp', now.millisecondsSinceEpoch);
        } else {
          print(
              "Metrics Data Structure (from API): ${json.encode(responseData)}");
          _updateStateWithMetrics(responseData);
        }
      } else {
        print('Failed to fetch metrics. Status: ${response.statusCode}');
        _userMetrics = {}; // Default or clear
      }
    } on TimeoutException {
      print("Timeout fetching metrics.");
      if (mounted) _userMetrics = {};
    } catch (error) {
      print("Error fetching metrics: $error");
      if (mounted) _userMetrics = {};
    } finally {
      if (mounted) setState(() => _isLoadingMetrics = false);
    }
  }

  void _updateStateWithMetrics(Map<String, dynamic> metricsData) {
    if (!mounted) return;
    setState(() {
      _userMetrics = {
        'age_range': metricsData['age_range'] ?? 'N/A',
        'sex': metricsData['sex'] ?? 'N/A',
        'weight': metricsData['weight']?.toString() ?? 'N/A',
        'height': metricsData['height']?.toString() ?? 'N/A',
        'activity_level': metricsData['activity_level'] ?? 'N/A',
        'bmi': metricsData['bmi']?.toString() ?? 'N/A',
        'bmi_category': metricsData['bmi_category'] ?? 'N/A',
        'ideal_weight': metricsData['ideal_weight']?.toString() ?? 'N/A',
        'bmr': metricsData['bmr']?.toString() ?? 'N/A',
        'daily_calories': metricsData['daily_calories']?.toString() ?? 'N/A',
        'cholesterol_level': metricsData['cholesterol_level'] ?? 'N/A',
        'sys_bp': metricsData['sys_bp']?.toString() ?? 'N/A',
        'dia_bp': metricsData['dia_bp']?.toString() ?? 'N/A',
        'pulse': metricsData['pulse']?.toString() ?? 'N/A',
        'recorded_at': metricsData['recorded_at'] ?? 'N/A',
      };

      if (!_isEditingMetrics) {
        _selectedAgeRange = _userMetrics['age_range'] != 'N/A'
            ? _userMetrics['age_range']
            : null;
        if (_selectedAgeRange != null &&
            !_ageRanges.contains(_selectedAgeRange)) _selectedAgeRange = null;

        _selectedSex =
            _userMetrics['sex'] != 'N/A' ? _userMetrics['sex'] : null;
        if (_selectedSex != null && !_sexs.contains(_selectedSex))
          _selectedSex = null;

        _selectedActivityLevel = _userMetrics['activity_level'] != 'N/A'
            ? _userMetrics['activity_level']
            : null;
        if (_selectedActivityLevel != null &&
            !_activityLevels.contains(_selectedActivityLevel))
          _selectedActivityLevel = null;

        _weightKg = _tryParseDouble(_userMetrics['weight']) ?? 0;
        _heightCm = _tryParseDouble(_userMetrics['height']) ?? 0;
        _updateWeightControllerBasedOnUnit();
        _updateHeightControllerBasedOnUnit();
      }
    });
  }

  Future<void> _fetchPreferences({bool forceRefresh = false}) async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingPreferences = false);
      return;
    }
    if (mounted) setState(() => _isLoadingPreferences = true);

    final prefs = await SharedPreferences.getInstance();
    final cachedPrefs = await UserCache.getData('user_preferences_cache');
    final cachedTimestamp = prefs.getInt('user_preferences_cache_timestamp');
    final now = DateTime.now();

    if (!forceRefresh &&
        cachedPrefs != null &&
        cachedTimestamp != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(cachedTimestamp)) <
            CacheConfig.preferencesCacheDuration) {
      print("[Profile] Using cached user preferences.");
      print(
          "Preferences Data Structure (from cache): ${json.encode(cachedPrefs)}");
      _updateStateWithPreferences(cachedPrefs);
      if (mounted) setState(() => _isLoadingPreferences = false);
      return;
    }

    print('[Profile] API fetch: Fetching user preferences...');
    final url = '$apiBaseUrl/rr/preferences/$_userId';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print(
            "Preferences Data Structure (from API): ${json.encode(responseData)}");

        // Extract preferences from response - handle the nested 'preferences' array structure
        Map<String, dynamic> prefsMap = {};
        if (responseData.containsKey('preferences') &&
            responseData['preferences'] is List &&
            responseData['preferences'].isNotEmpty) {
          // Get the first preferences entry from the array
          prefsMap = Map<String, dynamic>.from(responseData['preferences'][0]);
          print("Extracted preferences: ${json.encode(prefsMap)}");
          _updateStateWithPreferences(prefsMap);
          await UserCache.saveData('user_preferences_cache', prefsMap);
          await prefs.setInt(
              'user_preferences_cache_timestamp', now.millisecondsSinceEpoch);
        } else if (responseData.containsKey('data')) {
          prefsMap = Map<String, dynamic>.from(responseData['data']);
          _updateStateWithPreferences(prefsMap);
          await UserCache.saveData('user_preferences_cache', prefsMap);
          await prefs.setInt(
              'user_preferences_cache_timestamp', now.millisecondsSinceEpoch);
        } else {
          print(
              "Preferences Data Structure (from API): ${json.encode(responseData)}");
          _updateStateWithPreferences(responseData);
        }
      } else {
        print('Failed to fetch preferences. Status: ${response.statusCode}');
        _userPreferences = {};
      }
    } on TimeoutException {
      print("Timeout fetching preferences.");
      if (mounted) _userPreferences = {};
    } catch (error) {
      print("Error fetching preferences: $error");
      if (mounted) _userPreferences = {};
    } finally {
      if (mounted) setState(() => _isLoadingPreferences = false);
    }
  }

  void _updateStateWithPreferences(Map<String, dynamic> prefData) {
    if (!mounted) return;
    
    setState(() {
      _userPreferences = {
        'goals': prefData['goals'] ?? 'N/A',
        'diet_type': prefData['diet_type'] ?? 'N/A',
        'food_restrictions': _listToString(prefData['food_restrictions'], emptyValue: 'None'),
        'cuisine_preferences': _listToString(prefData['cuisine_preferences'], emptyValue: 'all'),
      };
      
      _isLoadingPreferences = false;
      
      // Load cuisine preferences
      final cuisinePrefs = getCaseInsensitive(prefData, 'cuisine_preferences');
      if (cuisinePrefs != null) {
        if (cuisinePrefs is List) {
          _selectedCuisines = List<String>.from(cuisinePrefs.whereType<String>());
        } else if (cuisinePrefs is String && cuisinePrefs.isNotEmpty) {
          // Handle case where cuisine_preferences is a comma-separated string
          _selectedCuisines = cuisinePrefs.split(',').map((e) => e.trim()).toList();
        } else {
          _selectedCuisines = [];
        }
      } else {
        _selectedCuisines = [];
      }

      if (!_isEditingPreferences) {
        _selectedGoal = _userPreferences['goals'] != 'N/A' ? _userPreferences['goals'] : null;
        if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal)) {
          _selectedGoal = null;
        }

        _selectedDietType = _userPreferences['diet_type'] != 'N/A' ? _userPreferences['diet_type'] : null;
        if (_selectedDietType != null && !_dietTypeOptions.contains(_selectedDietType)) {
          _selectedDietType = null;
        }

        String? currentRestrictionDisplay = _userPreferences['food_restrictions'];
        if (currentRestrictionDisplay == 'None') {
          _selectedFoodRestriction = 'None';
        } else if (currentRestrictionDisplay != null && currentRestrictionDisplay != 'N/A') {
          String firstItem = currentRestrictionDisplay.split(',').first.trim();
          _selectedFoodRestriction = _foodRestrictionsOptions.contains(firstItem) ? firstItem : null;
        } else {
          _selectedFoodRestriction = null;
        }
        
        if (_selectedFoodRestriction != null && !_foodRestrictionsOptions.contains(_selectedFoodRestriction)) {
          _selectedFoodRestriction = null;
        }
      }
    });
  }

  String _listToString(dynamic listOrString, {String emptyValue = 'N/A'}) {
    if (listOrString == null) return emptyValue;
    if (listOrString is List) {
      if (listOrString.isEmpty) return emptyValue;
      return listOrString.join(', ');
    }
    if (listOrString is String) {
      return listOrString.isEmpty ? emptyValue : listOrString;
    }
    return listOrString.toString();
  }

  String? _getFirstItemFromListOrString(dynamic data) {
    if (data == null) return null;
    if (data is List && data.isNotEmpty) {
      return data.first.toString();
    }
    if (data is String && data.isNotEmpty) {
      return data.split(',').first.trim();
    }
    return null;
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final File imageFile = File(image.path);
        await _uploadImage(imageFile);
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackBar('Error picking image: $e');
    }
  }

  Future<void> _uploadImage(File imageFile) async {
    if (_userId == null) {
      _showErrorSnackBar('User ID not found. Cannot upload image.');
      return;
    }
    _showSuccessSnackBar('processing image...'); // Temporary feedback

    try {
      // Upload to Imgur first
      Future<String?> uploadImageToImgur(File imageFile) async {
        try {
          final uploadUrl = Uri.parse('https://api.imgur.com/3/image');
          final request = http.MultipartRequest('POST', uploadUrl);
          request.headers['Authorization'] = '$imgurClientID';
          request.files
              .add(await http.MultipartFile.fromPath('image', imageFile.path));

          final response = await request.send();
          final responseData = await response.stream.bytesToString();
          final jsonResult = jsonDecode(responseData);
          return jsonResult['data']['link']?.toString();
        } catch (e) {
          print('Imgur upload error: \\$e');
          return null;
        }
      }

      final imgurUrl = await uploadImageToImgur(imageFile);

      if (!mounted) return;

      if (imgurUrl != null) {
        // Now send the Imgur URL to the user details endpoint
        final url = '$apiBaseUrl/rr/users/$_userId';
        final response = await http
            .patch(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
              },
              body: json.encode({
                'image': imgurUrl,
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          setState(() {
            _profileImageUrl = imgurUrl;
            _profileImagePath = null; // Clear local path if server URL is used
          });
          // Update userDetails map and cache
          _userDetails['image'] = imgurUrl;
          await UserCache.saveData('user_details_cache', _userDetails);
          await _saveImageToPrefs(''); // Clear local path pref
          _showSuccessSnackBar('Profile image updated successfully!');
        } else {
          _showErrorSnackBar('Failed to update profile with Imgur URL');
        }
      } else {
        _showErrorSnackBar('Failed to upload image to Imgur');
      }
    } on TimeoutException {
      if (mounted) _showErrorSnackBar('Image upload timed out.');
    } catch (e) {
      print("Error uploading image: $e");
      if (mounted) _showErrorSnackBar('Error uploading image: $e');
    }
  }

  Future<void> _saveImageToPrefs(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_path', path);
  }

  Future<void> _loadImageFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('image_path');
    if (path != null && path.isNotEmpty) {
      if (mounted) {
        setState(() {
          _profileImagePath = path;
        });
      }
    }
  }
  // *** END OF RECONSTRUCTED/MISSING METHODS ***

  Future<void> _saveEditedData() async {
    String endpointPath = '';
    Map<String, dynamic> dataToUpdate = {};
    String successMessage = '';
    String cacheKeyToInvalidate = '';
    String sectionBeingSaved = '';

    if (_isEditingUserDetails) {
      sectionBeingSaved = 'details';
      endpointPath = '/rr/users/$_userId';
      cacheKeyToInvalidate = 'user_details_cache';
      successMessage = 'User details updated successfully!';
      dataToUpdate = {
        'name': _userDetailsNameController.text,
        'email': _userDetailsEmailController.text,
        'phone_number': _userDetailsPhoneController.text,
        'location': _userDetailsLocationController.text,
      };
      dataToUpdate.removeWhere((key, value) => value == null || value.isEmpty);

      // Update local state immediately for responsiveness, will be overwritten by fetch on success/fail
      setState(() {
        _userDetails['Name'] = _userDetailsNameController.text;
        _userDetails['Email'] = _userDetailsEmailController.text;
        _userDetails['Phone_Number'] = _userDetailsPhoneController.text;
        _userDetails['Location'] = _userDetailsLocationController.text;
        _isEditingUserDetails = false;
      });
    } else if (_isEditingMetrics) {
      sectionBeingSaved = 'metrics';
      endpointPath = '/rr/metrics/$_userId';
      cacheKeyToInvalidate = 'user_metrics_cache';
      successMessage = 'Health metrics updated successfully!';
      _parseAndUpdateWeight();
      _parseAndUpdateHeight();

      // Compute dependent values
      String bmi = _calculateBmi(_heightCm, _weightKg);
      String idealWeight = (_heightCm > 0 && _selectedSex != null)
          ? (_selectedSex == 'Male'
              ? (50 + 0.91 * (_heightCm - 152.4)).toStringAsFixed(2)
              : (45.5 + 0.91 * (_heightCm - 152.4)).toStringAsFixed(2))
          : 'N/A';
      String bmiCategory = 'N/A';
      double? bmiValue = double.tryParse(bmi);
      if (bmiValue != null) {
        if (bmiValue < 18.5) {
          bmiCategory = 'Underweight';
        } else if (bmiValue < 25) {
          bmiCategory = 'Normal';
        } else if (bmiValue < 30) {
          bmiCategory = 'Overweight';
        } else {
          bmiCategory = 'Obese';
        }
      }
      double? bmr;
      if (_weightKg > 0 &&
          _heightCm > 0 &&
          _selectedAgeRange != null &&
          _selectedSex != null) {
        int age = 30; // Default age if parsing fails
        final ageMatch = RegExp(r'\d+').firstMatch(_selectedAgeRange!);
        if (ageMatch != null) {
          age = int.tryParse(ageMatch.group(0)!) ?? 30;
        }
        if (_selectedSex == 'Male') {
          bmr = 10 * _weightKg + 6.25 * _heightCm - 5 * age + 5;
        } else {
          bmr = 10 * _weightKg + 6.25 * _heightCm - 5 * age - 161;
        }
      }
      double? dailyCalories;
      if (bmr != null && _selectedActivityLevel != null) {
        final activityMultipliers = {
          'Sedentary': 1.2,
          'Lightly Active': 1.375,
          'Moderately Active': 1.55,
          'Very Active': 1.725,
          'Extra Active': 1.9 // Added just in case
        };
        dailyCalories =
            bmr * (activityMultipliers[_selectedActivityLevel!] ?? 1.2);
      }

      // Create a flat metrics object with only the allowed fields as per backend requirements
      // Convert all numeric values to strings to match backend expectations
      dataToUpdate = {
        'age_range': _selectedAgeRange,
        'sex': _selectedSex,
        'weight': _weightKg > 0 ? _weightKg.toString() : null,
        'height': _heightCm > 0 ? _heightCm.toString() : null,
        'activity_level': _selectedActivityLevel,
        // Note: Backend will calculate these dependent values automatically
        // We don't need to send them as they'll be computed server-side
      };

      // Remove null values
      dataToUpdate.removeWhere((key, value) => value == null);

      print("Sending metrics update: ${json.encode(dataToUpdate)}");

      setState(() {
        _userMetrics['age_range'] = _selectedAgeRange ?? 'N/A';
        _userMetrics['sex'] = _selectedSex ?? 'N/A';
        _userMetrics['weight'] =
            _weightKg > 0 ? _weightKg.toStringAsFixed(1) : 'N/A';
        _userMetrics['height'] =
            _heightCm > 0 ? _heightCm.toStringAsFixed(1) : 'N/A';
        _userMetrics['activity_level'] = _selectedActivityLevel ?? 'N/A';
        _userMetrics['bmi'] = bmi;
        _userMetrics['ideal_weight'] = idealWeight;
        _userMetrics['bmi_category'] = bmiCategory;
        _userMetrics['bmr'] = bmr?.toStringAsFixed(1) ?? 'N/A';
        _userMetrics['daily_calories'] =
            dailyCalories?.toStringAsFixed(1) ?? 'N/A';
        _isEditingMetrics = false;
      });
    } else if (_isEditingPreferences) {
      sectionBeingSaved = 'preferences';
      endpointPath = '/rr/users/$_userId/preferences';
      cacheKeyToInvalidate = 'user_preferences_cache';
      successMessage = 'Preferences updated successfully!';

      List<String> restrictionsToSend = [];
      if (_selectedFoodRestriction != null &&
          _selectedFoodRestriction != 'None') {
        restrictionsToSend.add(_selectedFoodRestriction!);
      }

      // Always include cuisine_preferences, even if empty, to clear existing preferences when needed
      dataToUpdate = {
        'goals': _selectedGoal,
        'diet_type': _selectedDietType,
        'food_restrictions': restrictionsToSend.isNotEmpty ? restrictionsToSend : [],
        'cuisine_preferences': _selectedCuisines, // Send empty list if no cuisines selected
      };

      setState(() {
        _userPreferences['goals'] = _selectedGoal ?? 'N/A';
        _userPreferences['diet_type'] = _selectedDietType ?? 'N/A';
        _userPreferences['food_restrictions'] =
            _listToString(restrictionsToSend, emptyValue: 'None');
        _isEditingPreferences = false;
      });
    } else {
      print("Save requested but no section is being edited.");
      return;
    }

    if (endpointPath.isNotEmpty && dataToUpdate.isNotEmpty) {
      final url = '$apiBaseUrl$endpointPath';
      print(
          "Attempting to PATCH data to $url with body: ${json.encode(dataToUpdate)}");
      try {
        final response = await http
            .patch(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(dataToUpdate),
            )
            .timeout(const Duration(seconds: 15));

        if (!mounted) return;

        if (response.statusCode == 200 ||
            response.statusCode == 204 ||
            response.statusCode == 201) {
          _showSuccessSnackBar(successMessage);
          if (cacheKeyToInvalidate.isNotEmpty) {
            await UserCache.removeData(cacheKeyToInvalidate);
            // Also remove timestamp to force fresh fetch
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('${cacheKeyToInvalidate}_timestamp');
          }
          // Refetch the specific section that was updated
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        } else {
          print(
              "Failed to update profile section. Status: ${response.statusCode}, Body: ${response.body}");
          _showErrorSnackBar(
              'Failed to update. Server error: ${response.statusCode}');
          // Revert optimistic UI update by refetching
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        }
      } on TimeoutException {
        if (mounted) {
          _showErrorSnackBar('Failed to save: Connection timed out.');
          // Revert optimistic UI update by refetching
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        }
      } catch (e) {
        print("Error saving profile data: $e");
        if (mounted) {
          _showErrorSnackBar('An error occurred while saving: $e');
          // Revert optimistic UI update by refetching
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        }
      }
    } else {
      if (endpointPath.isEmpty) {
        print("No valid endpoint path determined for saving.");
      }
      if (dataToUpdate.isEmpty) {
        print("No changes detected to save. Exiting edit mode.");
        // Exit edit mode even if no data to PATCH, as user might have just hit save without changes
        setState(() {
          _isEditingUserDetails = false;
          _isEditingMetrics = false;
          _isEditingPreferences = false;
        });
      }
    }
  }

  void _cancelEdit() {
    setState(() {
      _isEditingUserDetails = false;
      _isEditingMetrics = false;
      _isEditingPreferences = false;

      // Reload controllers from the original data maps
      if (_userDetails.isNotEmpty) {
        _userDetailsNameController.text =
            getCaseInsensitive(_userDetails, 'Name') ?? '';
        _userDetailsEmailController.text =
            getCaseInsensitive(_userDetails, 'Email') ?? '';
        _userDetailsPhoneController.text =
            getCaseInsensitive(_userDetails, 'Phone_Number') ?? '';
        _userDetailsLocationController.text =
            getCaseInsensitive(_userDetails, 'Location') ?? '';
      }

      if (_userMetrics.isNotEmpty) {
        double? currentWeightKg =
            _tryParseDouble(getCaseInsensitive(_userMetrics, 'weight'));
        double? currentHeightCm =
            _tryParseDouble(getCaseInsensitive(_userMetrics, 'height'));

        _selectedAgeRange =
            getCaseInsensitive(_userMetrics, 'age_range') != 'N/A'
                ? getCaseInsensitive(_userMetrics, 'age_range')
                : null;
        if (_selectedAgeRange != null &&
            !_ageRanges.contains(_selectedAgeRange)) _selectedAgeRange = null;
        _selectedSex = getCaseInsensitive(_userMetrics, 'sex') != 'N/A'
            ? getCaseInsensitive(_userMetrics, 'sex')
            : null;
        if (_selectedSex != null && !_sexs.contains(_selectedSex))
          _selectedSex = null;
        _selectedActivityLevel =
            getCaseInsensitive(_userMetrics, 'activity_level') != 'N/A'
                ? getCaseInsensitive(_userMetrics, 'activity_level')
                : null;
        if (_selectedActivityLevel != null &&
            !_activityLevels.contains(_selectedActivityLevel))
          _selectedActivityLevel = null;

        _weightKg = currentWeightKg ?? 0;
        _updateWeightControllerBasedOnUnit();
        _heightCm = currentHeightCm ?? 0;
        _updateHeightControllerBasedOnUnit();
      } else {
        // Default if _userMetrics is empty
        _selectedAgeRange = null;
        _selectedSex = null;
        _selectedActivityLevel = null;
        _weightKg = 0;
        _updateWeightControllerBasedOnUnit();
        _heightCm = 0;
        _updateHeightControllerBasedOnUnit();
      }

      if (_userPreferences.isNotEmpty) {
        _selectedGoal = getCaseInsensitive(_userPreferences, 'goals') != 'N/A'
            ? getCaseInsensitive(_userPreferences, 'goals')
            : null;
        if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal))
          _selectedGoal = null;
        _selectedDietType =
            getCaseInsensitive(_userPreferences, 'diet_type') != 'N/A'
                ? getCaseInsensitive(_userPreferences, 'diet_type')
                : null;
        if (_selectedDietType != null &&
            !_dietTypeOptions.contains(_selectedDietType))
          _selectedDietType = null;

        String? firstRestriction = _getFirstItemFromListOrString(
            getCaseInsensitive(_userPreferences, 'food_restrictions'));
        _selectedFoodRestriction = (firstRestriction != null &&
                _foodRestrictionsOptions.contains(firstRestriction))
            ? firstRestriction
            : (getCaseInsensitive(_userPreferences, 'food_restrictions') ==
                    'None'
                ? 'None'
                : null);

        if (_selectedFoodRestriction != null &&
            !_foodRestrictionsOptions.contains(_selectedFoodRestriction)) {
          _selectedFoodRestriction = null;
        }
      } else {
        // Default if _userPreferences is empty
        _selectedGoal = null;
        _selectedDietType = null;
        _selectedFoodRestriction = null;
      }
    });
  }

  // --- Weight/Height Unit Conversion and Update Logic ---
  void _onWeightInputChanged() {
    _parseAndUpdateWeight();
    if (_isEditingMetrics && mounted) {
      setState(() {}); // To re-calculate BMI etc. live if needed
    }
  }

  void _parseAndUpdateWeight() {
    final String text = _weightController.text.trim();
    final double? value = double.tryParse(text);
    if (value != null && value >= 0) {
      if (_weightUnit == 'kg') {
        _weightKg = value;
      } else {
        // lbs
        _weightKg = value * 0.453592; // lbs to kg
      }
    } else {
      _weightKg = 0;
    }
  }

  void _onHeightCmInputChanged() {
    _parseAndUpdateHeight();
    if (_isEditingMetrics && mounted) {
      setState(() {});
    }
  }

  void _onHeightFtInInputChanged() {
    _parseAndUpdateHeight();
    if (_isEditingMetrics && mounted) {
      setState(() {});
    }
  }

  void _parseAndUpdateHeight() {
    if (_heightUnit == 'cm') {
      final String text = _heightCmController.text.trim();
      final double? value = double.tryParse(text);
      if (value != null && value >= 0) {
        _heightCm = value;
      } else {
        _heightCm = 0;
      }
    } else {
      // ft/in
      final String feetText = _heightFeetController.text.trim();
      final String inchesText = _heightInchesController.text.trim();
      final double feet =
          double.tryParse(feetText.isEmpty ? '0' : feetText) ?? 0;
      final double inches =
          double.tryParse(inchesText.isEmpty ? '0' : inchesText) ?? 0;

      if (feet >= 0 && inches >= 0) {
        _heightCm = (feet * 30.48) + (inches * 2.54); // ft to cm and in to cm
      } else {
        _heightCm = 0;
      }
    }
  }

  void _updateWeightControllerBasedOnUnit() {
    if (!mounted) return;
    if (_weightUnit == 'kg') {
      _weightController.text =
          _weightKg > 0 ? _weightKg.toStringAsFixed(1) : '';
    } else {
      // lbs
      double lbs = _weightKg / 0.453592; // kg to lbs
      _weightController.text = lbs > 0 ? lbs.toStringAsFixed(1) : '';
    }
  }

  void _updateHeightControllerBasedOnUnit() {
    if (!mounted) return;
    if (_heightUnit == 'cm') {
      _heightCmController.text =
          _heightCm > 0 ? _heightCm.toStringAsFixed(1) : '';
      // Clear ft/in fields if they were used
      if (_heightFeetController.text.isNotEmpty) _heightFeetController.clear();
      if (_heightInchesController.text.isNotEmpty)
        _heightInchesController.clear();
    } else {
      // ft/in
      if (_heightCm > 0) {
        double totalInches = _heightCm / 2.54; // cm to total inches
        double feet = (totalInches ~/ 12).toDouble(); // Integer part for feet
        double inches = (totalInches % 12); // Remainder for inches
        _heightFeetController.text = feet > 0 ? feet.toStringAsFixed(0) : '';
        _heightInchesController.text =
            inches > 0 ? inches.toStringAsFixed(1) : '';
      } else {
        if (_heightFeetController.text.isNotEmpty)
          _heightFeetController.clear();
        if (_heightInchesController.text.isNotEmpty)
          _heightInchesController.clear();
      }
      // Clear cm field if it was used
      if (_heightCmController.text.isNotEmpty) _heightCmController.clear();
    }
  }

  void _updateWeightUnit(int index) {
    if (_weightSelection[index]) return; // No change if already selected
    _parseAndUpdateWeight(); // Ensure _weightKg is up-to-date before switching
    setState(() {
      _weightSelection = [false, false];
      _weightSelection[index] = true;
      _weightUnit = (index == 0) ? 'kg' : 'lbs';
      _updateWeightControllerBasedOnUnit(); // Update text field with new unit
    });
  }

  void _updateHeightUnit(int index) {
    if (_heightSelection[index]) return; // No change
    _parseAndUpdateHeight(); // Ensure _heightCm is up-to-date
    setState(() {
      _heightSelection = [false, false];
      _heightSelection[index] = true;
      _heightUnit = (index == 0) ? 'cm' : 'ft'; // 'ft' implies ft/in mode
      _updateHeightControllerBasedOnUnit();
    });
  }

  // --- BMI Calculation ---
  String _calculateBmi(double? heightCm, double? weightKg) {
    if (heightCm != null && heightCm > 0 && weightKg != null && weightKg > 0) {
      double heightM = heightCm / 100.0;
      double bmi = weightKg / (heightM * heightM);
      if (bmi.isNaN || bmi.isInfinite) return 'N/A';
      return bmi.toStringAsFixed(1);
    }
    return 'N/A';
  }

  // --- UI Helpers ---
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Logout ---
  Future<void> _logout() async {
    await FCMService.deactivateTokenWithBackend();
    final prefs = await SharedPreferences.getInstance();
    await UserCache.clearAllData(); // Clears all UserCache entries

    // More targeted removal from SharedPreferences
    final keysToRemove = <String>{
      'user_id', 'user_type', 'auth_token', // Common auth keys
      'image_path', // Specific to this page's local image caching
      'user_details_cache_timestamp',
      'user_metrics_cache_timestamp',
      'user_preferences_cache_timestamp'
    };
    // Remove general user session keys by pattern if any exist
    final allKeys = prefs.getKeys();
    final patterns = [
      RegExp(r'_id\b', caseSensitive: false),
      RegExp(r'_user_type\b', caseSensitive: false),
      RegExp(r'token\b', caseSensitive: false)
    ];
    for (final key in allKeys) {
      if (patterns.any((p) => p.hasMatch(key))) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
    print("Logged out, removed keys: $keysToRemove");

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SignUpOrLoginPage()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // --- Input Field Builders ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Function(String)? onChanged,
    int? maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15),
      decoration: _buildInputDecoration(label, prefixIcon: icon),
    );
  }

  InputDecoration _buildInputDecoration(String label,
      {IconData? prefixIcon, String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: GoogleFonts.poppins(color: kColorPrimary),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: kColorPrimary, size: 20)
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kColorBorder, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kColorBorder, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kColorPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kErrorColor, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: kErrorColor, width: 1.5),
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required IconData icon,
    required T? currentValue,
    required List<T> options,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    final T? validValue =
        (currentValue != null && options.contains(currentValue))
            ? currentValue
            : null;

    return DropdownButtonFormField<T>(
      decoration: _buildInputDecoration(label, prefixIcon: icon),
      value: validValue,
      hint: Text(hint ?? 'Select $label',
          style:
              GoogleFonts.poppins(color: kColorTextSecondary.withOpacity(0.7))),
      isExpanded: true,
      items: options.map((T value) {
        return DropdownMenuItem<T>(
          value: value,
          child: Text(value.toString(),
              style:
                  GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15)),
        );
      }).toList(),
      onChanged: onChanged,
      style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15),
      iconEnabledColor: kColorPrimary,
      dropdownColor: kColorSurface,
    );
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    bool isEditingAnySection =
        _isEditingUserDetails || _isEditingMetrics || _isEditingPreferences;

    // Show main shimmer if _isLoading is true AND (userDetails is empty AND no fetchError has occurred yet)
    // This prevents shimmer from showing if there's an error message to display or if some data is already loaded.
    bool showOverallShimmer =
        _isLoading && _userDetails.isEmpty && _fetchError.isEmpty;

    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: Text('Profile', style: GoogleFonts.poppins()),
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0,
        centerTitle: true,
        actions: [
          if (isEditingAnySection) ...[
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancel Changes',
              onPressed: _cancelEdit,
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: 'Save Changes',
              onPressed: _saveEditedData,
            ),
          ] else ...[
            AnimatedBuilder(
              animation: _refreshIconController,
              builder: (context, child) {
                bool isFetchingAnyData = _isLoadingUserDetails ||
                    _isLoadingMetrics ||
                    _isLoadingPreferences ||
                    _refreshIconController.isAnimating;
                return IconButton(
                  icon: RotationTransition(
                    turns: _refreshIconController,
                    child: const Icon(Icons.refresh),
                  ),
                  tooltip: isFetchingAnyData ? 'Refreshing...' : 'Refresh',
                  onPressed: isFetchingAnyData ? null : _fetchData,
                );
              },
            ),
          ],
        ],
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        color: kColorPrimary,
        child: showOverallShimmer
            ? _buildLoadingShimmer()
            : _fetchError.isNotEmpty &&
                    _userDetails
                        .isEmpty // Show error only if absolutely no user details loaded
                ? _buildErrorState(_fetchError)
                : ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      // Profile header should show even if details are partially loaded or only metrics/prefs error out
                      _buildProfileHeader(),
                      const SizedBox(height: 24.0),

                      // Individual section shimmers or content
                      _isLoadingUserDetails &&
                              _userDetails
                                  .isEmpty // Shimmer for user details only if truly loading and empty
                          ? _buildShimmerCard(
                              itemCount: 5, title: "User Details")
                          : _buildUserDetailsCard(),
                      const SizedBox(height: 16.0),

                      _isLoadingMetrics &&
                              _userMetrics.isEmpty // Shimmer for metrics
                          ? _buildShimmerCard(
                              itemCount: 8,
                              title:
                                  "Health Metrics") // Adjusted item count for typical metrics display
                          : _buildMetricsCard(),
                      const SizedBox(height: 16.0),

                      _isLoadingPreferences &&
                              _userPreferences
                                  .isEmpty // Shimmer for preferences
                          ? _buildShimmerCard(
                              itemCount: 3, title: "Preferences")
                          : _buildPreferencesCard(),
                      const SizedBox(height: 24.0),

                      _buildLogoutButton(),
                    ],
                  ),
      ),
    );
  }

  // --- Loading Shimmer Widgets ---
  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: kShimmerBaseColor,
      highlightColor: kShimmerHighlightColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Shimmer for Profile Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CircleAvatar(radius: 60, backgroundColor: Colors.white),
              const SizedBox(height: 12),
              Container(
                  height: 20,
                  width: 150,
                  color: Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4)),
              Container(
                  height: 16,
                  width: 200,
                  color: Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4)),
            ],
          ),
          const SizedBox(height: 24.0),
          _buildShimmerCard(
              itemCount: 5, title: "User Details"), // User Details Shimmer
          const SizedBox(height: 16.0),
          _buildShimmerCard(
              itemCount: 8, title: "Health Metrics"), // Metrics Shimmer
          const SizedBox(height: 16.0),
          _buildShimmerCard(
              itemCount: 3, title: "Preferences"), // Preferences Shimmer
        ],
      ),
    );
  }

  Widget _buildShimmerCard({required int itemCount, String? title}) {
    return Card(
      elevation: 1.0,
      shadowColor: Colors.grey.shade200,
      margin: EdgeInsets.zero, // Handled by ListView padding
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: kColorSurface, // Will be overridden by Shimmer
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Container(
                  height: 20,
                  width: title.length * 8.0,
                  color: Colors.white), // Approx width
              const SizedBox(height: 12),
              const Divider(
                  color: kColorDivider,
                  height: 1), // Show divider in shimmer too
              const SizedBox(height: 12),
            ],
            ...List.generate(
              itemCount,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 22,
                        width: 22,
                        color: Colors.white), // Icon placeholder
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 14,
                              width: 80,
                              color: Colors.white), // Label placeholder
                          const SizedBox(height: 6),
                          Container(
                              height: 16,
                              width: 120 + (index % 3 * 20.0),
                              color: Colors
                                  .white), // Value placeholder (varying width)
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Error State Widget ---
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Profile',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kColorTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.poppins(fontSize: 15, color: kColorTextSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text("Retry", style: GoogleFonts.poppins()),
              onPressed: _fetchData,
              style: ElevatedButton.styleFrom(
                foregroundColor: kColorTextOnPrimary,
                backgroundColor: kColorPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- Profile Header Widget ---
  Widget _buildProfileHeader() {
    ImageProvider<Object> displayImage;
    // Prioritize API image URL, then local path, then default
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      displayImage = CachedNetworkImageProvider(_profileImageUrl!);
    } else if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        displayImage = FileImage(file);
      } else {
        displayImage = const AssetImage(
            'assets/images/proffr.png'); // Fallback if local file missing
      }
    } else {
      displayImage = const AssetImage('assets/images/proffr.png');
    }

    String displayName = getCaseInsensitive<String>(_userDetails, 'Name') ??
        (_isLoadingUserDetails && _userDetails.isEmpty
            ? 'Loading...'
            : 'User Name');
    String displayEmail = getCaseInsensitive<String>(_userDetails, 'Email') ??
        (_isLoadingUserDetails && _userDetails.isEmpty ? '' : 'No Email');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: kColorPrimaryLightest,
                backgroundImage: displayImage,
                onBackgroundImageError: (exception, stackTrace) {
                  print(
                      "Error loading profile image from provider: $exception");
                  // Optionally, set to a default image directly in state if error occurs
                },
                child: (_profileImageUrl == null ||
                            _profileImageUrl!.isEmpty) &&
                        (_profileImagePath == null ||
                            _profileImagePath!.isEmpty)
                    ? Icon(Icons.person,
                        size: 60, color: kColorPrimary.withOpacity(0.5))
                    : null, // Show person icon only if no image is set at all
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: kColorPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: Offset(1, 1))
                    ]),
                child: const Icon(Icons.edit,
                    size: 18, color: kColorTextOnPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: kColorTextPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        if (displayEmail.isNotEmpty && displayEmail != 'No Email')
          Text(
            displayEmail,
            style:
                GoogleFonts.poppins(fontSize: 15, color: kColorTextSecondary),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  // --- Card Builders ---
  Widget _buildStyledCard({
    required String title,
    required List<Widget> children,
    required bool isEditing,
    required VoidCallback onEdit,
  }) {
    bool isAnyOtherSectionEditing =
        (_isEditingUserDetails || _isEditingMetrics || _isEditingPreferences) &&
            !isEditing;

    return Card(
      elevation: 1.0,
      shadowColor: Colors.grey.shade200,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: kColorPrimaryDark),
                  ),
                ),
                if (!isEditing &&
                    !isAnyOtherSectionEditing) // Show edit button only if no other section is being edited
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 22, color: kColorPrimary),
                    tooltip: "Edit $title",
                    onPressed: onEdit,
                    splashRadius: 24,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                if (isEditing) // Show "Editing..." indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: kColorPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Editing...',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: kColorPrimary,
                            fontWeight: FontWeight.w500)),
                  )
              ],
            ),
            const Divider(color: kColorDivider, thickness: 1, height: 24),
            _buildGroupedInfoRows(children, isEditing),
          ],
        ),
      ),
    );
  }

  String _formatJoinedDate(String? dateString) {
    if (dateString == null || dateString == 'N/A' || dateString.isEmpty)
      return 'N/A';
    try {
      // Attempt to parse common ISO 8601 format first
      DateTime dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('MMM d, yyyy').format(dateTime);
    } catch (e) {
      // Fallback for other potential date formats if needed, or just return original
      print("Error parsing date '$dateString': $e. Returning as is.");
      return dateString; // Or handle more gracefully
    }
  }

  // --- Location Animation & Fetch Methods ---
  void _startLocationHintAnimation() {
    _locationHintTimer?.cancel();
    _locationHintDots = 0;
    _locationHintTimer =
        Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted || !_isFetchingLocation) {
        timer.cancel();
        if (mounted && !_isFetchingLocation)
          setState(() => _locationHintDots = 0);
        return;
      }
      if (mounted) {
        setState(() => _locationHintDots = (_locationHintDots + 1) % 4);
      }
    });
  }

  void _stopLocationHintAnimation() {
    _locationHintTimer?.cancel();
    if (mounted) setState(() => _locationHintDots = 0);
  }

  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true;
      _userDetailsLocationController.clear(); // Clear old text
    });
    _startLocationHintAnimation();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _stopLocationHintAnimation();
          setState(() {
            _isFetchingLocation = false;
            _userDetailsLocationController.text = ''; // Ensure it's clear
          });
          _showErrorSnackBar(
              'Location services are disabled. Please enable GPS.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied by user.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Location permissions permanently denied. Please enable in app settings.');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15), // Timeout for position fetching
      );

      String displayAddress =
          "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      String coordsForStorage =
          "${position.latitude},${position.longitude}"; // For storage

      // Attempt reverse geocoding (optional, can fail gracefully)
      try {
        // Using a free reverse geocoding service, replace if you have a preferred one or API key
        final String geocodeApiUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final geocodeResponse = await http
            .get(Uri.parse(geocodeApiUrl))
            .timeout(const Duration(seconds: 10));
        if (geocodeResponse.statusCode == 200) {
          final geocodeData = json.decode(geocodeResponse.body);
          if (geocodeData['display_name'] != null) {
            displayAddress = geocodeData['display_name'];
          }
        } else {
          print('Reverse geocoding failed: ${geocodeResponse.statusCode}');
        }
      } catch (e) {
        print('Error during reverse geocoding: $e');
        // Falls back to Lat/Lon display
      }

      if (mounted) {
        _stopLocationHintAnimation();
        setState(() {
          // Store the more detailed address for display, but consider what to save to backend (coords or full address)
          _userDetailsLocationController.text = displayAddress;
          // If you want to store just coordinates, you'd use coordsForStorage when saving.
          _isFetchingLocation = false;
        });
        _showSuccessSnackBar('Location acquired!');
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        _stopLocationHintAnimation();
        setState(() {
          _isFetchingLocation = false;
          _userDetailsLocationController.text = 'Failed: Location timeout';
        });
        _showErrorSnackBar('Getting location timed out.');
      }
    } catch (e) {
      if (mounted) {
        _stopLocationHintAnimation();
        setState(() {
          _isFetchingLocation = false;
          _userDetailsLocationController.text =
              'Failed: ${e.toString().replaceFirst("Exception: ", "")}';
        });
        _showErrorSnackBar(
            'Error getting location: ${e.toString().replaceFirst("Exception: ", "")}');
      }
    }
  }

  Widget _buildLocationField() {
    String currentHintText = _isFetchingLocation
        ? "Acquiring location" + "." * _locationHintDots // Animated dots
        : "Tap icon to get current location";

    return AnimatedOpacity(
      opacity: _isFetchingLocation ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
        children: [
          Expanded(
            child: TextFormField(
              controller: _userDetailsLocationController,
              readOnly: true, // Location is set by the button
              style:
                  GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 14),
              decoration: _buildInputDecoration(
                "Location Address", // Changed label
                prefixIcon: Icons.location_on_outlined,
                hintText: currentHintText,
              ).copyWith(
                // Ensure content padding works well with multiline
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 14.0, horizontal: 12.0),
              ),
              maxLines: 2, // Allow for longer addresses
              // No validator needed for readOnly field set programmatically
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(
                top: 4.0), // Adjust button position slightly
            child: IconButton(
              icon: Icon(Icons.my_location, color: kColorPrimaryDark),
              tooltip: 'Get Current Location',
              onPressed: _isFetchingLocation
                  ? null
                  : _getCurrentLocation, // Disable while fetching
            ),
          ),
        ],
      ),
    );
  }

  // --- Grouped Info Row Helper (Corrected definition) ---
  Widget _buildGroupedInfoRows(List<Widget> children, bool isEditing) {
    if (isEditing) {
      // In edit mode, just a simple column of children (input fields)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .map((child) => Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 4.0), // Add some spacing between edit fields
                  child: child,
                ))
            .toList(),
      );
    }

    // In display mode, group items visually
    List<Widget> groupedChildren = [];
    List<Widget> buffer =
        []; // To hold non-CustomGroupContainer items to be grouped

    for (var child in children) {
      if (child is CustomGroupContainer) {
        // If buffer has items, group them first
        if (buffer.isNotEmpty) {
          groupedChildren.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border:
                    Border.all(color: kColorBorder.withOpacity(0.7), width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buffer.map((e) => e).toList(), // Add buffered items
              ),
            ),
          );
          buffer.clear(); // Clear buffer after adding
        }
        // Add the CustomGroupContainer directly
        groupedChildren.add(Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 4.0), // Consistent vertical margin
          child: child,
        ));
      } else {
        // Add other widgets (like _buildInfoRow) to the buffer
        buffer.add(child);
      }
    }

    // Flush any remaining items in the buffer
    if (buffer.isNotEmpty) {
      groupedChildren.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: kColorBorder.withOpacity(0.7), width: 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buffer.map((e) => e).toList(),
          ),
        ),
      );
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: groupedChildren);
  }

  // --- Card Content Widgets ---
  Widget _buildUserDetailsCard() {
    return _buildStyledCard(
      title: 'User Details',
      isEditing: _isEditingUserDetails,
      onEdit: () {
        setState(() {
          _isEditingUserDetails = true;
          _isEditingMetrics =
              false; // Ensure other sections are not in edit mode
          _isEditingPreferences = false;
          // Populate controllers from current state
          _userDetailsNameController.text =
              getCaseInsensitive<String>(_userDetails, 'Name') ?? '';
          _userDetailsEmailController.text =
              getCaseInsensitive<String>(_userDetails, 'Email') ?? '';
          _userDetailsPhoneController.text =
              getCaseInsensitive<String>(_userDetails, 'Phone_Number') ?? '';
          _userDetailsLocationController.text =
              getCaseInsensitive<String>(_userDetails, 'Location') ?? '';
        });
      },
      children: _isEditingUserDetails
          ? [
              // Widgets for editing user details
              _buildTextField(
                controller: _userDetailsNameController,
                label: 'Name',
                icon: Icons.person_outline,
              ),
              _buildTextField(
                controller: _userDetailsEmailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              _buildTextField(
                controller: _userDetailsPhoneController,
                label: 'Phone',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              _buildLocationField(), // Special field for location editing
            ]
          : [
              // Widgets for displaying user details
              _buildInfoRow(
                icon: Icons.badge_outlined,
                label: 'User ID',
                value:
                    getCaseInsensitive(_userDetails, 'User_Id')?.toString() ??
                        'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.person_outline,
                label: 'Name',
                value:
                    getCaseInsensitive<String>(_userDetails, 'Name') ?? 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value:
                    getCaseInsensitive<String>(_userDetails, 'Email') ?? 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value:
                    getCaseInsensitive<String>(_userDetails, 'Phone_Number') ??
                        'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: getCaseInsensitive<String>(_userDetails, 'Location') ??
                    'N/A',
                isEditing: false,
                maxLines: 2,
              ),
              _buildInfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Joined',
                value: _formatJoinedDate(
                    getCaseInsensitive(_userDetails, 'Registration_Date')),
                isEditing: false,
              ),
            ],
    );
  }

  Widget _buildMetricsCard() {
    return _buildStyledCard(
      title: 'Health Metrics',
      isEditing: _isEditingMetrics,
      onEdit: () {
        setState(() {
          _isEditingMetrics = true;
          _isEditingUserDetails = false;
          _isEditingPreferences = false;

          // Populate controllers and selected values from _userMetrics
          double? currentWeightKg =
              _tryParseDouble(getCaseInsensitive(_userMetrics, 'weight'));
          double? currentHeightCm =
              _tryParseDouble(getCaseInsensitive(_userMetrics, 'height'));

          _selectedAgeRange =
              getCaseInsensitive(_userMetrics, 'age_range') != 'N/A'
                  ? getCaseInsensitive(_userMetrics, 'age_range')
                  : null;
          if (_selectedAgeRange != null &&
              !_ageRanges.contains(_selectedAgeRange)) _selectedAgeRange = null;

          _selectedSex = getCaseInsensitive(_userMetrics, 'sex') != 'N/A'
              ? getCaseInsensitive(_userMetrics, 'sex')
              : null;
          if (_selectedSex != null && !_sexs.contains(_selectedSex))
            _selectedSex = null;

          _selectedActivityLevel =
              getCaseInsensitive(_userMetrics, 'activity_level') != 'N/A'
                  ? getCaseInsensitive(_userMetrics, 'activity_level')
                  : null;
          if (_selectedActivityLevel != null &&
              !_activityLevels.contains(_selectedActivityLevel))
            _selectedActivityLevel = null;

          _weightKg = currentWeightKg ?? 0;
          _heightCm = currentHeightCm ?? 0;
          _updateWeightControllerBasedOnUnit(); // Populates _weightController
          _updateHeightControllerBasedOnUnit(); // Populates _heightCmController or ft/in controllers
        });
      },
      children: _isEditingMetrics
          ? _buildMetricsEditingWidgets()
          : [
              _buildInfoRow(
                icon: Icons.height_outlined,
                label: 'Height',
                value: getCaseInsensitive(_userMetrics, 'height') != 'N/A' &&
                        getCaseInsensitive(_userMetrics, 'height') != null
                    ? '${getCaseInsensitive(_userMetrics, 'height')} cm'
                    : 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.fitness_center_outlined,
                label: 'Weight',
                value: getCaseInsensitive(_userMetrics, 'weight') != 'N/A' &&
                        getCaseInsensitive(_userMetrics, 'weight') != null
                    ? '${getCaseInsensitive(_userMetrics, 'weight')} kg'
                    : 'N/A',
                isEditing: false,
              ),
              CustomGroupContainer(
                child: Container(
                  decoration: BoxDecoration(
                    // Inner container to ensure consistent border if CustomGroupContainer doesn't provide one
                    border: _isEditingMetrics
                        ? Border.all(color: Colors.transparent)
                        : Border.all(
                            color: kColorBorder.withOpacity(0.7), width: 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInfoRow(
                        icon: Icons.monitor_weight_outlined,
                        label: 'BMI',
                        value: getCaseInsensitive(_userMetrics, 'bmi') ?? 'N/A',
                        isEditing: false,
                      ),
                      _buildInfoRow(
                        icon: Icons.accessibility_new_outlined,
                        label: 'BMI Category',
                        value:
                            getCaseInsensitive(_userMetrics, 'bmi_category') ??
                                'N/A',
                        isEditing: false,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 16.0, right: 16.0, bottom: 12.0, top: 0.0),
                        child: _buildBmiVisualIndicator(_tryParseDouble(
                            getCaseInsensitive(_userMetrics, 'bmi'))),
                      ),
                    ],
                  ),
                ),
              ),
              CustomGroupContainer(
                child: Container(
                  decoration: BoxDecoration(
                    border: _isEditingMetrics
                        ? Border.all(color: Colors.transparent)
                        : Border.all(
                            color: kColorBorder.withOpacity(0.7), width: 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInfoRow(
                        icon: Icons.directions_run_outlined,
                        label: 'Activity Level',
                        value: getCaseInsensitive(
                                _userMetrics, 'activity_level') ??
                            'N/A',
                        isEditing: false,
                      ),
                      _buildInfoRow(
                        icon: Icons.cake_outlined,
                        label: 'Age Range',
                        value: getCaseInsensitive(_userMetrics, 'age_range') ??
                            'N/A',
                        isEditing: false,
                      ),
                    ],
                  ),
                ),
              ),
              _buildInfoRow(
                icon: Icons.wc_outlined,
                label: 'Sex',
                value: getCaseInsensitive(_userMetrics, 'sex') ?? 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                // Ideal Weight
                icon: Icons.scale_outlined,
                label: 'Ideal Weight (Est.)',
                value: getCaseInsensitive(_userMetrics, 'ideal_weight') !=
                            'N/A' &&
                        getCaseInsensitive(_userMetrics, 'ideal_weight') != null
                    ? '${getCaseInsensitive(_userMetrics, 'ideal_weight')} kg'
                    : 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.bolt_outlined,
                label: 'BMR (Est.)',
                value: getCaseInsensitive(_userMetrics, 'bmr') != 'N/A' &&
                        getCaseInsensitive(_userMetrics, 'bmr') != null
                    ? '${getCaseInsensitive(_userMetrics, 'bmr')} kcal'
                    : 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                icon: Icons.restaurant_outlined,
                label: 'Daily Calories (Est.)',
                value: getCaseInsensitive(_userMetrics, 'daily_calories') !=
                            'N/A' &&
                        getCaseInsensitive(_userMetrics, 'daily_calories') !=
                            null
                    ? '${getCaseInsensitive(_userMetrics, 'daily_calories')} kcal'
                    : 'N/A',
                isEditing: false,
              ),
              _buildInfoRow(
                // Other medical metrics - assuming they are less frequently edited manually
                icon: Icons.opacity_outlined,
                label: 'Cholesterol',
                value: getCaseInsensitive(_userMetrics, 'cholesterol_level') ??
                    'N/A',
                isEditing: false, // Not editable in this version
              ),
              _buildInfoRow(
                icon: Icons.favorite_border_outlined,
                label: 'Blood Pressure (Sys/Dia)',
                value:
                    '${getCaseInsensitive(_userMetrics, 'sys_bp') ?? 'N/A'} / ${getCaseInsensitive(_userMetrics, 'dia_bp') ?? 'N/A'}',
                isEditing: false, // Not editable
              ),
              _buildInfoRow(
                icon: Icons.monitor_heart_outlined,
                label: 'Pulse',
                value: getCaseInsensitive(_userMetrics, 'pulse') ?? 'N/A',
                isEditing: false, // Not editable
              ),
              _buildInfoRow(
                icon: Icons.update_outlined,
                label: 'Last Recorded',
                value: _formatJoinedDate(
                    getCaseInsensitive(_userMetrics, 'recorded_at')),
                isEditing: false,
              ),
            ],
    );
  }

  List<Widget> _buildMetricsEditingWidgets() {
    String calculatedBmi = _calculateBmi(_heightCm, _weightKg);
    // For BMR and Daily Calories preview during editing:
    double? bmrPreview;
    if (_weightKg > 0 &&
        _heightCm > 0 &&
        _selectedAgeRange != null &&
        _selectedSex != null) {
      int age = 30;
      final ageMatch = RegExp(r'\d+').firstMatch(_selectedAgeRange!);
      if (ageMatch != null) age = int.tryParse(ageMatch.group(0)!) ?? 30;
      if (_selectedSex == 'Male')
        bmrPreview = 10 * _weightKg + 6.25 * _heightCm - 5 * age + 5;
      else
        bmrPreview = 10 * _weightKg + 6.25 * _heightCm - 5 * age - 161;
    }
    double? dailyCaloriesPreview;
    if (bmrPreview != null && _selectedActivityLevel != null) {
      final activityMultipliers = {
        'Sedentary': 1.2,
        'Lightly Active': 1.375,
        'Moderately Active': 1.55,
        'Very Active': 1.725
      };
      dailyCaloriesPreview =
          bmrPreview * (activityMultipliers[_selectedActivityLevel!] ?? 1.2);
    }

    return [
      _buildDropdownField<String>(
        label: 'Age Range',
        icon: Icons.cake_outlined,
        currentValue: _selectedAgeRange,
        options: _ageRanges,
        onChanged: (value) => setState(() => _selectedAgeRange = value),
      ),
      _buildDropdownField<String>(
        label: 'Sex',
        icon: Icons.wc_outlined,
        currentValue: _selectedSex,
        options: _sexs,
        onChanged: (value) => setState(() => _selectedSex = value),
      ),
      _buildWeightInputRow(),
      _buildHeightInputRow(),
      _buildDropdownField<String>(
        label: 'Activity Level',
        icon: Icons.directions_run_outlined,
        currentValue: _selectedActivityLevel,
        options: _activityLevels,
        onChanged: (value) => setState(() => _selectedActivityLevel = value),
      ),
      // Display calculated BMI, BMR, Daily Calories dynamically during editing
      Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: Column(
          children: [
            _buildInfoRow(
              icon: Icons.monitor_weight_outlined,
              label: 'BMI (Calculated)',
              value: calculatedBmi,
              isEditing: false, // Display only
            ),
            if (calculatedBmi != 'N/A')
              Padding(
                padding:
                    const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                child: _buildBmiVisualIndicator(_tryParseDouble(calculatedBmi)),
              ),
            _buildInfoRow(
              icon: Icons.bolt_outlined,
              label: 'BMR (Est. Preview)',
              value: bmrPreview != null
                  ? '${bmrPreview.toStringAsFixed(0)} kcal'
                  : 'N/A',
              isEditing: false, // Display only
            ),
            _buildInfoRow(
              icon: Icons.restaurant_menu_outlined,
              label: 'Daily Calories (Est. Preview)',
              value: dailyCaloriesPreview != null
                  ? '${dailyCaloriesPreview.toStringAsFixed(0)} kcal'
                  : 'N/A',
              isEditing: false, // Display only
            ),
          ],
        ),
      ),
      // Display non-editable metrics for context if needed
      _buildInfoRow(
        icon: Icons.opacity_outlined,
        label: 'Cholesterol (Last Known)',
        value: getCaseInsensitive(_userMetrics, 'cholesterol_level') ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.favorite_border_outlined,
        label: 'Blood Pressure (Last Known)',
        value:
            '${getCaseInsensitive(_userMetrics, 'sys_bp') ?? 'N/A'} / ${getCaseInsensitive(_userMetrics, 'dia_bp') ?? 'N/A'}',
        isEditing: false,
      ),
    ];
  }

  Widget _buildPreferencesCard() {
    return _buildStyledCard(
      title: 'Preferences',
      isEditing: _isEditingPreferences,
      onEdit: () {
        setState(() {
          _isEditingPreferences = true;
          _isEditingUserDetails = false;
          _isEditingMetrics = false;
          // Populate controllers from _userPreferences
          _selectedGoal = getCaseInsensitive(_userPreferences, 'goals') != 'N/A'
              ? getCaseInsensitive(_userPreferences, 'goals')
              : null;
          if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal))
            _selectedGoal = null;

          _selectedDietType =
              getCaseInsensitive(_userPreferences, 'diet_type') != 'N/A'
                  ? getCaseInsensitive(_userPreferences, 'diet_type')
                  : null;
          if (_selectedDietType != null &&
              !_dietTypeOptions.contains(_selectedDietType))
            _selectedDietType = null;

          String? currentRestrictionDisplay =
              getCaseInsensitive(_userPreferences, 'food_restrictions');
          if (currentRestrictionDisplay == 'None') {
            _selectedFoodRestriction = 'None';
          } else if (currentRestrictionDisplay != null &&
              currentRestrictionDisplay != 'N/A') {
            String firstItem =
                currentRestrictionDisplay.split(',').first.trim();
            _selectedFoodRestriction =
                _foodRestrictionsOptions.contains(firstItem) ? firstItem : null;
          } else {
            _selectedFoodRestriction = null;
          }
          if (_selectedFoodRestriction != null &&
              !_foodRestrictionsOptions.contains(_selectedFoodRestriction)) {
            _selectedFoodRestriction = null;
          }
        });
      },
      children: _isEditingPreferences
          ? _buildPreferencesEditingWidgets()
          : _buildPreferencesDisplayWidgets(),
    );
  }

  List<Widget> _buildPreferencesDisplayWidgets() {
    return [
      _buildInfoRow(
        icon: Icons.flag_outlined,
        label: 'Goals',
        value: getCaseInsensitive(_userPreferences, 'goals') ?? 'Not Set',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.restaurant_menu_outlined,
        label: 'Diet Type',
        value: getCaseInsensitive(_userPreferences, 'diet_type') ?? 'Not Set',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.no_food_outlined,
        label: 'Food Restrictions',
        value:
            getCaseInsensitive(_userPreferences, 'food_restrictions') ?? 'None',
        isEditing: false,
        maxLines: 3,
      ),
      _buildInfoRow(
        icon: Icons.ramen_dining_outlined,
        label: 'Cuisine Preferences',
        value: getCaseInsensitive(_userPreferences, 'cuisine_preferences') ??
            'Not Set',
        isEditing: false,
        maxLines: 3,
      ),
      const SizedBox(height: 16),
      _buildMealRecommendationsButton(),
    ];
  }

  List<Widget> _buildPreferencesEditingWidgets() {
    return [
      _buildDropdownField<String>(
        label: 'Goals',
        icon: Icons.flag_outlined,
        currentValue: _selectedGoal,
        options: _goalsOptions,
        onChanged: (value) => setState(() => _selectedGoal = value),
      ),
      _buildDropdownField<String>(
        label: 'Diet Type',
        icon: Icons.restaurant_menu_outlined,
        currentValue: _selectedDietType,
        options: _dietTypeOptions,
        onChanged: (value) => setState(() => _selectedDietType = value),
      ),
      _buildDropdownField<String>(
        label: 'Food Restrictions (Primary)', 
        icon: Icons.no_food_outlined,
        currentValue: _selectedFoodRestriction,
        options: _foodRestrictionsOptions, // Includes "None"
        hint: "Select primary restriction",
        onChanged: (value) => setState(() => _selectedFoodRestriction = value),
      ),
      const SizedBox(height: 8),
      // Cuisine preferences multi-select
      Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
              child: Row(
                children: [
                  Icon(Icons.ramen_dining_outlined, size: 20, color: Colors.grey[700]),
                  const SizedBox(width: 12),
                  Text(
                    'Cuisine Preferences',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _cuisineOptions.map((cuisine) {
                final isSelected = _selectedCuisines.contains(cuisine);
                return FilterChip(
                  label: Text(cuisine),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedCuisines.add(cuisine);
                      } else {
                        _selectedCuisines.remove(cuisine);
                      }
                    });
                  },
                  selectedColor: kColorPrimary.withOpacity(0.2),
                  checkmarkColor: kColorPrimary,
                  labelStyle: GoogleFonts.poppins(
                    color: isSelected ? kColorPrimary : Colors.grey[800],
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                  backgroundColor: Colors.grey[200],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? kColorPrimary : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_selectedCuisines.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                child: Text(
                  'Select your favorite cuisines',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      _buildMealRecommendationsButton(),
    ];
  }

  Widget _buildMealRecommendationsButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OnlymealsScreen()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: kColorPrimary,
          foregroundColor: kColorTextOnPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        icon: const Icon(Icons.menu_book_outlined, size: 20),
        label: Text('View Meal Recommendations', style: GoogleFonts.poppins()),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: TextButton.icon(
        icon: Icon(Icons.logout, color: Colors.red.shade700),
        label: Text("Don't Logout",
            style:
                GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 16)),
        onPressed: _logout,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }

  // --- Info Row Widget (Handles Display/Edit for Simple Fields) ---
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool
        isEditing, // This parameter is now less used directly by _buildInfoRow itself for TextField creation
    TextEditingController?
        controller, // Kept for potential direct use, but _buildUserDetailsCard now provides TextFields directly
    TextInputType? keyboardType,
    int? maxLines = 1,
  }) {
    final labelStyle = GoogleFonts.poppins(
        fontWeight: FontWeight.w500, color: kColorTextSecondary, fontSize: 15);
    final valueStyle =
        GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15);

    // This widget is now primarily for DISPLAY purposes.
    // Editing fields are constructed directly in _buildUserDetailsCard, _buildMetricsEditingWidgets etc.
    // If 'isEditing' is true and a controller is passed, it implies a TextField would be built by the caller.
    // Here, we always build the display version.

    Widget contentWidget = Text(
      value.isEmpty ? 'N/A' : value,
      style: valueStyle,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );

    // If a controller is provided, it implies this row MIGHT be part of an edit form,
    // but _buildInfoRow itself doesn't create the TextField.
    // The padding adjustment for icon is based on whether it's a simple display or part of a form-like structure.
    bool isPotentiallyInForm = controller != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Adjust icon alignment slightly if it's likely next to a form field (even if read-only)
            padding: EdgeInsets.only(top: isPotentiallyInForm ? 3.0 : 1.0),
            child: Icon(icon, color: kColorPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 4),
                contentWidget, // Always display content for _buildInfoRow
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Weight Input Row (for Editing Metrics) ---
  Widget _buildWeightInputRow() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 4.0), // Reduced vertical padding
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align items to the top of the row
        children: [
          Expanded(
            child: TextFormField(
              controller: _weightController,
              decoration: _buildInputDecoration(
                  'Weight', // Label inside the input decoration
                  prefixIcon: Icons.fitness_center_outlined),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(
                    r'^\d*\.?\d*')) // Allow numbers and one decimal point
              ],
              style:
                  GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(
                top: 4.0), // Align ToggleButtons with TextFormField content
            child: ToggleButtons(
              isSelected: _weightSelection,
              onPressed: _updateWeightUnit,
              borderRadius: BorderRadius.circular(8.0),
              selectedColor: Colors.white,
              color: kColorPrimary,
              fillColor: kColorPrimary,
              constraints: const BoxConstraints(
                  minHeight: 48.0,
                  minWidth: 48.0), // Ensure buttons are tappable
              children: <Widget>[
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child:
                        Text('kg', style: GoogleFonts.poppins(fontSize: 14))),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child:
                        Text('lbs', style: GoogleFonts.poppins(fontSize: 14))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Height Input Row (for Editing Metrics) ---
  Widget _buildHeightInputRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _heightUnit == 'cm'
                ? TextFormField(
                    controller: _heightCmController,
                    decoration: _buildInputDecoration('Height',
                        prefixIcon: Icons.height_outlined,
                        hintText: 'cm' // Hint for unit
                        ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    style: GoogleFonts.poppins(
                        color: kColorTextPrimary, fontSize: 15),
                  )
                : Row(
                    // For ft/in input
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Common prefix icon for ft/in mode
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 12.0,
                            right: 8.0), // Align icon with text field content
                        child: Icon(Icons.height_outlined,
                            color: kColorPrimary, size: 20),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _heightFeetController,
                          decoration: _buildInputDecoration('Height (ft)',
                              prefixIcon: null), // No redundant icon
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: GoogleFonts.poppins(
                              color: kColorTextPrimary, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _heightInchesController,
                          decoration: _buildInputDecoration('(in)',
                              prefixIcon: null), // Label for inches
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          style: GoogleFonts.poppins(
                              color: kColorTextPrimary, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: ToggleButtons(
              isSelected: _heightSelection,
              onPressed: _updateHeightUnit,
              borderRadius: BorderRadius.circular(8.0),
              selectedColor: Colors.white,
              color: kColorPrimary,
              fillColor: kColorPrimary,
              constraints:
                  const BoxConstraints(minHeight: 48.0, minWidth: 48.0),
              children: <Widget>[
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child:
                        Text('cm', style: GoogleFonts.poppins(fontSize: 14))),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child:
                        Text('ft', style: GoogleFonts.poppins(fontSize: 14))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // BMI Indicator
  Widget _buildBmiVisualIndicator([double? bmiValue]) {
    // Try to get BMI from _userMetrics if not provided (e.g., during initial display)
    bmiValue ??= _tryParseDouble(getCaseInsensitive(_userMetrics, 'bmi'));

    if (bmiValue == null ||
        bmiValue <= 0 ||
        bmiValue.isNaN ||
        bmiValue.isInfinite) {
      return const SizedBox.shrink(); // Don't show if BMI is invalid
    }

    const double underweightThreshold = 18.5;
    const double normalMinThreshold = 18.5; // Explicit min for normal
    const double normalMaxThreshold = 24.9;
    const double overweightMinThreshold = 25.0; // Explicit min for overweight
    const double overweightMaxThreshold = 29.9;
    // Obese is >= 30.0

    Color barColor;
    String categoryText;

    // Determine category and color based on BMI value
    // Use API category if available and valid, otherwise calculate
    String apiCategory = getCaseInsensitive(_userMetrics, 'bmi_category') ?? '';
    bool useApiCategoryText = apiCategory.isNotEmpty && apiCategory != 'N/A';

    if (bmiValue < underweightThreshold) {
      barColor = Colors.blue.shade300;
      categoryText = useApiCategoryText ? apiCategory : 'Underweight';
    } else if (bmiValue >= normalMinThreshold &&
        bmiValue <= normalMaxThreshold) {
      barColor = Colors.green.shade400;
      categoryText = useApiCategoryText ? apiCategory : 'Normal';
    } else if (bmiValue >= overweightMinThreshold &&
        bmiValue <= overweightMaxThreshold) {
      barColor = Colors.orange.shade400;
      categoryText = useApiCategoryText ? apiCategory : 'Overweight';
    } else {
      // bmiValue > overweightMaxThreshold (i.e., >= 30.0)
      barColor = Colors.red.shade400;
      categoryText = useApiCategoryText ? apiCategory : 'Obese';
    }

    // Simple bar representation (could be enhanced with a pointer or more segments)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
            height: 10, // Slightly thicker bar
            decoration: BoxDecoration(
              // Could be a gradient or segmented bar in future
              color: Colors.grey.shade200, // Background for the bar track
              borderRadius: BorderRadius.circular(5),
            ),
            child: Align(
              // Align the actual colored bar within the track
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                // Width factor could represent position on a scale, but simple color is fine for now
                // For simplicity, full width with the category color
                widthFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            )),
        const SizedBox(height: 6),
        Text(
          categoryText,
          style: GoogleFonts.poppins(
              fontSize: 13,
              color: barColor,
              fontWeight: FontWeight.w500), // Slightly larger font
        )
      ],
    );
  }
}

// --- Global Helper Functions ---
T? getCaseInsensitive<T>(Map? map, String key) {
  if (map == null || key.isEmpty) return null;
  final lowerKey = key.toLowerCase();
  for (final entry in map.entries) {
    if (entry.key is String && entry.key.toString().toLowerCase() == lowerKey) {
      if (entry.value == null) return null;
      if (entry.value is T) {
        return entry.value as T;
      }
      // Attempt common conversions
      if (T == String) {
        return entry.value.toString() as T;
      }
      if (T == double) {
        if (entry.value is num) return (entry.value as num).toDouble() as T;
        if (entry.value is String)
          return double.tryParse(entry.value as String) as T?;
      }
      if (T == int) {
        if (entry.value is num) return (entry.value as num).toInt() as T;
        if (entry.value is String)
          return int.tryParse(entry.value as String) as T?;
      }
      // Fallback for other types if direct cast might work or if specific conversion is not handled
      try {
        return entry.value as T;
      } catch (e) {
        // print("getCaseInsensitive: Cast failed for key '$key', value '${entry.value}' (type ${entry.value.runtimeType}) to type $T. Error: $e");
        return null;
      }
    }
  }
  return null;
}

double? _tryParseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    if (value.trim().isEmpty || value.trim().toLowerCase() == 'n/a')
      return null;
    return double.tryParse(value);
  }
  return null;
}
