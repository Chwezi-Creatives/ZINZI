//cspell:disable
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // For jsonDecode, jsonEncode
import 'package:http/http.dart' as http; // Import the http package
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import flutter_dotenv
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File handling
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'dart:async'; // For Timer
import 'package:geolocator/geolocator.dart';
import 'package:zinzi/user_cache.dart'; // Assuming this path is correct
import 'package:zinzi/cache_config.dart'; // Assuming this path is correct
import 'package:zinzi/utils/image_utils.dart'; // Assuming this path is correct
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle

// --- Consistent Color Palette (from chefsignup222.dart) ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color lighterTeal = Color(0xFFE0F2F1); // Teal 50
const Color darkTeal = Color(0xFF004D40); // Teal 900
const Color accentTeal = Color(0xFF009688); // Teal 500
const Color whiteColor = Colors.white; // Main background color
const Color textFieldFillColor =
    Color(0xFFF5F5F5); // Light grey fill for inputs on white BG
const Color subtleTextColor = Color(0xFF757575); // Grey 600
const Color errorColor = Color(0xFFD32F2F); // Red 700 for errors
const Color disabledColor = Colors.grey;
const Color readyForPickupColor =
    Colors.blueAccent; // Color for Ready for Pickup status
const Color assignedColor =
    Colors.deepPurpleAccent; // Color for Assigned status
const Color kColorWarning = Color(0xFFFFA000); // Warning color (Orange)

// --- Predefined value lists (for ProfileTab forms) ---
final List<String> responseTimes = [
  "Immediate",
  "1 Hour",
  "2 Hours",
  "4 Hours"
];
final List<String> teamSizes = ["1", "2", "3", "4", "5", "6+", "10+"];
final List<String> minNoticeOptions = [
  "1 hour notice",
  "1 day notice",
  "1 Week notice",
  "1 Month notice",
  "1 Quarter",
  "1 Year notice"
];
final List<String> allLanguages = [
  "English",
  "Runyankole",
  "Indian",
  "Rukiga",
  "Luganda",
  "Arabic",
  "Jewish",
  "Lusoga",
  "Lugbala",
  "Spanish",
  "French",
  "German",
  "Italian"
];
final List<String> allSpecialties = [
  "Barbeque",
  "Mixologists",
  "Baristers",
  "Pastry",
  "Ugandan",
  "Salads",
  "Juices",
  "Luwombo",
  "West African",
  "Ethiopian",
  "Eritrean",
  "Somali",
  "Congolese",
  "Thai",
  "Jewish",
  "Indian"
];
final List<String> allCertifications = [
  "None",
  "Food handling & Safety",
  "Culinary Arts",
  "Nutrition",
  "Pastry"
];
final List<String> allEquipment = [
  "None",
  "Plates",
  "Cups",
  "Grill",
  "Oven",
  "Measuring cups",
  "Tables",
  "Dishes",
  "Knife Set",
  "Cutting Board"
];
final List<String> allAvailability = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday"
];
final List<String> perGigCategories = [
  '5 people',
  '10 people',
  '20+ people',
  '50+ people',
  '100+ people'
];
final Map<String, String> perGigCategoryKeys = {
  '5 people': '5_people',
  '10 people': '10_people',
  '20+ people': '20_plus_people',
  '50+ people': '50_plus_people',
  '100+ people': '100_plus_people'
};

String get _apibaseurl {
  try {
    return dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';
  } catch (e) {
    print(
        "Error accessing dotenv for API_BASE_URL-intranet. Ensure dotenv.load() was called. Using fallback. Error: $e");
    return 'https://api.example.com';
  }
}

class ChefProfile {
  final int chefid;
  String name;
  String? bio;
  String? image; // URL
  String? availability; // Comma-separated String
  String? certifications; // Comma-separated String
  final String chefType;
  int? experience;
  String? languages; // Comma-separated String
  String? location;
  String? minNotice;
  String? price;
  String? responseTime;
  String? sampleMenu; // Comma-separated String URLs
  String? specialties; // Comma-separated String
  String? teamSize;
  bool isActive;
  bool isEmailVerified;
  String? equipment; // Comma-separated String
  File? localImageFile; // For local image editing
  Map<String, dynamic>? pricing;

  ChefProfile({
    required this.chefid,
    required this.name,
    this.bio,
    this.image,
    this.availability,
    this.certifications,
    required this.chefType,
    this.experience,
    this.languages,
    this.location,
    this.minNotice,
    this.price,
    this.responseTime,
    this.sampleMenu,
    this.specialties,
    this.teamSize,
    required this.isActive,
    this.isEmailVerified = false,
    this.equipment,
    this.pricing,
    this.localImageFile,
  });

