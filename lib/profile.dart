import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math'; // Import for min function
import 'dart:async'; // Import for TimeoutException
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/allmeals.dart';
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
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/cache_config.dart'; // Import CacheConfig
import 'package:shimmer/shimmer.dart'; // For loading effect
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter/services.dart'; // For input formatters

// --- Re-add Color Constants (or import from a shared file) ---
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
        final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
            dotenv.env['API_BASE_URL-intranet'] ??
            'https://default.url';
        int? userId = prefs.getInt('user_id');
        if (userId != null) {
          final response = await http
              .get(Uri.parse(
                  '$apiBaseUrl/rr/rusers/$userId')) // Assuming /rr/rusers endpoint
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            Map<String, dynamic>? userMap =
                _parseUserResponseStatic(responseData);
            if (userMap != null) {
              await UserCache.saveData('user_details_cache', userMap);
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
    await _loadImageFromPrefs();
    if (_userId != null) {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = await UserCache.getData('user_details_cache');
      final cachedTimestampMillis =
          prefs.getInt('user_details_cache_timestamp');
      final now = DateTime.now();

      bool isCacheValid = cachedData != null &&
          cachedTimestampMillis != null &&
          now.difference(
                  DateTime.fromMillisecondsSinceEpoch(cachedTimestampMillis)) <
              CacheConfig.profileCacheDuration;

      if (isCacheValid) {
        print("[Profile] Using cached user details.");
        _updateStateWithUserDetails(Map<String, dynamic>.from(cachedData!));
        setState(() => _isLoading = false); // Stop main loading indicator
        // Fetch metrics and preferences in the background regardless
        _fetchMetrics();
        _fetchPreferences();
      } else {
        print("[Profile] Cache invalid or missing. Fetching all data.");
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
    // Try to get user_id as string first, fall back to int for backward compatibility
    final userIdStr = prefs.getString('user_id');
    _userId = userIdStr != null ? int.tryParse(userIdStr) : prefs.getInt('user_id');
    _userType = prefs.getString('user_type');
    print("Loaded User ID: $_userId, User Type: $_userType");
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _userDetails
          .isEmpty; // Show overall shimmer only if no details loaded yet
      _fetchError = '';
      // Reset individual loading flags for refresh effect
      _isLoadingUserDetails = true;
      _isLoadingMetrics = true;
      _isLoadingPreferences = true;
    });
    _startRefreshAnimation();

    try {
      // Fetch data concurrently
      await Future.wait([
        _fetchUserDetails(),
        _fetchMetrics(),
        _fetchPreferences(),
      ]);
    } catch (e) {
      if (mounted) {
        print("Error during concurrent data fetch: $e");
        setState(() {
          _fetchError = "Failed to load profile data. Please try again.";
          // Ensure loading flags are false even on error
          _isLoadingUserDetails = false;
          _isLoadingMetrics = false;
          _isLoadingPreferences = false;
        });
        _showErrorSnackBar(_fetchError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // Hide overall loading indicator
          // Individual flags are set to false within their respective fetchers' finally blocks
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
    final url =
        '$apiBaseUrl/rr/rusers/$_userId'; // Assuming /rr/rusers endpoint
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
          _updateStateWithUserDetails(userMap);
          await UserCache.saveData('user_details_cache', userMap);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_details_cache_timestamp',
              DateTime.now().millisecondsSinceEpoch);
        } else {
          print("User details parsing failed or data empty: $responseData");
          // Consider setting default user details state here
          _userDetails = {}; // Example reset
        }
      } else {
        print('Failed to fetch user details. Status: ${response.statusCode}');
        _userDetails = {}; // Example reset
      }
    } on TimeoutException {
      print("Timeout fetching user details.");
      _userDetails = {}; // Example reset
    } catch (error) {
      print("Error fetching user details: $error");
      _userDetails = {}; // Example reset
    } finally {
      if (mounted) setState(() => _isLoadingUserDetails = false);
    }
  }

  // Instance parser method using the static one
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
        'image': userData['image'] ?? userData['image'], // Check both keys
      };
      _profileImageUrl = _userDetails['image'];

      // Pre-fill controllers only if not currently editing this section
      if (!_isEditingUserDetails) {
        _userDetailsNameController.text = _userDetails['Name'] ?? '';
        _userDetailsEmailController.text = _userDetails['Email'] ?? '';
        _userDetailsPhoneController.text = _userDetails['Phone_Number'] ?? '';
        _userDetailsLocationController.text = _userDetails['Location'] ?? '';
      }
    });
  }

  Future<void> _fetchMetrics() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingMetrics = false);
      return;
    }
    final url = '$apiBaseUrl/rr/metrics/$_userId';
    print("Fetching Metrics from URL: $url");
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("Metrics Response: ${response.statusCode} - ${response.body}");
      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Updated parsing logic based on logs
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('metrics') &&
            responseData['metrics'] is List &&
            (responseData['metrics'] as List).isNotEmpty &&
            responseData['metrics'][0] is Map) {
          final metrics = Map<String, dynamic>.from(responseData['metrics'][0]);
          _updateStateWithMetrics(metrics);
        } else {
          print(
              "Metrics data parsing failed or empty (expected structure not found): $responseData");
          _setDefaultMetricsState();
        }
      } else {
        print('Could not fetch metrics. Status: ${response.statusCode}');
        _setDefaultMetricsState(); // Set defaults on error
      }
    } on TimeoutException {
      print("Timeout fetching metrics.");
      _setDefaultMetricsState(); // Set defaults on timeout
    } catch (error) {
      print("Error fetching metrics: $error");
      _setDefaultMetricsState(); // Set defaults on error
    } finally {
      if (mounted) setState(() => _isLoadingMetrics = false);
    }
  }

  void _setDefaultMetricsState() {
    if (!mounted) return;
    setState(() {
      _userMetrics = {
        'age_range': 'N/A',
        'sex': 'N/A',
        'height': 'N/A',
        'weight': 'N/A',
        'bmi': 'N/A',
        'activity_level': 'N/A',
        'cholesterol_level': 'N/A',
        'sys_bp': 'N/A',
        'dia_bp': 'N/A',
        'pulse': 'N/A',
        'ideal_weight': 'N/A',
        'bmi_category': 'N/A',
        'bmr': 'N/A',
        'daily_calories': 'N/A',
        'recorded_at': 'N/A',
      };
      // Reset editing state variables if not editing
      if (!_isEditingMetrics) {
        _selectedAgeRange = null;
        _selectedSex = null;
        _selectedActivityLevel = null;
        _weightController.clear();
        _heightCmController.clear();
        _heightFeetController.clear();
        _heightInchesController.clear();
        _weightKg = 0;
        _heightCm = 0;
        _weightUnit = 'kg';
        _weightSelection = [true, false];
        _heightUnit = 'cm';
        _heightSelection = [true, false];
      }
    });
  }

  void _updateStateWithMetrics(Map<String, dynamic> metrics) {
    if (!mounted) return;
    // Safely parse numeric values
    double? fetchedHeightCm = _tryParseDouble(metrics['height']);
    double? fetchedWeightKg = _tryParseDouble(metrics['weight']);
    String calculatedBmi = _calculateBmi(fetchedHeightCm, fetchedWeightKg);

    setState(() {
      _userMetrics = {
        'age_range': metrics['age_range'] ?? 'N/A',
        'sex': metrics['sex'] ?? 'N/A',
        'height': fetchedHeightCm?.toString() ?? 'N/A',
        'weight': fetchedWeightKg?.toString() ?? 'N/A',
        'bmi': metrics['bmi']?.toString() ?? calculatedBmi, // Prefer API BMI
        'activity_level': metrics['activity_level'] ?? 'N/A',
        'cholesterol_level': metrics['cholesterol_level']?.toString() ?? 'N/A',
        'sys_bp': metrics['sys_bp']?.toString() ?? 'N/A',
        'dia_bp': metrics['dia_bp']?.toString() ?? 'N/A',
        'pulse': metrics['pulse']?.toString() ?? 'N/A',
        'ideal_weight': metrics['ideal_weight']?.toString() ?? 'N/A',
        'bmi_category': metrics['bmi_category'] ?? 'N/A',
        'bmr': metrics['bmr']?.toString() ?? 'N/A',
        'daily_calories': metrics['daily_calories']?.toString() ?? 'N/A',
        'recorded_at': metrics['recorded_at'] ?? 'N/A',
      };

      // Update internal state for editing (only if not currently editing)
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

        _weightKg = fetchedWeightKg ?? 0;
        _updateWeightControllerBasedOnUnit();

        _heightCm = fetchedHeightCm ?? 0;
        _updateHeightControllerBasedOnUnit();
      }
    });
  }

  Future<void> _fetchPreferences() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoadingPreferences = false);
      return;
    }
    final url = '$apiBaseUrl/rr/preferences/$_userId';
    print("Fetching Preferences from URL: $url");
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("Preferences Response: ${response.statusCode} - ${response.body}");
      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Updated parsing logic based on logs
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('preferences') &&
            responseData['preferences'] is List &&
            (responseData['preferences'] as List).isNotEmpty &&
            responseData['preferences'][0] is Map) {
          final preferences =
              Map<String, dynamic>.from(responseData['preferences'][0]);
          _updateStateWithPreferences(preferences);
        } else {
          print(
              "Preferences data parsing failed or empty (expected structure not found): $responseData");
          _setDefaultPreferencesState();
        }
      } else {
        print('Could not fetch preferences. Status: ${response.statusCode}');
        _setDefaultPreferencesState();
      }
    } on TimeoutException {
      print("Timeout fetching preferences.");
      _setDefaultPreferencesState();
    } catch (error) {
      print("Error fetching preferences: $error");
      _setDefaultPreferencesState();
    } finally {
      if (mounted) setState(() => _isLoadingPreferences = false);
    }
  }

  void _setDefaultPreferencesState() {
    if (!mounted) return;
    setState(() {
      _userPreferences = {
        'goals': 'N/A',
        'diet_type': 'N/A',
        'food_restrictions': 'N/A', // Display as string
        'cuisine_preferences': 'N/A', // Display as string
      };
      // Reset editing state variables if not editing
      if (!_isEditingPreferences) {
        _selectedGoal = null;
        _selectedDietType = null;
        _selectedFoodRestriction = null; // Set to null initially
      }
    });
  }

  // Helper function to safely convert potential list/string to string
  String _listToString(dynamic value,
      {String defaultValue = 'N/A', String emptyValue = 'None'}) {
    if (value == null) return defaultValue;
    if (value is List) {
      if (value.isEmpty) return emptyValue;
      return value
          .where((item) => item != null && item.toString().isNotEmpty)
          .join(', ');
    }
    String strValue = value.toString();
    if (strValue.startsWith('[') && strValue.endsWith(']')) {
      try {
        List<dynamic> list = json.decode(strValue);
        if (list.isEmpty) return emptyValue;
        return list
            .where((item) => item != null && item.toString().isNotEmpty)
            .join(', ');
      } catch (e) {
        String content = strValue.substring(1, strValue.length - 1);
        return content.isEmpty
            ? emptyValue
            : content; // Return content or emptyValue
      }
    }
    // If it's just a plain string or number, return it, or defaultValue if empty
    return strValue.isNotEmpty ? strValue : defaultValue;
  }

  // Helper function to get the first item from a list or string representation
  String? _getFirstItemFromListOrString(dynamic value) {
    if (value == null) return null;
    List<String> items = [];
    if (value is List) {
      items = List<String>.from(
          value.map((e) => e.toString()).where((s) => s.isNotEmpty));
    } else {
      // Use helper, defaulting to empty string if N/A to avoid "N/A" being split
      String strValue = _listToString(value, defaultValue: '', emptyValue: '');
      if (strValue.isNotEmpty && strValue != 'None') {
        items = strValue
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return items.isNotEmpty ? items.first : null;
  }

  void _updateStateWithPreferences(Map<String, dynamic> preferences) {
    if (!mounted) return;
    setState(() {
      dynamic rawRestrictions = preferences['food_restrictions'];
      dynamic rawCuisines = preferences['cuisine_preferences'];

      _userPreferences = {
        'goals': preferences['goals'] ?? 'N/A',
        'diet_type': preferences['diet_type'] ?? 'N/A',
        'food_restrictions': _listToString(rawRestrictions, emptyValue: 'None'),
        'cuisine_preferences':
            _listToString(rawCuisines, emptyValue: 'Not Set'),
      };

      if (!_isEditingPreferences) {
        _selectedGoal = _userPreferences['goals'] != 'N/A'
            ? _userPreferences['goals']
            : null;
        if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal))
          _selectedGoal = null;

        _selectedDietType = _userPreferences['diet_type'] != 'N/A'
            ? _userPreferences['diet_type']
            : null;
        if (_selectedDietType != null &&
            !_dietTypeOptions.contains(_selectedDietType))
          _selectedDietType = null;

        // For single-select dropdown, take the first restriction if available
        String? firstRestriction =
            _getFirstItemFromListOrString(rawRestrictions);
        // Check if the extracted first item is a valid option in our dropdown list
        _selectedFoodRestriction = (firstRestriction != null &&
                _foodRestrictionsOptions.contains(firstRestriction))
            ? firstRestriction
            // If no valid first item, check if the display string ended up as 'None'
            : (_userPreferences['food_restrictions'] == 'None' ? 'None' : null);

        // Final validity check: if selected value is not null AND not in options, reset to null
        if (_selectedFoodRestriction != null &&
            !_foodRestrictionsOptions.contains(_selectedFoodRestriction)) {
          _selectedFoodRestriction = null;
        }
      }
    });
  }

  // --- Image Handling ---
  Future<void> _pickImage() async {
    final imagePicker = ImagePicker();
    try {
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (pickedFile != null && mounted) {
        final imageFile = File(pickedFile.path);
        setState(() {
          _profileImagePath = imageFile.path; // Update local path for display
          _profileImageUrl = null; // Clear network URL
        });
        await _saveImageToPrefs(imageFile.path); // Save local path preference
        await _uploadProfilePicture(imageFile); // Attempt to upload
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackBar("Could not pick image: $e");
    }
  }

  Future<void> _uploadProfilePicture(File imageFile) async {
    if (_userId == null) {
      _showErrorSnackBar("Cannot upload image: User not identified.");
      return;
    }
    final imgurClientID = dotenv.env['IMGUR_CLIENT_ID'] ?? '';
    if (imgurClientID.isEmpty) {
      _showErrorSnackBar(
          'Image upload configuration missing (Imgur Client ID).');
      return;
    }

    final String imgurUploadUrl = 'https://api.imgur.com/3/image';
    // Optional: Show an upload indicator
    // setState(() { _isUploadingImage = true; });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(imgurUploadUrl));
      request.headers['Authorization'] = 'Client-ID $imgurClientID';
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));

      final response =
          await request.send().timeout(const Duration(seconds: 30));
      final responseData = await http.Response.fromStream(response);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(responseData.body);
        if (jsonResponse['success'] == true &&
            jsonResponse['data']?['link'] != null) {
          final newImageUrl = jsonResponse['data']['link'];
          print("Imgur upload successful: $newImageUrl");

          // Update backend with this new Imgur URL
          // IMPORTANT: Verify this endpoint is correct for your API (might be /rr/rusers/)
          final backendUpdateUrl = '$apiBaseUrl/rr/users/$_userId';
          final updateBody = json.encode({'image': newImageUrl});

          final backendResponse = await http
              .patch(
                Uri.parse(backendUpdateUrl),
                headers: {'Content-Type': 'application/json'},
                body: updateBody,
              )
              .timeout(const Duration(seconds: 15));

          if (mounted) {
            if (backendResponse.statusCode == 200 ||
                backendResponse.statusCode == 204) {
              _showSuccessSnackBar('Profile picture updated successfully!');
              setState(() {
                _profileImageUrl = newImageUrl;
                _userDetails['image'] = newImageUrl; // Update local data
              });
              await UserCache.removeData(
                  'user_details_cache'); // Invalidate cache
            } else {
              print(
                  "Backend update failed: ${backendResponse.statusCode} - ${backendResponse.body}");
              _showErrorSnackBar(
                  'Failed to save new profile picture URL to backend.');
              // Optional: Revert UI change if backend update fails
              // setState(() { _profileImagePath = null; _profileImageUrl = _userDetails['profile_picture']; });
            }
          }
        } else {
          throw Exception('Imgur upload failed: Invalid response structure.');
        }
      } else {
        print('Imgur upload failed: ${responseData.body}');
        throw Exception(
            'Failed to upload image to Imgur. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      print("Error uploading profile picture: $e");
      if (mounted) _showErrorSnackBar('Error uploading profile picture: $e');
      // Optional: Revert UI change
      // setState(() { _profileImagePath = null; _profileImageUrl = _userDetails['profile_picture']; });
    } finally {
      // if (mounted) setState(() { _isUploadingImage = false; });
    }
  }

  Future<void> _saveImageToPrefs(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('image_path', imagePath);
  }

  Future<void> _loadImageFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      _profileImagePath = prefs.getString('image_path');
      // No setState needed here, display logic handles null
    }
  }

  // --- Editing Save/Cancel Logic ---
  Future<void> _saveEditedData() async {
    if (_userId == null) {
      _showErrorSnackBar('Cannot save data. User not identified.');
      return;
    }

    Map<String, dynamic> dataToUpdate = {};
    String endpointPath = '';
    String cacheKeyToInvalidate = '';
    String successMessage = 'Profile updated successfully!';
    String sectionBeingSaved = ''; // For re-fetching logic

    if (_isEditingUserDetails) {
      sectionBeingSaved = 'details';
      endpointPath = '/rr/users/$_userId'; // CHECK THIS ENDPOINT
      cacheKeyToInvalidate = 'user_details_cache';
      dataToUpdate = {
        'name': _userDetailsNameController.text.trim(),
        'email': _userDetailsEmailController.text.trim(),
        'phone_number': _userDetailsPhoneController.text.trim(),
        'location': _userDetailsLocationController.text.trim(),
      };
      // Optimistic UI update
      setState(() {
        _userDetails['Name'] = dataToUpdate['name'];
        _userDetails['Email'] = dataToUpdate['email'];
        _userDetails['Phone_Number'] = dataToUpdate['phone_number'];
        _userDetails['Location'] = dataToUpdate['location'];
        _isEditingUserDetails = false;
      });
    } else if (_isEditingMetrics) {
      sectionBeingSaved = 'metrics';
      endpointPath = '/rr/metrics/$_userId';
      successMessage = 'Health metrics updated successfully!';
      _parseAndUpdateWeight();
      _parseAndUpdateHeight();

      dataToUpdate = {
        'age_range': _selectedAgeRange,
        'sex': _selectedSex,
        'weight': _weightKg > 0 ? _weightKg : null,
        'height': _heightCm > 0 ? _heightCm : null,
        'activity_level': _selectedActivityLevel,
      };
      dataToUpdate.removeWhere((key, value) => value == null);

      // Optimistic UI update
      setState(() {
        _userMetrics['age_range'] = _selectedAgeRange ?? 'N/A';
        _userMetrics['sex'] = _selectedSex ?? 'N/A';
        _userMetrics['weight'] =
            _weightKg > 0 ? _weightKg.toStringAsFixed(1) : 'N/A';
        _userMetrics['height'] =
            _heightCm > 0 ? _heightCm.toStringAsFixed(1) : 'N/A';
        _userMetrics['activity_level'] = _selectedActivityLevel ?? 'N/A';
        _userMetrics['bmi'] = _calculateBmi(_heightCm, _weightKg);
        _isEditingMetrics = false;
      });
    } else if (_isEditingPreferences) {
      sectionBeingSaved = 'preferences';
      endpointPath = '/rr/preferences/$_userId';
      successMessage = 'Preferences updated successfully!';
      List<String> restrictionsToSend = [];
      if (_selectedFoodRestriction != null &&
          _selectedFoodRestriction != 'None') {
        restrictionsToSend.add(_selectedFoodRestriction!);
      }

      dataToUpdate = {
        'goals': _selectedGoal,
        'diet_type': _selectedDietType,
        'food_restrictions': restrictionsToSend, // Send as list
      };
      dataToUpdate.removeWhere((key, value) => value == null);

      // Optimistic UI update
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

    // --- API Call ---
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
          }
          // Re-fetch the specific data that was just updated
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        } else {
          print(
              "Failed to update profile section. Status: ${response.statusCode}, Body: ${response.body}");
          _showErrorSnackBar(
              'Failed to update. Server error: ${response.statusCode}');
          // Attempt to re-fetch data on failure to revert optimistic changes
          if (sectionBeingSaved == 'details') await _fetchUserDetails();
          if (sectionBeingSaved == 'metrics') await _fetchMetrics();
          if (sectionBeingSaved == 'preferences') await _fetchPreferences();
        }
      } on TimeoutException {
        if (mounted)
          _showErrorSnackBar('Failed to save: Connection timed out.');
        // Attempt to re-fetch data on failure
        if (sectionBeingSaved == 'details') await _fetchUserDetails();
        if (sectionBeingSaved == 'metrics') await _fetchMetrics();
        if (sectionBeingSaved == 'preferences') await _fetchPreferences();
      } catch (e) {
        print("Error saving profile data: $e");
        if (mounted) _showErrorSnackBar('An error occurred while saving: $e');
        // Attempt to re-fetch data on failure
        if (sectionBeingSaved == 'details') await _fetchUserDetails();
        if (sectionBeingSaved == 'metrics') await _fetchMetrics();
        if (sectionBeingSaved == 'preferences') await _fetchPreferences();
      }
    } else {
      if (endpointPath.isEmpty)
        print("No valid endpoint path determined for saving.");
      if (dataToUpdate.isEmpty) {
        print("No changes detected to save.");
        // Reset editing flags even if nothing was sent
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

      // User Details reset
      if (_userDetails.isNotEmpty) {
        _userDetailsNameController.text = _userDetails['Name'] ?? '';
        _userDetailsEmailController.text = _userDetails['Email'] ?? '';
        _userDetailsPhoneController.text = _userDetails['Phone_Number'] ?? '';
        _userDetailsLocationController.text = _userDetails['Location'] ?? '';
      }

      // Metrics reset (rely on _updateStateWithMetrics having set the correct base state)
      if (_userMetrics.isNotEmpty) {
        double? currentWeightKg = _tryParseDouble(_userMetrics['weight']);
        double? currentHeightCm = _tryParseDouble(_userMetrics['height']);

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

        _weightKg = currentWeightKg ?? 0;
        _updateWeightControllerBasedOnUnit();
        _heightCm = currentHeightCm ?? 0;
        _updateHeightControllerBasedOnUnit();
      } else {
        _selectedAgeRange = null;
        _selectedSex = null;
        _selectedActivityLevel = null;
        _weightKg = 0;
        _updateWeightControllerBasedOnUnit();
        _heightCm = 0;
        _updateHeightControllerBasedOnUnit();
      }

      // Preferences reset (rely on _updateStateWithPreferences having set the correct base state)
      if (_userPreferences.isNotEmpty) {
        _selectedGoal = _userPreferences['goals'] != 'N/A'
            ? _userPreferences['goals']
            : null;
        if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal))
          _selectedGoal = null;
        _selectedDietType = _userPreferences['diet_type'] != 'N/A'
            ? _userPreferences['diet_type']
            : null;
        if (_selectedDietType != null &&
            !_dietTypeOptions.contains(_selectedDietType))
          _selectedDietType = null;

        // Use the logic from _updateStateWithPreferences to reset the single dropdown value
        String? firstRestriction = _getFirstItemFromListOrString(
            _userPreferences[
                'food_restrictions']); // Note: This uses the *processed* string
        _selectedFoodRestriction = (firstRestriction != null &&
                _foodRestrictionsOptions.contains(firstRestriction))
            ? firstRestriction
            : (_userPreferences['food_restrictions'] == 'None' ? 'None' : null);
        if (_selectedFoodRestriction != null &&
            !_foodRestrictionsOptions.contains(_selectedFoodRestriction)) {
          _selectedFoodRestriction = null;
        }
      } else {
        _selectedGoal = null;
        _selectedDietType = null;
        _selectedFoodRestriction = null;
      }
    });
  }

  // --- Weight/Height Unit Conversion and Update Logic ---
  void _onWeightInputChanged() {
    _parseAndUpdateWeight();
    // Optional: Live update BMI display during edit
    if (_isEditingMetrics && mounted) {
      setState(() {}); // Trigger rebuild to show updated calculated BMI
    }
  }

  void _parseAndUpdateWeight() {
    final String text = _weightController.text.trim();
    final double? value = double.tryParse(text);
    if (value != null && value >= 0) {
      // Allow 0
      if (_weightUnit == 'kg') {
        _weightKg = value;
      } else {
        // lbs
        _weightKg = value * 0.453592;
      }
    } else {
      _weightKg = 0; // Reset if empty or invalid
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
        // Allow 0
        _heightCm = value;
      } else {
        _heightCm = 0; // Reset if empty or invalid
      }
    } else {
      // ft/in
      final String feetText = _heightFeetController.text.trim();
      final String inchesText = _heightInchesController.text.trim();
      // Treat empty fields as 0
      final double feet =
          double.tryParse(feetText.isEmpty ? '0' : feetText) ?? 0;
      final double inches =
          double.tryParse(inchesText.isEmpty ? '0' : inchesText) ?? 0;

      if (feet >= 0 && inches >= 0) {
        // Ensure inches are handled correctly (e.g., don't allow >= 12 if desired, though parser accepts it)
        _heightCm = (feet * 30.48) + (inches * 2.54);
      } else {
        _heightCm = 0; // Reset if negative values somehow entered
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
      double lbs = _weightKg / 0.453592;
      _weightController.text = lbs > 0 ? lbs.toStringAsFixed(1) : '';
    }
  }

  void _updateHeightControllerBasedOnUnit() {
    if (!mounted) return;
    if (_heightUnit == 'cm') {
      _heightCmController.text =
          _heightCm > 0 ? _heightCm.toStringAsFixed(1) : '';
      if (_heightFeetController.text.isNotEmpty) _heightFeetController.clear();
      if (_heightInchesController.text.isNotEmpty)
        _heightInchesController.clear();
    } else {
      // ft
      if (_heightCm > 0) {
        double totalInches = _heightCm / 2.54;
        double feet = (totalInches ~/ 12).toDouble();
        double inches = (totalInches % 12);
        _heightFeetController.text = feet > 0 ? feet.toStringAsFixed(0) : '';
        _heightInchesController.text =
            inches > 0 ? inches.toStringAsFixed(1) : '';
      } else {
        if (_heightFeetController.text.isNotEmpty)
          _heightFeetController.clear();
        if (_heightInchesController.text.isNotEmpty)
          _heightInchesController.clear();
      }
      if (_heightCmController.text.isNotEmpty) _heightCmController.clear();
    }
  }

  void _updateWeightUnit(int index) {
    if (_weightSelection[index]) return; // No change if already selected
    _parseAndUpdateWeight(); // Store current value in _weightKg
    setState(() {
      _weightSelection = [false, false];
      _weightSelection[index] = true;
      _weightUnit = (index == 0) ? 'kg' : 'lbs';
      _updateWeightControllerBasedOnUnit(); // Update display
    });
  }

  void _updateHeightUnit(int index) {
    if (_heightSelection[index]) return; // No change
    _parseAndUpdateHeight(); // Store current value in _heightCm
    setState(() {
      _heightSelection = [false, false];
      _heightSelection[index] = true;
      _heightUnit = (index == 0) ? 'cm' : 'ft';
      _updateHeightControllerBasedOnUnit(); // Update display
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

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await UserCache.clearAllData(); // Clear specific cache
    await prefs.clear(); // Clear all SharedPreferences
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

  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
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
          // Display 'None' specially if needed, otherwise default toString()
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
    bool isInitialDataLoaded =
        !_isLoading && (_userDetails.isNotEmpty || _fetchError.isNotEmpty);

    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0,
        centerTitle: true,
        actions: [
          // Show Save/Cancel buttons in AppBar only when editing
          if (isEditingAnySection) ...[
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancel Changes',
              onPressed: _cancelEdit,
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_outlined), // Or Icons.check
              tooltip: 'Save Changes',
              onPressed: _saveEditedData, // Use the unified save function
            ),
          ] else ...[
            // Refresh button when not editing
            AnimatedBuilder(
              animation: _refreshIconController,
              builder: (context, child) {
                // Check if any section is currently fetching data
                bool isFetching = _isLoadingUserDetails ||
                    _isLoadingMetrics ||
                    _isLoadingPreferences ||
                    _refreshIconController.isAnimating;
                return IconButton(
                  icon: RotationTransition(
                    turns: _refreshIconController,
                    child: const Icon(Icons.refresh),
                  ),
                  tooltip: isFetching ? 'Refreshing...' : 'Refresh',
                  onPressed:
                      isFetching ? null : _fetchData, // Disable if fetching
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
        child: _isLoading &&
                !isInitialDataLoaded // Show shimmer only on initial full load
            ? _buildLoadingShimmer()
            : _fetchError.isNotEmpty &&
                    _userDetails.isEmpty // Show error only if *nothing* loaded
                ? _buildErrorState(_fetchError)
                : ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      _buildProfileHeader(),
                      const SizedBox(height: 24.0),

                      // --- Card Order ---
                      // 1. User Details Card (Always first)
                      _isLoadingUserDetails
                          ? _buildShimmerCard(
                              itemCount: 5) // Shimmer for user details
                          : _buildUserDetailsCard(),
                      const SizedBox(height: 16.0),

                      // 2. Metrics Card
                      _isLoadingMetrics
                          ? _buildShimmerCard(
                              itemCount:
                                  12) // Increased count for more metrics display
                          : _buildMetricsCard(),
                      const SizedBox(height: 16.0),

                      // 3. Preferences Card
                      _isLoadingPreferences
                          ? _buildShimmerCard(
                              itemCount: 4) // Shimmer for preferences
                          : _buildPreferencesCard(),
                      const SizedBox(height: 24.0),

                      // 4. Logout Button
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
          // Shimmer for Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CircleAvatar(radius: 60, backgroundColor: Colors.white),
              const SizedBox(height: 12),
              Container(height: 20, width: 150, color: Colors.white),
              const SizedBox(height: 8),
              Container(height: 16, width: 200, color: Colors.white),
            ],
          ),
          const SizedBox(height: 24.0),
          _buildShimmerCard(itemCount: 5), // User Details
          const SizedBox(height: 16.0),
          _buildShimmerCard(
              itemCount: 12), // Metrics (Adjust count based on displayed rows)
          const SizedBox(height: 16.0),
          _buildShimmerCard(itemCount: 4), // Preferences
        ],
      ),
    );
  }

  // Builds the outer card structure for shimmer
  Widget _buildShimmerCard({required int itemCount}) {
    return Card(
      elevation: 1.0,
      shadowColor: Colors.grey.shade200,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child:
            _buildShimmerCardContent(itemCount: itemCount, includeTitle: true),
      ),
    );
  }

  // Builds the inner content of a shimmer card (rows)
  Widget _buildShimmerCardContent(
      {required int itemCount, bool includeTitle = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (includeTitle) ...[
          Container(
              height: 20, width: 120, color: Colors.white), // Title Shimmer
          const SizedBox(height: 12),
          const Divider(color: kColorDivider, height: 1),
          const SizedBox(height: 12),
        ],
        ...List.generate(
            itemCount,
            (index) => Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 10.0), // Consistent padding
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 22, width: 22, color: Colors.white), // Icon
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 14,
                              width: 80,
                              color: Colors.white), // Label
                          const SizedBox(height: 6),
                          Container(
                              height: 16,
                              width: 120,
                              color: Colors.white), // Value/Input shimmer
                        ],
                      ))
                    ],
                  ),
                )),
      ],
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
              label: const Text("Retry"),
              onPressed: _fetchData, // Call fetch all data
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
    // Determine the best image source to display
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      displayImage = CachedNetworkImageProvider(_profileImageUrl!);
    } else if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        displayImage = FileImage(file);
      } else {
        // If local file doesn't exist (edge case), use default
        displayImage = const AssetImage('assets/images/proffr.png');
      }
    } else {
      // Default asset image if neither URL nor local path is available
      displayImage = const AssetImage('assets/images/proffr.png');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _pickImage, // Allow changing image anytime
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: kColorPrimaryLightest,
                backgroundImage: displayImage,
                onBackgroundImageError: (exception, stackTrace) {
                  print("Error loading profile image: $exception");
                  // Optionally force default image on error by clearing state
                  // setState(() { _profileImageUrl = null; _profileImagePath = null; });
                },
                child: displayImage ==
                            const AssetImage('assets/images/proffr.png') &&
                        _profileImageUrl == null &&
                        _profileImagePath == null
                    ? Icon(Icons.person,
                        size: 60,
                        color: kColorPrimary.withOpacity(
                            0.5)) // Placeholder icon only if default asset is used AND no other image is set
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: kColorPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 3)
                    ]),
                child: const Icon(Icons.edit,
                    size: 18, color: kColorTextOnPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _userDetails['Name'] ?? 'User Name',
          style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: kColorTextPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        if (_userDetails['Email'] != null && _userDetails['Email'] != 'N/A')
          Text(
            _userDetails['Email'] ?? '',
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
    // Determine if any section is currently being edited
    bool isAnyEditing =
        _isEditingUserDetails || _isEditingMetrics || _isEditingPreferences;

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
                // Show Edit button only if NOT editing this specific card AND no *other* card is being edited
                if (!isEditing && !isAnyEditing)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 22, color: kColorPrimary),
                    tooltip: "Edit $title",
                    onPressed: onEdit,
                    splashRadius: 24,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                // Indicate that this section IS being edited (subtle)
                if (isEditing)
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
            Column(children: children), // Content is always Column now
          ],
        ),
      ),
    );
  }

  String _formatJoinedDate(String? dateString) {
    if (dateString == null || dateString == 'N/A') return 'N/A';
    try {
      // Attempt to parse ISO 8601 format (common in APIs)
      final dateTime =
          DateTime.parse(dateString).toLocal(); // Convert to local time
      return DateFormat('MMM d, yyyy')
          .format(dateTime); // Format as "Jan 1, 2023"
    } catch (e) {
      print("Error parsing date '$dateString': $e");
      // Fallback: Try to return the original string if parsing fails
      return dateString;
    }
  }

  // --- Card Content Widgets ---

  Widget _buildUserDetailsCard() {
    return _buildStyledCard(
      title: 'User Details',
      isEditing: _isEditingUserDetails,
      onEdit: () {
        setState(() {
          _isEditingUserDetails = true;
          _isEditingMetrics = false;
          _isEditingPreferences = false;
          // Ensure controllers have the latest data before editing starts
          _userDetailsNameController.text = _userDetails['Name'] ?? '';
          _userDetailsEmailController.text = _userDetails['Email'] ?? '';
          _userDetailsPhoneController.text = _userDetails['Phone_Number'] ?? '';
          _userDetailsLocationController.text = _userDetails['Location'] ?? '';
        });
      },
      children: [
        _buildInfoRow(
          icon: Icons.badge_outlined,
          label: 'User ID',
          value: _userDetails['User_Id']?.toString() ?? 'N/A',
          isEditing: false,
        ),
        _buildInfoRow(
          icon: Icons.person_outline,
          label: 'Name',
          value: _userDetails['Name'] ?? 'N/A',
          isEditing: _isEditingUserDetails,
          controller: _userDetailsNameController,
        ),
        _buildInfoRow(
          icon: Icons.email_outlined,
          label: 'Email',
          value: _userDetails['Email'] ?? 'N/A',
          isEditing: _isEditingUserDetails,
          controller: _userDetailsEmailController,
          keyboardType: TextInputType.emailAddress,
        ),
        _buildInfoRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: _userDetails['Phone_Number'] ?? 'N/A',
          isEditing: _isEditingUserDetails,
          controller: _userDetailsPhoneController,
          keyboardType: TextInputType.phone,
        ),
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          label: 'Location',
          value: _userDetails['Location'] ?? 'N/A',
          isEditing: _isEditingUserDetails,
          controller: _userDetailsLocationController,
          maxLines: 2,
        ),
        _buildInfoRow(
          icon: Icons.calendar_today_outlined,
          label: 'Joined',
          value: _formatJoinedDate(_userDetails['Registration_Date']),
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
          // Initialize state from the _userMetrics map for editing
          double? currentWeightKg = _tryParseDouble(_userMetrics['weight']);
          double? currentHeightCm = _tryParseDouble(_userMetrics['height']);

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
          _weightKg = currentWeightKg ?? 0;
          _heightCm = currentHeightCm ?? 0;
          // Update controllers based on the stored kg/cm values and current unit selection
          _updateWeightControllerBasedOnUnit();
          _updateHeightControllerBasedOnUnit();
        });
      },
      children: _isEditingMetrics
          ? _buildMetricsEditingWidgets() // Show editing widgets
          : _buildMetricsDisplayWidgets(), // Show display widgets
    );
  }

  List<Widget> _buildMetricsDisplayWidgets() {
    String displayBmi = _userMetrics['bmi'] ?? 'N/A';

    return [
      _buildInfoRow(
        icon: Icons.height_outlined,
        label: 'Height',
        value: _userMetrics['height'] != 'N/A'
            ? '${_userMetrics['height']} cm'
            : 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.fitness_center_outlined,
        label: 'Weight',
        value: _userMetrics['weight'] != 'N/A'
            ? '${_userMetrics['weight']} kg'
            : 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.monitor_weight_outlined,
        label: 'BMI',
        value: displayBmi,
        isEditing: false,
      ),
      if (displayBmi != 'N/A') ...[
        const SizedBox(height: 8),
        _buildBmiVisualIndicator(double.tryParse(displayBmi)),
        const SizedBox(height: 8),
      ],
      _buildInfoRow(
        // Display BMI Category from API
        icon: Icons.accessibility_new_outlined,
        label: 'BMI Category',
        value: _userMetrics['bmi_category'] ?? 'N/A', isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.cake_outlined,
        label: 'Age Range',
        value: _userMetrics['age_range'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.wc_outlined,
        label: 'Sex',
        value: _userMetrics['sex'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.directions_run_outlined,
        label: 'Activity Level',
        value: _userMetrics['activity_level'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.opacity_outlined,
        label: 'Cholesterol',
        value: _userMetrics['cholesterol_level'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.favorite_border_outlined,
        label: 'Blood Pressure (Sys/Dia)',
        value:
            '${_userMetrics['sys_bp'] ?? 'N/A'} / ${_userMetrics['dia_bp'] ?? 'N/A'}',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.monitor_heart_outlined,
        label: 'Pulse',
        value: _userMetrics['pulse'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.scale_outlined,
        label: 'Ideal Weight (Est.)',
        value: _userMetrics['ideal_weight'] != 'N/A'
            ? '${_userMetrics['ideal_weight']} kg'
            : 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.local_fire_department_outlined,
        label: 'BMR (Est.)',
        value: _userMetrics['bmr'] != 'N/A'
            ? '${_userMetrics['bmr']} kcal'
            : 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.restaurant_outlined,
        label: 'Daily Calories (Est.)',
        value: _userMetrics['daily_calories'] != 'N/A'
            ? '${_userMetrics['daily_calories']} kcal'
            : 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.update_outlined,
        label: 'Last Recorded',
        value:
            _formatJoinedDate(_userMetrics['recorded_at']), // Format the date
        isEditing: false,
      ),
    ];
  }

  List<Widget> _buildMetricsEditingWidgets() {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Age Range',
          icon: Icons.cake_outlined,
          currentValue: _selectedAgeRange,
          options: _ageRanges,
          onChanged: (value) => setState(() => _selectedAgeRange = value),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Sex',
          icon: Icons.wc_outlined,
          currentValue: _selectedSex,
          options: _sexs,
          onChanged: (value) => setState(() => _selectedSex = value),
        ),
      ),
      _buildWeightInputRow(), // Combined input + unit toggle
      _buildHeightInputRow(), // Combined input + unit toggle
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Activity Level',
          icon: Icons.directions_run_outlined,
          currentValue: _selectedActivityLevel,
          options: _activityLevels,
          onChanged: (value) => setState(() => _selectedActivityLevel = value),
        ),
      ),
      Padding(
        // Display calculated BMI live
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: _buildInfoRow(
          icon: Icons.monitor_weight_outlined,
          label: 'BMI (Calculated)',
          value: _calculateBmi(
              _heightCm, _weightKg), // Calculate live based on inputs
          isEditing: false, // Always display, not editable
        ),
      ),
      // Optionally display other non-editable fields for context
      _buildInfoRow(
        icon: Icons.opacity_outlined,
        label: 'Cholesterol',
        value: _userMetrics['cholesterol_level'] ?? 'N/A',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.favorite_border_outlined,
        label: 'Blood Pressure (Sys/Dia)',
        value:
            '${_userMetrics['sys_bp'] ?? 'N/A'} / ${_userMetrics['dia_bp'] ?? 'N/A'}',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.monitor_heart_outlined,
        label: 'Pulse',
        value: _userMetrics['pulse'] ?? 'N/A',
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
          // Initialize selections from the userPreferences map
          _selectedGoal = _userPreferences['goals'] != 'N/A'
              ? _userPreferences['goals']
              : null;
          if (_selectedGoal != null && !_goalsOptions.contains(_selectedGoal))
            _selectedGoal = null;
          _selectedDietType = _userPreferences['diet_type'] != 'N/A'
              ? _userPreferences['diet_type']
              : null;
          if (_selectedDietType != null &&
              !_dietTypeOptions.contains(_selectedDietType))
            _selectedDietType = null;

          // Reset selection based on the *display* string in the map
          String currentRestrictionDisplay =
              _userPreferences['food_restrictions'] ?? 'N/A';
          if (currentRestrictionDisplay == 'None') {
            _selectedFoodRestriction = 'None';
          } else if (currentRestrictionDisplay != 'N/A') {
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
        value: _userPreferences['goals'] ?? 'Not Set',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.restaurant_menu_outlined,
        label: 'Diet Type',
        value: _userPreferences['diet_type'] ?? 'Not Set',
        isEditing: false,
      ),
      _buildInfoRow(
        icon: Icons.no_food_outlined, label: 'Restrictions',
        value: _userPreferences['food_restrictions'] ??
            'None', // Use processed string
        isEditing: false, maxLines: 3, // Allow wrapping
      ),
      _buildInfoRow(
        icon: Icons.ramen_dining_outlined, label: 'Cuisine Preferences',
        value: _userPreferences['cuisine_preferences'] ??
            'Not Set', // Use processed string
        isEditing: false, maxLines: 3, // Allow wrapping
      ),
      const SizedBox(height: 16),
      _buildMealRecommendationsButton(), // Button always visible
    ];
  }

  List<Widget> _buildPreferencesEditingWidgets() {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Goals',
          icon: Icons.flag_outlined,
          currentValue: _selectedGoal,
          options: _goalsOptions,
          onChanged: (value) => setState(() => _selectedGoal = value),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Diet Type',
          icon: Icons.restaurant_menu_outlined,
          currentValue: _selectedDietType,
          options: _dietTypeOptions,
          onChanged: (value) => setState(() => _selectedDietType = value),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: _buildDropdownField<String>(
          label: 'Food Restrictions', icon: Icons.no_food_outlined,
          currentValue: _selectedFoodRestriction,
          options: _foodRestrictionsOptions, // Includes 'None'
          onChanged: (value) =>
              setState(() => _selectedFoodRestriction = value),
        ),
      ),
      // Add inputs for other editable preferences like cuisine if needed
      const SizedBox(height: 16),
      _buildMealRecommendationsButton(), // Button visible during edit too
    ];
  }

  Widget _buildMealRecommendationsButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AllMealsScreen()),
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
        label: Text('Logout',
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
    required bool isEditing,
    TextEditingController? controller,
    TextInputType? keyboardType,
    int? maxLines = 1,
  }) {
    final labelStyle = GoogleFonts.poppins(
        fontWeight: FontWeight.w500, color: kColorTextSecondary, fontSize: 15);
    final valueStyle =
        GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.only(top: 4.0), // Adjust alignment slightly
            child: Icon(icon, color: kColorPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle), // Always show label
                const SizedBox(height: 4),
                // Show TextField if editing AND controller is provided, otherwise show Text
                isEditing && controller != null
                    ? _buildTextField(
                        // Use the general text field builder
                        controller: controller,
                        label: label, // Pass label for decoration
                        icon: icon, // Pass icon for decoration
                        keyboardType: keyboardType,
                        maxLines: maxLines,
                      )
                    : Text(
                        value.isEmpty ? 'N/A' : value,
                        style: valueStyle,
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align units toggle better
        children: [
          Expanded(
            child: TextFormField(
              controller: _weightController,
              decoration: _buildInputDecoration('Weight',
                  prefixIcon: Icons.fitness_center_outlined),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
              ], // Allow leading decimal point
              // onChanged handled by listener
              style:
                  GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding:
                const EdgeInsets.only(top: 8.0), // Adjust vertical alignment
            child: ToggleButtons(
              isSelected: _weightSelection,
              onPressed: _updateWeightUnit,
              borderRadius: BorderRadius.circular(8.0),
              selectedColor: Colors.white,
              color: kColorPrimary,
              fillColor: kColorPrimary,
              constraints:
                  const BoxConstraints(minHeight: 40.0, minWidth: 48.0),
              children: const <Widget>[
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('kg')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('lbs')),
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _heightUnit == 'cm'
                ? TextFormField(
                    // CM Input
                    controller: _heightCmController,
                    decoration: _buildInputDecoration('Height',
                        prefixIcon: Icons.height_outlined),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    style: GoogleFonts.poppins(
                        color: kColorTextPrimary, fontSize: 15),
                  )
                : Row(
                    // FT + IN Input Row
                    crossAxisAlignment:
                        CrossAxisAlignment.start, // Align fields vertically
                    children: [
                      // Add the icon only once, before the feet field
                      Padding(
                        padding: const EdgeInsets.only(
                            top: 12.0,
                            right: 8.0), // Align icon with input text
                        child: Icon(Icons.height_outlined,
                            color: kColorPrimary, size: 20),
                      ),
                      Expanded(
                        // Feet Input
                        child: TextFormField(
                          controller: _heightFeetController,
                          decoration: _buildInputDecoration('ft').copyWith(
                              prefixIcon: null), // Remove redundant icon
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
                        // Inches Input
                        child: TextFormField(
                          controller: _heightInchesController,
                          decoration: _buildInputDecoration('in').copyWith(
                              prefixIcon: null), // Remove redundant icon
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
            // Unit Toggle
            padding: const EdgeInsets.only(top: 8.0),
            child: ToggleButtons(
              isSelected: _heightSelection,
              onPressed: _updateHeightUnit,
              borderRadius: BorderRadius.circular(8.0),
              selectedColor: Colors.white,
              color: kColorPrimary,
              fillColor: kColorPrimary,
              constraints:
                  const BoxConstraints(minHeight: 40.0, minWidth: 48.0),
              children: const <Widget>[
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('cm')),
                Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ft')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // BMI Indicator
  Widget _buildBmiVisualIndicator([double? bmiValue]) {
    // Use value from state map if not provided
    bmiValue ??= _tryParseDouble(_userMetrics['bmi']);

    if (bmiValue == null ||
        bmiValue <= 0 ||
        bmiValue.isNaN ||
        bmiValue.isInfinite) {
      return const SizedBox.shrink(); // Don't show indicator for invalid BMI
    }

    const double underweightThreshold = 18.5;
    const double normalThreshold = 24.9;
    const double overweightThreshold = 29.9;

    Color barColor;
    String category;

    String apiCategory = _userMetrics['bmi_category'] ?? '';
    bool useApiCategory = apiCategory.isNotEmpty && apiCategory != 'N/A';

    if (bmiValue < underweightThreshold) {
      barColor = Colors.blue.shade300;
      category = useApiCategory ? apiCategory : 'Underweight';
    } else if (bmiValue < normalThreshold) {
      barColor = Colors.green.shade400;
      category = useApiCategory ? apiCategory : 'Normal';
    } else if (bmiValue < overweightThreshold) {
      barColor = Colors.orange.shade400;
      category = useApiCategory ? apiCategory : 'Overweight';
    } else {
      barColor = Colors.red.shade400;
      category = useApiCategory ? apiCategory : 'Obese';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          category, // Use determined category (API or calculated)
          style: GoogleFonts.poppins(
              fontSize: 12, color: barColor, fontWeight: FontWeight.w500),
        )
      ],
    );
  }
}

// --- Global Helper Functions ---
// Helper to safely parse double from dynamic input
double? _tryParseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value);
  }
  return null;
}
