import 'package:flutter/material.dart';
import 'package:zinzi2/app_drawer_unified.dart'
    as drawer; // Import the AppDrawer widget with prefix
import 'package:zinzi2/notifications/notification_widget.dart'; // Import notification widget
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:intl/intl.dart';
import 'dart:convert'; // For jsonDecode, jsonEncode
import 'package:http/http.dart' as http; // Import the http package
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import flutter_dotenv
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart'; // <<< IMPORT for image picking
import 'dart:io'; // <<< IMPORT for File handling
import 'package:multi_select_flutter/multi_select_flutter.dart'; // <<< IMPORT for MultiSelectDialogField
import 'dart:async'; // For Timer
import 'package:geolocator/geolocator.dart'; // For location fetching
import 'package:zinzi2/user_cache.dart';
import 'package:zinzi2/cache_config.dart'; // <<< IMPORT CacheConfig
import 'package:zinzi2/chef_verification_helper.dart'; // Import verification helper
import 'package:zinzi2/utils/image_utils.dart'; // Import ImageUtils for URL processing

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

// --- Predefined value lists (from chefsignup222.dart) ---

// Status Constants for consistent use throughout the app
const String statusPending = 'Pending';
const String statusAccepted = 'Accepted';
const String statusPreparing = 'Preparing';
const String statusReadyForPickup = 'Ready for Pickup';
const String statusAssigned = 'Assigned';
const String statusOutForDelivery = 'Out for Delivery';
const String statusDelivered = 'Delivered';
const String statusCancelled = 'Cancelled';
const String statusRejected = 'Rejected'; // Usually leads to Cancelled
const String statusShipped = 'Shipped'; // Could be for Gigs/Services starting
const String statusCompleted =
    'Completed'; // Final state after delivery/service
const String statusVerificationNeeded = 'Verification Needed';

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
    // Ensure dotenv is loaded, typically in main.dart
    // await dotenv.load(fileName: ".env");
    return dotenv.env['API_BASE_URL-intranet'] ??
        'https://api.example.com'; // Fallback
  } catch (e) {
    print(
        "Error accessing dotenv for API_BASE_URL-intranet. Ensure dotenv.load() was called. Using fallback. Error: $e");
    return 'https://api.example.com'; // Fallback
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
      isActive: json['is_active'] is bool
          ? json['is_active']
          : (json['is_active']?.toString().toLowerCase() == 'true' ||
              json['is_active'] == 1),
      isEmailVerified: json['is_email_verified'] is bool
          ? json['is_email_verified']
          : (json['is_email_verified']?.toString().toLowerCase() == 'true' ||
              json['is_email_verified'] == 1),
      equipment: _joinListSafe(json['equipment']),
      pricing: json['pricing'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['pricing'])
          : null,
    );
  }

  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'bio': bio,
      // 'image': image, // Image handled separately by updateChefProfileImage
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

  // For caching, include all display fields
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
      'equipment': equipment,
      'pricing': pricing,
    }..removeWhere((key, value) => value == null);
  }
}

class Order {
  final int orderId;
  final String mealName;
  final String? producerName;
  final DateTime orderDate;
  String orderStatus;
  final String paymentStatus;
  final String totalPrice;
  final String? deliveryAddress;
  final String? ingredients;
  final String? notes;
  final int quantity;
  final int? userId;
  final String? orderType;
  int? assignedRiderId;
  String? assignedRiderName;
  final String? customerName;
  final double? orderTotal;

  Order({
    required this.orderId,
    required this.mealName,
    this.producerName,
    required this.orderDate,
    required this.orderStatus,
    required this.paymentStatus,
    required this.totalPrice,
    this.deliveryAddress,
    this.ingredients,
    this.notes,
    required this.quantity,
    this.userId,
    this.orderType,
    this.assignedRiderId,
    this.assignedRiderName,
    this.customerName,
    this.orderTotal,
  });

  factory Order.fromMockJson(Map<String, dynamic> json) {
    final apiDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
    DateTime parsedDate;
    try {
      parsedDate = json['order_date'] != null
          ? apiDateFormat.parseUtc(json['order_date'])
          : DateTime.now().toUtc();
    } catch (e) {
      try {
        parsedDate = json['order_date'] != null
            ? (DateTime.tryParse(json['order_date'])?.toUtc() ??
                DateTime.now().toUtc())
            : DateTime.now().toUtc();
      } catch (e2) {
        print("Error parsing date: ${json['order_date']} - $e - $e2");
        parsedDate = DateTime.now().toUtc();
      }
    }
    int _parseIntSafe(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is double) return value.toInt();
      return 0;
    }

    int? _parseIntNullable(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    String? _getStringSafe(dynamic value) {
      return value?.toString();
    }

    double? _parseDoubleNullable(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return Order(
      orderId: _parseIntSafe(json['order_id']),
      mealName: _getStringSafe(
              json['product_name'] ?? json['meal_name'] ?? json['gig_title']) ??
          'N/A',
      producerName: _getStringSafe(json['producer_name']),
      orderDate: parsedDate,
      orderStatus: _getStringSafe(json['order_status']) ?? 'Unknown',
      paymentStatus: _getStringSafe(json['payment_status']) ?? 'Unknown',
      totalPrice: _getStringSafe(json['total_price']) ?? '0.00',
      deliveryAddress:
          _getStringSafe(json['delivery_address'] ?? json['gig_location']),
      ingredients:
          _getStringSafe(json['ingredients'] ?? json['gig_requirements']),
      notes: _getStringSafe(json['notes']),
      quantity: _parseIntSafe(json['quantity'] ?? json['gig_guests']),
      userId: _parseIntNullable(json['user_id']),
      orderType: _getStringSafe(json['order_type']),
      assignedRiderId: _parseIntNullable(
          json['assigned_rider_id'] ?? json['assigned_staff_id']),
      assignedRiderName: _getStringSafe(
          json['assigned_rider_name'] ?? json['assigned_staff_name']),
      customerName: _getStringSafe(json['customer_name']),
      orderTotal: _parseDoubleNullable(json['order_total']),
    );
  }
}

class MealProduct {
  final String mealId;
  final String mealName;
  final String? mealDescription;
  final String? imageLink;
  final double price;
  final String? ingredients;
  final String? prepTime;
  final String? skillLevel;
  final String? mealCategory;
  final String? complementaryDishes;
  final String? dietaryPreference;
  final String? allergies;

  MealProduct({
    required this.mealId,
    required this.mealName,
    this.mealDescription,
    this.imageLink,
    required this.price,
    this.ingredients,
    this.prepTime,
    this.skillLevel,
    this.mealCategory,
    this.complementaryDishes,
    this.dietaryPreference,
    this.allergies,
  });

  factory MealProduct.fromMockJson(Map<String, dynamic> json) {
    double parsePrice(dynamic priceValue) {
      if (priceValue == null) return 0.0;
      if (priceValue is int) return priceValue.toDouble();
      if (priceValue is double) return priceValue;
      if (priceValue is String) return double.tryParse(priceValue) ?? 0.0;
      return 0.0;
    }

    String? _getStringSafe(dynamic value) {
      return value?.toString();
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

    return MealProduct(
      mealId:
          _getStringSafe(json['Meal_id'] ?? json['meal_id'] ?? json['id']) ??
              'N/A_ID',
      mealName: _getStringSafe(
              json['Meal_name'] ?? json['meal_name'] ?? json['name']) ??
          'N/A',
      mealDescription: _getStringSafe(json['Meal_description'] ??
          json['meal_description'] ??
          json['description']),
      imageLink: _isValidUrl(_getStringSafe(
              json['Image_link'] ?? json['image_link'] ?? json['image']))
          ? _getStringSafe(
              json['Image_link'] ?? json['image_link'] ?? json['image'])
          : null,
      price: parsePrice(json['Price'] ?? json['price']),
      ingredients: _getStringSafe(json['Ingredients'] ?? json['ingredients']),
      prepTime: _getStringSafe(json['Prep_time'] ?? json['prep_time']),
      skillLevel: _getStringSafe(json['Skill_level'] ?? json['skill_level']),
      mealCategory:
          _getStringSafe(json['Meal_category'] ?? json['meal_category']),
      complementaryDishes: _getStringSafe(
          json['Complementary_dishes'] ?? json['complementary_dishes']),
      dietaryPreference: _getStringSafe(
          json['Dietary_preference'] ?? json['dietary_preference']),
      allergies: _getStringSafe(json['Allergies'] ?? json['allergies']),
    );
  }
}

class Rider {
  final int id;
  final String name;
  final String status;
  final bool isActive;

  Rider({
    required this.id,
    required this.name,
    required this.status,
    required this.isActive,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    int? _parseIntNullable(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    String? _getStringSafe(dynamic value) {
      return value?.toString();
    }

    bool _parseBoolSafe(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is int) return value == 1;
      return false;
    }

    return Rider(
      id: _parseIntNullable(
              json['rider_id'] ?? json['transporter_id'] ?? json['id']) ??
          0,
      name: _getStringSafe(
              json['name'] ?? json['rider_name'] ?? json['transporter_name']) ??
          'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown',
      isActive: _parseBoolSafe(json['is_active']),
    );
  }
}

class ApiService {
  final String _baseUrl = _apibaseurl;
  static String get _staticBaseUrl => _apibaseurl;

  ApiService(); // Constructor

  static Future<String?> _getChefId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('chef_user_id');
    } catch (e) {
      print("Error accessing SharedPreferences for chef_id: $e");
      return null;
    }
  }