  // ========== FIXED SECTION ==========
  factory ChefProfile.fromMockJson(Map<String, dynamic> json) {
    String? _joinListSafe(dynamic listData) {
      if (listData is List) {
        return listData
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(', ');
      } else if (listData is String) {
        return listData;
      }
      return null;
    }

    String? _getStringSafe(dynamic value) {
      return value?.toString();
    }

    int? _parseIntNullable(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    int _parseIntSafe(dynamic value) {
      return _parseIntNullable(value) ?? 0;
    }

    bool _parseBoolSafe(dynamic value) {
      if (value is bool) return value;
      if (value == null) return false;
      return (value.toString().toLowerCase() == 'true' || value == 1);
    }

    bool _isValidUrl(String? url) {
      if (url == null || url.isEmpty) return false;
      try {
        final uri = Uri.parse(url);
        return uri.isScheme('HTTP') || uri.isScheme('HTTPS');
      } catch (_) {
        return false;
      }
    }

    return ChefProfile(
      chefid: _parseIntSafe(json['chefid']),
      name: _getStringSafe(json['name']) ?? 'N/A',
      bio: _getStringSafe(json['bio']),
      image: _isValidUrl(_getStringSafe(json['image']))
          ? _getStringSafe(json['image'])
          : null,
      availability: _joinListSafe(json['availability']),
      certifications: _joinListSafe(json['certifications']),
      chefType: _getStringSafe(json['chef_type']) ?? 'Individual',
      experience: _parseIntNullable(json['experience']),
      languages: _joinListSafe(json['languages']),
      location: _getStringSafe(json['location']),
      minNotice: _getStringSafe(json['minnotice']),
      price: _getStringSafe(json['price']),
      responseTime: _getStringSafe(json['responsetime']),
      sampleMenu: _getStringSafe(json['samplemenu']),
      specialties: _joinListSafe(json['specialties']),
      teamSize: _getStringSafe(json['teamsize']),
      isActive: _parseBoolSafe(json['is_active']),
      isEmailVerified: _parseBoolSafe(json['is_email_verified']), // Correctly parsed and passed here
      equipment: _joinListSafe(json['equipment']),
      pricing: json['pricing'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['pricing'])
          : null,
    );
  }
  // ========== END OF FIXED SECTION ==========

  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'bio': bio,
      'availability': availability,
      'certifications': certifications,
      'chef_type': chefType,
      'experience': experience,
      'languages': languages,
      'location': location,
      'minnotice': minNotice,
      'price': price,
      'responsetime': responseTime,
      'specialties': specialties,
      'teamsize': teamSize,
      'equipment': equipment,
      'pricing': pricing,
      'is_active': isActive,
    }..removeWhere((key, value) => value == null);
  }

  Map<String, dynamic> toJsonForCache() {
    return {
      'chefid': chefid,
      'name': name,
      'bio': bio,
      'image': image,
      'availability': availability,
      'certifications': certifications,
      'chef_type': chefType,
      'experience': experience,
      'languages': languages,
      'location': location,
      'minnotice': minNotice,
      'price': price,
      'responsetime': responseTime,
      'samplemenu': sampleMenu,
      'specialties': specialties,
      'teamsize': teamSize,
      'is_active': isActive,
      'is_email_verified': isEmailVerified,
      'equipment': equipment,
      'pricing': pricing,
    }..removeWhere((key, value) => value == null && key != 'is_email_verified');
  }
}

class ApiService {
  final String _baseUrl = _apibaseurl;
  static String get _staticBaseUrl => _apibaseurl;

  ApiService();

  static Future<String?> _getChefId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('chef_user_id');
    } catch (e) {
      print("Error accessing SharedPreferences for chef_id: $e");
      return null;
    }
  }

  static dynamic _handleApiResponse(dynamic responseData) {
    if (responseData is List) {
      return responseData;
    } else if (responseData is Map && responseData.containsKey('data')) {
      if (responseData['data'] is List) {
        return responseData['data'];
      } else if (responseData['data'] is Map) {
        return responseData['data'];
      } else {
        print("API Warning: Response has 'data' key but value is not a List or Map.");
        return responseData['data'];
      }
    } else if (responseData is Map && responseData.containsKey('All_Meals')) {
      if (responseData['All_Meals'] is List) {
        return responseData['All_Meals'];
      } else {
        print("API Warning: Response has 'All_Meals' key but value is not a List.");
        return null;
      }
    } else if (responseData is Map && responseData.isNotEmpty) {
      return responseData;
    }
    print("API Warning: Unhandled response format. Expected List or Map. Got: ${responseData.runtimeType}");
    return null;
  }

  Future<ChefProfile> fetchChefProfile() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$_baseUrl/rr/rchefs/$chefId');
    print("Fetching profile from: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 23));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        if (handledData == null) {
          if (rawData is List && rawData.isEmpty) throw Exception('Failed to parse profile: API returned an empty list.');
          if (rawData is Map && rawData.isEmpty) throw Exception('Failed to parse profile: API returned an empty map.');
          throw Exception('Failed to parse profile: Unexpected API response format after handling.');
        }

        Map<String, dynamic> profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception('Failed to parse profile: Expected a map inside the list.');
          }
        } else if (handledData is Map<String, dynamic>) {
          if (handledData.containsKey('chefid')) {
            profileMap = handledData;
          } else {
            throw Exception('Failed to parse profile: Result map does not contain expected keys.');
          }
        } else {
          throw Exception('Failed to parse profile: Result is not a usable Map or List. Type: ${handledData.runtimeType}');
        }
        return ChefProfile.fromMockJson(profileMap);
      } else {
        print("Error fetching profile: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load chef profile (Status code: ${response.statusCode})');
      }
    } on TimeoutException {
      print("Timeout fetching profile for chef $chefId");
      throw Exception('Failed to load chef profile: Request timed out.');
    } catch (e) {
      print("Exception fetching profile: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load chef profile: $e');
    }
  }

  Future<bool> updateChefProfile(int chefId, Map<String, dynamic> profileData) async {
    final Uri uri = Uri.parse('$_baseUrl/rr/chefs/$chefId');
    print("Updating profile for chef $chefId at: $uri with data: ${jsonEncode(profileData)}");

    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(profileData),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200 || response.statusCode == 204) {
        print("Profile update successful for chef $chefId");
        return true;
      } else {
        print("Error updating chef profile for $chefId: ${response.statusCode} ${response.body}");
        return false;
      }
    } on TimeoutException {
      print("Timeout updating profile for chef $chefId");
      return false;
    } catch (e) {
      print("Exception updating chef profile: $e");
      return false;
    }
  }

  Future<String?> updateChefProfileImage(int chefId, File imageFile) async {
    try {
      final imgurUrl = await uploadImageToImgur(imageFile);
      if (imgurUrl == null) {
        print('Failed to upload image to Imgur.');
        return null;
      }
      final Uri uri = Uri.parse('$_baseUrl/rr/chefs/$chefId');
      final Map<String, dynamic> payload = {'image': imgurUrl};
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200 || response.statusCode == 204) {
        print('Profile image updated successfully with Imgur link.');
        return imgurUrl;
      } else {
        print('Failed to update chef profile with Imgur link: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error in updateChefProfileImage: $e');
      return null;
    }
  }

  Future<String?> uploadImageToImgur(File imageFile) async {
    final String? imgurClientId = dotenv.env['IMGUR_CLIENT_ID'];
    if (imgurClientId == null || imgurClientId.isEmpty) {
      print('Imgur Client ID missing in .env');
      return null;
    }
    try {
      final Uri imgurUri = Uri.parse('https://api.imgur.com/3/image');
      var request = http.MultipartRequest('POST', imgurUri);
      request.headers['Authorization'] = 'Client-ID $imgurClientId';
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData is Map &&
            responseData.containsKey('data') &&
            responseData['data'] is Map &&
            responseData['data'].containsKey('link')) {
          return responseData['data']['link'] as String?;
        } else {
          print('Imgur upload succeeded but link not found in response.');
          return null;
        }
      } else {
        print('Imgur upload failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Imgur upload error: $e');
      return null;
    }
  }

  static Map<String, String> _getWriteHeaders({bool requiresAuth = false}) {
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    return headers;
  }

  static Future<bool> updateProfileStatus(int chefId, bool isActive) async {
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/chefs/$chefId/status');
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(<String, bool>{'is_active': isActive}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print("Error updating profile status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating profile status: $e");
      return false;
    }
  }
}

class CachedImageWithShimmer extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;
  final double iconSize;
  final String? errorText;
  final File? localFile;

  const CachedImageWithShimmer({
    super.key,
    this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
    this.errorIcon = Icons.image_not_supported_outlined,
    this.iconSize = 35,
    this.errorText,
    this.localFile,
  });

  String? _getDirectImageLink(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    return ImageUtils.processImageUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;

    Widget imageWidget;

    if (localFile != null) {
      imageWidget = Image.file(
        localFile!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          print("Error loading local file: ${localFile!.path} - $error");
          return _buildErrorWidget(context, shimmerBase, shimmerHighlight,
              isLocalFileError: true);
        },
      );
    } else {
      final String? processedUrl = _getDirectImageLink(imageUrl);
      if (processedUrl == null || processedUrl.isEmpty) {
        imageWidget = _buildErrorWidget(context, shimmerBase, shimmerHighlight);
      } else {
        imageWidget = CachedNetworkImage(
            imageUrl: processedUrl,
            width: width,
            height: height,
            fit: fit,
            placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: shimmerBase,
                  highlightColor: shimmerHighlight,
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                ),
            errorWidget: (context, url, error) {
              print("CachedNetworkImage Error: Failed to load $url - $error");
              return _buildErrorWidget(context, shimmerBase, shimmerHighlight);
            });
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  Widget _buildErrorWidget(
      BuildContext context, Color baseColor, Color highlightColor,
      {bool isLocalFileError = false}) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(errorIcon, color: Colors.grey.shade500, size: iconSize),
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                isLocalFileError ? "Error Loading File" : errorText!,
                style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          ]
        ],
      ),
    );
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

extension ProfileTabRefreshExtension on _ProfileTabState {
  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    print("ProfileTab: manualRefreshFromAppBar triggered.");
    await _refreshProfile(); 
    print("ProfileTab: manualRefreshFromAppBar completed.");
  }
}

class _ProfileTabState extends State<ProfileTab> with AutomaticKeepAliveClientMixin {
  static ChefProfile? _profileCache;
  static DateTime? _profileCacheTimestamp;
  static const String _profileCacheKey = 'chef_profile_cache_v2';
  static const String _profileCacheTimestampKey = 'chef_profile_cache_timestamp_v2';

  static Future<void> _loadProfileCacheFromPrefs() async {
    try {
      final cachedData = await UserCache.getData(_profileCacheKey);
      final timestampData = await UserCache.getData(_profileCacheTimestampKey);

      if (cachedData is Map<String, dynamic> && timestampData is String) {
        try {
          _profileCache = ChefProfile.fromMockJson(cachedData);
          _profileCacheTimestamp = DateTime.tryParse(timestampData);
          if (_profileCacheTimestamp == null) {
            print("ProfileTab: Failed to parse cached timestamp. Clearing cache.");
            _profileCache = null;
            await UserCache.removeData(_profileCacheKey);
            await UserCache.removeData(_profileCacheTimestampKey);
          } else {
            print("ProfileTab: Loaded profile from cache.");
          }
        } catch (e) {
          print("Error parsing cached profile data: $e. Clearing cache.");
          _profileCache = null;
          _profileCacheTimestamp = null;
          await UserCache.removeData(_profileCacheKey);
          await UserCache.removeData(_profileCacheTimestampKey);
        }
      } else {
        _profileCache = null;
        _profileCacheTimestamp = null;
        print("ProfileTab: No valid profile cache found in prefs.");
      }
    } catch (e) {
      print("Error loading profile cache from UserCache: $e");
      _profileCache = null;
      _profileCacheTimestamp = null;
    }
  }

  static Future<void> _saveProfileCacheToPrefs(ChefProfile profile) async {
    try {
      Map<String, dynamic> cacheableProfile = profile.toJsonForCache();
      await UserCache.saveData(_profileCacheKey, cacheableProfile);
      final now = DateTime.now();
      await UserCache.saveData(_profileCacheTimestampKey, now.toIso8601String());

      _profileCache = profile;
      _profileCacheTimestamp = now;
      print("ProfileTab: Saved profile to cache.");
    } catch (e) {
      print("Error saving profile cache to UserCache: $e");
    }
  }

  Future<ChefProfile?>? _profileFuture;
  ChefProfile? _currentProfile;
  bool _isLoadingProfile = true;
  String _fetchError = '';
  bool _isLoadingStatus = false;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _didLoadProfile = false;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _experienceController;
  late TextEditingController _locationController;
  late TextEditingController _priceController;

  String? _selectedResponseTime;
  String? _selectedTeamSize;
  String? _selectedMinNotice;
  List<String> _selectedLanguages = [];
  List<String> _selectedSpecialties = [];
  List<String> _selectedCertifications = [];
  List<String> _selectedEquipment = [];
  List<String> _selectedAvailability = [];

  bool _isFetchingLocation = false;
  Timer? _locationHintTimer;
  int _locationHintDots = 0;