  Future<bool> updateChefStock(String payload) async {
    print("Stock Update Triggered (Coming Soon)");
    return false;
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
        print(
            "API Warning: Response has 'data' key but value is not a List or Map.");
        return responseData['data'];
      }
    } else if (responseData is Map && responseData.containsKey('All_Meals')) {
      if (responseData['All_Meals'] is List) {
        return responseData['All_Meals'];
      } else {
        print(
            "API Warning: Response has 'All_Meals' key but value is not a List.");
        return null;
      }
    } else if (responseData is Map && responseData.isNotEmpty) {
      return responseData;
    }
    print(
        "API Warning: Unhandled response format. Expected List or Map. Got: ${responseData.runtimeType}");
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
          if (rawData is List && rawData.isEmpty)
            throw Exception(
                'Failed to parse profile: API returned an empty list.');
          if (rawData is Map && rawData.isEmpty)
            throw Exception(
                'Failed to parse profile: API returned an empty map.');
          throw Exception(
              'Failed to parse profile: Unexpected API response format after handling.');
        }

        Map<String, dynamic> profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception(
                'Failed to parse profile: Expected a map inside the list.');
          }
        } else if (handledData is Map<String, dynamic>) {
          if (handledData.containsKey('chefid')) {
            profileMap = handledData;
          } else {
            throw Exception(
                'Failed to parse profile: Result map does not contain expected keys.');
          }
        } else {
          throw Exception(
              'Failed to parse profile: Result is not a usable Map or List. Type: ${handledData.runtimeType}');
        }
        return ChefProfile.fromMockJson(profileMap);
      } else {
        print(
            "Error fetching profile: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load chef profile (Status code: ${response.statusCode})');
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

  Future<bool> updateChefProfile(
      int chefId, Map<String, dynamic> profileData) async {
    final Uri uri = Uri.parse('$_baseUrl/rr/chefs/$chefId');
    print(
        "Updating profile for chef $chefId at: $uri with data: ${jsonEncode(profileData)}");

    try {
      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(profileData),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200 || response.statusCode == 204) {
        print("Profile update successful for chef $chefId");
        return true;
      } else {
        print(
            "Error updating chef profile for $chefId: ${response.statusCode} ${response.body}");
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
      // 1. Upload to Imgur
      final imgurUrl = await uploadImageToImgur(imageFile);
      if (imgurUrl == null) {
        print('Failed to upload image to Imgur.');
        return null;
      }
      // 2. PATCH the Imgur URL to backend profile update endpoint
      final Uri uri = Uri.parse('$_baseUrl/rr/chefs/$chefId');
      final Map<String, dynamic> payload = {'image': imgurUrl};
      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 200 || response.statusCode == 204) {
        print('Profile image updated successfully with Imgur link.');
        return imgurUrl;
      } else {
        print(
            'Failed to update chef profile with Imgur link: ${response.statusCode} ${response.body}');
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
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));
      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
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

  Future<List<Order>> fetchOrders() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$_baseUrl/rr/orders?chef_id=$chefId');
    print("Fetching orders from: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic ordersList = _handleApiResponse(rawData);
        if (ordersList is List) {
          if (ordersList.isEmpty) return [];
          return ordersList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return Order.fromMockJson(jsonItem);
                } else {
                  print(
                      "API Warning: Skipping non-map item in orders list: $jsonItem");
                  return null;
                }
              })
              .whereType<Order>()
              .toList();
        } else {
          print(
              "Orders API response format unexpected. Got: ${ordersList?.runtimeType}");
          if (ordersList == null || (ordersList is Map && ordersList.isEmpty))
            return [];
          throw Exception(
              'Failed to parse orders: Unexpected API response format (not a list)');
        }
      } else {
        print("Error fetching orders: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load orders (Status code: ${response.statusCode})');
      }
    } on TimeoutException {
      print("Timeout fetching orders for chef $chefId");
      throw Exception('Failed to load orders: Request timed out.');
    } catch (e) {
      print("Exception fetching orders: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load orders: $e');
    }
  }

  static Future<List<MealProduct>> fetchProducts() async {
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/meals');
    print("Fetching products/menu from: $uri");
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        List<dynamic>? menuList;
        if (rawData is List) {
          menuList = rawData;
        } else if (rawData is Map<String, dynamic>) {
          if (rawData.containsKey('data') && rawData['data'] is List) {
            menuList = rawData['data'];
          } else if (rawData.containsKey('All_Meals') &&
              rawData['All_Meals'] is List) {
            menuList = rawData['All_Meals'];
          } else if (rawData.isEmpty) {
            menuList = [];
          }
        }

        if (menuList == null) {
          dynamic handledData = _handleApiResponse(rawData);
          if (handledData is List) {
            menuList = handledData;
          } else {
            print(
                "Products API Warning: Response is not a recognized list format. Handling returned: ${handledData?.runtimeType}");
            menuList = null;
          }
        }

        if (menuList != null) {
          if (menuList.isEmpty) return [];
          return menuList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return MealProduct.fromMockJson(jsonItem);
                } else {
                  print(
                      "API Warning: Skipping non-map item in menu/products list: $jsonItem");
                  return null;
                }
              })
              .whereType<MealProduct>()
              .toList();
        } else {
          print(
              "Products API response format unexpected after all handling attempts. Raw data type: ${rawData.runtimeType}");
          throw Exception(
              'Failed to parse products: Unexpected API response format');
        }
      } else {
        print(
            "Error fetching products: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load products (Status code: ${response.statusCode})');
      }
    } on TimeoutException {
      print("Timeout fetching products");
      throw Exception('Failed to load products: Request timed out.');
    } catch (e) {
      print("Exception fetching products: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load products: $e');
    }
  }

  static Map<String, String> _getWriteHeaders({bool requiresAuth = false}) {
    // Defaulting requiresAuth to false if token isn't used
    // String? authToken = "YOUR_AUTH_TOKEN_HERE"; // TODO: Replace with actual token retrieval
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    // if (requiresAuth && (authToken?.isNotEmpty ?? false)) {
    //   headers['Authorization'] = 'Bearer $authToken';
    // }
    return headers;
  }

  static Future<bool> updateProfileStatus(int chefId, bool isActive) async {
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/chefs/$chefId/status');
    try {
      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(<String, bool>{'is_active': isActive}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating profile status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating profile status: $e");
      return false;
    }
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus,
      {int? chefId, String? completionCode}) async {
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/orders/$orderId/status');
    print(
        "Updating order $orderId status to $newStatus via general endpoint. Chef: $chefId, Code: $completionCode");
    try {
      final Map<String, dynamic> body = {'order_status': newStatus};
      if (chefId != null) body['chef_id'] = chefId;
      if (completionCode != null) body['completion_code'] = completionCode;

      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating order status: ${response.statusCode} ${response.body}");
        // Try to parse error message from body
        String apiErrorMsg = "Failed to update order status.";
        try {
          final errorBody = json.decode(response.body);
          if (errorBody is Map && errorBody.containsKey('message')) {
            apiErrorMsg = errorBody['message'];
          }
        } catch (_) {}
        throw Exception(apiErrorMsg); // Throw exception with API message
      }
    } on TimeoutException {
      print("Timeout updating order $orderId status.");
      throw Exception("Request timed out. Please try again.");
    } catch (e) {
      print("Exception updating order status: $e");
      if (e is Exception &&
          e.toString().contains("Failed to update order status.")) rethrow;
      throw Exception("An error occurred: ${e.toString()}");
    }
  }

  static Future<bool> assignOrderToRider(
      int orderId, int riderId, String newStatus) async {
    final Uri uri = Uri.parse(
        '$_staticBaseUrl/rr/orders/$orderId/status'); // Assuming status endpoint handles assignment
    print(
        "Assigning order $orderId to rider $riderId, setting status to $newStatus");

    try {
      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(<String, dynamic>{
              'order_status': newStatus,
              'transporter_id': riderId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print("Error assigning order: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception assigning order: $e");
      return false;
    }
  }

  Future<List<Rider>> fetchAvailableRiders() async {
    final Uri uri = Uri.parse('$_baseUrl/rr/transporters');
    print("Fetching available riders from: $uri");
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic riderList = _handleApiResponse(rawData);

        if (riderList is List) {
          if (riderList.isEmpty) return [];
          return riderList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return Rider.fromJson(jsonItem);
                } else {
                  print(
                      "API Warning: Skipping non-map item in riders list: $jsonItem");
                  return null;
                }
              })
              .whereType<Rider>()
              .toList();
        } else {
          print(
              "Riders API response format unexpected. Got: ${riderList?.runtimeType}");
          if (riderList == null || (riderList is Map && riderList.isEmpty))
            return [];
          throw Exception(
              'Failed to parse riders: Unexpected API response format');
        }
      } else {
        print("Error fetching riders: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load riders (Status code: ${response.statusCode})');
      }
    } on TimeoutException {
      print("Timeout fetching riders.");
      throw Exception('Failed to load riders: Request timed out.');
    } catch (e) {
      print("Exception fetching riders: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load riders: $e');
    }
  }

  static Future<MealProduct?> addProduct(
      Map<String, dynamic> productData) async {
    print("Add Product Triggered (Coming Soon)");
    return null;
  }

  static Future<bool> updateProduct(
      String mealId, Map<String, dynamic> productData) async {
    print("Update Product Triggered (Coming Soon)");
    return false;
  }

  static Future<bool> deleteProduct(String mealId) async {
    print("Delete Product Triggered (Coming Soon)");
    return false;
  }

  static Future<bool> addMealsToChefStock(List<String> mealIds) async {
    print("Add Meals to Stock Triggered (Coming Soon)");
    return false;
  }

  // Static Fetch Chefs (for preloading)
  static Future<List<dynamic>?> fetchChefsStatic() async {
    final url = '$_staticBaseUrl/rr/rchefs';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic chefsList = _handleApiResponse(rawData);
        if (chefsList is List) return chefsList;
        if (chefsList == null || (chefsList is Map && chefsList.isEmpty))
          return [];
        print(
            'Static fetchChefs: Unexpected response format after handling: ${chefsList?.runtimeType}');
        return null;
      } else {
        print(
            'Static fetchChefs: Failed to load chefs. Status code: ${response.statusCode}.');
        return null;
      }
    } on TimeoutException {
      print('Static fetchChefs: Request timed out.');
      return null;
    } catch (e) {
      print('Static fetchChefs: Error fetching chefs: $e');
      return null;
    }
  }

  // Static Fetch Producers (for preloading)
  static Future<List<dynamic>?> fetchProducersStatic() async {
    final url = '$_staticBaseUrl/rr/rproducers';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic producerList = _handleApiResponse(rawData);
        if (producerList is List) return producerList;
        if (producerList == null ||
            (producerList is Map && producerList.isEmpty)) return [];
        print(
            'Static fetchProducers: Unexpected response format after handling: ${producerList?.runtimeType}');
        return null;
      } else {
        print(
            'Static fetchProducers: Failed to load producers. Status code: ${response.statusCode}.');
        return null;
      }
    } on TimeoutException {
      print('Static fetchProducers: Request timed out.');
      return null;
    } catch (e) {
      print('Static fetchProducers: Error fetching producers: $e');
      return null;
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
    // Use the centralized ImageUtils for consistent URL processing
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
      // Process URL through our standardized image URL handler
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
                style:
                    textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
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

class ChefDash88new extends StatelessWidget {
  const ChefDash88new({super.key});

  @override
  Widget build(BuildContext context) {
    const Color lightBackgroundColor = Color(0xFFF5F5F5);
    const Color cardBackgroundColor = whiteColor;
    const Color primaryTextColorValue = darkTeal; // Renamed to avoid conflict
    const Color secondaryTextColorValue = Color(0xFF455A64); // Renamed
    const Color iconColorValue = primaryTeal; // Renamed
    const Color dividerColorValue = lightTeal; // Renamed
    const Color onlineColor = Colors.green;
    const Color offlineColor = Colors.grey;

    return MaterialApp(
      title: 'Chef Dashboard',
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
            labelStyle: const TextStyle(
                color: primaryTextColorValue, fontWeight: FontWeight.w500),
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            side: BorderSide.none,
            elevation: 0,
          ),
          listTileTheme: const ListTileThemeData(
            iconColor: iconColorValue,
            titleTextStyle: TextStyle(
                fontWeight: FontWeight.w500,
                color: primaryTextColorValue,
                fontSize: 16),
            subtitleTextStyle:
                TextStyle(color: secondaryTextColorValue, fontSize: 13),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith<Color?>(
                (Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) return onlineColor;
              if (states.contains(MaterialState.disabled))
                return Colors.grey.shade400;
              return offlineColor;
            }),
            trackColor: MaterialStateProperty.resolveWith<Color?>(
                (Set<MaterialState> states) {
              if (states.contains(MaterialState.selected))
                return onlineColor.withOpacity(0.5);
              if (states.contains(MaterialState.disabled))
                return Colors.grey.shade300;
              return offlineColor.withOpacity(0.4);
            }),
            trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
          ),
          textTheme: const TextTheme(
            headlineSmall: TextStyle(
                fontWeight: FontWeight.bold,
                color: darkTeal,
                fontSize: 22,
                letterSpacing: 0.2),
            titleLarge: TextStyle(
                fontWeight: FontWeight.w600, color: darkTeal, fontSize: 18),
            titleMedium: TextStyle(
                fontWeight: FontWeight.w600,
                color: primaryTextColorValue,
                fontSize: 16),
            titleSmall: TextStyle(
                fontWeight: FontWeight.w500,
                color: primaryTextColorValue,
                fontSize: 14),
            bodyLarge: TextStyle(
                color: primaryTextColorValue, fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(
                color: secondaryTextColorValue, fontSize: 14, height: 1.4),
            bodySmall:
                TextStyle(color: subtleTextColor, fontSize: 12, height: 1.3),
            labelLarge: TextStyle(
                color: whiteColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.8),
            labelMedium: TextStyle(
                color: primaryTeal, fontWeight: FontWeight.w500, fontSize: 14),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: accentTeal,
            foregroundColor: whiteColor,
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            labelStyle: const TextStyle(
                color: primaryTeal, fontWeight: FontWeight.w500),
            floatingLabelStyle: const TextStyle(
                color: primaryTeal, fontWeight: FontWeight.w600),
            hintStyle: const TextStyle(color: subtleTextColor),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorStyle: TextStyle(
                color: Colors.redAccent[700]?.withOpacity(0.9), fontSize: 11.5),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryTeal,
                foregroundColor: whiteColor,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.5)),
          ),
          dividerTheme: const DividerThemeData(
              color: dividerColorValue, thickness: 0.8, space: 24),
          iconTheme: const IconThemeData(color: iconColorValue, size: 22),
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(color: primaryTeal),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 4,
            contentTextStyle: const TextStyle(color: whiteColor),
          )),
      home: const ChefDashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChefDashboardScreen extends StatefulWidget {
  const ChefDashboardScreen({super.key});
  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _refreshIconController;
  bool _isRefreshing = false;

  final GlobalKey<_ProfileTabState> _profileTabKey =
      GlobalKey<_ProfileTabState>();
  final GlobalKey<_OrdersTabState> _ordersTabKey = GlobalKey<_OrdersTabState>();
  final GlobalKey<_GigsTabState> _gigsTabKey = GlobalKey<_GigsTabState>();
  final GlobalKey<_ProductsTabState> _productsTabKey =
      GlobalKey<_ProductsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _tabController.addListener(_handleTabChangeForPolling);
    // Start polling only for the initial tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleTabChangeForPolling();
    });
  }

  void _handleTabChangeForPolling() {
    final ordersTab = _ordersTabKey.currentState;
    final gigsTab = _gigsTabKey.currentState;
    // Pause both first
    if (ordersTab != null) {
      ordersTab._ordersPollingTimer?.cancel();
    }
    if (gigsTab != null) {
      gigsTab._gigsPollingTimer?.cancel();
    }
    // Resume polling for active tab
    bool pollingNow = false;
    switch (_tabController.index) {
      case 1:
        if (ordersTab != null) {
          ordersTab._startOrdersPolling();
          pollingNow = true;
        }
        break;
      case 2:
        if (gigsTab != null) {
          gigsTab._startGigsPolling();
          pollingNow = true;
        }
        break;
    }
    // Animate refresh icon during polling
    if (pollingNow && !_refreshIconController.isAnimating && !_isRefreshing) {
      _refreshIconController.repeat();
    } else if (!pollingNow && !_isRefreshing) {
      _refreshIconController.reset();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChangeForPolling);
    _tabController.dispose();
    _refreshIconController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    if (!_refreshIconController.isAnimating) _refreshIconController.repeat();

    bool didRefresh = false;
    try {
      if (mounted) {
        final currentIndex = _tabController.index;
        switch (currentIndex) {
          case 0:
            final state = _profileTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 1:
            final state = _ordersTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 2:
            final state = _gigsTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 3:
            final state = _productsTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
        }
      }
      if (!didRefresh) {
        print(
            "Warning: Could not trigger refresh for tab ${_tabController.index}. Using fallback delay.");
        await Future.delayed(const Duration(milliseconds: 900));
      }
    } catch (e) {
      print("Error during refresh propagation: $e");
    } finally {
      _refreshIconController.reset();
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: drawer.AppDrawer(invokedBy: 'chef_dashboard'),
      appBar: AppBar(
        title: const Text('Chef Dashboard'),
        actions: [
          AnimatedBuilder(
            animation: _refreshIconController,
            builder: (context, child) {
              return IconButton(
                icon: Transform.rotate(
                  angle: _refreshIconController.value * 2 * 3.14159,
                  child: const Icon(Icons.refresh),
                ),
                tooltip: 'Refresh',
                onPressed: _isRefreshing ? null : _handleRefresh,
              );
            },
          ),
          // Notification Bell Icon
          NotificationWidget(
            key: ValueKey('chef_dashboard_notifications'),
            iconColor: Colors.white,
            showCounter: true,
            // notificationCount can be omitted to use provider.unreadCount, or set a value here if needed, e.g. notificationCount: 0,
            targetUserType: 'chef',
          ),
        ],
        bottom: TabBar(
          isScrollable: false,
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_pin_circle_outlined), text: 'Profile'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
            Tab(icon: Icon(Icons.work_outline_rounded), text: 'Gigs'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ProfileTab(key: _profileTabKey),
          OrdersTab(key: _ordersTabKey),
          GigsTab(key: _gigsTabKey),
          ProductsTab(key: _productsTabKey),
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
    await _refreshProfile(); // Await the refresh
    print("ProfileTab: manualRefreshFromAppBar completed.");
  }
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin {
  static ChefProfile? _profileCache;
  static DateTime? _profileCacheTimestamp;
  static const String _profileCacheKey =
      'chef_profile_cache_v2'; // Versioned key
  static const String _profileCacheTimestampKey =
      'chef_profile_cache_timestamp_v2';

  static Future<void> _loadProfileCacheFromPrefs() async {
    try {
      final cachedData = await UserCache.getData(_profileCacheKey);
      final timestampData = await UserCache.getData(_profileCacheTimestampKey);

      if (cachedData is Map<String, dynamic> && timestampData is String) {
        try {
          _profileCache = ChefProfile.fromMockJson(cachedData);
          _profileCacheTimestamp = DateTime.tryParse(timestampData);
          if (_profileCacheTimestamp == null) {
            // Handle parse failure
            print(
                "ProfileTab: Failed to parse cached timestamp. Clearing cache.");
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
      // Use toJsonForCache to ensure all necessary fields are saved
      Map<String, dynamic> cacheableProfile = profile.toJsonForCache();
      await UserCache.saveData(_profileCacheKey, cacheableProfile);
      final now = DateTime.now();
      await UserCache.saveData(
          _profileCacheTimestampKey, now.toIso8601String());

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
    _perGigPriceControllers.values
        .forEach((controller) => controller.dispose());
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
          now.difference(_profileCacheTimestamp!) <
              CacheConfig.profileCacheDuration;

      if (cacheIsValid) {
        print("ProfileTab: Displaying valid cached profile.");
        setState(() {
          _currentProfile = _profileCache;
          if (_currentProfile != null)
            _updateControllersFromProfile(_currentProfile!);
          _isLoadingProfile = false;
          _profileFuture = Future.value(_currentProfile);
        });
      } else {
        print("ProfileTab: Cached profile expired or timestamp missing.");
        setState(() {
          _currentProfile = _profileCache; // Show stale data
          if (_currentProfile != null)
            _updateControllersFromProfile(_currentProfile!);
          _isLoadingProfile = true; // Indicate background loading
          _profileFuture = Future.value(_currentProfile); // For builder
        });
        await _fetchProfileAndUpdate(); // Fetch in background
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
    if (_profileFuture != null &&
        _isLoadingProfile &&
        _currentProfile != null) {
      print(
          "ProfileTab: Background fetch already in progress or future assigned.");
      return;
    }

    final apiService = ApiService();
    final fetchFuture = apiService.fetchChefProfile();
    if (mounted) {
      setState(() {
        _profileFuture =
            fetchFuture.then((profile) => profile).catchError((_) => null);
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
          // Only show full error UI if no cache
          setState(() {
            _fetchError = errorMsg;
            _isLoadingProfile = false;
          });
          _showErrorSnackbar(errorMsg);
        } else {
          // Have cached data, show subtle error
          _showInfoSnackbar(
              "Couldn't update profile, showing last known data.");
          setState(() {
            _isLoadingProfile = false; // Stop background loading indicator
            _fetchError = ''; // Clear fetchError as we are showing cached data
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

  List<String> _parseAndFilterList(
      String? commaSeparatedString, List<String> allowedValues) {
    if (commaSeparatedString == null || commaSeparatedString.trim().isEmpty)
      return [];
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

    _selectedResponseTime =
        _validateSingleSelection(profile.responseTime, responseTimes);
    _selectedTeamSize = _validateSingleSelection(profile.teamSize, teamSizes);
    _selectedMinNotice =
        _validateSingleSelection(profile.minNotice, minNoticeOptions);

    _selectedSpecialties =
        _parseAndFilterList(profile.specialties, allSpecialties);
    _selectedLanguages = _parseAndFilterList(profile.languages, allLanguages);
    _selectedEquipment = _parseAndFilterList(profile.equipment, allEquipment);
    _selectedAvailability =
        _parseAndFilterList(profile.availability, allAvailability);
    _selectedCertifications =
        _parseAndFilterList(profile.certifications, allCertifications);

    // Clear local image file when repopulating from profile (e.g. on cancel edit)
    profile.localImageFile = null;
  }

  void _updateProfileFromControllers() {
    if (_currentProfile == null) return;
    _currentProfile!.name = _nameController.text.trim();
    _currentProfile!.bio =
        _bioController.text.trim().isEmpty ? null : _bioController.text.trim();
    _currentProfile!.experience =
        int.tryParse(_experienceController.text.trim());
    _currentProfile!.location = _locationController.text.trim().isEmpty
        ? null
        : _locationController.text.trim();
    _currentProfile!.price = _priceController.text.trim().isEmpty
        ? null
        : _priceController.text.trim();

    _currentProfile!.responseTime = _selectedResponseTime;
    _currentProfile!.teamSize = _selectedTeamSize;
    _currentProfile!.minNotice = _selectedMinNotice;
    _currentProfile!.specialties =
        _selectedSpecialties.isEmpty ? null : _selectedSpecialties.join(',');
    _currentProfile!.languages =
        _selectedLanguages.isEmpty ? null : _selectedLanguages.join(',');
    _currentProfile!.equipment =
        _selectedEquipment.isEmpty ? null : _selectedEquipment.join(',');
    _currentProfile!.availability =
        _selectedAvailability.isEmpty ? null : _selectedAvailability.join(',');
    _currentProfile!.certifications = _selectedCertifications.isEmpty
        ? null
        : _selectedCertifications.join(',');
  }

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
      if (mounted)
        setState(() => _locationHintDots = (_locationHintDots + 1) % 4);
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
        if (permission == LocationPermission.denied)
          throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever)
        throw Exception('Location permissions permanently denied.');

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));

      String displayAddress =
          "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      String coords = "${position.latitude},${position.longitude}";

      try {
        final String apiUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
          if (mounted)
            _showInfoSnackbar('Could not fetch address. Using coordinates.');
        }
      } catch (e) {
        if (mounted)
          _showInfoSnackbar('Could not fetch address. Using coordinates.');
      }

      if (mounted) {
        setState(() {
          _locationController.text =
              (displayAddress.isNotEmpty && !displayAddress.startsWith("Lat:"))
                  ? "$displayAddress ($coords)"
                  : "Location Acquired ($coords)";
        });
        _showSuccessSnackbar('Location acquired!');
      }
    } on TimeoutException catch (_) {
      if (mounted) _showErrorSnackbar('Getting location timed out.');
    } catch (e) {
      if (mounted)
        _showErrorSnackbar('Error getting location: ${e.toString()}');
    } finally {
      if (mounted) {
        _stopLocationHintAnimation();
        setState(() {
          _isFetchingLocation = false;
          if (_locationController.text.isEmpty)
            _locationController.text = 'Failed to get location';
        });
      }
    }
  }

  Future<void> _toggleActiveStatus(bool newValue) async {
    if (_currentProfile == null || _isLoadingStatus || _isEditing) return;
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _isLoadingStatus = true);

    final originalStatus = _currentProfile!.isActive;
    setState(() => _currentProfile!.isActive = newValue); // Optimistic

    try {
      bool success = await ApiService.updateProfileStatus(
          _currentProfile!.chefid, newValue);
      if (mounted) {
        if (!success) {
          setState(() => _currentProfile!.isActive = originalStatus); // Revert
          _showErrorSnackbar('Failed to update status.');
        } else {
          _showSuccessSnackbar('Status updated.');
          await _saveProfileCacheToPrefs(_currentProfile!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentProfile!.isActive = originalStatus); // Revert
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
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
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

    _updateProfileFromControllers(); // Updates _currentProfile from form fields

    bool textFieldsUpdateSuccess = false;
    String? newImageUrl;

    try {
      // 1. Handle Profile Image Update (if a local file was picked)
      if (_currentProfile!.localImageFile != null) {
        _showInfoSnackbar("Attempting image update (Coming Soon)...");
        // ApiService().updateChefProfileImage will print "Coming Soon" and return null
        newImageUrl = await ApiService().updateChefProfileImage(
            _currentProfile!.chefid, _currentProfile!.localImageFile!);
        if (newImageUrl != null) {
          _currentProfile!.image =
              newImageUrl; // Update profile object if API returned new URL
          _showSuccessSnackbar(
              "Profile image conceptually updated (URL received).");
        } else {
          _showInfoSnackbar(
              "Profile image upload is 'Coming Soon' (no new URL from API). Old image URL retained.");
        }
      }

      // 2. Update Profile Text Fields (and other non-image data)
      final apiService = ApiService();
      final profileDataForUpdate = _currentProfile!.toJsonForUpdate();
      // If a new image URL was obtained and should be part of the main PATCH, add it.
      // Otherwise, the 'image' field in toJsonForUpdate will be the old one or null.
      if (newImageUrl != null) {
        profileDataForUpdate['image'] = newImageUrl;
      }

      textFieldsUpdateSuccess = await apiService.updateChefProfile(
          _currentProfile!.chefid, profileDataForUpdate);

      if (mounted) {
        if (textFieldsUpdateSuccess) {
          _showSuccessSnackbar('Profile details updated successfully!');
          // Clear local file regardless of API-side "Coming Soon" status for image upload
          // This prevents re-attempting the same local file upload if user doesn't pick a new one
          _currentProfile!.localImageFile = null;

          await _saveProfileCacheToPrefs(_currentProfile!);
          setState(() {
            _isEditing = false;
            // _updateControllersFromProfile(_currentProfile!); // Already reflects _currentProfile due to _updateProfileFromControllers()
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
      content: Text('$featureName feature is Coming Soon!',
          style: const TextStyle(color: whiteColor)),
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
        final bool isLoadingFromState = _isLoadingProfile; // Use state flag

        if (isLoadingFromState && !hasData) {
          return _buildProfileShimmer();
        } else if ((snapshot.hasError || _fetchError.isNotEmpty) && !hasData) {
          final errorToShow = snapshot.error?.toString() ?? _fetchError;
          return _buildErrorState(errorToShow);
        } else if (!isLoadingFromState &&
            !hasData &&
            !snapshot.hasError &&
            _fetchError.isEmpty) {
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
          // Fallback, should ideally not be reached if logic above is correct
          return _buildProfileShimmer(); // Or some other placeholder
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
            Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                    color: whiteColor,
                    borderRadius: BorderRadius.circular(50))),
            const SizedBox(width: 20),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                      width: MediaQuery.of(context).size.width * 0.5,
                      height: 26,
                      color: whiteColor,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(
                      width: MediaQuery.of(context).size.width * 0.3,
                      height: 20,
                      color: whiteColor),
                ])),
            Container(
                width: 40,
                height: 40,
                color: whiteColor,
                margin: const EdgeInsets.only(left: 16)),
          ]),
          const SizedBox(height: 24),
          Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                  color: whiteColor, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 20),
          Container(
              width: double.infinity,
              height: 450,
              decoration: BoxDecoration(
                  color: whiteColor, borderRadius: BorderRadius.circular(12))),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.cloud_off_rounded,
            color: Theme.of(context).colorScheme.error, size: 50),
        const SizedBox(height: 16),
        Text('Error Loading Profile',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _refreshProfile)
      ]),
    ));
  }

  Widget _buildProfileHeader(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16.0), // Ensure some bottom margin
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Column(
          // Use Column for better layout of edit mode elements
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
                            child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(Icons.edit,
                                    color: whiteColor, size: 18)),
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
                              decoration: const InputDecoration(
                                  labelText: 'Name',
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 8)),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'Name cannot be empty'
                                      : null,
                              textInputAction: TextInputAction.next,
                            )
                          : Text(
                              profile.name.isEmpty ? '(No Name)' : profile.name,
                              style: textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(profile.chefType,
                          style: textTheme.titleMedium
                              ?.copyWith(color: colorScheme.secondary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            profile.isEmailVerified
                                ? Icons.verified
                                : Icons.email_outlined,
                            size: 14,
                            color: profile.isEmailVerified
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            profile.isEmailVerified
                                ? 'Email Verified'
                                : 'Email Not Verified',
                            style: textTheme.labelSmall?.copyWith(
                              color: profile.isEmailVerified
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Edit/Cancel/Save buttons logic moved here for better alignment
                if (!_isEditing && !_isSaving)
                  IconButton(
                    tooltip: 'Edit Profile',
                    icon: Icon(Icons.edit_outlined,
                        color: colorScheme.primary, size: 28),
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
                      onPressed: _isSaving
                          ? null
                          : () {
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
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: whiteColor))
                          : const Icon(Icons.save_alt_rounded, size: 20),
                      label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                      onPressed: _isSaving ? null : _saveProfileChanges,
                    ),
                  ],
                ),
              ),
            if (_isSaving &&
                !_isEditing) // Show only spinner if saving initiated from a non-edit mode action (e.g. status toggle)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveStatusCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final bool isActive = profile.isActive;
    final Color activeColor =
        isActive ? Colors.green.shade600 : Colors.grey.shade600;
    final Color cardBgColor =
        isActive ? Colors.green.shade50 : Colors.grey.shade200;

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
        onTap: (_isEditing || _isLoadingStatus)
            ? null
            : () => _toggleActiveStatus(!isActive),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isActive ? 'You are Online' : 'You are Offline',
                        style: textTheme.titleMedium?.copyWith(
                            color: activeColor, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        isActive
                            ? 'Visible to customers'
                            : 'Not currently visible',
                        style: textTheme.bodySmall
                            ?.copyWith(color: activeColor.withOpacity(0.8))),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IgnorePointer(
                child: Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: isActive,
                    onChanged: (val) {}, // Handled by InkWell
                    activeColor: activeColor,
                    inactiveThumbColor: Colors.grey.shade600,
                    inactiveTrackColor: Colors.grey.shade600.withOpacity(0.4),
                  ),
                ),
              ),
              if (_isLoadingStatus)
                const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.0))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailsCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    // --- START PATCH: Add teal border around every two chef details when not editing ---
    final List<Widget> detailWidgets = [
      _buildEditableField(
          context, Icons.info_outline_rounded, 'Bio', _bioController,
          isMultiLine: true),
      _buildEditableMultiSelectField(
          context,
          Icons.star_outline_rounded,
          'Specialties',
          _selectedSpecialties,
          allSpecialties,
          (values) => setState(() => _selectedSpecialties = values),
          hint: 'Select specialties'),
      _buildEditableField(context, Icons.timer_outlined, 'Experience (Years)',
          _experienceController, keyboardType: TextInputType.number,
          validator: (value) {
        if (value == null || value.isEmpty) return null;
        if (int.tryParse(value) == null) return 'Must be a valid number';
        if (int.parse(value) < 0) return 'Cannot be negative';
        return null;
      }),
      _buildEditableField(context, Icons.attach_money_rounded,
          'Est. Price/Rate', _priceController,
          hint: 'e.g., 50/hr or 100/plate'),
      _buildEditableDropdownField(
          context,
          Icons.schedule_rounded,
          'Min. Notice',
          _selectedMinNotice,
          minNoticeOptions,
          (value) => setState(() => _selectedMinNotice = value),
          hint: 'Select minimum notice',
          validator: (v) => v == null ? 'Required' : null),
      _buildEditableDropdownField(
          context,
          Icons.access_time_rounded,
          'Response Time',
          _selectedResponseTime,
          responseTimes,
          (value) => setState(() => _selectedResponseTime = value),
          hint: 'Select response time'),
      _buildEditableMultiSelectField(
          context,
          Icons.language_rounded,
          'Languages',
          _selectedLanguages,
          allLanguages,
          (values) => setState(() => _selectedLanguages = values),
          hint: 'Select languages'),
      _buildEditableMultiSelectField(
          context,
          Icons.build_circle_outlined,
          'Equipment',
          _selectedEquipment,
          allEquipment,
          (values) => setState(() => _selectedEquipment = values),
          hint: 'Select available equipment'),
      _buildEditableMultiSelectField(
          context,
          Icons.calendar_today_rounded,
          'Availability',
          _selectedAvailability,
          allAvailability,
          (values) => setState(() => _selectedAvailability = values),
          hint: 'Select availability days'),
      _buildEditableMultiSelectField(
          context,
          Icons.verified_user_outlined,
          'Certifications',
          _selectedCertifications,
          allCertifications,
          (values) => setState(() => _selectedCertifications = values),
          hint: 'Select certifications'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Icon(Icons.location_on_outlined,
                    size: 20,
                    color: Theme.of(context)
                        .listTileTheme
                        .iconColor
                        ?.withOpacity(0.8))),
            Expanded(
              child: _isEditing
                  ? TextFormField(
                      controller: _locationController,
                      style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                      decoration: _buildInputDecoration(
                        'Primary Location',
                        hintText: _isFetchingLocation
                            ? 'Fetching location${'.' * _locationHintDots}'
                            : 'e.g., City, State or Service Area',
                        suffixIcon: _isFetchingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : IconButton(
                                icon: const Icon(Icons.my_location_rounded,
                                    size: 22),
                                color: primaryTeal,
                                tooltip: 'Get Current Location',
                                onPressed: _isFetchingLocation
                                    ? null
                                    : _getCurrentLocation,
                              ),
                      ),
                      validator: (value) => (value == null ||
                              value.trim().isEmpty ||
                              value.startsWith('Failed'))
                          ? 'Please provide a valid location'
                          : null,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Primary Location',
                            style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600])),
                        const SizedBox(height: 3),
                        Text(
                          _locationController.text.trim().isEmpty
                              ? 'Not provided'
                              : _locationController.text.trim(),
                          style: textTheme.bodyMedium?.copyWith(
                              color: _locationController.text.trim().isEmpty
                                  ? Colors.grey[500]
                                  : textTheme.bodyMedium?.color,
                              height: 1.4),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      _buildEditableDropdownField(
          context,
          Icons.group_outlined,
          'Team Size',
          _selectedTeamSize,
          teamSizes,
          (value) => setState(() => _selectedTeamSize = value),
          hint: 'Select team size'),
    ];

    Widget detailsBody;
    if (!_isEditing) {
      // Group every three widgets and wrap in a bordered container
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ));
      }
      detailsBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: borderedGroups,
      );
    } else {
      detailsBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detailWidgets,
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 1),
      color: _isEditing
          ? Theme.of(context).cardTheme.color?.withOpacity(0.95)
          : Theme.of(context).cardTheme.color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text('Chef Details',
                  style: textTheme.titleLarge?.copyWith(
                      color: _isEditing
                          ? Theme.of(context).colorScheme.primary
                          : null)),
            ),
            const Divider(),
            detailsBody,
            if (!_isEditing &&
                profile.sampleMenu != null &&
                profile.sampleMenu!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSampleMenuGallery(context, profile.sampleMenu!),
            ] else if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 15.0, left: 4.0),
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: Icon(Icons.menu_book_rounded,
                      size: 20, color: Theme.of(context).colorScheme.secondary),
                  label: Text("Edit Sample Menu Items (Coming Soon)",
                      style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondary)),
                  onPressed: () =>
                      _showComingSoonSnackbar("Sample Menu Editing"),
                ),
              ),
          ],
        ),
      ),
    );
    // --- END PATCH ---
  }

  InputDecoration _buildInputDecoration(String label,
      {IconData? prefixIcon, Widget? suffixIcon, String? hintText}) {
    return InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle:
            const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: subtleTextColor, fontSize: 14),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: primaryTeal.withOpacity(0.8), size: 20)
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: textFieldFillColor,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: lightTeal, width: 1.0)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.0)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        errorStyle:
            TextStyle(color: errorColor.withOpacity(0.9), fontSize: 11));
  }

  Widget _buildEditableField(BuildContext context, IconData icon, String label,
      TextEditingController controller,
      {String? hint,
      bool isMultiLine = false,
      TextInputType keyboardType = TextInputType.text,
      String? Function(String?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = controller.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment:
            isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding:
                EdgeInsets.only(top: isMultiLine ? 12.0 : 0.0, right: 16.0),
            child: Icon(icon,
                size: 20,
                color: Theme.of(context)
                    .listTileTheme
                    .iconColor
                    ?.withOpacity(0.8)),
          ),
          Expanded(
            child: _isEditing
                ? TextFormField(
                    controller: controller,
                    keyboardType:
                        isMultiLine ? TextInputType.multiline : keyboardType,
                    textInputAction: isMultiLine
                        ? TextInputAction.newline
                        : TextInputAction.next,
                    maxLines: isMultiLine ? null : 1,
                    minLines: isMultiLine ? 2 : 1,
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                    decoration: _buildInputDecoration(label, hintText: hint),
                    validator: validator,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue.isEmpty ? 'Not provided' : displayValue,
                          style: textTheme.bodyMedium?.copyWith(
                              color: displayValue.isEmpty
                                  ? Colors.grey[500]
                                  : textTheme.bodyMedium?.color,
                              height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableDropdownField(
      BuildContext context,
      IconData icon,
      String label,
      String? currentValue,
      List<String> options,
      Function(String?) onChanged,
      {String? hint,
      String? Function(String?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue = currentValue ?? 'Not provided';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Icon(icon,
                  size: 20,
                  color: Theme.of(context)
                      .listTileTheme
                      .iconColor
                      ?.withOpacity(0.8))),
          Expanded(
            child: _isEditing
                ? DropdownButtonFormField<String>(
                    value: currentValue,
                    items: options
                        .map((String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value,
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: darkTeal),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: onChanged,
                    decoration: _buildInputDecoration(label, hintText: hint),
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                    isExpanded: true,
                    validator: validator,
                    hint: hint != null
                        ? Text(hint,
                            style: Theme.of(context)
                                .inputDecorationTheme
                                .hintStyle)
                        : null,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue,
                          style: textTheme.bodyMedium?.copyWith(
                              color: currentValue == null
                                  ? Colors.grey[500]
                                  : textTheme.bodyMedium?.color,
                              height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableMultiSelectField(
      BuildContext context,
      IconData icon,
      String label,
      List<String> currentValues,
      List<String> allItems,
      Function(List<String>) onConfirm,
      {String? hint,
      String? Function(List<dynamic>?)? validator}) {
    final textTheme = Theme.of(context).textTheme;
    final displayValue =
        currentValues.isEmpty ? 'Not provided' : currentValues.join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(top: 12.0, right: 16.0),
              child: Icon(icon,
                  size: 20,
                  color: Theme.of(context)
                      .listTileTheme
                      .iconColor
                      ?.withOpacity(0.8))),
          Expanded(
            child: _isEditing
                ? MultiSelectDialogField<String>(
                    items: allItems
                        .map((item) => MultiSelectItem(item, item))
                        .toList(),
                    initialValue: currentValues,
                    title: Text(label),
                    buttonText: Text(label,
                        style: textTheme.bodyMedium?.copyWith(
                            color: primaryTeal, fontWeight: FontWeight.w500)),
                    decoration: BoxDecoration(
                        color: textFieldFillColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: lightTeal, width: 1.0)),
                    chipDisplay: MultiSelectChipDisplay(
                      chipColor: lightTeal.withOpacity(0.9),
                      textStyle: textTheme.bodySmall
                          ?.copyWith(color: darkTeal, fontSize: 11.5),
                      icon: Icon(Icons.close,
                          color: darkTeal.withOpacity(0.7), size: 14),
                      onTap: (value) =>
                          setState(() => currentValues.remove(value)),
                      scrollBar: HorizontalScrollBar(isAlwaysShown: false),
                      scroll: true,
                      alignment: Alignment.centerLeft,
                    ),
                    selectedColor: primaryTeal,
                    selectedItemsTextStyle:
                        textTheme.bodyMedium?.copyWith(color: primaryTeal),
                    itemsTextStyle:
                        textTheme.bodyMedium?.copyWith(color: darkTeal),
                    searchable: true,
                    searchHint: 'Search $label',
                    confirmText: const Text('OK'),
                    cancelText: const Text('CANCEL'),
                    onConfirm: (results) =>
                        onConfirm(List<String>.from(results)),
                    validator: validator,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(displayValue,
                          style: textTheme.bodyMedium?.copyWith(
                              color: currentValues.isEmpty
                                  ? Colors.grey[500]
                                  : textTheme.bodyMedium?.color,
                              height: 1.4)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSampleMenuGallery(BuildContext context, String sampleMenuUrls) {
    final List<String> urls = sampleMenuUrls
        .split(',')
        .map((url) => url.trim())
        .where((url) =>
            url.isNotEmpty &&
            (url.startsWith('http://') || url.startsWith('https://')))
        .toList();
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
              Icon(Icons.menu_book_rounded,
                  size: 20,
                  color: Theme.of(context)
                      .listTileTheme
                      .iconColor
                      ?.withOpacity(0.8)),
              const SizedBox(width: 12),
              Text("Sample Menu",
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
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

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

extension OrdersTabRefreshExtension on _OrdersTabState {
  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    print("OrdersTab: manualRefreshFromAppBar triggered.");
    _loadOrders();
    while (mounted && _isLoadingOrders) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print("OrdersTab: manualRefreshFromAppBar completed.");
  }
}

class _OrdersTabState extends State<OrdersTab>
    with AutomaticKeepAliveClientMixin {
  final Set<int> _loadingOrderIds =
      {}; // Track loading states for specific orders

  Future<List<Order>>? _ordersFuture;
  List<Order> _allFetchedOrders = [];
  List<Order> _mealOrders = [];
  String _selectedFilter = 'All';
  bool _isLoadingOrders = false;
  bool _didLoadOrders = false;

  final List<String> _orderStatusesForFilter = [
    // Renamed for clarity
    'All', statusPending, statusAccepted, statusPreparing, statusReadyForPickup,
    statusAssigned, statusOutForDelivery, statusDelivered, statusCancelled,
    statusVerificationNeeded, statusCompleted,
  ];

  Timer? _ordersPollingTimer;

  @override
  bool get wantKeepAlive => true;

  void _startOrdersPolling() {
    _ordersPollingTimer?.cancel();
    _ordersPollingTimer =
        Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;
      await _pollOrdersStatus();
    });
  }

  Future<void> _pollOrdersStatus() async {
    try {
      final fetchedOrders = await ApiService().fetchOrders();
      if (!mounted) return;
      // Only update statuses, don't disrupt overlays/dialogs
      for (final fetched in fetchedOrders) {
        final idx = _mealOrders.indexWhere((o) => o.orderId == fetched.orderId);
        if (idx != -1 && _mealOrders[idx].orderStatus != fetched.orderStatus) {
          setState(() {
            _mealOrders[idx].orderStatus = fetched.orderStatus;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _startOrdersPolling();
  }

  @override
  void dispose() {
    _ordersPollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadOrders) {
      _didLoadOrders = true;
      _loadOrders();
    }
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _isLoadingOrders = true;
      _allFetchedOrders = [];
      _mealOrders = [];
      _ordersFuture = ApiService().fetchOrders();
    });
    try {
      final fetchedOrders =
          await _ordersFuture!.timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _allFetchedOrders = fetchedOrders;
      _mealOrders = _allFetchedOrders
          .where((order) =>
              order.orderType?.toLowerCase() == 'meal' ||
              order.orderType == null ||
              order.orderType!.isEmpty)
          .toList();
      _mealOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    } on TimeoutException {
      print("Timeout fetching orders.");
      if (mounted) {
        _showErrorSnackbar(
            'Request timed out. Please check your connection and try again.');
        _allFetchedOrders = [];
        _mealOrders = [];
      }
    } catch (error, stackTrace) {
      print("Error in _loadOrders (OrdersTab): $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading orders: ${error.toString()}');
        _allFetchedOrders = [];
        _mealOrders = [];
      }
    } finally {
      if (mounted) setState(() => _isLoadingOrders = false);
    }
  }

  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return;
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _RiderSelectionDialog(
          apiService: ApiService(), orderId: order.orderId),
    );
    if (!mounted || result == null) {
      // Handle null (cancel) or unmounted
      if (result == null) print('Rider assignment cancelled or dialog closed.');
      return;
    }

    if (result is Rider) {
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      await _markReadyForAnyRider(order);
    }
  }

  Future<void> _showRiderAssignmentConfirmation(
      Order order, Rider rider) async {
    if (!mounted) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Confirm Assignment for Order #${order.orderId}'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign this order to rider:'),
              const SizedBox(height: 8),
              Text('  Name: ${rider.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('  Status: ${rider.isActive ? "Active" : "Inactive"}'),
              Text('  ID: ${rider.id}'),
              if (!rider.isActive)
                Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Warning: Rider is currently inactive.',
                        style: TextStyle(color: Colors.orange.shade800))),
            ]),
        actions: <Widget>[
          TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false)),
          TextButton(
              child: Text(
                  rider.isActive ? 'Confirm Assignment' : 'Assign Anyway',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary)),
              onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      await _assignSpecificRider(order, rider);
    } else {
      _showInfoSnackbar("Rider assignment cancelled.");
    }
  }

  Future<void> _assignSpecificRider(Order order, Rider rider) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _mealOrders[orderIndex].orderStatus;
    final originalRiderId = _mealOrders[orderIndex].assignedRiderId;
    final originalRiderName = _mealOrders[orderIndex].assignedRiderName;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);

    setState(() {
      _mealOrders[orderIndex].orderStatus = statusAssigned;
      _mealOrders[orderIndex].assignedRiderId = rider.id;
      _mealOrders[orderIndex].assignedRiderName = rider.name;
      if (allIndex != -1) {
        _allFetchedOrders[allIndex].orderStatus = statusAssigned;
        _allFetchedOrders[allIndex].assignedRiderId = rider.id;
        _allFetchedOrders[allIndex].assignedRiderName = rider.name;
      }
    });
    _showLoadingSnackbar("Assigning to ${rider.name}...");

    try {
      bool success = await ApiService.assignOrderToRider(
          order.orderId, rider.id, statusAssigned);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar(
              'Order ${order.orderId} assigned to ${rider.name}.');
          _showOrderNextStepDialog(statusAssigned);
        } else {
          _showErrorSnackbar(
              'Failed to assign order ${order.orderId} to ${rider.name}.');
          setState(() {
            // Revert
            _mealOrders[orderIndex].orderStatus = originalStatus;
            _mealOrders[orderIndex].assignedRiderId = originalRiderId;
            _mealOrders[orderIndex].assignedRiderName = originalRiderName;
            if (allIndex != -1) {/* revert _allFetchedOrders too */}
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('An error occurred assigning rider.');
        setState(() {/* Revert */});
      }
    }
  }

  Future<void> _markReadyForAnyRider(Order order) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _mealOrders[orderIndex].orderStatus;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);

    setState(() {
      _mealOrders[orderIndex].orderStatus = statusReadyForPickup;
      _mealOrders[orderIndex].assignedRiderId = null;
      _mealOrders[orderIndex].assignedRiderName = null;
      if (allIndex != -1) {/* update _allFetchedOrders */}
    });
    _showLoadingSnackbar("Marking order as ready...");

    try {
      bool success = await ApiService.updateOrderStatus(
          order.orderId, statusReadyForPickup);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar(
              'Order ${order.orderId} marked as Ready for Pickup.');
          _showOrderNextStepDialog(statusReadyForPickup);
        } else {
          _showErrorSnackbar(
              'Failed to mark order ${order.orderId} as Ready for Pickup.');
          setState(() {/* Revert */});
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('Error updating order status.');
        setState(() {/* Revert */});
      }
    }
  }

  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final originalStatus = _mealOrders[orderIndex].orderStatus;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);

    setState(() {
      _mealOrders[orderIndex].orderStatus = newStatus;
      if (allIndex != -1) {
        _allFetchedOrders[allIndex].orderStatus = newStatus;
        if (newStatus == statusPreparing || newStatus == statusCancelled) {
          _mealOrders[orderIndex].assignedRiderId = null;
          _mealOrders[orderIndex].assignedRiderName = null;
          _allFetchedOrders[allIndex].assignedRiderId = null;
          _allFetchedOrders[allIndex].assignedRiderName = null;
        }
      }
    });
    _showLoadingSnackbar("Updating status to $newStatus...");

    try {
      bool success =
          await ApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (!success) {
          setState(() {/* Revert */});
          _showErrorSnackbar('Failed to update order ${order.orderId} status.');
        } else {
          _showSuccessSnackbar(
              'Order ${order.orderId} status updated to $newStatus.');
          _showOrderNextStepDialog(newStatus);
          setState(() {});
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {/* Revert */});
        _showErrorSnackbar('Error updating order status: ${e.toString()}');
      }
    }
  }

  // This method handles the flow for marking an order as delivered or completed
  // It shows a verification dialog to collect the completion code from the customer
  Future<void> _initiateCompletionFlow(Order order, String targetStatus) async {
    if (!mounted) return;
    final orderId = order.orderId;
    setState(() => _loadingOrderIds.add(orderId));
    try {
      final chefIdString = await ApiService._getChefId();
      final chefId = int.tryParse(chefIdString ?? '');
      if (chefId == null) {
        setState(() => _loadingOrderIds.remove(orderId));
        _showErrorSnackbar('Chef ID not found.');
        return;
      }
      await ApiService.updateOrderStatus(orderId, targetStatus, chefId: chefId);
      setState(() => _loadingOrderIds.remove(orderId));
      // Immediately show the completion code dialog, do not refresh or check status
      _showCompletionCodeVerificationDialog(context, order, targetStatus);
    } catch (e) {
      setState(() => _loadingOrderIds.remove(orderId));
      _showErrorSnackbar('Error updating order status: ${e.toString()}');
    }
  }

  void _showCompletionCodeVerificationDialog(
      BuildContext context, Order order, String targetStatus) {
    // Show dialog immediately, do not refresh orders after completion
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _CompletionCodeDialog(
          order: order,
          targetStatus: targetStatus,
          onSuccess: () {
            // Do nothing: silent background status update will handle UI
          },
          onError: (String errorMessage) {
            if (mounted) {
              _showErrorSnackbar(errorMessage);
            }
          },
          showLoadingCallback: (String message) {
            if (mounted) {
              _showLoadingSnackbar(message);
            }
          },
          dismissLoadingCallback: () {
            if (mounted) {
              _dismissLoadingSnackbar();
            }
          },
        );
      },
    );
  }

  int _findOrderIndex(int orderId) {
    final index = _mealOrders.indexWhere((o) => o.orderId == orderId);
    if (index == -1) print("Warning: Order $orderId not found in _mealOrders.");
    return index;
  }

  List<Order> _getFilteredMealOrders() {
    if (_selectedFilter == 'All') return _mealOrders;
    return _mealOrders
        .where((order) =>
            order.orderStatus.toLowerCase() == _selectedFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Order>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        Widget body;
        final bool isLoading = _isLoadingOrders;
        if (isLoading && _mealOrders.isEmpty) {
          body = _buildOrdersShimmer();
        } else if (snapshot.hasError && _mealOrders.isEmpty) {
          body =
              _buildErrorState(snapshot.error?.toString() ?? 'Unknown error.');
        } else {
          final filteredOrders = _getFilteredMealOrders();
          if (_mealOrders.isEmpty && !isLoading) {
            body = _buildEmptyState('You have no meal orders yet.');
          } else if (filteredOrders.isEmpty &&
              _mealOrders.isNotEmpty &&
              _selectedFilter != 'All') {
            body = _buildEmptyState('No meal orders match "$_selectedFilter".');
          } else {
            body = _buildOrderList(
                _selectedFilter == 'All' ? _mealOrders : filteredOrders);
          }
        }
        return Column(children: [
          _buildFilterChips(!isLoading || _mealOrders.isNotEmpty),
          Expanded(child: body)
        ]);
      },
    );
  }

  Widget _buildOrderList(List<Order> ordersToShow) {
    return RefreshIndicator(
      onRefresh: () async => _loadOrders(),
      color: Theme.of(context).colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: ordersToShow.length,
        itemBuilder: (context, index) => _buildOrderCard(
            context, ordersToShow[index],
            handleReadyForShipping: _handleReadyForShipping,
            updateSimpleStatus: _updateSimpleOrderStatus),
      ),
    );
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

  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(whiteColor)),
        const SizedBox(width: 16),
        Text(message)
      ]),
      duration: const Duration(minutes: 1),
      backgroundColor: Colors.black87,
    ));
  }

  void _dismissLoadingSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showOrderNextStepDialog(String newStatus) {
    if (!mounted) return;
    String title = "Status Updated";
    String message = "Order status changed to $newStatus.";
    switch (newStatus) {
      case statusAccepted:
        title = "Order Accepted!";
        message =
            "Great! Start preparing. Mark 'Ready' or 'Assign Rider' when done.";
        break;
      case statusPreparing:
        title = "Preparation Started";
        message = "Keep it up! Mark 'Ready' or 'Assign Rider' once ready.";
        break;
      case statusReadyForPickup:
        title = "Ready for Pickup!";
        message = "Order available for any rider to collect.";
        break;
      case statusAssigned:
        title = "Rider Assigned!";
        message = "Assigned rider notified to pick up.";
        break;
      case statusOutForDelivery:
        title = "Out for Delivery";
        message = "Rider is on their way.";
        break;
      case statusDelivered:
        title = "Order Delivered!";
        message = "Customer received their order.";
        break;
      case statusCompleted:
        title = "Order Completed!";
        message = "This order is now completed.";
        break;
      case statusVerificationNeeded:
        title = "Verification Required";
        message = "A verification code is needed from the customer.";
        break;
      case statusCancelled:
        title = "Order Cancelled";
        message = "The order has been cancelled.";
        break;
      case statusShipped:
        title = "Order Shipped";
        message = "Order marked as shipped.";
        break;
      default:
        message = "Order status is now '$newStatus'.";
    }
    showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Text(title),
              content: Text(message),
              actions: <Widget>[
                TextButton(
                    child: const Text("OK"),
                    onPressed: () => Navigator.of(context).pop())
              ],
            ));
  }

  Widget _buildOrdersShimmer() {
    /* ... Same as provided ... */
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
        itemCount: 5,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: whiteColor,
                        borderRadius: BorderRadius.circular(22))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          height: 18,
                          color: whiteColor,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: 14,
                          color: whiteColor),
                    ])),
                const SizedBox(width: 16),
                Container(
                    width: 80,
                    height: 25,
                    decoration: BoxDecoration(
                        color: whiteColor,
                        borderRadius: BorderRadius.circular(15))),
              ]),
            )),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    /* ... Same as provided ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error, size: 50),
        const SizedBox(height: 16),
        Text('Error Loading Orders',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadOrders)
      ]),
    ));
  }

  Widget _buildEmptyState(String message) {
    /* ... Same as provided ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(message,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Refresh'),
            onPressed: _loadOrders,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey[700]))
      ]),
    ));
  }

  Widget _buildFilterChips(bool showChips) {
    if (!showChips) return const SizedBox.shrink();
    final statuses = _orderStatusesForFilter; // Use the renamed list
    final chipTheme = Theme.of(context).chipTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Wrap(
            spacing: 8.0,
            children: statuses.map((status) {
              final isSelected = _selectedFilter == status;
              return ChoiceChip(
                label: Text(status),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedFilter = status);
                },
                selectedColor: colorScheme.primary.withOpacity(0.15),
                backgroundColor: chipTheme.backgroundColor ?? lighterTeal,
                labelStyle: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : (chipTheme.labelStyle?.color ?? Colors.black),
                    fontSize: 13),
                side: isSelected
                    ? BorderSide(color: colorScheme.primary, width: 1)
                    : (chipTheme.side ??
                        BorderSide(color: Colors.grey.shade300, width: 0.8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                visualDensity: VisualDensity.compact,
              );
            }).toList()),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Order order,
      {required Function(Order) handleReadyForShipping,
      required Function(Order, String) updateSimpleStatus}) {
    debugPrint(
        '[GIGS] _buildOrderCard called for orderId: \\${order.orderId}, status: \\${order.orderStatus}');
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a',
        Localizations.localeOf(context).toString());
    final statusColor = _getStatusColor(order.orderStatus);
    final statusIcon = _getStatusIcon(order.orderStatus);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<int>(order.orderId),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        onExpansionChanged: (isExpanding) {
          debugPrint(
              '[GIGS] onExpansionChanged called for orderId: \\${order.orderId}, isExpanding: \\${isExpanding}, status: \\${order.orderStatus}');
          if (isExpanding &&
              order.orderStatus.toLowerCase() ==
                  statusVerificationNeeded.toLowerCase()) {
            debugPrint(
                '[GIGS] Triggering verification dialog for orderId: \\${order.orderId} (status: \\${order.orderStatus})');
            _initiateCompletionFlow(
                order, statusDelivered); // Or statusCompleted directly
          }
        },
        leading: CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(statusIcon, color: statusColor, size: 22)),
        title: Text(order.mealName,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: Text(
                '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
                style: textTheme.bodySmall)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_loadingOrderIds.contains(order.orderId))
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          if (order.orderStatus.toLowerCase() ==
              statusVerificationNeeded.toLowerCase())
            Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: Icon(Icons.warning_amber_rounded,
                    color: kColorWarning, size: 20)),
          Chip(
            label: Text(order.orderStatus, overflow: TextOverflow.ellipsis),
            backgroundColor: statusColor.withOpacity(0.15),
            labelStyle: TextStyle(
                color: statusColor, fontWeight: FontWeight.w600, fontSize: 11),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
          ),
        ]),
        iconColor: colorScheme.primary,
        collapsedIconColor: Colors.grey[500],
        backgroundColor: colorScheme.surface,
        collapsedBackgroundColor: colorScheme.surface,
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
                .copyWith(top: 0),
        children: [
          Builder(builder: (_) {
            debugPrint(
                '[GIGS] ExpansionTile children built for orderId: ${order.orderId}');
            return SizedBox.shrink();
          }),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          _buildDetailRow(context, Icons.person_outline_rounded, 'Customer ID',
              order.userId?.toString() ?? 'N/A'),
          _buildDetailRow(context, Icons.storefront_outlined, 'Producer',
              order.producerName),
          _buildDetailRow(context, Icons.shopping_bag_outlined, 'Quantity',
              order.quantity.toString()),
          _buildDetailRow(context, Icons.payment_rounded, 'Payment',
              '${order.paymentStatus} (${order.totalPrice})'),
          _buildDetailRow(context, Icons.location_on_outlined, 'Delivery To',
              order.deliveryAddress),
          _buildDetailRow(context, Icons.restaurant_outlined,
              'Ingredients Req.', order.ingredients),
          _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
          if (order.assignedRiderId != null)
            _buildDetailRow(
                context,
                Icons.two_wheeler_rounded,
                'Assigned Rider',
                '${order.assignedRiderName ?? 'Rider ID: ${order.assignedRiderId}'}'),
          const SizedBox(height: 16),
          _buildActionButtons(
              context, order, handleReadyForShipping, updateSimpleStatus),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      BuildContext context,
      Order order,
      Function(Order) handleReadyForShipping,
      Function(Order, String) updateSimpleStatus) {
    final currentStatus = order.orderStatus.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;

    final canAccept = currentStatus == statusPending.toLowerCase();
    final canReadyOrAssign = currentStatus == statusPreparing.toLowerCase() ||
        currentStatus == statusAccepted.toLowerCase();
    final canReject = currentStatus != statusDelivered.toLowerCase() &&
        currentStatus != statusCompleted.toLowerCase() &&
        currentStatus != statusCancelled.toLowerCase() &&
        currentStatus != statusOutForDelivery.toLowerCase();
    final canMarkDelivered =
        (currentStatus == statusOutForDelivery.toLowerCase() ||
                currentStatus == statusAssigned.toLowerCase() ||
                currentStatus == statusReadyForPickup.toLowerCase()) &&
            currentStatus != statusDelivered.toLowerCase() &&
            currentStatus != statusCompleted.toLowerCase();
    final canMarkCompleted = (currentStatus == statusDelivered.toLowerCase() ||
            currentStatus == statusOutForDelivery.toLowerCase()) &&
        currentStatus != statusCompleted.toLowerCase();
    final needsVerification =
        currentStatus == statusVerificationNeeded.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            if (canAccept)
              TextButton.icon(
                  icon:
                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Accept'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700),
                  onPressed: () => updateSimpleStatus(order, statusAccepted)),
            if (canReadyOrAssign)
              Tooltip(
                  message: 'Mark Ready for Pickup or Assign Specific Rider',
                  child: TextButton.icon(
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Text('Ready/Assign'),
                      style: TextButton.styleFrom(
                          foregroundColor: readyForPickupColor),
                      onPressed: () => handleReadyForShipping(order))),
            if (canMarkDelivered)
              TextButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Mark Delivered'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700),
                  onPressed: () =>
                      _initiateCompletionFlow(order, statusDelivered)),
            if (canMarkCompleted)
              TextButton.icon(
                  icon:
                      const Icon(Icons.assignment_turned_in_outlined, size: 18),
                  label: const Text('Mark Completed'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700),
                  onPressed: () =>
                      _initiateCompletionFlow(order, statusCompleted)),
            if (canReject)
              TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Reject'),
                  style:
                      TextButton.styleFrom(foregroundColor: colorScheme.error),
                  onPressed: () => _showRejectConfirmation(
                      context, order, updateSimpleStatus)),
          ]),
    );
  }

  void _showRejectConfirmation(BuildContext context, Order order,
      Function(Order, String) updateSimpleStatusCallback) {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text("Confirm Rejection"),
              content: Text(
                  "Reject Order #${order.orderId} (${order.mealName})? This cannot be undone."),
              actions: <Widget>[
                TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.of(dialogContext).pop()),
                TextButton(
                    child: Text("Reject Order",
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      updateSimpleStatusCallback(order, statusCancelled);
                    }),
              ],
            ));
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            size: 18,
            color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
        const SizedBox(width: 12),
        Expanded(
            child: RichText(
                text: TextSpan(style: textTheme.bodyMedium, children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          TextSpan(text: value),
        ])))
      ]),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade600;
      case 'accepted':
        return Colors.lightBlue.shade600;
      case 'preparing':
        return Colors.blue.shade700;
      case 'ready for pickup':
        return readyForPickupColor;
      case 'assigned':
        return assignedColor;
      case 'shipped':
      case 'out for delivery':
        return Colors.purple.shade500;
      case 'delivered':
      case 'completed':
        return Colors.green.shade600;
      case 'verification needed':
        return kColorWarning;
      case 'cancelled':
      case 'rejected':
        return Colors.red.shade500;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_bottom_rounded;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'preparing':
        return Icons.soup_kitchen_rounded;
      case 'ready for pickup':
        return Icons.inventory_2_outlined;
      case 'assigned':
        return Icons.person_pin_circle_outlined;
      case 'shipped':
        return Icons.local_shipping_outlined;
      case 'out for delivery':
        return Icons.two_wheeler_rounded;
      case 'delivered':
      case 'completed':
        return Icons.check_circle_rounded;
      case 'verification needed':
        return Icons.password_rounded;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

// Separate stateful widget for the completion code dialog to properly manage controller lifecycle
class _CompletionCodeDialog extends StatefulWidget {
  final Order order;
  final String targetStatus;
  final VoidCallback onSuccess;
  final Function(String) onError;
  final Function(String) showLoadingCallback;
  final VoidCallback dismissLoadingCallback;

  const _CompletionCodeDialog({
    Key? key,
    required this.order,
    required this.targetStatus,
    required this.onSuccess,
    required this.onError,
    required this.showLoadingCallback,
    required this.dismissLoadingCallback,
  }) : super(key: key);

  @override
  _CompletionCodeDialogState createState() => _CompletionCodeDialogState();
}

class _CompletionCodeDialogState extends State<_CompletionCodeDialog> {
  final TextEditingController _completionCodeController =
      TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  @override
  void dispose() {
    // Properly dispose the controller when the widget is disposed
    _completionCodeController.dispose();
    super.dispose();
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Verify Completion Code',
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryTeal)),
      content: Form(
          key: _formKey,
          child: SingleChildScrollView(
              child: ListBody(children: <Widget>[
            Text(
                'Please ask the customer for the completion code to mark order as ${widget.targetStatus.toLowerCase()}:',
                style: TextStyle(color: subtleTextColor)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _completionCodeController,
              decoration: InputDecoration(
                  labelText: 'Completion Code', border: OutlineInputBorder()),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Please enter code' : null,
            ),
            if (_errorMessage != null && _errorMessage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
          ]))),
      actions: <Widget>[
        TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop()),
        ElevatedButton(
            child: const Text('Submit Code'), onPressed: _submitCode),
      ],
    );
  }

  Future<void> _submitCode() async {
    if (_formKey.currentState!.validate()) {
      final codeToSubmit = _completionCodeController.text;
      widget.showLoadingCallback('Submitting code...');

      try {
        bool success = await ApiService.updateOrderStatus(
            widget.order.orderId, widget.targetStatus,
            completionCode: codeToSubmit);

        widget.dismissLoadingCallback();

        if (mounted) {
          if (success) {
            Navigator.of(context).pop(); // Close the dialog
            widget.onSuccess();
          }
        }
      } catch (e) {
        widget.dismissLoadingCallback();
        if (mounted) {
          _setError(e.toString());
        }
      }
    }
  }
}

class _RiderSelectionDialog extends StatefulWidget {
  final ApiService apiService;
  final int orderId;
  const _RiderSelectionDialog(
      {required this.apiService, required this.orderId, Key? key})
      : super(key: key);
  @override
  _RiderSelectionDialogState createState() => _RiderSelectionDialogState();
}

class _RiderSelectionDialogState extends State<_RiderSelectionDialog> {
  List<Rider> _allRiders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    if (mounted)
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    try {
      final riders = await widget.apiService.fetchAvailableRiders();
      if (mounted) {
        riders.sort((a, b) {
          // Sort by active status first, then by name
          if (a.isActive && !b.isActive) return -1;
          if (!a.isActive && b.isActive) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        setState(() {
          _allRiders = riders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _errorMessage = "Error fetching riders: ${e.toString()}";
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Assign Rider/Staff'),
        IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchRiders,
            tooltip: 'Refresh List',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero),
      ]),
      content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.5,
          child: _buildContent()),
      actions: <Widget>[
        TextButton(
            child: const Text("Mark Ready (Any)"),
            onPressed: () =>
                Navigator.of(context).pop(true)), // True for "Any Rider"
        TextButton(
            child: const Text("Cancel"),
            onPressed: () =>
                Navigator.of(context).pop(null)), // Null for cancel
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null)
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                ElevatedButton(
                    onPressed: _fetchRiders, child: const Text("Retry"))
              ])));
    if (_allRiders.isEmpty)
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(8.0),
              child:
                  Text("No riders/staff found.", textAlign: TextAlign.center)));

    return ListView.builder(
      itemCount: _allRiders.length,
      itemBuilder: (context, index) {
        final rider = _allRiders[index];
        final bool isAvailable = rider.isActive;
        final Color tileColor = isAvailable
            ? Theme.of(context).dialogBackgroundColor
            : Colors.grey.shade200;
        final Color textColor = isAvailable
            ? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black)
            : Colors.grey.shade600;
        final Color iconColor =
            isAvailable ? primaryTeal : Colors.grey.shade500;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: isAvailable ? 0.5 : 0.5,
          color: tileColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: isAvailable
                  ? BorderSide.none
                  : BorderSide(color: Colors.grey.shade300)),
          child: ListTile(
            leading: CircleAvatar(
                backgroundColor: iconColor.withOpacity(0.1),
                child: Icon(Icons.two_wheeler, color: iconColor, size: 20)),
            title: Text(rider.name,
                style: TextStyle(
                    color: textColor,
                    fontWeight:
                        isAvailable ? FontWeight.normal : FontWeight.w300)),
            subtitle: Text(isAvailable ? 'Status: Active' : 'Status: Inactive',
                style: TextStyle(color: textColor.withOpacity(0.7))),
            trailing: isAvailable
                ? const Icon(Icons.chevron_right)
                : Icon(Icons.block,
                    color: Colors.grey.shade500,
                    size: 18), // Updated icon for inactive
            onTap: () =>
                Navigator.of(context).pop(rider), // Pop with the Rider object
            dense: true,
          ),
        );
      },
    );
  }
}

class GigsTab extends StatefulWidget {
  const GigsTab({super.key});
  @override
  State<GigsTab> createState() => _GigsTabState();
}

extension GigsTabRefreshExtension on _GigsTabState {
  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    print("GigsTab: manualRefreshFromAppBar triggered.");
    _loadOrders();
    while (mounted && _isLoadingGigs) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print("GigsTab: manualRefreshFromAppBar completed.");
  }
}

class _GigsTabState extends State<GigsTab> with AutomaticKeepAliveClientMixin {
  final Set<int> _loadingOrderIds =
      {}; // Track loading states for specific gig orders

  @override
  bool get wantKeepAlive => true;

  Future<List<Order>>? _ordersFuture;
  List<Order> _allFetchedOrders = [];
  List<Order> _gigOrders = [];
  bool _isLoadingGigs = false;
  String? _errorMessage;
  bool _didLoadGigs = false;
  // Track previous gig statuses for smarter UI updates
  final Map<int, String> _previousGigStatuses = {};

  Timer? _gigsPollingTimer;
  bool _isVerificationProcessActive = false;

  @override
  void initState() {
    super.initState();
    _startGigsPolling();
  }

  void _startGigsPolling() {
    _gigsPollingTimer?.cancel();
    _gigsPollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _isVerificationProcessActive) return;
      await _pollGigsStatus();
    });
  }

  void _pauseGigsPolling() {
    _gigsPollingTimer?.cancel();
  }

  void _resumeGigsPolling() {
    if (_gigsPollingTimer == null || !_gigsPollingTimer!.isActive) {
      _startGigsPolling();
    }
  }

  Future<void> _pollGigsStatus() async {
    try {
      final fetchedOrders = await ApiService().fetchOrders();
      if (!mounted) return;
      final newGigOrders = fetchedOrders
          .where((o) => o.orderType?.toLowerCase() == 'gig')
          .toList()
        ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

      // Build new status map
      final Map<int, String> newStatusMap = {
        for (final o in newGigOrders) o.orderId: o.orderStatus
      };

      // Check for changes: status or data
      bool dataChanged = false;
      if (newGigOrders.length != _gigOrders.length) {
        dataChanged = true;
      } else {
        for (int i = 0; i < newGigOrders.length; i++) {
          final old = _gigOrders[i];
          final updated = newGigOrders[i];
          if (old.orderId != updated.orderId ||
              old.orderStatus != updated.orderStatus ||
              old.orderDate != updated.orderDate ||
              old.totalPrice != updated.totalPrice) {
            dataChanged = true;
            break;
          }
        }
      }
      // Also check for any status changes
      for (final entry in newStatusMap.entries) {
        if (_previousGigStatuses[entry.key] != entry.value) {
          dataChanged = true;
          break;
        }
      }
      if (dataChanged) {
        setState(() {
          _allFetchedOrders = fetchedOrders;
          _gigOrders = newGigOrders;
          _previousGigStatuses
            ..clear()
            ..addAll(newStatusMap);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _gigsPollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadGigs) {
      _didLoadGigs = true;
      _loadOrders();
    }
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _isLoadingGigs = true;
      _errorMessage = null;
      _allFetchedOrders = [];
      _gigOrders = [];
      _ordersFuture = ApiService().fetchOrders();
    });
    try {
      final fetchedOrders = await _ordersFuture!;
      if (mounted) {
        _allFetchedOrders = fetchedOrders;
        _gigOrders = _allFetchedOrders
            .where((o) => o.orderType?.toLowerCase() == 'gig')
            .toList();
        _gigOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
        setState(() => _isLoadingGigs = false);
      }
    } catch (e, stackTrace) {
      if (mounted) {
        _errorMessage = "Failed to load gigs: ${e.toString()}";
        setState(() {
          _isLoadingGigs = false;
          _allFetchedOrders = [];
          _gigOrders = [];
        });
      }
    }
  }

  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return;
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _RiderSelectionDialog(
          apiService: ApiService(), orderId: order.orderId),
    );
    if (!mounted || result == null) {
      if (result == null) print('Staff assignment cancelled for Gig.');
      return;
    }
    if (result is Rider) {
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      await _markReadyForAnyRider(order);
    }
  }

  Future<void> _showRiderAssignmentConfirmation(
      Order order, Rider rider) async {
    if (!mounted) return;
    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Text('Confirm Assignment for Gig #${order.orderId}'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assign this Gig to:'),
                    const SizedBox(height: 8),
                    Text('  Name: ${rider.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('  Status: ${rider.isActive ? "Active" : "Inactive"}'),
                    Text('  ID: ${rider.id}'),
                    if (!rider.isActive)
                      Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('Warning: Staff is currently inactive.',
                              style: TextStyle(color: Colors.orange.shade800))),
                  ]),
              actions: <Widget>[
                TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(dialogContext).pop(false)),
                TextButton(
                    child: Text(rider.isActive
                        ? 'Confirm Assignment'
                        : 'Assign Anyway'),
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary),
                    onPressed: () => Navigator.of(dialogContext).pop(true)),
              ],
            ));
    if (confirm == true) {
      if (!mounted) return;
      await _assignSpecificRider(order, rider);
    } else {
      _showInfoSnackbar("Assignment cancelled.");
    }
  }

  Future<void> _assignSpecificRider(Order order, Rider rider) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _gigOrders[orderIndex]
        .orderStatus; /* ... and other original fields ... */
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);
    setState(() {
      /* Optimistic UI update */
      _gigOrders[orderIndex].orderStatus = statusAssigned;
      _gigOrders[orderIndex].assignedRiderId = rider.id;
      _gigOrders[orderIndex].assignedRiderName = rider.name;
      if (allIndex != -1) {/* update _allFetchedOrders */}
    });
    _showLoadingSnackbar("Assigning ${rider.name} to Gig...");
    try {
      bool success = await ApiService.assignOrderToRider(
          order.orderId, rider.id, statusAssigned);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar(
              "Staff ${rider.name} assigned to Gig ${order.orderId}.");
          _showOrderNextStepDialog(statusAssigned);
        } else {
          _showErrorSnackbar('Failed to assign ${rider.name}.');
          setState(() {/* Revert */});
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {/* Revert */});
        _showErrorSnackbar('Error assigning staff.');
      }
    }
  }

  Future<void> _markReadyForAnyRider(Order order) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _gigOrders[orderIndex].orderStatus;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);
    setState(() {
      /* Optimistic UI update */
      _gigOrders[orderIndex].orderStatus =
          statusReadyForPickup; // For gigs, this might mean ready for service/staff
      _gigOrders[orderIndex].assignedRiderId = null;
      _gigOrders[orderIndex].assignedRiderName = null;
      if (allIndex != -1) {/* update _allFetchedOrders */}
    });
    _showLoadingSnackbar("Marking Gig as Ready...");
    try {
      bool success = await ApiService.updateOrderStatus(
          order.orderId, statusReadyForPickup);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar("Gig ${order.orderId} marked as Ready.");
          _showOrderNextStepDialog(statusReadyForPickup);
        } else {
          _showErrorSnackbar('Failed to mark Gig Ready.');
          setState(() {/* Revert */});
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('Error marking Gig Ready.');
        setState(() {/* Revert */});
      }
    }
  }

  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final originalStatus = _gigOrders[orderIndex].orderStatus;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);
    setState(() {
      /* Optimistic UI update */
      _gigOrders[orderIndex].orderStatus = newStatus;
      if (allIndex != -1) {
        _allFetchedOrders[allIndex].orderStatus = newStatus;
        if (newStatus == statusPreparing ||
            newStatus == statusCancelled ||
            newStatus == statusAccepted) {
          _gigOrders[orderIndex].assignedRiderId = null;
          _gigOrders[orderIndex].assignedRiderName = null;
          _allFetchedOrders[allIndex].assignedRiderId = null;
          _allFetchedOrders[allIndex].assignedRiderName = null;
        }
      }
    });
    _showLoadingSnackbar("Updating Gig status to $newStatus...");
    try {
      bool success =
          await ApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Gig ${order.orderId} status updated.');
          _showOrderNextStepDialog(newStatus);
          setState(() {});
        } else {
          _showErrorSnackbar('Failed to update Gig status.');
          setState(() {/* Revert */});
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {/* Revert */});
        _showErrorSnackbar('Error updating Gig status: ${e.toString()}');
      }
    }
  }

  Future<void> _updateGigStatus(Order order, String targetStatus) async {
    if (!mounted) return;
    final orderId = order.orderId;
    setState(() => _loadingOrderIds.add(orderId));
    try {
      final chefIdString = await ApiService._getChefId();
      final chefId = int.tryParse(chefIdString ?? '');
      if (chefId == null) {
        if (!mounted) return;
        setState(() => _loadingOrderIds.remove(orderId));
        _showErrorSnackbar('Chef ID not found.');
        return;
      }
      bool success = await ApiService.updateOrderStatus(orderId, targetStatus,
          chefId: chefId);
      if (!mounted) return;
      setState(() => _loadingOrderIds.remove(orderId));
      if (success) {
        if (!mounted) return;
        _showSuccessSnackbar('Gig #$orderId marked as $targetStatus.');
      } else {
        if (!mounted) return;
        _showErrorSnackbar('Failed to update gig status.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOrderIds.remove(orderId));
      _showErrorSnackbar('Error updating gig status: ${e.toString()}');
    }
  }

  Future<void> _initiateCompletionFlow(Order order, String targetStatus) async {
    debugPrint(
        '[GIGS][FLOW] _initiateCompletionFlow called for orderId: ${order.orderId}, status: ${order.orderStatus}, targetStatus: ${targetStatus}');
    if (!mounted) return;
    final orderId = order.orderId;
    setState(() => _loadingOrderIds.add(orderId));
    try {
      final chefIdString = await ApiService._getChefId();
      final chefId = int.tryParse(chefIdString ?? '');
      if (chefId == null) {
        setState(() => _loadingOrderIds.remove(orderId));
        _showErrorSnackbar('Chef ID not found.');
        return;
      }
      await ApiService.updateOrderStatus(orderId, targetStatus, chefId: chefId);
      setState(() => _loadingOrderIds.remove(orderId));
      // Immediately show the completion code dialog, do not refresh or check status
      _showCompletionCodeVerificationDialog(context, order, targetStatus);
    } catch (e) {
      setState(() => _loadingOrderIds.remove(orderId));
      _showErrorSnackbar('Error updating order status: ${e.toString()}');
    }
  }

  void _showCompletionCodeVerificationDialog(
      BuildContext context, Order order, String targetStatus) {
    debugPrint(
        '[GIGS][DIALOG] Showing completion code verification dialog for orderId: ${order.orderId}, targetStatus: ${targetStatus}');
    // Show dialog immediately, do not refresh gigs after completion
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _CompletionCodeDialog(
          order: order,
          targetStatus: targetStatus,
          onSuccess: () {
            // Do nothing: silent status update will handle UI
          },
          onError: (String errorMessage) {
            // Error will now be shown inline in the dialog
          },
          showLoadingCallback: (String message) {
            if (mounted) {
              _showLoadingSnackbar(message);
            }
          },
          dismissLoadingCallback: () {
            if (mounted) {
              _dismissLoadingSnackbar();
            }
          },
        );
      },
    );
  }

  int _findOrderIndex(int orderId) =>
      _gigOrders.indexWhere((o) => o.orderId == orderId);
  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4)));
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: Colors.green.shade600));
  }

  void _showInfoSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: Colors.blueGrey.shade600));
  }

  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(whiteColor)),
          const SizedBox(width: 16),
          Text(message)
        ]),
        duration: const Duration(minutes: 1),
        backgroundColor: Colors.black87));
  }

  void _dismissLoadingSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showOrderNextStepDialog(String newStatus) {
    if (!mounted) return;
    String title = "Gig Status Updated";
    String message = "Gig status changed to $newStatus.";
    switch (newStatus) {
      case statusAccepted:
        title = "Gig Accepted!";
        message = "Great! Prepare. Mark 'Ready' or 'Assign Staff' when set.";
        break;
      case statusPreparing:
        title = "Gig Preparation Started";
        message = "Mark 'Ready' or 'Assign Staff' once complete.";
        break;
      case statusReadyForPickup:
        title = "Gig Ready!";
        message = "Gig ready. Staff/rider can proceed.";
        break; // "Ready for Pickup" is a bit meal-centric, but okay for now
      case statusAssigned:
        title = "Staff Assigned!";
        message = "Assigned person notified for this gig.";
        break;
      case statusOutForDelivery:
        title = "Gig In Progress";
        message = "Service is underway.";
        break; // "Out for Delivery" for gigs could mean "Service Started" or "En Route"
      case statusDelivered:
      case statusCompleted:
        title = "Gig Completed!";
        message = "Fantastic! Gig successfully completed.";
        break;
      case statusCancelled:
        title = "Gig Cancelled";
        message = "The gig has been cancelled.";
        break;
      case statusShipped:
        title = "Gig Service Started";
        message = "Service for this gig has begun.";
        break;
      default:
        message = "Gig status is now '$newStatus'.";
    }
    showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                title: Text(title),
                content: Text(message),
                actions: <Widget>[
                  TextButton(
                      child: const Text("OK"),
                      onPressed: () => Navigator.of(context).pop())
                ]));
  }

  Widget _buildOrdersShimmer() {
    /* ... Same as OrdersTab ... */
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
        itemCount: 5,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: whiteColor,
                        borderRadius: BorderRadius.circular(22))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          height: 18,
                          color: whiteColor,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: 14,
                          color: whiteColor),
                    ])),
                const SizedBox(width: 16),
                Container(
                    width: 80,
                    height: 25,
                    decoration: BoxDecoration(
                        color: whiteColor,
                        borderRadius: BorderRadius.circular(15))),
              ]),
            )),
      ),
    );
  }

  Widget _buildErrorState(String errorMsg) {
    /* ... Same as OrdersTab ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error, size: 50),
        const SizedBox(height: 16),
        Text('Error Loading Gigs',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(errorMsg,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadOrders)
      ]),
    ));
  }

  Widget _buildEmptyState(String message) {
    /* ... Same as OrdersTab, maybe different icon ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.work_off_outlined,
            size: 60, color: Colors.grey[400]), // Changed Icon
        const SizedBox(height: 16),
        Text(message,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Refresh'),
            onPressed: _loadOrders,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey[700]))
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Order>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        final bool isLoading = _isLoadingGigs;
        if (isLoading && _gigOrders.isEmpty) return _buildOrdersShimmer();
        if (_errorMessage != null && _gigOrders.isEmpty)
          return _buildErrorState(_errorMessage!);
        if (snapshot.hasError && _gigOrders.isEmpty && _errorMessage == null)
          return _buildErrorState(snapshot.error.toString());
        if (_gigOrders.isEmpty && !isLoading)
          return _buildEmptyState('You have no gigs yet.');
        return _buildGigList();
      },
    );
  }

  Widget _buildGigList() {
    return RefreshIndicator(
      onRefresh: () async => _loadOrders(),
      color: Theme.of(context).colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _gigOrders.length,
        itemBuilder: (context, index) => _buildOrderCard(
          context,
          _gigOrders[index],
          handleReadyForShipping: _handleReadyForShipping,
          updateSimpleStatus: _updateSimpleOrderStatus,
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    Order order, {
    required Function(Order) handleReadyForShipping,
    required Function(Order, String) updateSimpleStatus,
  }) {
    if (order.orderStatus.toLowerCase() ==
        statusVerificationNeeded.toLowerCase()) {
      debugPrint(
          '[GIGS][BUILD] Gig card built: orderId: \\${order.orderId}, status: \\${order.orderStatus} [VERIFICATION NEEDED]');
    } else {
      debugPrint(
          '[GIGS][BUILD] Gig card built: orderId: \\${order.orderId}, status: \\${order.orderStatus}');
    }
    final textTheme = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy ' "at" ' h:mm a',
        Localizations.localeOf(context).toString());
    final statusColor = _getStatusColor(order.orderStatus);
    final statusIcon = _getStatusIcon(order.orderStatus);
    return GestureDetector(
      onTap: () async {
        debugPrint(
            '[GIGS][UI][TAP] Gig tapped: orderId: ${order.orderId}, status: ${order.orderStatus}');
        if (order.orderStatus.toLowerCase() ==
            statusVerificationNeeded.toLowerCase()) {
          debugPrint(
              '[GIGS][UI][TAP] Verification needed - showing verification dialog for orderId: ${order.orderId}');
          try {
            setState(() => _isVerificationProcessActive = true);
            // Use the ChefVerificationHelper to show the verification dialog
            final bool verified =
                await ChefVerificationHelper.showVerificationDialog(
                    context, order);
            if (verified && mounted) {
              // If verification was successful, update the gig status to completed
              await ChefVerificationHelper.updateOrderStatusAfterVerification(
                  order.orderId, statusCompleted);
              _showSuccessSnackbar(
                  'Gig #${order.orderId} verified and marked as completed!');
              // Refresh the gigs list
              _loadOrders();
            }
          } catch (e, stack) {
            debugPrint(
                '[GIGS][UI][ERROR] Exception in verification handler for gig: ${e.toString()}\n$stack');
            if (mounted) {
              _showErrorSnackbar('Verification failed: ${e.toString()}');
            }
          } finally {
            if (mounted) {
              setState(() => _isVerificationProcessActive = false);
            }
          }
        }
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey<int>(order.orderId),
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          leading: CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          title: Text(
            order.mealName,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: Text(
              '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
              style: textTheme.bodySmall,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingOrderIds.contains(order.orderId))
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              _buildStatusChip(order.orderStatus),
            ],
          ),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(context, Icons.person_outline, 'Customer',
                      order.customerName),
                  _buildDetailRow(context, Icons.location_on_outlined,
                      'Location', order.deliveryAddress),
                  _buildDetailRow(context, Icons.list_alt_rounded,
                      'Requirements', order.ingredients),
                  _buildDetailRow(
                      context, Icons.notes_rounded, 'Notes', order.notes),
                  if (order.assignedRiderId != null)
                    _buildDetailRow(
                      context,
                      Icons.badge_outlined,
                      'Assigned Staff',
                      order.assignedRiderName ?? 'ID: ${order.assignedRiderId}',
                    ),
                  const SizedBox(height: 16),
                  _buildActionButtons(context, order, handleReadyForShipping,
                      updateSimpleStatus),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 10),
            _buildDetailRow(context, Icons.person_outline_rounded, 'Customer',
                order.userId?.toString() ?? order.customerName ?? 'N/A'),
            _buildDetailRow(context, Icons.event_seat_outlined, 'Guests/Qty',
                order.quantity.toString()),
            _buildDetailRow(context, Icons.payment_rounded, 'Payment',
                '${order.paymentStatus} (${order.totalPrice})'),
            _buildDetailRow(context, Icons.location_on_outlined, 'Location',
                order.deliveryAddress),
            _buildDetailRow(context, Icons.list_alt_rounded, 'Requirements',
                order.ingredients),
            _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
            if (order.assignedRiderId != null)
              _buildDetailRow(context, Icons.badge_outlined, 'Assigned Staff',
                  '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}'),
            const SizedBox(height: 16),
            _buildActionButtons(
                context, order, handleReadyForShipping, updateSimpleStatus),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
      BuildContext context,
      Order order,
      Function(Order) handleReadyForShipping,
      Function(Order, String) updateSimpleStatus) {
    final currentStatus = order.orderStatus.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;
    final isPending = currentStatus == statusPending.toLowerCase();
    final isAccepted = currentStatus == statusAccepted.toLowerCase();
    final isInProgress = currentStatus == statusPreparing.toLowerCase() ||
        currentStatus == statusOutForDelivery.toLowerCase();
    final isCompleted = currentStatus == statusCompleted.toLowerCase() ||
        currentStatus == statusDelivered.toLowerCase();
    final needsVerification =
        currentStatus == statusVerificationNeeded.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            if (isPending)
              TextButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Accept'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.green.shade700),
                onPressed: () => _updateGigStatus(order, statusAccepted),
              ),
            if (isAccepted)
              TextButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('In Progress'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade700),
                onPressed: () => _updateGigStatus(order, statusPreparing),
              ),
            if (needsVerification)
              TextButton.icon(
                icon: const Icon(Icons.password_rounded, size: 18),
                label: const Text('Verify Completion'),
                style: TextButton.styleFrom(foregroundColor: kColorWarning),
                onPressed: () async {
                  try {
                    setState(() => _isVerificationProcessActive = true);
                    // Use the ChefVerificationHelper to show the verification dialog
                    final bool verified =
                        await ChefVerificationHelper.showVerificationDialog(
                            context, order);
                    if (verified && mounted) {
                      // If verification was successful, update the gig status to completed
                      await ChefVerificationHelper
                          .updateOrderStatusAfterVerification(
                              order.orderId, statusCompleted);
                      _showSuccessSnackbar(
                          'Gig #${order.orderId} verified and marked as completed!');
                      // Refresh the gigs list
                      _loadOrders();
                    }
                  } catch (e) {
                    if (mounted) {
                      _showErrorSnackbar(
                          'Verification failed: ${e.toString()}');
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isVerificationProcessActive = false);
                    }
                  }
                },
              ),
            if (isInProgress && !isCompleted && !needsVerification)
              TextButton.icon(
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: const Text('Mark Completed'),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.blue.shade700),
                onPressed: () =>
                    _initiateCompletionFlow(order, statusCompleted),
              ),
          ]),
    );
  }

  void _showRejectConfirmation(BuildContext context, Order order,
      Function(Order, String) updateSimpleStatusCallback) {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text("Confirm Rejection"),
              content:
                  Text("Reject Gig #${order.orderId} (${order.mealName})?"),
              actions: <Widget>[
                TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.of(dialogContext).pop()),
                TextButton(
                    child: Text("Reject Gig",
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      updateSimpleStatusCallback(order, statusCancelled);
                    }),
              ],
            ));
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            size: 18,
            color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
        const SizedBox(width: 12),
        Expanded(
            child: RichText(
                text: TextSpan(style: textTheme.bodyMedium, children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          TextSpan(text: value),
        ])))
      ]),
    );
  }

  Color _getStatusColor(String status) {
    /* ... Same as OrdersTab ... */
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade600;
      case 'accepted':
        return Colors.lightBlue.shade600;
      case 'preparing':
        return Colors.blue.shade700;
      case 'ready for pickup':
        return readyForPickupColor; // For gigs, this could mean "Ready for Service"
      case 'assigned':
        return assignedColor;
      case 'shipped': // For gigs, "Service Started" or "En Route"
      case 'out for delivery':
        return Colors.purple.shade500;
      case 'delivered':
      case 'completed':
        return Colors.green.shade600;
      case 'cancelled':
      case 'rejected':
        return Colors.red.shade500;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getStatusIcon(String status) {
    /* ... Same as OrdersTab, icons might need adjustment for "Gig" context ... */
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_bottom_rounded;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'preparing':
        return Icons.construction_outlined; // More generic for prep
      case 'ready for pickup':
        return Icons.flag_circle_outlined; // Ready for service
      case 'assigned':
        return Icons.badge_outlined; // Staff assigned
      case 'shipped': // Service started / en route
      case 'out for delivery':
        return Icons.directions_run_outlined; // Or specific gig icon
      case 'delivered':
      case 'completed':
        return Icons.celebration_outlined; // Gig done
      case 'verification needed':
        return Icons.password_rounded; // Verification icon
      case 'cancelled':
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Widget _buildStatusChip(String status) {
    final Color statusColor = _getStatusColor(status);
    return Chip(
      label: Text(status, overflow: TextOverflow.ellipsis),
      backgroundColor: statusColor.withOpacity(0.15),
      labelStyle: TextStyle(
          color: statusColor, fontWeight: FontWeight.w600, fontSize: 11),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

extension ProductsTabRefreshExtension on _ProductsTabState {
  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    print("ProductsTab: manualRefreshFromAppBar triggered.");
    _loadProducts();
    while (mounted && _isLoadingProducts) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print("ProductsTab: manualRefreshFromAppBar completed.");
  }
}

class _ProductsTabState extends State<ProductsTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<MealProduct>>? _productsFuture;
  List<MealProduct> _products = [];
  bool _isLoadingProducts = false;
  bool _didLoadProducts = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadProducts) {
      _didLoadProducts = true;
      _loadProducts();
    }
  }

  void _loadProducts() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _isLoadingProducts = true;
      _products = [];
      _productsFuture = ApiService.fetchProducts();
    });
    _productsFuture!.then((products) {
      if (mounted) {
        _products = products;
        _products.sort((a, b) => a.mealName.compareTo(b.mealName));
        setState(() => _isLoadingProducts = false);
      }
    }).catchError((error, stackTrace) {
      if (mounted) {
        _showErrorSnackbar('Error loading menu: ${error.toString()}');
        setState(() {
          _isLoadingProducts = false;
          _products = [];
        });
      }
    });
  }

  void _showComingSoonSnackbar(String featureName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$featureName feature is Coming Soon!',
          style: const TextStyle(color: whiteColor)),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      duration: const Duration(seconds: 2),
    ));
  }

  void _handleAddProduct() => _showComingSoonSnackbar("Adding new meals");
  void _handleEditProduct(MealProduct product) =>
      _showComingSoonSnackbar("Editing meals");
  void _handleDeleteProduct(MealProduct product) =>
      _showComingSoonSnackbar("Deleting meals");
  void _handleToggleSelection(MealProduct product) =>
      _showComingSoonSnackbar("Selecting meals for stock");
  Future<void> _handleUpdateStock() async =>
      _showComingSoonSnackbar("Updating stock levels");

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: FutureBuilder<List<MealProduct>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          final bool isLoading = _isLoadingProducts;
          if (isLoading && _products.isEmpty) return _buildProductsShimmer();
          if (snapshot.hasError && _products.isEmpty)
            return _buildErrorState(
                snapshot.error?.toString() ?? 'Unknown error.');
          if (_products.isEmpty && !isLoading)
            return _buildEmptyState('No menu items. Add your first meal!');
          return _buildProductList(_products);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleAddProduct,
        tooltip: 'Add New Meal (Coming Soon)',
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add Meal"),
      ),
    );
  }

  Widget _buildProductList(List<MealProduct> productsToShow) {
    return RefreshIndicator(
      onRefresh: () async => _loadProducts(),
      color: Theme.of(context).colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 90.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: productsToShow.length,
        itemBuilder: (context, index) => _buildProductCard(
            context, productsToShow[index],
            onEdit: () => _handleEditProduct(productsToShow[index]),
            onSelectToggle: () => _handleToggleSelection(productsToShow[index]),
            onDelete: () => _handleDeleteProduct(productsToShow[index]),
            isSelected: false), // Forced false as selection is "Coming Soon"
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    /* ... Same as other tabs ... */
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4)));
  }

  Widget _buildProductsShimmer() {
    /* ... Same as provided ... */
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHighlight,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8.0, bottom: 90.0),
        itemCount: 4,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                        color: whiteColor,
                        borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          height: 18,
                          color: whiteColor,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: double.infinity,
                          height: 14,
                          color: whiteColor,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.25,
                          height: 14,
                          color: whiteColor,
                          margin: const EdgeInsets.only(bottom: 8)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.2,
                          height: 18,
                          color: whiteColor),
                    ])),
                const SizedBox(width: 8),
                Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: whiteColor,
                          borderRadius: BorderRadius.circular(18))),
                ])
              ]),
            )),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    /* ... Same as provided ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.restaurant_menu_outlined,
            color: Theme.of(context).colorScheme.error, size: 50),
        const SizedBox(height: 16),
        Text('Error Loading Menu',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(error,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadProducts)
      ]),
    ));
  }

  Widget _buildEmptyState(String message) {
    /* ... Same as provided ... */
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.menu_book_rounded, size: 60, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(message,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text("Use the '+' button below to add one (Coming Soon).",
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[500]),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Refresh'),
            onPressed: _loadProducts,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey[700]))
      ]),
    ));
  }

  Widget _buildProductCard(BuildContext context, MealProduct product,
      {required VoidCallback onEdit,
      required VoidCallback onSelectToggle,
      required VoidCallback onDelete,
      required bool isSelected}) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final formatCurrency = NumberFormat.currency(
        locale: 'en_UG', symbol: 'UGX ', decimalDigits: 0);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 90,
              height: 90,
              child: CachedImageWithShimmer(
                imageUrl: product.imageLink,
                width: 90,
                height: 90,
                borderRadius: 8.0,
                fit: BoxFit.cover,
                errorIcon: Icons.restaurant_menu_outlined,
                iconSize: 35,
                errorText: "No Image",
              )),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(product.mealName.isEmpty ? '(No Name)' : product.mealName,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(product.mealDescription ?? 'No description.',
                    style: textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(formatCurrency.format(product.price),
                    style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary)),
              ])),
          const SizedBox(width: 8),
          Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(context,
                    icon: Icons.radio_button_unchecked_rounded,
                    tooltip: 'Select (Coming Soon)',
                    color: Colors.grey.shade400,
                    onPressed: onSelectToggle),
                // Edit and Delete are also "Coming Soon" via their handlers
                // _buildActionButton(context, icon: Icons.edit_outlined, tooltip: 'Edit (Coming Soon)', color: Colors.blueGrey, onPressed: onEdit),
                // _buildActionButton(context, icon: Icons.delete_outline, tooltip: 'Delete (Coming Soon)', color: Colors.redAccent, onPressed: onDelete),
              ])
        ]),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context,
      {required IconData icon,
      required String tooltip,
      required Color color,
      required VoidCallback onPressed}) {
    return SizedBox(
        height: 36,
        width: 36,
        child: IconButton(
          icon: Icon(icon, size: 20),
          color: color,
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          splashRadius: 22,
        ));
  }
}