  late TextEditingController _monthlyPriceController;
  late Map<String, TextEditingController> _perGigPriceControllers;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _bioController = TextEditingController();
    _experienceController = TextEditingController();
    _locationController = TextEditingController();
    _priceController = TextEditingController();
    _monthlyPriceController = TextEditingController();
    _perGigPriceControllers = {
      for (var key in perGigCategoryKeys.values) key: TextEditingController()
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadProfile) {
      _didLoadProfile = true;
      _initializeProfileData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _monthlyPriceController.dispose();
    _perGigPriceControllers.values.forEach((controller) => controller.dispose());
    _locationHintTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeProfileData() async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true;
        _fetchError = '';
        _isEditing = false;
        _isSaving = false;
      });
    }

    await _loadProfileCacheFromPrefs();

    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) < CacheConfig.profileCacheDuration;

      if (cacheIsValid) {
        print("ProfileTab: Displaying valid cached profile.");
        setState(() {
          _currentProfile = _profileCache;
          if (_currentProfile != null) _updateControllersFromProfile(_currentProfile!);
          _isLoadingProfile = false;
          _profileFuture = Future.value(_currentProfile);
        });
      } else {
        print("ProfileTab: Cached profile expired or timestamp missing.");
        setState(() {
          _currentProfile = _profileCache; 
          if (_currentProfile != null) _updateControllersFromProfile(_currentProfile!);
          _isLoadingProfile = true; 
          _profileFuture = Future.value(_currentProfile); 
        });
        await _fetchProfileAndUpdate(); 
      }
    } else if (mounted) {
      print("ProfileTab: No cached profile found, fetching...");
      setState(() {
        _isLoadingProfile = true;
        _profileFuture = null;
      });
      await _fetchProfileAndUpdate();
    }
  }

  Future<void> _fetchProfileAndUpdate() async {
    if (_profileFuture != null && _isLoadingProfile && _currentProfile != null) {
      print("ProfileTab: Background fetch already in progress or future assigned.");
      return;
    }

    final apiService = ApiService();
    final fetchFuture = apiService.fetchChefProfile();
    if (mounted) {
      setState(() {
        _profileFuture = fetchFuture.then((profile) => profile).catchError((_) => null);
        if (_currentProfile == null) _isLoadingProfile = true;
      });
    }

    try {
      final profile = await fetchFuture;
      if (mounted) {
        print("ProfileTab: Fetched fresh profile data successfully.");
        await _saveProfileCacheToPrefs(profile);
        setState(() {
          _currentProfile = profile;
          _updateControllersFromProfile(profile);
          _isLoadingProfile = false;
          _fetchError = '';
        });
      }
    } catch (error, stackTrace) {
      print("Error fetching fresh profile: $error\n$stackTrace");
      if (mounted) {
        final errorMsg = 'Failed to load profile: ${error.toString()}';
        if (_currentProfile == null) {
          setState(() {
            _fetchError = errorMsg;
            _isLoadingProfile = false;
          });
          _showErrorSnackbar(errorMsg);
        } else {
          _showInfoSnackbar("Couldn't update profile, showing last known data.");
          setState(() {
            _isLoadingProfile = false; 
            _fetchError = ''; 
          });
        }
      }
    }
  }

  Future<void> _refreshProfile() async {
    if (mounted) {
      setState(() {
        _isEditing = false;
        _isSaving = false;
        _currentProfile?.localImageFile = null;
        _isLoadingProfile = true;
        _fetchError = '';
      });
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    await _fetchProfileAndUpdate();
  }

  List<String> _parseAndFilterList(String? commaSeparatedString, List<String> allowedValues) {
    if (commaSeparatedString == null || commaSeparatedString.trim().isEmpty) return [];
    final Set<String> allowedSet = Set.from(allowedValues);
    return commaSeparatedString
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && allowedSet.contains(item))
        .toList();
  }

  String? _validateSingleSelection(String? value, List<String> allowedValues) {
    return (value != null && allowedValues.contains(value)) ? value : null;
  }

  void _updateControllersFromProfile(ChefProfile profile) {
    _nameController.text = profile.name;
    _bioController.text = profile.bio ?? '';
    _experienceController.text = profile.experience?.toString() ?? '';
    _locationController.text = profile.location ?? '';
    _priceController.text = profile.price ?? '';

    _selectedResponseTime = _validateSingleSelection(profile.responseTime, responseTimes);
    _selectedTeamSize = _validateSingleSelection(profile.teamSize, teamSizes);
    _selectedMinNotice = _validateSingleSelection(profile.minNotice, minNoticeOptions);

    _selectedSpecialties = _parseAndFilterList(profile.specialties, allSpecialties);
    _selectedLanguages = _parseAndFilterList(profile.languages, allLanguages);
    _selectedEquipment = _parseAndFilterList(profile.equipment, allEquipment);
    _selectedAvailability = _parseAndFilterList(profile.availability, allAvailability);
    _selectedCertifications = _parseAndFilterList(profile.certifications, allCertifications);
    
    profile.localImageFile = null;
  }

  void _updateProfileFromControllers() {
    if (_currentProfile == null) return;
    _currentProfile!.name = _nameController.text.trim();
    _currentProfile!.bio = _bioController.text.trim().isEmpty ? null : _bioController.text.trim();
    _currentProfile!.experience = int.tryParse(_experienceController.text.trim());
    _currentProfile!.location = _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
    _currentProfile!.price = _priceController.text.trim().isEmpty ? null : _priceController.text.trim();

    _currentProfile!.responseTime = _selectedResponseTime;
    _currentProfile!.teamSize = _selectedTeamSize;
    _currentProfile!.minNotice = _selectedMinNotice;
    _currentProfile!.specialties = _selectedSpecialties.isEmpty ? null : _selectedSpecialties.join(',');
    _currentProfile!.languages = _selectedLanguages.isEmpty ? null : _selectedLanguages.join(',');
    _currentProfile!.equipment = _selectedEquipment.isEmpty ? null : _selectedEquipment.join(',');
    _currentProfile!.availability = _selectedAvailability.isEmpty ? null : _selectedAvailability.join(',');
    _currentProfile!.certifications = _selectedCertifications.isEmpty ? null : _selectedCertifications.join(',');
  }

  void _startLocationHintAnimation() {
    _locationHintTimer?.cancel();
    _locationHintDots = 0;
    _locationHintTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted || !_isFetchingLocation) {
        timer.cancel();
        if (mounted && !_isFetchingLocation) setState(() => _locationHintDots = 0);
        return;
      }
      if (mounted) setState(() => _locationHintDots = (_locationHintDots + 1) % 4);
    });
  }

  void _stopLocationHintAnimation() {
    _locationHintTimer?.cancel();
    if (mounted) setState(() => _locationHintDots = 0);
  }

  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return;
    if (mounted) {
      setState(() {
        _isFetchingLocation = true;
        _locationController.clear();
      });
      _startLocationHintAnimation();
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Location permissions permanently denied.');

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 15));

      String displayAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      String coords = "${position.latitude},${position.longitude}";

      try {
        final String apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
          if (mounted) _showInfoSnackbar('Could not fetch address. Using coordinates.');
        }
      } catch (e) {
        if (mounted) _showInfoSnackbar('Could not fetch address. Using coordinates.');
      }

      if (mounted) {
        setState(() {
          _locationController.text = (displayAddress.isNotEmpty && !displayAddress.startsWith("Lat:"))
              ? "$displayAddress ($coords)"
              : "Location Acquired ($coords)";
        });
        _showSuccessSnackbar('Location acquired!');
      }
    } on TimeoutException catch (_) {
      if (mounted) _showErrorSnackbar('Getting location timed out.');
    } catch (e) {
      if (mounted) _showErrorSnackbar('Error getting location: ${e.toString()}');
    } finally {
      if (mounted) {
        _stopLocationHintAnimation();
        setState(() {
          _isFetchingLocation = false;
          if (_locationController.text.isEmpty) _locationController.text = 'Failed to get location';
        });
      }
    }
  }

  Future<void> _toggleActiveStatus(bool newValue) async {
    if (_currentProfile == null || _isLoadingStatus || _isEditing) return;
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _isLoadingStatus = true);

    final originalStatus = _currentProfile!.isActive;
    setState(() => _currentProfile!.isActive = newValue); 

    try {
      bool success = await ApiService.updateProfileStatus(_currentProfile!.chefid, newValue);
      if (mounted) {
        if (!success) {
          setState(() => _currentProfile!.isActive = originalStatus); 
          _showErrorSnackbar('Failed to update status.');
        } else {
          _showSuccessSnackbar('Status updated.');
          await _saveProfileCacheToPrefs(_currentProfile!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentProfile!.isActive = originalStatus); 
        _showErrorSnackbar('Error updating status.');
      }
    } finally {
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _pickImage() async {
    if (!_isEditing || _isSaving || _currentProfile == null) return;

    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        if (mounted) {
          setState(() {
            _currentProfile!.localImageFile = File(pickedFile.path);
          });
        }
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackbar("Could not pick image: ${e.toString()}");
    }
  }

 Future<void> _saveProfileChanges() async {
    if (_currentProfile == null || !_isEditing || _isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showErrorSnackbar('Please fix errors before saving.');
      return;
    }
    _formKey.currentState!.save();
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _isSaving = true);

    _updateProfileFromControllers(); 

    bool textFieldsUpdateSuccess = false;
    String? newImageUrl;

    try {
      if (_currentProfile!.localImageFile != null) {
        _showInfoSnackbar("Attempting image update...");
        newImageUrl = await ApiService().updateChefProfileImage(
            _currentProfile!.chefid, _currentProfile!.localImageFile!);
        if (newImageUrl != null) {
          _currentProfile!.image = newImageUrl; 
          _showSuccessSnackbar("Profile image updated.");
        } else {
           _showInfoSnackbar("Profile image upload failed or no new URL. Old image URL retained.");
        }
      }

      final apiService = ApiService();
      final profileDataForUpdate = _currentProfile!.toJsonForUpdate();
      if (newImageUrl != null) { // If a new image was successfully uploaded and URL obtained
        profileDataForUpdate['image'] = newImageUrl;
      }
      
      textFieldsUpdateSuccess = await apiService.updateChefProfile(
          _currentProfile!.chefid, profileDataForUpdate);

      if (mounted) {
        if (textFieldsUpdateSuccess) {
          _showSuccessSnackbar('Profile details updated successfully!');
          _currentProfile!.localImageFile = null; 
          await _saveProfileCacheToPrefs(_currentProfile!);
          setState(() {
            _isEditing = false;
          });
        } else {
          _showErrorSnackbar('Failed to save profile details.');
        }
      }
    } catch (e) {
      print("Error saving profile: $e");
      if (mounted) _showErrorSnackbar('An error occurred while saving.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green.shade600,
    ));
  }

  void _showInfoSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.blueGrey.shade600,
    ));
  }

  void _showComingSoonSnackbar(String featureName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$featureName feature is Coming Soon!', style: const TextStyle(color: whiteColor)),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<ChefProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final bool hasData = _currentProfile != null;
        final bool isLoadingFromState = _isLoadingProfile;

        if (isLoadingFromState && !hasData) {
          return _buildProfileShimmer();
        } else if ((snapshot.hasError || _fetchError.isNotEmpty) && !hasData) {
          final errorToShow = snapshot.error?.toString() ?? _fetchError;
          return _buildErrorState(errorToShow);
        } else if (!isLoadingFromState && !hasData && !snapshot.hasError && _fetchError.isEmpty) {
          return _buildErrorState('Profile data not found.');
        } else if (hasData && _currentProfile != null) {
          final profile = _currentProfile!;
          return RefreshIndicator(
            onRefresh: _refreshProfile,
            color: Theme.of(context).colorScheme.primary,
            child: Form(
                key: _formKey,
                child: Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(16.0),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _buildProfileHeader(context, profile),
                        const SizedBox(height: 24),
                        _buildActiveStatusCard(context, profile),
                        const SizedBox(height: 20),
                        _buildProfileDetailsCard(context, profile),
                        const SizedBox(height: 70),
                      ],
                    ),
                    if (isLoadingFromState && hasData && !_isEditing)
                      const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(minHeight: 2)),
                  ],
                )),
          );
        } else {
          return _buildProfileShimmer(); 
        }
      },
    );
  }

  Widget _buildProfileShimmer() {
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 100, height: 100, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(50))),
            const SizedBox(width: 20),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: MediaQuery.of(context).size.width * 0.5, height: 26, color: whiteColor, margin: const EdgeInsets.only(bottom: 8)),
              Container(width: MediaQuery.of(context).size.width * 0.3, height: 20, color: whiteColor),
            ])),
            Container(width: 40, height: 40, color: whiteColor, margin: const EdgeInsets.only(left: 16)),
          ]),
          const SizedBox(height: 24),
          Container(width: double.infinity, height: 60, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 20),
          Container(width: double.infinity, height: 450, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(12))),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.cloud_off_rounded, color: Theme.of(context).colorScheme.error, size: 50),
        const SizedBox(height: 16),
        Text('Error Loading Profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        ElevatedButton.icon(icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Retry'), onPressed: _refreshProfile)
      ]),
    ));
  }

  Widget _buildProfileHeader(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16.0), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CachedImageWithShimmer(
                        localFile: _isEditing ? profile.localImageFile : null,
                        imageUrl: profile.image,
                        width: 100,
                        height: 100,
                        borderRadius: 50,
                        fit: BoxFit.cover,
                        errorIcon: Icons.person_rounded,
                        iconSize: 50,
                        errorText: "No Pic",
                      ),
                    ),
                    if (_isEditing)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Material(
                          color: colorScheme.secondary.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          elevation: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _pickImage,
                            child: const Padding(padding: EdgeInsets.all(6.0), child: Icon(Icons.edit, color: whiteColor, size: 18)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _isEditing
                          ? TextFormField(
                              controller: _nameController,
                              style: textTheme.headlineSmall,
                              decoration: const InputDecoration(labelText: 'Name', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                              validator: (value) => (value == null || value.trim().isEmpty) ? 'Name cannot be empty' : null,
                              textInputAction: TextInputAction.next,
                            )
                          : Text(profile.name.isEmpty ? '(No Name)' : profile.name, style: textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(profile.chefType, style: textTheme.titleMedium?.copyWith(color: colorScheme.secondary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            profile.isEmailVerified ? Icons.verified : Icons.email_outlined,
                            size: 14,
                            color: profile.isEmailVerified ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            profile.isEmailVerified ? 'Email Verified' : 'Email Not Verified',
                            style: textTheme.labelSmall?.copyWith(
                              color: profile.isEmailVerified ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!_isEditing && !_isSaving)
                  IconButton(
                    tooltip: 'Edit Profile',
                    icon: Icon(Icons.edit_outlined, color: colorScheme.primary, size: 28),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
              ],
            ),
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () {
                        setState(() {
                          _isEditing = false;
                          _updateControllersFromProfile(profile);
                          profile.localImageFile = null;
                          _formKey.currentState?.reset();
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: whiteColor)) : const Icon(Icons.save_alt_rounded, size: 20),
                      label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                      onPressed: _isSaving ? null : _saveProfileChanges,
                    ),
                  ],
                ),
              ),
            if (_isSaving && !_isEditing) 
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveStatusCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final bool isActive = profile.isActive;
    final Color activeColor = isActive ? Colors.green.shade600 : Colors.grey.shade600;
    final Color cardBgColor = isActive ? Colors.green.shade50 : Colors.grey.shade200;

    return Card(
      elevation: _isEditing ? 0 : 0,
      margin: const EdgeInsets.symmetric(vertical: 1),
      color: cardBgColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: activeColor.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: (_isEditing || _isLoadingStatus) ? null : () => _toggleActiveStatus(!isActive),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isActive ? 'You are Online' : 'You are Offline', style: textTheme.titleMedium?.copyWith(color: activeColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(isActive ? 'Visible to customers' : 'Not currently visible', style: textTheme.bodySmall?.copyWith(color: activeColor.withOpacity(0.8))),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IgnorePointer(
                child: Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: isActive,
                    onChanged: (val) {}, 
                    activeColor: activeColor,
                    inactiveThumbColor: Colors.grey.shade600,
                    inactiveTrackColor: Colors.grey.shade600.withOpacity(0.4),
                  ),
                ),
              ),
              if (_isLoadingStatus)
                const Padding(padding: EdgeInsets.only(left: 8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailsCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final List<Widget> detailWidgets = [
      _buildEditableField(context, Icons.info_outline_rounded, 'Bio', _bioController, isMultiLine: true),
      _buildEditableMultiSelectField(context, Icons.star_outline_rounded, 'Specialties', _selectedSpecialties, allSpecialties, (values) => setState(() => _selectedSpecialties = values), hint: 'Select specialties'),
      _buildEditableField(context, Icons.timer_outlined, 'Experience (Years)', _experienceController, keyboardType: TextInputType.number, validator: (value) {
        if (value == null || value.isEmpty) return null;
        if (int.tryParse(value) == null) return 'Must be a valid number';
        if (int.parse(value) < 0) return 'Cannot be negative';
        return null;
      }),
      _buildEditableField(context, Icons.attach_money_rounded, 'Est. Price/Rate', _priceController, hint: 'e.g., 50/hr or 100/plate'),
      _buildEditableDropdownField(context, Icons.schedule_rounded, 'Min. Notice', _selectedMinNotice, minNoticeOptions, (value) => setState(() => _selectedMinNotice = value), hint: 'Select minimum notice', validator: (v) => v == null ? 'Required' : null),
      _buildEditableDropdownField(context, Icons.access_time_rounded, 'Response Time', _selectedResponseTime, responseTimes, (value) => setState(() => _selectedResponseTime = value), hint: 'Select response time'),
      _buildEditableMultiSelectField(context, Icons.language_rounded, 'Languages', _selectedLanguages, allLanguages, (values) => setState(() => _selectedLanguages = values), hint: 'Select languages'),
      _buildEditableMultiSelectField(context, Icons.build_circle_outlined, 'Equipment', _selectedEquipment, allEquipment, (values) => setState(() => _selectedEquipment = values), hint: 'Select available equipment'),
      _buildEditableMultiSelectField(context, Icons.calendar_today_rounded, 'Availability', _selectedAvailability, allAvailability, (values) => setState(() => _selectedAvailability = values), hint: 'Select availability days'),
      _buildEditableMultiSelectField(context, Icons.verified_user_outlined, 'Certifications', _selectedCertifications, allCertifications, (values) => setState(() => _selectedCertifications = values), hint: 'Select certifications'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(padding: const EdgeInsets.only(right: 16.0), child: Icon(Icons.location_on_outlined, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8))),
            Expanded(
              child: _isEditing
                  ? TextFormField(
                      controller: _locationController,
                      style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                      decoration: _buildInputDecoration(
                        'Primary Location',
                        hintText: _isFetchingLocation ? 'Fetching location${'.' * _locationHintDots}' : 'e.g., City, State or Service Area',
                        suffixIcon: _isFetchingLocation
                            ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(
                                icon: const Icon(Icons.my_location_rounded, size: 22),
                                color: primaryTeal,
                                tooltip: 'Get Current Location',
                                onPressed: _isFetchingLocation ? null : _getCurrentLocation,
                              ),
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty || value.startsWith('Failed')) ? 'Please provide a valid location' : null,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Primary Location', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                        const SizedBox(height: 3),
                        Text(
                          _locationController.text.trim().isEmpty ? 'Not provided' : _locationController.text.trim(),
                          style: textTheme.bodyMedium?.copyWith(color: _locationController.text.trim().isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color, height: 1.4),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      _buildEditableDropdownField(context, Icons.group_outlined, 'Team Size', _selectedTeamSize, teamSizes, (value) => setState(() => _selectedTeamSize = value), hint: 'Select team size'),
    ];

    Widget detailsBody;
    if (!_isEditing) {
      List<Widget> borderedGroups = [];
      for (int i = 0; i < detailWidgets.length; i += 3) {
        final children = <Widget>[];
        children.add(detailWidgets[i]);
        if (i + 1 < detailWidgets.length) children.add(detailWidgets[i + 1]);
        if (i + 2 < detailWidgets.length) children.add(detailWidgets[i + 2]);
        borderedGroups.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: primaryTeal, width: 0.8),
            borderRadius: BorderRadius.circular(10),
            color: Colors.teal[50]?.withOpacity(0.08),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ));
      }
      detailsBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: borderedGroups);
    } else {
      detailsBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: detailWidgets);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 1),
      color: _isEditing ? Theme.of(context).cardTheme.color?.withOpacity(0.95) : Theme.of(context).cardTheme.color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text('Chef Details', style: textTheme.titleLarge?.copyWith(color: _isEditing ? Theme.of(context).colorScheme.primary : null)),
            ),
            const Divider(),
            detailsBody,
            if (!_isEditing && profile.sampleMenu != null && profile.sampleMenu!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSampleMenuGallery(context, profile.sampleMenu!),
            ] else if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 15.0, left: 4.0),
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: Icon(Icons.menu_book_rounded, size: 20, color: Theme.of(context).colorScheme.secondary),
                  label: Text("Edit Sample Menu Items (Coming Soon)", style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                  onPressed: () => _showComingSoonSnackbar("Sample Menu Editing"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon, Widget? suffixIcon, String? hintText}) {
    return InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: subtleTextColor, fontSize: 14),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: primaryTeal.withOpacity(0.8), size: 20) : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: textFieldFillColor,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: lightTeal, width: 1.0)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: errorColor, width: 1.0)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: errorColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        errorStyle: TextStyle(color: errorColor.withOpacity(0.9), fontSize: 11));
  }

  Widget _buildEditableField(BuildContext context, IconData icon, String label, TextEditingController controller, {String? hint, bool isMultiLine = false, TextInputType keyboardType = TextInputType.text, String? Function(String?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = controller.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: isMultiLine ? 12.0 : 0.0, right: 16.0),
            child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
          ),
          Expanded(
            child: _isEditing
                ? TextFormField(
                    controller: controller,
                    keyboardType: isMultiLine ? TextInputType.multiline : keyboardType,
                    textInputAction: isMultiLine ? TextInputAction.newline : TextInputAction.next,
                    maxLines: isMultiLine ? null : 1,
                    minLines: isMultiLine ? 2 : 1,
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                    decoration: _buildInputDecoration(label, hintText: hint),
                    validator: validator,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue.isEmpty ? 'Not provided' : displayValue, style: textTheme.bodyMedium?.copyWith(color: displayValue.isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color, height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableDropdownField(BuildContext context, IconData icon, String label, String? currentValue, List<String> options, Function(String?) onChanged, {String? hint, String? Function(String?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = currentValue ?? 'Not provided';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(padding: const EdgeInsets.only(right: 16.0), child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8))),
          Expanded(
            child: _isEditing
                ? DropdownButtonFormField<String>(
                    value: currentValue,
                    items: options.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value, style: textTheme.bodyMedium?.copyWith(color: darkTeal), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: onChanged,
                    decoration: _buildInputDecoration(label, hintText: hint),
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                    isExpanded: true,
                    validator: validator,
                    hint: hint != null ? Text(hint, style: Theme.of(context).inputDecorationTheme.hintStyle) : null,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue, style: textTheme.bodyMedium?.copyWith(color: currentValue == null ? Colors.grey[500] : textTheme.bodyMedium?.color, height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableMultiSelectField(BuildContext context, IconData icon, String label, List<String> currentValues, List<String> allItems, Function(List<String>) onConfirm, {String? hint, String? Function(List<dynamic>?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = currentValues.isEmpty ? 'Not provided' : currentValues.join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 12.0, right: 16.0), child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8))),
          Expanded(
            child: _isEditing
                ? MultiSelectDialogField<String>(
                    items: allItems.map((item) => MultiSelectItem(item, item)).toList(),
                    initialValue: currentValues,
                    title: Text(label),
                    buttonText: Text(label, style: textTheme.bodyMedium?.copyWith(color: primaryTeal, fontWeight: FontWeight.w500)),
                    decoration: BoxDecoration(color: textFieldFillColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: lightTeal, width: 1.0)),
                    chipDisplay: MultiSelectChipDisplay(
                      chipColor: lightTeal.withOpacity(0.9),
                      textStyle: textTheme.bodySmall?.copyWith(color: darkTeal, fontSize: 11.5),
                      icon: Icon(Icons.close, color: darkTeal.withOpacity(0.7), size: 14),
                      onTap: (value) => setState(() => currentValues.remove(value)),
                      scrollBar: HorizontalScrollBar(isAlwaysShown: false),
                      scroll: true,
                      alignment: Alignment.centerLeft,
                    ),
                    selectedColor: primaryTeal,
                    selectedItemsTextStyle: textTheme.bodyMedium?.copyWith(color: primaryTeal),
                    itemsTextStyle: textTheme.bodyMedium?.copyWith(color: darkTeal),
                    searchable: true,
                    searchHint: 'Search $label',
                    confirmText: const Text('OK'),
                    cancelText: const Text('CANCEL'),
                    onConfirm: (results) => onConfirm(List<String>.from(results)),
                    validator: validator,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue, style: textTheme.bodyMedium?.copyWith(color: currentValues.isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color, height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleMenuGallery(BuildContext context, String sampleMenuUrls) {
    final List<String> urls = sampleMenuUrls.split(',').map((url) => url.trim()).where((url) => url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))).toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(children: [
              Icon(Icons.menu_book_rounded, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
              const SizedBox(width: 12),
              Text("Sample Menu", style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
          SizedBox(
            height: 110.0,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: SizedBox(
                  width: 90.0,
                  height: 90.0,
                  child: CachedImageWithShimmer(
                    imageUrl: urls[index],
                    width: 90.0,
                    height: 90.0,
                    fit: BoxFit.cover,
                    borderRadius: 8.0,
                    errorIcon: Icons.no_food_outlined,
                    iconSize: 30,
                    errorText: "Menu Item",
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// Wrapper for chef_profile.dart to make it runnable and apply a similar theme
class ChefProfileApp extends StatelessWidget {
  const ChefProfileApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Theme copied from ChefDash88new for visual consistency
    const Color lightBackgroundColor = Color(0xFFF5F5F5);
    const Color cardBackgroundColor = whiteColor;
    const Color primaryTextColorValue = darkTeal;
    const Color secondaryTextColorValue = Color(0xFF455A64);
    const Color iconColorValue = primaryTeal;
    const Color dividerColorValue = lightTeal;
    const Color onlineColor = Colors.green;
    const Color offlineColor = Colors.grey;
    
    return MaterialApp(
      title: 'Chef Profile',
       theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryTeal,
            primary: primaryTeal,
            secondary: accentTeal,
            background: lightBackgroundColor,
            surface: cardBackgroundColor,
            onPrimary: whiteColor,
            onSecondary: whiteColor,
            onBackground: primaryTextColorValue,
            onSurface: primaryTextColorValue,
            error: Colors.redAccent[700]!,
            onError: whiteColor,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: lightBackgroundColor,
          appBarTheme: AppBarTheme(
            backgroundColor: primaryTeal,
            foregroundColor: whiteColor,
            elevation: 1.0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            titleTextStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: whiteColor,
              letterSpacing: 0.5,
            ),
            iconTheme: const IconThemeData(color: whiteColor),
          ),
          tabBarTheme: const TabBarTheme(
            indicatorColor: whiteColor,
            labelColor: whiteColor,
            unselectedLabelColor: lightTeal,
            labelStyle: TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
          ),
          cardTheme: CardTheme(
            elevation: 1.5,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade50, width: 0.5),
            ),
            color: cardBackgroundColor,
          ),
          chipTheme: ChipThemeData(
            backgroundColor: lighterTeal,
            labelStyle: const TextStyle(color: primaryTextColorValue, fontWeight: FontWeight.w500),
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            side: BorderSide.none,
            elevation: 0,
          ),
          listTileTheme: const ListTileThemeData(
            iconColor: iconColorValue,
            titleTextStyle: TextStyle(fontWeight: FontWeight.w500, color: primaryTextColorValue, fontSize: 16),
            subtitleTextStyle: TextStyle(color: secondaryTextColorValue, fontSize: 13),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) return onlineColor;
              if (states.contains(MaterialState.disabled)) return Colors.grey.shade400;
              return offlineColor;
            }),
            trackColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) return onlineColor.withOpacity(0.5);
              if (states.contains(MaterialState.disabled)) return Colors.grey.shade300;
              return offlineColor.withOpacity(0.4);
            }),
            trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
          ),
          textTheme: const TextTheme(
            headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: darkTeal, fontSize: 22, letterSpacing: 0.2),
            titleLarge: TextStyle(fontWeight: FontWeight.w600, color: darkTeal, fontSize: 18),
            titleMedium: TextStyle(fontWeight: FontWeight.w600, color: primaryTextColorValue, fontSize: 16),
            titleSmall: TextStyle(fontWeight: FontWeight.w500, color: primaryTextColorValue, fontSize: 14),
            bodyLarge: TextStyle(color: primaryTextColorValue, fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(color: secondaryTextColorValue, fontSize: 14, height: 1.4),
            bodySmall: TextStyle(color: subtleTextColor, fontSize: 12, height: 1.3),
            labelLarge: TextStyle(color: whiteColor, fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.8),
            labelMedium: TextStyle(color: primaryTeal, fontWeight: FontWeight.w500, fontSize: 14),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: accentTeal,
            foregroundColor: whiteColor,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: textFieldFillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: lightTeal, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: primaryTeal, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
            floatingLabelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w600),
            hintStyle: const TextStyle(color: subtleTextColor),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorStyle: TextStyle(color: Colors.redAccent[700]?.withOpacity(0.9), fontSize: 11.5),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.redAccent[700]!, width: 1.0),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.redAccent[700]!, width: 1.5),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: primaryTeal,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryTeal,
                foregroundColor: whiteColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.5)),
          ),
          dividerTheme: const DividerThemeData(color: dividerColorValue, thickness: 0.8, space: 24),
          iconTheme: const IconThemeData(color: iconColorValue, size: 22),
          progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryTeal),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 4,
            contentTextStyle: const TextStyle(color: whiteColor),
          )),
      home: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: whiteColor),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Chef Profile'),
          // You might want a refresh button here if `manualRefreshFromAppBar` is to be used
          // actions: [
          //   IconButton(
          //     icon: Icon(Icons.refresh),
          //     onPressed: () {
          //       // How to access _profileTabKey.currentState.manualRefreshFromAppBar()?
          //       // This would require passing a key to ProfileTab if used this way.
          //       // For simplicity, the ProfileTab's internal RefreshIndicator will handle pull-to-refresh.
          //     },
          //   ),
          // ],
        ),
        body: const ProfileTab(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}