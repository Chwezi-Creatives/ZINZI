import 'package:flutter/material.dart';
import 'package:zinzi2/app_drawer.dart'; // Import the AppDrawer widget
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
import 'package:zinzi2/user_cache.dart'; // <<< IMPORT UserCache
import 'package:zinzi2/cache_config.dart'; // <<< IMPORT CacheConfig
// http and dart:convert are already imported

// --- Consistent Color Palette (from chefsignup222.dart) ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color lighterTeal = Color(0xFFE0F2F1); // Teal 50
const Color darkTeal = Color(0xFF004D40); // Teal 900
const Color accentTeal = Color(0xFF009688); // Teal 500
const Color whiteColor = Colors.white; // Main background color
const Color textFieldFillColor = Color(0xFFF5F5F5); // Light grey fill for inputs on white BG
const Color subtleTextColor = Color(0xFF757575); // Grey 600
const Color errorColor = Color(0xFFD32F2F); // Red 700 for errors
const Color disabledColor = Colors.grey;
const Color readyForPickupColor = Colors.blueAccent; // Color for Ready for Pickup status
const Color assignedColor = Colors.deepPurpleAccent; // Color for Assigned status

// --- Predefined value lists (from chefsignup222.dart) ---
// These are needed for dropdowns and multi-selects during editing
final List<String> responseTimes = ["Immediate", "1 Hour", "2 Hours", "4 Hours"];
final List<String> teamSizes = ["1", "2", "3", "4", "5", "6+", "10+"];
final List<String> minNoticeOptions = ["1 hour notice", "1 day notice", "1 Week notice", "1 Month notice", "1 Quarter", "1 Year notice"];
final List<String> allLanguages = ["English", "Runyankole", "Indian", "Rukiga", "Luganda", "Arabic", "Jewish", "Lusoga", "Lugbala", "Spanish", "French", "German", "Italian"];
final List<String> allSpecialties = ["Barbeque", "Mixologists", "Baristers", "Pastry", "Ugandan", "Salads", "Juices", "Luwombo", "West African", "Ethiopian", "Eritrean", "Somali", "Congolese", "Thai", "Jewish", "Indian"];
final List<String> allCertifications = ["None", "Food handling & Safety", "Culinary Arts", "Nutrition", "Pastry"];
final List<String> allEquipment = ["None", "Plates", "Cups", "Grill", "Oven", "Measuring cups", "Tables", "Dishes", "Knife Set", "Cutting Board"];
final List<String> allAvailability = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
// chefTypes is not directly needed for profile editing here
final List<String> perGigCategories = ['5 people', '10 people', '20+ people', '50+ people', '100+ people'];
final Map<String, String> perGigCategoryKeys = {'5 people': '5_people', '10 people': '10_people', '20+ people': '20_plus_people', '50+ people': '50_plus_people', '100+ people': '100_plus_people'};

// Load environment variables (ensure .env file is present and loaded in main())
// Example: await dotenv.load(fileName: ".env"); in main()
final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
    'https://your-api.example.com'; // Provide a fallback

// --- Data Models (ChefProfile, Order, MealProduct, Rider) ---
// Keeping data models the same as they are well-defined.
// Small modification to ChefProfile for editability tracking.
class ChefProfile {
  final int chefid;
  String name; // Mutable for editing
  String? bio; // Mutable for editing
  String? image; // URL - Mutable for editing
  String? availability; // Comma-separated String - Mutable for editing
  String? certifications; // Comma-separated String - Mutable for editing
  final String chefType; // Likely not editable
  int? experience; // Mutable for editing
  String? languages; // Comma-separated String - Mutable for editing
  String? location; // Mutable for editing
  String? minNotice; // Mutable for editing
  String? price; // Mutable for editing
  String? responseTime; // Mutable for editing
  String? sampleMenu; // Comma-separated String URLs - Potentially editable via a different mechanism
  String? specialties; // Comma-separated String - Mutable for editing
  String? teamSize; // Mutable for editing
  bool isActive; // Mutable for toggle
  String? equipment; // Comma-separated String - Mutable for editing

  // Added field to track local image file for editing
  File? localImageFile;
  Map<String, dynamic>? pricing; // Added for detailed pricing {per_month: num, per_gig: {key: num}}

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
    this.equipment,
    this.pricing, // Added
    this.localImageFile, // Initialize with null
  });

  // Factory constructor remains the same for parsing initial data
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
          : (json['is_active'] == 'true' || json['is_active'] == 1),
      equipment: _joinListSafe(json['equipment']),
      // Parse nested pricing data safely
      pricing: json['pricing'] is Map<String, dynamic> ? Map<String, dynamic>.from(json['pricing']) : null,
    );
  }

  // Method to convert profile to JSON for updating (only editable fields)
  // NOTE: Image handling needs separate multipart request logic in ApiService
  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'bio': bio,
      // 'image': image, // Image handled separately
      'availability': availability,
      'certifications': certifications,
      'chef_type': chefType, // Include non-editable but potentially useful fields
      'experience': experience,
      'languages': languages,
      'location': location,
      'minnotice': minNotice, // Match API key if different from field name
      'price': price, // Keep the general price field for now
      'responsetime': responseTime, // Match API key if different from field name
      'specialties': specialties,
      'teamsize': teamSize, // Match API key if different from field name
      'equipment': equipment,
      'pricing': pricing, // Added pricing map
      'is_active': isActive, // Status might be updated here or via separate endpoint
    }..removeWhere((key, value) => value == null); // Remove nulls if API doesn't like them
  }
}

// --- Order Model ---
class Order {
  final int orderId;
  final String mealName;
  final String? producerName;
  final DateTime orderDate;
  String orderStatus; // Mutable
  final String paymentStatus;
  final String totalPrice;
  final String? deliveryAddress;
  final String? ingredients;
  final String? notes;
  final int quantity;
  final int? userId; // Allow null
  final String? orderType; // <<< Used for filtering
  int? assignedRiderId; // <<< NEW: To hold assigned rider ID
  String? assignedRiderName; // <<< NEW: Optional, for display

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
    this.assignedRiderId, // <<< NEW
    this.assignedRiderName, // <<< NEW
  });

  // Factory constructor remains the same
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

    return Order(
      orderId: _parseIntSafe(json['order_id']),
      mealName: _getStringSafe(json['meal_name']) ?? 'N/A',
      producerName: _getStringSafe(json['producer_name']),
      orderDate: parsedDate,
      orderStatus: _getStringSafe(json['order_status']) ?? 'Unknown',
      paymentStatus: _getStringSafe(json['payment_status']) ?? 'Unknown',
      totalPrice: _getStringSafe(json['total_price']) ?? '0.00',
      deliveryAddress: _getStringSafe(json['delivery_address']),
      ingredients: _getStringSafe(json['ingredients']),
      notes: _getStringSafe(json['notes']),
      quantity: _parseIntSafe(json['quantity']),
      userId: _parseIntNullable(json['user_id']),
      orderType: _getStringSafe(json['order_type']),
      assignedRiderId: _parseIntNullable(json['assigned_rider_id']), // <<< NEW
      assignedRiderName: _getStringSafe(json['assigned_rider_name']), // <<< NEW
    );
  }
}

// --- MealProduct Model ---
// Keeping this model the same
class MealProduct {
  final String mealId;
  final String mealName;
  final String? mealDescription;
  final String? imageLink; // URL
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

  // Factory constructor remains the same
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
      mealId: _getStringSafe(json['Meal_id'] ?? json['meal_id'] ?? json['id']) ?? 'N/A_ID',
      mealName: _getStringSafe(json['Meal_name'] ?? json['meal_name'] ?? json['name']) ?? 'N/A',
      mealDescription: _getStringSafe(json['Meal_description'] ?? json['meal_description'] ?? json['description']),
      imageLink: _isValidUrl(_getStringSafe(json['Image_link'] ?? json['image_link'] ?? json['image']))
          ? _getStringSafe(json['Image_link'] ?? json['image_link'] ?? json['image'])
          : null,
      price: parsePrice(json['Price'] ?? json['price']),
      ingredients: _getStringSafe(json['Ingredients'] ?? json['ingredients']),
      prepTime: _getStringSafe(json['Prep_time'] ?? json['prep_time']),
      skillLevel: _getStringSafe(json['Skill_level'] ?? json['skill_level']),
      mealCategory: _getStringSafe(json['Meal_category'] ?? json['meal_category']),
      complementaryDishes: _getStringSafe(json['Complementary_dishes'] ?? json['complementary_dishes']),
      dietaryPreference: _getStringSafe(json['Dietary_preference'] ?? json['dietary_preference']),
      allergies: _getStringSafe(json['Allergies'] ?? json['allergies']),
    );
  }
}

// --- Rider/Transporter Model (NEW) ---
class Rider {
  final int id;
  final String name;
  final String status; // Keep original status string if needed elsewhere
  final bool isActive; // NEW: Field for availability based on 'is_active'
  // Add other relevant fields like phone, current_location etc. if provided by API

  Rider({
    required this.id,
    required this.name,
    required this.status,
    required this.isActive, // Add to constructor
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

      // Helper to parse boolean safely
      bool _parseBoolSafe(dynamic value) {
        if (value == null) return false;
        if (value is bool) return value;
        if (value is String) return value.toLowerCase() == 'true';
        if (value is int) return value == 1; // Handle potential integer representation
        return false;
      }

    return Rider(
      // Adjust keys based on the actual API response for /rrtransporters
      id: _parseIntNullable(json['rider_id'] ?? json['transporter_id'] ?? json['id']) ?? 0,
      name: _getStringSafe(json['name'] ?? json['rider_name'] ?? json['transporter_name']) ?? 'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown', // Keep original status string
      // Ensure _parseBoolSafe is called even if json['is_active'] is null
      isActive: _parseBoolSafe(json['is_active']),
    );
  }
}


// --- API Service (ApiService) ---
class ApiService {
  static String apibaseurl = '';
  ApiService() {
    apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
        'https://your-api.example.com'; // Provide a fallback
  }

  static Future<String?> _getChefId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('chef_user_id');
    } catch (e) {
      print("Error accessing SharedPreferences: $e");
      return null;
    }
  }

  // --- Update Chef Stock (Modified to show "Coming Soon") ---
  Future<bool> updateChefStock(String payload) async {
    // <<< MODIFICATION: Immediately return false and potentially show message
    // (Message shown in UI layer)
    print("Stock Update Triggered (Coming Soon)");
    return false; // Indicate failure/block
  }

  static dynamic _handleApiResponse(dynamic responseData) {
    // Keeping this helper as is
    if (responseData is List) {
      return responseData;
    } else if (responseData is Map && responseData.containsKey('data')) {
      if (responseData['data'] is List) {
        return responseData['data'];
      } else {
        print("API Warning: Response has 'data' key but value is not a List.");
        return responseData['data']; // Return the non-list data? Or null? Returning data for now.
      }
    } else if (responseData is Map && responseData.containsKey('All_Meals')) {
      if (responseData['All_Meals'] is List) {
        return responseData['All_Meals'];
      } else {
        print("API Warning: Response has 'All_Meals' key but value is not a List.");
        return null;
      }
    } else if (responseData is Map) {
      // If it's just a map, return it directly (e.g., single object response)
      return responseData;
    }
    print("API Warning: Unhandled response format. Expected List or Map. Got: ${responseData.runtimeType}");
    return null; // Return null if format is completely unknown
  }

  // --- Fetch Chef Profile (Remains the same) ---
  Future<ChefProfile> fetchChefProfile() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/rchefs/$chefId');
    print("Fetching profile from: $uri");

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);
        if (handledData == null) {
          // Check if rawData was a list/map before handling, maybe it was just empty
          if (rawData is List && rawData.isEmpty) {
             throw Exception('Failed to parse profile: API returned an empty list.');
          } else if (rawData is Map && rawData.isEmpty) {
             throw Exception('Failed to parse profile: API returned an empty map.');
          }
          throw Exception('Failed to parse profile: Unexpected API response format after handling.');
        }
        Map<String, dynamic> profileMap;
        // Handle cases where API might return a list with one chef, or just the chef object directly
        if (handledData is List && handledData.isNotEmpty) {
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception('Failed to parse profile: Expected a map inside the list.');
          }
        } else if (handledData is Map<String, dynamic>) {
          // Check if it's the actual profile map or still nested under 'data' somehow
          if (handledData.containsKey('chefid')) { // Heuristic check
             profileMap = handledData;
          } else {
              // Maybe it was nested like {'data': {chef details}} - handleApiResponse might return the inner map
              // Re-check if this case needs specific handling based on API
             throw Exception('Failed to parse profile: Result is not a usable Map.');
          }

        } else {
          throw Exception('Failed to parse profile: Result is not a usable Map or List.');
        }
        return ChefProfile.fromMockJson(profileMap);
      } else {
        print("Error fetching profile: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load chef profile (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching profile: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load chef profile: $e');
    }
  }

  // --- Update Chef Profile (NEW METHOD for text fields) ---
  Future<bool> updateChefProfile(int chefId, Map<String, dynamic> profileData) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/chefs/$chefId'); // Assuming PATCH/PUT to /rr/chefs/{chefId}
    print("Updating profile for chef $chefId at: $uri with data: ${jsonEncode(profileData)}");

    try {
      // Using PATCH assuming partial updates are allowed
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(profileData),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print("Profile update successful for chef $chefId");
        return true;
      } else {
        print("Error updating chef profile for $chefId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating chef profile: $e");
      return false;
    }
  }

  // --- Update Chef Profile Image (NEW METHOD - Placeholder) ---
  // This would typically involve a multipart request
  Future<String?> updateChefProfileImage(int chefId, File imageFile) async {
    // <<< MODIFICATION: Placeholder for "Coming Soon"
    print("Profile Image Update Triggered (Coming Soon) for Chef ID: $chefId");
    // Simulate success returning null (no new URL) or a placeholder
    // In a real scenario:
    // 1. Create multipart request
    // 2. Add image file
    // 3. Add other fields if needed (e.g., chef_id)
    // 4. Send request
    // 5. Parse response (might contain the new image URL)
    // final Uri uri = Uri.parse('$apibaseurl/rr/chefs/$chefId/image'); // Example endpoint
    // var request = http.MultipartRequest('POST', uri); // Or PUT/PATCH
    // request.headers.addAll(_getWriteHeaders(requiresAuth: true)); // Add auth if needed
    // request.files.add(await http.MultipartFile.fromPath('profile_image', imageFile.path));
    // request.fields['chef_id'] = chefId.toString(); // Example field
    // try {
    //   var streamedResponse = await request.send();
    //   var response = await http.Response.fromStream(streamedResponse);
    //   if (response.statusCode == 200 || response.statusCode == 201) {
    //     final responseData = json.decode(response.body);
    //     // Extract the new image URL from responseData, e.g., responseData['imageUrl']
    //     return responseData['imageUrl'];
    //   } else {
    //     print("Error uploading image: ${response.statusCode} ${response.body}");
    //     return null;
    //   }
    // } catch (e) {
    //   print("Exception uploading image: $e");
    //   return null;
    // }
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
    return null; // Indicate no new URL or feature not ready
  }


  // --- Fetch Orders (Remains the same - Tabs will filter) ---
  Future<List<Order>> fetchOrders() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/orders?chef_id=$chefId');
    print("Fetching orders from: $uri");

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic ordersList = _handleApiResponse(rawData);
        if (ordersList is List) {
          return ordersList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return Order.fromMockJson(jsonItem);
                } else {
                  print("API Warning: Skipping non-map item in orders list: $jsonItem");
                  return null;
                }
              })
              .whereType<Order>()
              .toList();
        } else {
          print("Orders API response format unexpected: Expected a List after handling. Got: ${ordersList?.runtimeType}");
          if (ordersList == null || (ordersList is Map && ordersList.isEmpty)) {
             return []; // Return empty list if response was null or empty map
          }
          // If ordersList is not null and not empty map, but also not a list, throw error
          throw Exception('Failed to parse orders: Unexpected API response format (not a list)');
        }
      } else {
        print("Error fetching orders: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load orders (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching orders: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load orders: $e');
    }
  }

  // --- Fetch Products/Meals (Remains the same) ---
  static Future<List<MealProduct>> fetchProducts() async {
    final Uri uri = Uri.parse('$apibaseurl/rr/meals');
    print("Fetching products/menu from: $uri");
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        List<dynamic>? menuList;
        // Check if the response itself is the list
        if (rawData is List) {
           menuList = rawData;
        }
        // Check if it's nested under 'data'
        else if (rawData is Map<String, dynamic> && rawData.containsKey('data')) {
           if (rawData['data'] is List) {
             menuList = rawData['data'];
           } else {
             print("Products API Warning: 'data' key exists but value is not a List.");
             menuList = null;
           }
        }
        // Check if it's nested under 'All_Meals'
        else if (rawData is Map<String, dynamic> && rawData.containsKey('All_Meals')) {
             if (rawData['All_Meals'] is List) {
                menuList = rawData['All_Meals'];
             } else {
                print("API Warning: Response has 'All_Meals' key but value is not a List.");
                menuList = null;
             }
        }
        // Try the general handler as a fallback
        else {
          dynamic handledData = _handleApiResponse(rawData); // This might return a List
          if(handledData is List){
             menuList = handledData;
          } else {
             print("Products API Warning: Response is not a recognized list format. Handling returned: ${handledData?.runtimeType}");
             menuList = null;
          }
        }

        // Process the extracted list
        if (menuList != null) {
          return menuList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return MealProduct.fromMockJson(jsonItem);
                } else {
                  print("API Warning: Skipping non-map item in menu/products list: $jsonItem");
                  return null;
                }
              })
              .whereType<MealProduct>()
              .toList();
        } else {
           // If menuList is still null after all checks
           print("Products API response format unexpected after all handling attempts. Expected a List. Raw data type: ${rawData.runtimeType}");
           // Handle empty response gracefully
           if (rawData is Map && rawData.isEmpty) {
               return [];
           }
           throw Exception('Failed to parse products: Unexpected API response format');
        }
      } else {
        print("Error fetching products: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load products (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching products: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load products: $e');
    }
  }

  static Map<String, String> _getWriteHeaders({bool requiresAuth = true}) {
    // Keeping this helper as is
    String? authToken; // TODO: Replace with actual token retrieval
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    // Combine null check and isNotEmpty check to address lint warning
    if (requiresAuth && (authToken?.isNotEmpty ?? false)) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  // --- Update Chef's Active Status (Remains the same) ---
  static Future<bool> updateProfileStatus(int chefId, bool isActive) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/chefs/$chefId/status');
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(<String, bool>{ 'is_active': isActive, }),
      );
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

  // --- Update Order Status (For marking 'Ready for Pickup' by ANY rider, or other simple status changes) ---
  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    // NOTE: This is now primarily for statuses *other than* assigning a specific rider.
    // Use assignOrderToRider for specific assignments.
    final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status');
    print("Updating order $orderId status to $newStatus via general endpoint");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(<String, String>{ 'order_status': newStatus, }),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print("Error updating order status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating order status: $e");
      return false;
    }
  }

  // --- Assign Order to Specific Rider (NEW) ---
  static Future<bool> assignOrderToRider(int orderId, int riderId, String newStatus) async {
      // Adjust endpoint and payload based on your API design
      // Option 1: Specific assignment endpoint
      // final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/assign');
      // Option 2: Update status endpoint that also takes rider_id
      final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status'); // Let's assume this for now
      print("Assigning order $orderId to rider $riderId, setting status to $newStatus");

      try {
          final response = await http.patch(
              uri,
              headers: _getWriteHeaders(),
              body: jsonEncode(<String, dynamic>{
                  'order_status': newStatus,
                  'transporter_id': riderId,
                  // Optionally send rider_name if API expects it
              }),
          );
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


  // --- Fetch Available Riders (NEW) ---
  Future<List<Rider>> fetchAvailableRiders() async {
    // TODO: Refine endpoint if needed (e.g., add query params for location/availability)
    final Uri uri = Uri.parse('$apibaseurl/rr/transporters');
    print("Fetching available riders from: $uri");

    try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
            final dynamic rawData = json.decode(response.body);
            // Adjust based on actual API response structure (e.g., nested under 'data' or 'riders')
            final dynamic riderList = _handleApiResponse(rawData);

            if (riderList is List) {
                return riderList
                    .map((jsonItem) {
                        if (jsonItem is Map<String, dynamic>) {
                             // <<< FILTERING: Only include 'available' riders (adjust status string if needed)
                             // Make the status check case-insensitive and handle potential nulls
                             if (jsonItem['is_active']?.toString().toLowerCase() == 'true') {
                                return Rider.fromJson(jsonItem);
                             } else {
                                 print("Skipping non-available rider: ${jsonItem['name']} (${jsonItem['status']})");
                                 return null;
                             }
                        } else {
                            print("API Warning: Skipping non-map item in riders list: $jsonItem");
                            return null;
                        }
                    })
                    .whereType<Rider>() // Filters out nulls
                    .toList();
            } else {
                print("Riders API response format unexpected: Expected a List after handling. Got: ${riderList?.runtimeType}");
                if (riderList == null || (riderList is Map && riderList.isEmpty)) {
                    return []; // No riders found or error in parsing
                }
                throw Exception('Failed to parse riders: Unexpected API response format');
            }
        } else {
            print("Error fetching riders: ${response.statusCode} ${response.body}");
            throw Exception('Failed to load riders (Status code: ${response.statusCode})');
        }
    } catch (e) {
        print("Exception fetching riders: $e");
        if (e is Exception) rethrow;
        throw Exception('Failed to load riders: $e');
    }
  }


  // --- Add a New Product/Meal (Modified to show "Coming Soon") ---
  static Future<MealProduct?> addProduct(Map<String, dynamic> productData) async {
    // <<< MODIFICATION: Immediately return null and potentially show message
    // (Message shown in UI layer)
    print("Add Product Triggered (Coming Soon)");
    return null; // Indicate failure/block
  }

  // --- Update an Existing Product/Meal (Modified to show "Coming Soon") ---
  static Future<bool> updateProduct(String mealId, Map<String, dynamic> productData) async {
    // <<< MODIFICATION: Immediately return false and potentially show message
    // (Message shown in UI layer)
    print("Update Product Triggered (Coming Soon)");
    return false; // Indicate failure/block
  }

  // --- Delete a Product/Meal (Modified to show "Coming Soon") ---
  static Future<bool> deleteProduct(String mealId) async {
    // <<< MODIFICATION: Immediately return false and potentially show message
    // (Message shown in UI layer)
    print("Delete Product Triggered (Coming Soon)");
    return false; // Indicate failure/block
  }

  // --- Add selected meals to chef's stock (Modified to show "Coming Soon") ---
  static Future<bool> addMealsToChefStock(List<String> mealIds) async {
     // <<< MODIFICATION: Immediately return false and potentially show message
    // (Message shown in UI layer)
    print("Add Meals to Stock Triggered (Coming Soon)");
    return false; // Indicate failure/block
  }
  // --- Static Fetch Chefs (for preloading) ---
  static Future<List<dynamic>?> fetchChefsStatic() async {
    final url = '$apibaseurl/rr/rchefs';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic chefsList = _handleApiResponse(rawData); // Use existing static helper

        if (chefsList is List) {
           // Optionally map to a simpler structure if needed, but returning raw list is fine for caching
           // For now, just return the list as is from the handler
           return chefsList;
        } else {
          print('Static fetchChefs: Unexpected response format after handling: ${chefsList?.runtimeType}');
          return null; // Indicate failure to get a list
        }
      } else {
        print('Static fetchChefs: Failed to load chefs. Status code: ${response.statusCode}.');
        return null; // Indicate failure
      }
    } on TimeoutException {
      print('Static fetchChefs: Request timed out.');
      return null; // Indicate failure
    } catch (e) {
      print('Static fetchChefs: Error fetching chefs: $e');
      return null; // Indicate failure
    }
  }

  // --- Static Fetch Producers (for preloading) ---
  static Future<List<dynamic>?> fetchProducersStatic() async {
    final url = '$apibaseurl/rr/rproducers';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic producerList = _handleApiResponse(rawData); // Use existing static helper

        if (producerList is List) {
           // Optionally map to a simpler structure if needed, but returning raw list is fine for caching
           // For now, just return the list as is from the handler
           return producerList;
        } else {
          print('Static fetchProducers: Unexpected response format after handling: ${producerList?.runtimeType}');
          return null; // Indicate failure to get a list
        }
      } else {
        print('Static fetchProducers: Failed to load producers. Status code: ${response.statusCode}.');
        return null; // Indicate failure
      }
    } on TimeoutException {
      print('Static fetchProducers: Request timed out.');
      return null; // Indicate failure
    } catch (e) {
      print('Static fetchProducers: Error fetching producers: $e');
      return null; // Indicate failure
    }
  }
}

// +++ REUSABLE IMAGE WIDGET +++
// Keeping this widget as is - it's already good.
class CachedImageWithShimmer extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;
  final double iconSize;
  final String? errorText; // Optional text for error state
  final File? localFile; // <<< NEW: Added to display local file for editing

  const CachedImageWithShimmer({
    super.key,
    this.imageUrl, // Made optional
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
    this.errorIcon = Icons.image_not_supported_outlined, // Default error icon
    this.iconSize = 35,
    this.errorText,
    this.localFile, // <<< NEW
  }); // Removed assertion: assert(imageUrl != null || localFile != null, 'Either imageUrl or localFile must be provided.');


  String? _getDirectImageLink(String? url) {
    if (url == null ||
        url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }
    // Keep GDrive logic if needed, otherwise simplify
    if (url.contains('drive.google.com')) {
      try {
        Uri uri = Uri.parse(url);
        String? fileId;
        if (uri.pathSegments.contains('d')) {
          int idIndex = uri.pathSegments.indexOf('d');
          if (idIndex >= 0 && idIndex + 1 < uri.pathSegments.length) {
            fileId = uri.pathSegments[idIndex + 1];
          }
        }
        else if (uri.queryParameters.containsKey('id')) {
          fileId = uri.queryParameters['id'];
        }
        if (fileId != null && fileId.isNotEmpty && !fileId.contains('/')) {
          fileId = fileId.split('&').first; // Handle potential extra params
          return 'https://drive.google.com/uc?export=view&id=$fileId';
        }
      } catch (e) {
        print("Error parsing GDrive URL: $url - $e");
      }
      return null; // Return null if parsing fails or ID isn't found
    }
    // Assume other valid URLs are direct links
    return url;
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
      // Display local file if available
      imageWidget = Image.file(
        localFile!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
           print("Error loading local file: ${localFile!.path} - $error");
           return _buildErrorWidget(context, shimmerBase, shimmerHighlight, isLocalFileError: true);
        },
      );
    } else {
      // Otherwise, try loading network image
      final String? processedUrl = _getDirectImageLink(imageUrl);
      if (processedUrl == null || processedUrl.isEmpty) {
        // If URL is invalid or null after processing, show error
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
                      color: Theme.of(context).cardColor, // Use theme color for placeholder background
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

    // Apply clipping
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  Widget _buildErrorWidget(
      BuildContext context, Color baseColor, Color highlightColor, {bool isLocalFileError = false}) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.2), // Use shimmer base for background
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            errorIcon,
            color: Colors.grey.shade500,
            size: iconSize,
          ),
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
// +++ END REUSABLE IMAGE WIDGET +++


// --- Main Application Widget ---
// Theming remains largely the same, adjustments made later if needed by redesign.
class ChefDash88new extends StatelessWidget {
  const ChefDash88new({super.key});

  @override
  Widget build(BuildContext context) {
    // Define core colors (already defined above)
    // ... (keep existing colors) ...
    const Color lightBackgroundColor = Color(0xFFF5F5F5); // Correct definition
    const Color cardBackgroundColor = whiteColor; // Correct definition
    const Color primaryTextColor = darkTeal; // Correct definition
    const Color secondaryTextColor = Color(0xFF455A64); // Correct definition
    const Color iconColor = primaryTeal; // Correct definition
    const Color dividerColor = lightTeal; // Correct definition
    const Color onlineColor = Colors.green; // Correct definition
    const Color offlineColor = Colors.grey; // Correct definition


    return MaterialApp(
      title: 'Chef Dashboard',
      theme: ThemeData(
          // --- Color Scheme ---
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryTeal,
            primary: primaryTeal,
            secondary: accentTeal,
            background: lightBackgroundColor, // Use defined variable
            surface: cardBackgroundColor, // Card background - Use defined variable
            onPrimary: whiteColor,
            onSecondary: whiteColor,
            onBackground: primaryTextColor, // Use defined variable
            onSurface: primaryTextColor, // Text on cards - Use defined variable
            error: Colors.redAccent[700]!,
            onError: whiteColor,
            brightness: Brightness.light,
          ),
          // --- Component Themes ---
          scaffoldBackgroundColor: lightBackgroundColor, // Use defined variable
          appBarTheme: AppBarTheme(
            backgroundColor: primaryTeal,
            foregroundColor: whiteColor,
            elevation: 1.0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            titleTextStyle: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: whiteColor, letterSpacing: 0.5,
            ),
            iconTheme: const IconThemeData(color: whiteColor),
          ),
          tabBarTheme: TabBarTheme(
            indicatorColor: whiteColor,
            labelColor: whiteColor,
            unselectedLabelColor: lightTeal,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          ),
          cardTheme: CardTheme(
            elevation: 1.5,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade50, width: 0.5),
            ),
            color: cardBackgroundColor, // Default card background - Use defined variable
          ),
          chipTheme: ChipThemeData(
            backgroundColor: lighterTeal,
            labelStyle: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w500), // Use defined variable
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            side: BorderSide.none, // Explicitly none
            elevation: 0,
          ),
          listTileTheme: ListTileThemeData(
            iconColor: iconColor, // Use defined variable
            titleTextStyle: TextStyle( fontWeight: FontWeight.w500, color: primaryTextColor, fontSize: 16, ), // Use defined variable
            subtitleTextStyle: TextStyle( color: secondaryTextColor, fontSize: 13, ), // Use defined variable
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          switchTheme: SwitchThemeData( // Define switch colors
            thumbColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) {
                return onlineColor; // Thumb color when ON - Use defined variable
              }
              if (states.contains(MaterialState.disabled)) {
                return Colors.grey.shade400;
              }
              return offlineColor; // Thumb color when OFF - Use defined variable
            }),
            trackColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
              if (states.contains(MaterialState.selected)) {
                return onlineColor.withOpacity(0.5); // Track color when ON - Use defined variable
              }
               if (states.contains(MaterialState.disabled)) {
                return Colors.grey.shade300;
              }
              return offlineColor.withOpacity(0.4); // Track color when OFF - Use defined variable
            }),
             trackOutlineColor: MaterialStateProperty.all(Colors.transparent), // Remove outline
          ),
          textTheme: TextTheme(
            headlineSmall: TextStyle( fontWeight: FontWeight.bold, color: darkTeal, fontSize: 22, letterSpacing: 0.2),
            titleLarge: TextStyle( fontWeight: FontWeight.w600, color: darkTeal, fontSize: 18),
            titleMedium: TextStyle( fontWeight: FontWeight.w600, color: primaryTextColor, fontSize: 16), // Use defined variable
            titleSmall: TextStyle( fontWeight: FontWeight.w500, color: primaryTextColor, fontSize: 14), // Use defined variable
            bodyLarge: TextStyle(color: primaryTextColor, fontSize: 16, height: 1.4), // Use defined variable
            bodyMedium: TextStyle(color: secondaryTextColor, fontSize: 14, height: 1.4), // Use defined variable
            bodySmall: TextStyle(color: subtleTextColor, fontSize: 12, height: 1.3), // Use defined variable
            labelLarge: TextStyle( color: whiteColor, fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.8, ),
            labelMedium: TextStyle( color: primaryTeal, fontWeight: FontWeight.w500, fontSize: 14, ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: accentTeal, foregroundColor: whiteColor, elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            // fillColor: Colors.teal.shade50.withOpacity(0.5), // Replaced with consistent color
            fillColor: textFieldFillColor, // Use defined variable
            border: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none, ),
            enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: lightTeal, width: 1), ),
            focusedBorder: OutlineInputBorder( borderSide: BorderSide(color: primaryTeal, width: 1.5), borderRadius: BorderRadius.circular(10), ),
            labelStyle: TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
            floatingLabelStyle: TextStyle(color: primaryTeal, fontWeight: FontWeight.w600),
            hintStyle: TextStyle(color: subtleTextColor), // Use defined variable
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            errorStyle: TextStyle(color: Colors.redAccent[700]?.withOpacity(0.9), fontSize: 11.5), // Subtle error text
            errorBorder: OutlineInputBorder( // Define border style on error
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.redAccent[700]!, width: 1.0),
              ),
             focusedErrorBorder: OutlineInputBorder( // Define border style on focus + error
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
                backgroundColor: primaryTeal, foregroundColor: whiteColor, elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle( fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.5)),
          ),
          dividerTheme: DividerThemeData( color: dividerColor, thickness: 0.8, space: 24, ), // Use defined variable
          iconTheme: const IconThemeData( color: iconColor, size: 22, ), // Use defined variable
          progressIndicatorTheme: const ProgressIndicatorThemeData( color: primaryTeal, ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 4,
            contentTextStyle: const TextStyle(color: whiteColor), // Default text color for snackbars
          )),
      home: const ChefDashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Main Dashboard Screen (with Tabs) ---
// Structure remains the same (4 tabs)
class ChefDashboardScreen extends StatefulWidget {
  const ChefDashboardScreen({super.key});
  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Add the standard drawer
      drawer: const AppDrawer(), 
      appBar: AppBar(
        title: const Text('Chef Dashboard'),
        bottom: TabBar(
          isScrollable: false, // Keep tabs fixed
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_pin_circle_outlined), text: 'Profile'), // Changed icon
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
            Tab(icon: Icon(Icons.work_outline_rounded), text: 'Gigs'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ProfileTab(),
          OrdersTab(), // Will filter for meals
          GigsTab(), // Will filter for gigs
          ProductsTab(), // Will show "Coming Soon" for actions
        ],
      ),
    );
  }
}


// --- Profile Tab Widget (Reorganized and Editable) ---
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin {
  // --- Caching ---
  static ChefProfile? _profileCache;
  static DateTime? _profileCacheTimestamp;
  static const String _profileCacheKey = 'chef_profile_cache';
  static const String _profileCacheTimestampKey = 'chef_profile_cache_timestamp';

  // Load cache from UserCache
  static Future<void> _loadProfileCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_profileCacheKey);
    final timestampData = await UserCache.getData(_profileCacheTimestampKey);

    if (cachedData is Map<String, dynamic> && timestampData is String) {
      try {
        _profileCache = ChefProfile.fromMockJson(cachedData); // Assuming fromMockJson works
        _profileCacheTimestamp = DateTime.parse(timestampData);
      } catch (e) {
        print("Error parsing cached profile: $e");
        _profileCache = null;
        _profileCacheTimestamp = null;
        // Clear potentially corrupted cache
        await UserCache.removeData(_profileCacheKey);
        await UserCache.removeData(_profileCacheTimestampKey);
      }
    } else {
       _profileCache = null;
       _profileCacheTimestamp = null;
    }
  }

  // Save cache to UserCache
  static Future<void> _saveProfileCacheToPrefs(ChefProfile profile) async {
    // Convert profile to a suitable Map for JSON encoding if needed
    // Assuming ChefProfile has a toJson method or can be directly encoded
    // For now, let's assume we need a toJson method in ChefProfile
    // If ChefProfile.fromMockJson works, we might need a toJson() that produces compatible JSON
    // Let's assume toJsonForUpdate() is close enough for caching purposes,
    // but ideally, a full toJson() would be better.
    // For simplicity, we'll cache the result of toJsonForUpdate() plus the ID.
    Map<String, dynamic> cacheableProfile = profile.toJsonForUpdate();
    cacheableProfile['chefid'] = profile.chefid; // Ensure ID is included
    cacheableProfile['image'] = profile.image; // Ensure image URL is included
    // Add any other non-editable fields needed for display if not in toJsonForUpdate()
    cacheableProfile['chef_type'] = profile.chefType;
    cacheableProfile['is_active'] = profile.isActive;


    await UserCache.saveData(_profileCacheKey, cacheableProfile);
    await UserCache.saveData(
        _profileCacheTimestampKey, DateTime.now().toIso8601String());
    _profileCache = profile; // Update in-memory cache
    _profileCacheTimestamp = DateTime.now();
  }
  // --- End Caching ---

  Future<ChefProfile?>? _profileFuture; // Can be null if loaded from cache
  ChefProfile? _currentProfile;
  bool _isLoadingProfile = true; // Track loading state
  String _fetchError = ''; // Store fetch error
  bool _isLoadingStatus = false; // For online/offline toggle
  bool _isEditing = false; // To toggle edit mode
  bool _isSaving = false; // To show saving indicator
  bool _didLoadProfile = false;
  final _formKey = GlobalKey<FormState>(); // For validating edits

  // Controllers for editable fields
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  // Removed: late TextEditingController _specialtiesController;
  late TextEditingController _experienceController;
  // Removed: late TextEditingController _languagesController;
  late TextEditingController _locationController;
  // Removed: late TextEditingController _minNoticeController;
  late TextEditingController _priceController; // Keep for price/rate text field
  // Removed: late TextEditingController _responseTimeController;
  // Removed: late TextEditingController _teamSizeController;
  // Removed: late TextEditingController _equipmentController;
  // Removed: late TextEditingController _availabilityController;
  // Removed: late TextEditingController _certificationsController; // Was missing, but removing anyway

  // State variables for Dropdowns and MultiSelects during editing
  String? _selectedResponseTime;
  String? _selectedTeamSize;
  String? _selectedMinNotice;
  List<String> _selectedLanguages = [];
  List<String> _selectedSpecialties = [];
  List<String> _selectedCertifications = [];
  List<String> _selectedEquipment = [];
  List<String> _selectedAvailability = [];

  // Location Fetching State
  bool _isFetchingLocation = false;
  Timer? _locationHintTimer;
  int _locationHintDots = 0;

  // Pricing Controllers
  late TextEditingController _monthlyPriceController;
  late Map<String, TextEditingController> _perGigPriceControllers;

// Removed duplicate location state variables
  @override
  bool get wantKeepAlive => true; // Keep state across tab switches

  @override
  void initState() {
    super.initState();
    // Initialize controllers (empty initially)
    _nameController = TextEditingController();
    _bioController = TextEditingController();
    // Removed: _specialtiesController = TextEditingController();
    _experienceController = TextEditingController();
    // Removed: _languagesController = TextEditingController();
    _locationController = TextEditingController();
    // Removed: _minNoticeController = TextEditingController();
    _priceController = TextEditingController(); // Keep for the general 'Est. Price/Rate' field
    // Removed: _responseTimeController = TextEditingController();
    _monthlyPriceController = TextEditingController();
    _perGigPriceControllers = { for (var key in perGigCategoryKeys.values) key: TextEditingController() };
    // Removed: _teamSizeController = TextEditingController();
    // Removed: _equipmentController = TextEditingController();
    // Removed: _availabilityController = TextEditingController();
    // Removed: _certificationsController = TextEditingController();
    // Load profile moved to didChangeDependencies
  }

   @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load profile only once when dependencies change (typically once)
    if (!_didLoadProfile) {
      _didLoadProfile = true;
      // Start the combined cache load and background fetch process
      _initializeProfileData();
    }
  }

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _nameController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _monthlyPriceController.dispose();
    _perGigPriceControllers.values.forEach((controller) => controller.dispose());
    _locationHintTimer?.cancel(); // Dispose location timer
    super.dispose();
  }

  // Combined cache load and background fetch
  Future<void> _initializeProfileData() async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true; // Start loading
        _fetchError = '';
        _isEditing = false; // Ensure not in edit mode on load
        _isSaving = false;
      });
    }

    // 1. Load from cache
    await _loadProfileCacheFromPrefs();

    // 2. Display cached data immediately if available
    if (_profileCache != null && mounted) {
      // Check cache validity (optional, but good practice)
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) < CacheConfig.profileCacheDuration; // Use correct duration

      if (cacheIsValid) {
         print("ProfileTab: Displaying valid cached profile.");
         setState(() {
           _currentProfile = _profileCache;
           _updateControllersFromProfile(_currentProfile!);
           _isLoadingProfile = false; // Stop loading indicator
           _profileFuture = Future.value(_currentProfile); // Set future for FutureBuilder
         });
      } else {
         print("ProfileTab: Cached profile expired, will fetch fresh data.");
         // Keep showing stale cache while fetching, but ensure loading is true
         setState(() {
            _currentProfile = _profileCache; // Show stale data
            _updateControllersFromProfile(_currentProfile!);
            _isLoadingProfile = true; // Indicate background loading
            _profileFuture = null; // Reset future, will be set by fetch
         });
      }
    } else if (mounted) {
       print("ProfileTab: No cached profile found, fetching...");
       // No cache, ensure loading is true
       setState(() {
         _isLoadingProfile = true;
         _profileFuture = null; // Reset future
       });
    }

    // 3. Fetch fresh data in the background (regardless of cache state)
    await _fetchProfileAndUpdate();
  }


  // Separate function to fetch and update state/cache
  Future<void> _fetchProfileAndUpdate() async {
    final apiService = ApiService();
    try {
      final profile = await apiService.fetchChefProfile();
      if (mounted) {
        print("ProfileTab: Fetched fresh profile data.");
        await _saveProfileCacheToPrefs(profile); // Save fresh data to cache
        setState(() {
          _currentProfile = profile;
          _updateControllersFromProfile(profile);
          _isLoadingProfile = false; // Done loading
          _fetchError = ''; // Clear any previous error
          _profileFuture = Future.value(profile); // Update future for FutureBuilder
        });
      }
    } catch (error, stackTrace) {
      print("Error fetching fresh profile: $error\n$stackTrace");
      if (mounted) {
        // Only show error if there's no cached data to display
        if (_currentProfile == null) {
          setState(() {
            _fetchError = 'Failed to load profile: $error';
            _isLoadingProfile = false; // Stop loading
            _profileFuture = Future.error(error); // Set future to error state
          });
          _showErrorSnackbar('Error loading profile: $error');
        } else {
           // Keep showing cached data, log error silently or show subtle indicator
           print("ProfileTab: Failed to fetch fresh profile, showing cached version. Error: $error");
           // Optionally show a less intrusive snackbar
           // _showInfoSnackbar("Couldn't update profile, showing last known data.");
           // Ensure loading indicator stops if it was showing for background fetch
           setState(() {
              _isLoadingProfile = false;
              // Keep _profileFuture pointing to the cached data if it was set
              if (_profileFuture == null) {
                 _profileFuture = Future.value(_currentProfile);
              }
           });
        }
      }
    }
  }

  // Renamed original _loadProfile to _refreshProfile for clarity (used by refresh button)
  void _refreshProfile() {
     // Reset edit state when reloading
    if (mounted) {
       setState(() {
         _isEditing = false;
         _isSaving = false;
         _currentProfile?.localImageFile = null; // Clear local image selection
         _isLoadingProfile = true; // Show loading indicator during manual refresh
         _fetchError = '';
       });
       // Clear previous snackbars if any
       ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    // Fetch fresh data and update
    _fetchProfileAndUpdate();
  }


  // Helper function to safely parse comma-separated string into a list,
  // filtering against allowed values.
  List<String> _parseAndFilterList(String? commaSeparatedString, List<String> allowedValues) {
    if (commaSeparatedString == null || commaSeparatedString.trim().isEmpty) {
      return [];
    }
    // Split, trim, remove empty strings, and filter based on allowed values
    return commaSeparatedString
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && allowedValues.contains(item))
        .toList();
  }

  // Helper function to validate a single selection against allowed values
  String? _validateSingleSelection(String? value, List<String> allowedValues) {
    if (value != null && allowedValues.contains(value)) {
      return value;
    }
    // Return null or a default value if the profile data is invalid/not in the list
    // Returning null might be safer to avoid accidentally selecting a default
    return null; // Or: return allowedValues.isNotEmpty ? allowedValues.first : null;
  }

  // Helper to update controllers and state variables when profile data is loaded or edit cancelled
  void _updateControllersFromProfile(ChefProfile profile) {
    // Update text controllers
    _nameController.text = profile.name;
    _bioController.text = profile.bio ?? '';
    _experienceController.text = profile.experience?.toString() ?? '';
    _locationController.text = profile.location ?? '';
    _priceController.text = profile.price ?? ''; // Assuming price is a free text field for now

    // Update state variables for dropdowns using the validation helper
    _selectedResponseTime = _validateSingleSelection(profile.responseTime, responseTimes);
    _selectedTeamSize = _validateSingleSelection(profile.teamSize, teamSizes);
    _selectedMinNotice = _validateSingleSelection(profile.minNotice, minNoticeOptions);

    // Update state variables for multi-selects by parsing and filtering
    _selectedSpecialties = _parseAndFilterList(profile.specialties, allSpecialties);
    _selectedLanguages = _parseAndFilterList(profile.languages, allLanguages);
    _selectedEquipment = _parseAndFilterList(profile.equipment, allEquipment);
    _selectedAvailability = _parseAndFilterList(profile.availability, allAvailability);
    _selectedCertifications = _parseAndFilterList(profile.certifications, allCertifications);

    // Note: localImageFile is handled separately by the picker logic

    // Ensure UI reflects changes if this is called after the initial build (e.g., after cancelling edit)
    if (mounted) {
      setState(() {});
    }
  }

  // Helper to update the profile object from controllers and state variables before saving
  void _updateProfileFromControllers() {
     if (_currentProfile == null) return;
     // Update profile fields from their corresponding controllers/state variables
     _currentProfile!.name = _nameController.text.trim();
     _currentProfile!.bio = _bioController.text.trim().isEmpty ? null : _bioController.text.trim();
     _currentProfile!.specialties = _selectedSpecialties.isEmpty ? null : _selectedSpecialties.join(',');
     _currentProfile!.experience = int.tryParse(_experienceController.text.trim()); // Handle potential parse error
     _currentProfile!.languages = _selectedLanguages.isEmpty ? null : _selectedLanguages.join(',');
     _currentProfile!.location = _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
     _currentProfile!.minNotice = _selectedMinNotice; // Assign directly from state variable
     _currentProfile!.price = _priceController.text.trim().isEmpty ? null : _priceController.text.trim();
     _currentProfile!.responseTime = _selectedResponseTime; // Assign directly from state variable
     _currentProfile!.teamSize = _selectedTeamSize; // Assign directly from state variable
     _currentProfile!.equipment = _selectedEquipment.isEmpty ? null : _selectedEquipment.join(',');
     _currentProfile!.availability = _selectedAvailability.isEmpty ? null : _selectedAvailability.join(',');
     _currentProfile!.certifications = _selectedCertifications.isEmpty ? null : _selectedCertifications.join(',');
     // Location is handled by its controller, which gets updated by _getCurrentLocation
      // localImageFile is already set by the picker if an image was changed
  }

  // --- Location Handling (Copied & adapted from chefsignup222.dart) ---

  void _startLocationHintAnimation() {
    _locationHintTimer?.cancel(); // Cancel any existing timer
    _locationHintDots = 0;
    _locationHintTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      // Check if the widget is still mounted and if location fetching is still active
      if (!mounted || !_isFetchingLocation) {
        timer.cancel();
        if (mounted && !_isFetchingLocation) setState(() => _locationHintDots = 0); // Reset dots if stopped
        return;
      }
      // Update dots for animation
      if (mounted) setState(() => _locationHintDots = (_locationHintDots + 1) % 4); // Cycle 0, 1, 2, 3
    });
  }

  void _stopLocationHintAnimation() {
    _locationHintTimer?.cancel();
    if (mounted) setState(() => _locationHintDots = 0); // Reset dots when stopped
  }

  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return; // Prevent multiple simultaneous fetches

    if (mounted) {
      setState(() {
        _isFetchingLocation = true;
        _locationController.clear(); // Clear previous location text
      });
      _startLocationHintAnimation(); // Start the ... animation
    }


    try {
      // 1. Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
           throw Exception('Location services are disabled. Please enable them in your device settings.');
      }

      // 2. Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
             throw Exception('Location permissions were denied. Please grant permission to get location.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
           throw Exception('Location permissions are permanently denied. Please enable them in app settings.');
      }

      // 3. Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high, // Request high accuracy
          timeLimit: const Duration(seconds: 15)); // Set a reasonable timeout

      // 4. Reverse Geocode (optional, to get a readable address)
      String displayAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}"; // Fallback
      String coords = "${position.latitude}, ${position.longitude}"; // Store coords

      try {
        // Using geocode.maps.co - REMEMBER to handle potential API limits or switch service if needed
        // Ensure you have appropriate attribution if required by the service.
        final String apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        // Add timeout to the HTTP request as well
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // Use display_name if available, otherwise keep the lat/lon fallback
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
           print("Reverse geocode error: ${response.statusCode}");
           // Don't throw an exception here, just use the lat/lon string
           _showErrorSnackbar('Could not fetch readable address. Using coordinates.'); // Use existing snackbar helper
        }
      } catch (e) {
         // Catch network errors or timeouts during geocoding
         print("Reverse geocode exception: $e");
         _showErrorSnackbar('Could not fetch readable address. Using coordinates.'); // Use existing snackbar helper
      }

       // 5. Update state (if still mounted)
       if (mounted) {
         setState(() {
           // Update the text controller directly
           _locationController.text = (displayAddress.isNotEmpty && !displayAddress.startsWith("Lat:"))
              ? "$displayAddress ($coords)" // Show Address (Coords)
              : "Location Acquired ($coords)"; // Show Coords only if address fetch failed
           _isFetchingLocation = false; // Turn off loading state
         });
          _stopLocationHintAnimation(); // Stop the ... animation
         _showSuccessSnackbar('Location acquired successfully!'); // Use existing snackbar helper
       }

    } on TimeoutException catch (_) {
        // Handle timeout from Geolocator.getCurrentPosition
       if (mounted) {
         setState(() {
            _isFetchingLocation = false;
            _locationController.text = 'Failed to get location (Timeout)'; // Inform user
         });
          _stopLocationHintAnimation();
         _showErrorSnackbar('Getting location timed out. Please try again.');
       }
    } catch (e) {
       // Handle other exceptions (permissions, service disabled, etc.)
       if (mounted) {
         setState(() {
            _isFetchingLocation = false;
            _locationController.text = 'Failed to get location'; // Inform user
         });
          _stopLocationHintAnimation();
         _showErrorSnackbar('Error getting location: ${e.toString()}');
       }
    }
  }
  // --- End Location Handling ---


  Future<void> _toggleActiveStatus(bool newValue) async {
    // Prevent toggling if profile isn't loaded, already changing status, or in edit mode
    if (_currentProfile == null || _isLoadingStatus || _isEditing) return;

    // Clear previous snackbars
    if(mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();

    // Set loading state
    setState(() => _isLoadingStatus = true);

    final originalStatus = _currentProfile!.isActive;
    // Optimistic UI update: Change the switch immediately
    setState(() => _currentProfile!.isActive = newValue);

    try {
      // Call API to update status
      bool success = await ApiService.updateProfileStatus(_currentProfile!.chefid, newValue);

      // Handle API response (if mounted)
      if (mounted) {
        if (!success) {
          // If API call failed, revert the switch state
          setState(() => _currentProfile!.isActive = originalStatus);
          _showErrorSnackbar('Failed to update status. Please try again.');
        } else {
          // If successful, show confirmation
          _showSuccessSnackbar('Status updated successfully.');
        }
      }
    } catch (e) {
      // Handle exceptions during API call
      print("Error in _toggleActiveStatus: $e");
      if (mounted) {
        // Revert the switch state on error
        setState(() => _currentProfile!.isActive = originalStatus);
        _showErrorSnackbar('An error occurred while updating status.');
      }
    } finally {
      // Always turn off loading indicator (if mounted)
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

   Future<void> _pickImage() async {
    if (_currentProfile == null || !_isEditing) return; // Only allow picking in edit mode
    try {
       final ImagePicker picker = ImagePicker();
       // Pick an image from the gallery
       final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

       if (pickedFile != null) {
          // If an image was picked, update the state with the File object
          if (mounted) {
             setState(() {
                // Store the selected image file locally in the profile object
                _currentProfile!.localImageFile = File(pickedFile.path);
             });
             // The image will be displayed via CachedImageWithShimmer using localFile
             // Actual upload happens when _saveProfileChanges is called
          }
       }
    } catch (e) {
       // Handle potential errors during image picking (e.g., permissions)
       print("Error picking image: $e");
       if (mounted) _showErrorSnackbar("Could not pick image: $e");
    }
   }

   Future<void> _saveProfileChanges() async {
     // Ensure profile exists, we are editing, and not already saving
     if (_currentProfile == null || !_isEditing || _isSaving) return;

     // 1. Validate the form fields
     if (!(_formKey.currentState?.validate() ?? false)) {
       _showErrorSnackbar('Please fix the errors marked in red before saving.');
       return; // Stop saving if validation fails
     }

     // 2. Save form field values (though we update from controllers/state directly)
     _formKey.currentState!.save(); // Trigger onSaved if implemented, otherwise just completes validation

     // 3. Set saving state and clear snackbars
     if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
     setState(() => _isSaving = true);

     // 4. Update the _currentProfile object with data from controllers/state variables
     _updateProfileFromControllers();

     // 5. Perform API calls
     bool profileUpdateSuccess = false;
     bool imageUpdateSuccess = true; // Assume success if no image was changed
     // String? newImageUrl; // Commented out as the upload logic using it is commented out
     // To store the potentially updated image URL from API

     try {
       // 5a. Update Profile Image (if a new one was picked)
       if (_currentProfile!.localImageFile != null) {
          // final apiService = ApiService(); // Commented out as the upload logic using it is commented out
          // <<< MODIFICATION: Show "Coming Soon" for image upload >>>
          _showComingSoonSnackbar("Profile image update");
          await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
          // --- Real Image Upload Logic (Commented Out) ---
          // print("Attempting to upload profile image...");
          // newImageUrl = await apiService.updateChefProfileImage(_currentProfile!.chefid, _currentProfile!.localImageFile!);
          // if (newImageUrl == null) {
          //   imageUpdateSuccess = false; // Mark image upload as failed
          //   _showErrorSnackbar('Failed to upload profile image. Text changes were not saved.');
          // } else {
          //    print("Image upload successful, new URL: $newImageUrl");
          //    _currentProfile!.image = newImageUrl; // Update profile object with the new URL
          // }
          // --- End Real Image Upload Logic ---
          // For "Coming Soon", assume it didn't *fail*阻止text update, but didn't succeed either.
          imageUpdateSuccess = true; // Let text changes proceed for now
          // We will clear the local file later regardless.
       }

       // 5b. Update Profile Text Fields (only if image update didn't critically fail)
       if (imageUpdateSuccess) {
         final apiService = ApiService();
         // Get the data payload from the updated profile object
         final profileData = _currentProfile!.toJsonForUpdate();
         print("Attempting to update profile text data...");
         profileUpdateSuccess = await apiService.updateChefProfile(_currentProfile!.chefid, profileData);
         if (!profileUpdateSuccess) {
             _showErrorSnackbar('Failed to save profile details. Please try again.');
         }
       }

       // 6. Handle results (if mounted)
       if (mounted) {
         if (profileUpdateSuccess && imageUpdateSuccess) {
           // Both parts succeeded (or image was skipped/simulated)
           _showSuccessSnackbar('Profile updated successfully!');
           setState(() {
             _isEditing = false; // Exit edit mode
             // Clear the local file selection after successful save/simulation
             // If image upload were real and succeeded, _updateControllersFromProfile would use the new URL
             _currentProfile!.localImageFile = null;
             // Refresh controllers/state from the potentially updated _currentProfile
             // This ensures UI reflects saved data (including new image URL if applicable)
             _updateControllersFromProfile(_currentProfile!);
           });
           // Optionally: call _loadProfile() here to force a full reload from server,
           // ensuring absolute consistency, but might cause a brief loading flicker.
         }
         // Error messages handled within the try block
       }

     } catch (e) {
       // Catch any unexpected errors during the process
       print("Error saving profile: $e");
       if (mounted) {
         _showErrorSnackbar('An error occurred while saving the profile.');
       }
     } finally {
       // 7. Always turn off saving indicator (if mounted)
       if (mounted) {
         setState(() => _isSaving = false);
       }
     }
   }

  // --- Snackbar Helpers ---
  void _showErrorSnackbar(String message) {
     if (!mounted) return; // Check if the widget is still in the tree
     ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove existing snackbars
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text(message),
       backgroundColor: Theme.of(context).colorScheme.error, // Use theme error color
       duration: const Duration(seconds: 4), // Show for longer
     ));
  }

  void _showSuccessSnackbar(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).removeCurrentSnackBar();
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text(message),
       backgroundColor: Colors.green.shade600, // Use a success color
     ));
  }

   void _showComingSoonSnackbar(String featureName) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).removeCurrentSnackBar();
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text('$featureName feature is Coming Soon!', style: const TextStyle(color: whiteColor)), // Ensure text is visible
       backgroundColor: Theme.of(context).colorScheme.secondary, // Use theme secondary color
       duration: const Duration(seconds: 2),
     ));
   }
   // --- End Snackbar Helpers ---

  @override
  Widget build(BuildContext context) {
    // Ensure AutomaticKeepAliveClientMixin is honored
    super.build(context);

    return FutureBuilder<ChefProfile?>( // Changed type to nullable ChefProfile
      future: _profileFuture, // The future driving the builder
      builder: (context, snapshot) {
        // ---- Loading State ----
        // Show shimmer only on initial load (when _currentProfile is still null)
        if (_isLoadingProfile && _currentProfile == null) { // Use _isLoadingProfile state
          return _buildProfileShimmer();
        }
        // ---- Error State ----
        // Show error state if fetch failed and we don't have a previously loaded profile
        else if (_fetchError.isNotEmpty && _currentProfile == null) { // Use _fetchError state
          return _buildErrorState(_fetchError); // Pass the stored error message
        }
        // ---- Empty State (Future completed but no data) ----
        // This case might be less likely with cache-first, but keep for robustness
        else if (snapshot.connectionState == ConnectionState.done && !snapshot.hasData && _currentProfile == null) {
           return _buildErrorState('Profile data not found.'); // Treat no data as an error state
        }
        // ---- Success/Loaded State ----
        else {
          // Use _currentProfile if available (avoids flicker during refresh/save)
          // This will be populated by _initializeProfileData or _fetchProfileAndUpdate
          final profile = _currentProfile;

          // Fallback if somehow profile is still null after checks (shouldn't happen often)
          if (profile == null) {
             // This case should ideally be caught by the error state above, but as a safeguard:
             return _buildErrorState('Failed to load profile data.');
          }

          // --- Handle potential background updates ---
          // The _fetchProfileAndUpdate method already handles updating _currentProfile
          // and controllers when new data arrives, so this block can be simplified
          // or potentially removed if _fetchProfileAndUpdate's logic is sufficient.
          // Let's remove this block as _fetchProfileAndUpdate already updates the state.
          /*
          if (!_isEditing && snapshot.hasData && _currentProfile?.chefid != snapshot.data!.chefid) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
                if(mounted) {
                  setState(() => _currentProfile = snapshot.data!);
                  _updateControllersFromProfile(_currentProfile!);
                }
             });
          }
          */

          // Build the main profile UI
          return RefreshIndicator(
            onRefresh: () async => _refreshProfile(), // Trigger reload on pull-to-refresh
            color: Theme.of(context).colorScheme.primary,
            child: Form( // Wrap the scrollable content in a Form for validation
               key: _formKey,
               child: ListView(
                 padding: const EdgeInsets.all(16.0),
                 physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable even with little content
                 children: [
                   _buildProfileHeader(context, profile),
                   const SizedBox(height: 24),
                   _buildActiveStatusCard(context, profile), // Online/Offline toggle card
                   const SizedBox(height: 20),
                   _buildProfileDetailsCard(context, profile), // Main details card (editable/view)
                   const SizedBox(height: 20),
                    // Show Save/Cancel buttons only when editing
                   if (_isEditing) _buildEditActions(context),
                   // Show loading indicator if a background fetch is in progress AND we are not editing
                   // (Avoids showing indicator while user is actively typing/interacting)
                   if (_isLoadingProfile && !_isEditing)
                      const LinearProgressIndicator(),
                   const SizedBox(height: 70), // Extra space at the bottom
                 ],
               ),
            ),
          );
        }
      },
    );
  }

  // --- Shimmer Placeholder for Profile ---
  Widget _buildProfileShimmer() {
    final shimmerBase = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade300 : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade100 : Colors.grey.shade500;

    return Shimmer.fromColors(
      baseColor: shimmerBase, highlightColor: shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        physics: const NeverScrollableScrollPhysics(), // Disable scrolling for shimmer
        children: [
          // Shimmer Header
          Row( crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container( width: 100, height: 100, decoration: BoxDecoration( color: whiteColor, borderRadius: BorderRadius.circular(50), ), ),
              const SizedBox(width: 20),
              Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: MediaQuery.of(context).size.width * 0.5, height: 26, color: whiteColor, margin: const EdgeInsets.only(bottom: 8)),
                    Container(width: MediaQuery.of(context).size.width * 0.3, height: 20, color: whiteColor),
                  ], ), ),
              Container(width: 40, height: 40, color: whiteColor, margin: const EdgeInsets.only(left: 16)), // Placeholder for edit button
            ],
          ),
          const SizedBox(height: 24),
          // Shimmer Toggle Card
          Container( width: double.infinity, height: 60, decoration: BoxDecoration( color: whiteColor, borderRadius: BorderRadius.circular(12), ), ),
          const SizedBox(height: 20),
          // Shimmer Details Card
          Container( width: double.infinity, height: 450, decoration: BoxDecoration( color: whiteColor, borderRadius: BorderRadius.circular(12), ), ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- Error State Widget ---
  Widget _buildErrorState(Object error) {
     return Center( child: Padding( padding: const EdgeInsets.all(24.0),
       child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
           Icon(Icons.cloud_off_rounded, color: Theme.of(context).colorScheme.error, size: 50),
           const SizedBox(height: 16),
           Text( 'Error Loading Profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center, ),
           const SizedBox(height: 8),
           Text( error.toString(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, ),
           const SizedBox(height: 24),
           ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Retry'), onPressed: _refreshProfile, ) // Retry button calls _refreshProfile
         ],
       ),
     ));
  }


 // --- New Profile Header with Edit Button ---
  Widget _buildProfileHeader(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Image with Edit Overlay
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Profile Image Display
            SizedBox(
              width: 100, // Slightly larger image
              height: 100,
              child: CachedImageWithShimmer(
                // Use local file if editing and one has been picked, otherwise use network URL
                localFile: _isEditing ? profile.localImageFile : null,
                imageUrl: profile.image,
                width: 100,
                height: 100,
                borderRadius: 50, // Circular image
                fit: BoxFit.cover,
                errorIcon: Icons.person_rounded, // Icon for error/no image
                iconSize: 50,
                errorText: "No Pic",
              ),
            ),
            // Edit Icon Overlay (only visible in edit mode)
            if (_isEditing)
              Positioned(
                bottom: 0,
                right: 0,
                child: Material( // Use Material for elevation and ink effect
                  color: colorScheme.secondary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  elevation: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _pickImage, // Trigger image picker on tap
                    child: const Padding(
                      padding: EdgeInsets.all(6.0),
                      child: Icon(Icons.edit, color: whiteColor, size: 18), // Edit icon
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 20),
        // Name and Chef Type (Name becomes editable)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, // Center vertically
            children: [
              // Conditional Widget: TextFormField in edit mode, Text otherwise
              _isEditing
                  ? TextFormField(
                      controller: _nameController, // Use the name controller
                      style: textTheme.headlineSmall, // Match display style
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        isDense: true, // Make it compact
                        contentPadding: EdgeInsets.symmetric(vertical: 8), // Adjust padding
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Name cannot be empty' : null, // Basic validation
                      textInputAction: TextInputAction.next, // Move to next field on enter
                    )
                  : Text( // Display Name
                        profile.name.isEmpty ? '(No Name)' : profile.name, // Handle empty name
                        style: textTheme.headlineSmall
                    ),
              const SizedBox(height: 6),
              // Chef Type (Not editable)
              Text(
                profile.chefType,
                style: textTheme.titleMedium?.copyWith(color: colorScheme.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Edit/Cancel Toggle Button
        if (!_isSaving) // Hide button while saving
            IconButton(
              tooltip: _isEditing ? 'Cancel Edit' : 'Edit Profile',
              icon: Icon(
                _isEditing ? Icons.close_rounded : Icons.edit_outlined, // Change icon based on mode
                color: _isEditing ? colorScheme.error : colorScheme.primary, // Change color
                size: 28,
              ),
              onPressed: () {
                setState(() {
                  if (_isEditing) {
                    // If cancelling edit, reset changes
                    _updateControllersFromProfile(profile); // Reset controllers to original profile data
                    profile.localImageFile = null; // Clear any selected local image
                  }
                  // Toggle edit mode
                  _isEditing = !_isEditing;
                });
              },
            ),
        // Show progress indicator while saving
        if (_isSaving)
          const SizedBox(
            width: 28, height: 28, // Match IconButton size
            child: CircularProgressIndicator(strokeWidth: 2.5)
          ),
      ],
    );
  }

  // --- New Active Status Card (Full Width Toggle) ---
  Widget _buildActiveStatusCard(BuildContext context, ChefProfile profile) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool isActive = profile.isActive;
    // Define colors based on active status
    final Color activeColor = isActive ? Colors.green.shade600 : Colors.grey.shade600;
    final Color offlineColor = Colors.grey.shade600; // Define offline color explicitly
    final Color cardBgColor = isActive ? Colors.green.shade50 : Colors.grey.shade200;

    return Card(
      elevation: _isEditing ? 0 : 1.5, // Reduce elevation when other fields are being edited
      margin: EdgeInsets.zero, // Remove default card margin for full width effect
      color: cardBgColor, // Dynamic background color
      clipBehavior: Clip.antiAlias, // Ensure inkwell respects border radius
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: activeColor.withOpacity(0.3), width: 1), // Subtle border matching status
      ),
      child: InkWell(
        // Allow toggling only when *not* in general edit mode
        onTap: _isEditing ? null : () => _toggleActiveStatus(!isActive),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status Text (Dynamic)
              Expanded(
                 child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                         isActive ? 'Profile Online' : 'Profile Offline',
                         style: textTheme.titleMedium?.copyWith(color: activeColor, fontWeight: FontWeight.bold),
                       ),
                       const SizedBox(height: 2),
                        Text(
                         isActive ? 'Visible to customers' : 'Not currently visible',
                         style: textTheme.bodySmall?.copyWith(color: activeColor.withOpacity(0.8)),
                       ),
                    ],
                 ),
              ),
              const SizedBox(width: 16),
              // Switch (Visual Indicator Only - interaction disabled)
              IgnorePointer( // Prevents user from directly tapping the switch
                 child: Transform.scale(
                   scale: 0.9, // Make switch slightly smaller
                   child: Switch(
                     value: isActive,
                     onChanged: (val) {}, // State changes handled by InkWell tap
                     // Use theme colors for consistency (defined in main theme)
                     activeColor: activeColor, // Use the defined activeColor
                     inactiveThumbColor: offlineColor, // Use the defined offlineColor
                     inactiveTrackColor: offlineColor.withOpacity(0.4), // Use the defined offlineColor
                     // Optional: Explicitly set theme colors again here if needed
                     // thumbColor: Theme.of(context).switchTheme.thumbColor,
                     // trackColor: Theme.of(context).switchTheme.trackColor,
                   ),
                 ),
              ),
              // Loading Indicator (Shown while API call is in progress)
              if (_isLoadingStatus)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0), // Space it from the switch
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.0)),
                ),
            ],
          ),
        ),
      ),
    );
  }


  // --- Profile Details Card (Now with Editable Fields) ---
  Widget _buildProfileDetailsCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      // Make card slightly transparent when editing for visual separation
      color: _isEditing ? Theme.of(context).cardTheme.color?.withOpacity(0.95) : Theme.of(context).cardTheme.color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text('Chef Details', style: textTheme.titleLarge?.copyWith(color: _isEditing ? Theme.of(context).colorScheme.primary : null)),
            ),
            const Divider(),

            // --- Editable Fields ---
            // Use helper functions to build rows consistently
            _buildEditableField(context, Icons.info_outline_rounded, 'Bio', _bioController, isMultiLine: true),
            _buildEditableMultiSelectField(context, Icons.star_outline_rounded, 'Specialties', _selectedSpecialties, allSpecialties, (values) => setState(() => _selectedSpecialties = values), hint: 'Select specialties'),
            _buildEditableField(context, Icons.timer_outlined, 'Experience (Years)', _experienceController, keyboardType: TextInputType.number),
            _buildEditableField(context, Icons.attach_money_rounded, 'Est. Price/Rate', _priceController, hint: 'e.g., 50/hr or 100/plate'),
            _buildEditableDropdownField(context, Icons.schedule_rounded, 'Min. Notice', _selectedMinNotice, minNoticeOptions, (value) => setState(() => _selectedMinNotice = value), hint: 'Select minimum notice'),
            _buildEditableDropdownField(context, Icons.access_time_rounded, 'Response Time', _selectedResponseTime, responseTimes, (value) => setState(() => _selectedResponseTime = value), hint: 'Select response time'),
            _buildEditableMultiSelectField(context, Icons.language_rounded, 'Languages', _selectedLanguages, allLanguages, (values) => setState(() => _selectedLanguages = values), hint: 'Select languages'),
            _buildEditableMultiSelectField(context, Icons.build_circle_outlined, 'Equipment', _selectedEquipment, allEquipment, (values) => setState(() => _selectedEquipment = values), hint: 'Select available equipment'),
            _buildEditableMultiSelectField(context, Icons.calendar_today_rounded, 'Availability', _selectedAvailability, allAvailability, (values) => setState(() => _selectedAvailability = values), hint: 'Select availability days'),
            _buildEditableMultiSelectField(context, Icons.verified_user_outlined, 'Certifications', _selectedCertifications, allCertifications, (values) => setState(() => _selectedCertifications = values), hint: 'Select certifications'),

            // --- Custom Location Field with Fetch Button ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, // Align items vertically centered
                children: [
                  // Location Icon
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Icon(Icons.location_on_outlined, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
                  ),
                  // Location Field (Editable or Display)
                  Expanded(
                    child: _isEditing
                        ? TextFormField( // Location Input Field
                            controller: _locationController,
                            style: textTheme.bodyMedium?.copyWith(color: darkTeal),
                            decoration: _buildInputDecoration( // Use consistent input decoration
                              'Primary Location',
                              hintText: _isFetchingLocation
                                  ? 'Fetching location${'.' * _locationHintDots}' // Show loading animation
                                  : 'e.g., City, State or Service Area',
                              // Add suffix icon for fetching location
                              suffixIcon: _isFetchingLocation
                                  ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))) // Loading indicator
                                  : IconButton(
                                      icon: const Icon(Icons.my_location_rounded, size: 22),
                                      color: primaryTeal,
                                      tooltip: 'Get Current Location',
                                      onPressed: _isFetchingLocation ? null : _getCurrentLocation, // Call fetch function, disable while fetching
                                    ),
                            ),
                            // Basic validation for location
                            validator: (value) => (value == null || value.trim().isEmpty || value.startsWith('Failed')) ? 'Please provide a valid location or fetch current' : null,
                          )
                        : Column( // Location Display View
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Primary Location', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                              const SizedBox(height: 3),
                              Text(
                                _locationController.text.trim().isEmpty ? 'Not provided' : _locationController.text.trim(),
                                style: textTheme.bodyMedium?.copyWith(
                                   color: _locationController.text.trim().isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color,
                                   height: 1.4
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            // --- End Custom Location Field ---

            _buildEditableDropdownField(context, Icons.group_outlined, 'Team Size', _selectedTeamSize, teamSizes, (value) => setState(() => _selectedTeamSize = value), hint: 'Select team size'),

             // --- Sample Menu Section ---
             // Display gallery in view mode, show "Edit (Coming Soon)" button in edit mode
             if (!_isEditing && profile.sampleMenu != null && profile.sampleMenu!.isNotEmpty) ...[
               const SizedBox(height: 10), // Add spacing before non-editable section
               _buildSampleMenuGallery(context, profile.sampleMenu!), // Show the gallery
             ]
             else if (_isEditing)
               Padding(
                  padding: const EdgeInsets.only(top: 15.0, left: 4.0),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero), // Remove default padding
                    icon: Icon(Icons.menu_book_rounded, size: 20, color: Theme.of(context).colorScheme.secondary),
                    label: Text("Edit Sample Menu Items (Coming Soon)", style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                    onPressed: () => _showComingSoonSnackbar("Sample Menu Editing"), // Show snackbar on press
                 ),
               ),
          ],
        ),
      ),
    );
  }

  // --- Consistent InputDecoration Helper ---
  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon, Widget? suffixIcon, String? hintText}) {
     return InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: TextStyle(color: primaryTeal, fontWeight: FontWeight.w500), // Removed const
          hintStyle: TextStyle(color: subtleTextColor, fontSize: 14), // Removed const
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: primaryTeal, size: 20) : null,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: textFieldFillColor, // Use consistent light fill
          // Use theme defaults where possible, override specifics
          border: const OutlineInputBorder( // Default border (can be overridden by enabled, focused etc.)
             borderRadius: BorderRadius.all(Radius.circular(10)),
             borderSide: BorderSide.none, // Make base border invisible if using filled
          ),
          enabledBorder: OutlineInputBorder( // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: lightTeal, width: 1.0), // Use light teal border
          ),
          focusedBorder: OutlineInputBorder( // Border when focused
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: primaryTeal, width: 1.5), // Use primary teal border, thicker
          ),
          errorBorder: OutlineInputBorder( // Border when validation fails
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: errorColor, width: 1.0), // Use error color border
          ),
          focusedErrorBorder: OutlineInputBorder( // Border when validation fails and focused
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: errorColor, width: 1.5), // Use error color border, thicker
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0), // Inner padding
          errorStyle: TextStyle(color: errorColor.withOpacity(0.9), fontSize: 11) // Style for validation error text
      );
  }

  // --- Helper for building editable/display rows for TextFields ---
  Widget _buildEditableField(
    BuildContext context,
    IconData icon,
    String label,
    TextEditingController controller, {
    String? hint,
    bool isMultiLine = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator, // Optional validator function
  }) {
    final textTheme = Theme.of(context).textTheme;
    // Get the current display value from the controller (for view mode)
    final displayValue = controller.text.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0), // Vertical spacing for the row
      child: Row(
        // Align icon to top for multi-line fields, center otherwise
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
           // Icon on the left
           Padding(
             padding: EdgeInsets.only(
                 top: isMultiLine ? 12.0 : 0.0, // Adjust top padding for multi-line alignment
                 right: 16.0),
             child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
           ),
           // Expanded takes remaining space for the field/text
          Expanded(
            child: _isEditing
                ? TextFormField( // Editable TextField
                    controller: controller, // Use the provided controller
                    keyboardType: isMultiLine ? TextInputType.multiline : keyboardType,
                    textInputAction: isMultiLine ? TextInputAction.newline : TextInputAction.next, // Allow newline for multiline, next otherwise
                    maxLines: isMultiLine ? null : 1, // null allows infinite lines for multiline
                    minLines: isMultiLine ? 2 : 1, // Set min lines for multiline fields
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal), // Text style inside the field
                    decoration: _buildInputDecoration( // Use the helper for consistent decoration
                      label,
                      hintText: hint,
                    ),
                     validator: validator, // Pass the validator function
                  )
                : Column( // Display View (using Column for label + value)
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display Label
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      // Display Value
                      Text(
                        displayValue.isEmpty ? 'Not provided' : displayValue, // Show placeholder if empty
                        style: textTheme.bodyMedium?.copyWith(
                           color: displayValue.isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color, // Dim color if not provided
                           height: 1.4 // Adjust line height for readability
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // --- Helper for building editable/display rows for Dropdowns ---
  Widget _buildEditableDropdownField(
    BuildContext context,
    IconData icon,
    String label,
    String? currentValue, // Current selected value (from state)
    List<String> options, // List of available options
    Function(String?) onChanged, { // Callback when value changes
    String? hint,
    String? Function(String?)? validator, // Optional validator
  }) {
    final textTheme = Theme.of(context).textTheme;
    // Determine display value for view mode
    final displayValue = currentValue ?? 'Not provided';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Dropdowns are usually single line
        children: [
          // Icon
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
          ),
          // Dropdown or Display Text
          Expanded(
            child: _isEditing
                ? DropdownButtonFormField<String>(
                    value: currentValue, // Set the current value
                    items: options.map((String value) { // Create dropdown items from options list
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: textTheme.bodyMedium?.copyWith(color: darkTeal)),
                      );
                    }).toList(),
                    onChanged: onChanged, // Call the provided callback on change
                    decoration: _buildInputDecoration(label, hintText: hint), // Consistent decoration
                    style: textTheme.bodyMedium?.copyWith(color: darkTeal), // Style for selected item
                    isExpanded: true, // Make dropdown take full width
                    validator: validator ?? (value) => (value == null || value.isEmpty) ? '$label cannot be empty' : null, // Default or provided validator
                  )
                : Column( // Display View (consistent with TextField helper)
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(
                        displayValue,
                        style: textTheme.bodyMedium?.copyWith(
                           color: currentValue == null ? Colors.grey[500] : textTheme.bodyMedium?.color,
                           height: 1.4
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

 // --- Helper for building editable/display rows for MultiSelect ---
  Widget _buildEditableMultiSelectField(
    BuildContext context,
    IconData icon,
    String label,
    List<String> currentValues, // Current selected values (from state)
    List<String> allItems, // List of all available items
    Function(List<String>) onConfirm, { // Callback when dialog is confirmed
    String? hint,
    String? Function(List<dynamic>?)? validator, // Optional validator (takes List<dynamic>?)
  }) {
    final textTheme = Theme.of(context).textTheme;
    // Create display string for view mode
    final displayValue = currentValues.isEmpty ? 'Not provided' : currentValues.join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align icon to top for multi-select appearance
        children: [
          // Icon
          Padding(
            padding: const EdgeInsets.only(top: 12.0, right: 16.0), // Adjust padding for alignment
            child: Icon(icon, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)),
          ),
          // MultiSelect or Display Text
          Expanded(
            child: _isEditing
                ? InputDecorator( // Wrap in InputDecorator to apply consistent label/border look
                    decoration: _buildInputDecoration(label).copyWith(
                       contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0), // Adjust padding for chip display
                       // Remove internal borders of InputDecorator, we'll add one to the container below
                       border: InputBorder.none,
                       enabledBorder: InputBorder.none,
                       focusedBorder: InputBorder.none,
                       errorBorder: InputBorder.none,
                       focusedErrorBorder: InputBorder.none,
                    ),
                    child: Container( // Container to hold the MultiSelect field and apply visual styling
                       padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0), // Internal padding for the MultiSelect
                       decoration: BoxDecoration(
                          color: textFieldFillColor, // Use consistent fill
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: lightTeal, width: 1.0), // Consistent border
                       ),
                       child: MultiSelectDialogField<String>(
                          items: allItems.map((item) => MultiSelectItem(item, item)).toList(),
                          initialValue: currentValues, // Set initial selected values
                          title: Text(label), // Title for the dialog
                          //buttonIcon: Icon(Icons.arrow_drop_down, color: primaryTeal), // Dropdown icon
                          buttonText: Text( // Text displayed on the button before opening dialog
                            label, // Show label as the button text
                            style: textTheme.bodyMedium?.copyWith(color: primaryTeal, fontWeight: FontWeight.w500), // Mimic label style
                          ),
                          decoration: const BoxDecoration(border: Border()), // Remove internal decoration of field
                          selectedColor: primaryTeal.withOpacity(0.7), // Color for checkmarks in dialog
                          selectedItemsTextStyle: textTheme.bodyMedium?.copyWith(color: primaryTeal),
                          itemsTextStyle: textTheme.bodyMedium?.copyWith(color: darkTeal),
                          onConfirm: onConfirm, // Callback when user confirms selection
                          chipDisplay: MultiSelectChipDisplay( // How selected items are shown below the button
                            chipColor: lightTeal.withOpacity(0.8), // Chip background color
                            textStyle: textTheme.bodySmall?.copyWith(color: darkTeal), // Text style in chips
                            icon: const Icon(Icons.close, color: darkTeal, size: 14), // Chip close icon
                            onTap: (value) { // Handle chip removal
                                setState(() {
                                  currentValues.remove(value); // Remove from the list
                                  onConfirm(currentValues); // Trigger state update
                                });
                            },
                             scrollBar: HorizontalScrollBar(isAlwaysShown: true), // Add scrollbar if chips overflow
                             scroll: true, // Enable horizontal scrolling for chips
                          ),
                          searchable: true, // Allow searching within the dialog
                          // Optional: Add validator if needed
                          validator: validator,
                        ),
                     ),
                  )
                : Column( // Display View (consistent with other helpers)
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey[600])),
                      const SizedBox(height: 3),
                      Text(
                        displayValue,
                        style: textTheme.bodyMedium?.copyWith(
                           color: currentValues.isEmpty ? Colors.grey[500] : textTheme.bodyMedium?.color,
                           height: 1.4
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }


  // --- Save/Cancel Buttons for Edit Mode ---
  Widget _buildEditActions(BuildContext context) {
     return Padding(
       padding: const EdgeInsets.only(top: 16.0), // Spacing above buttons
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end, // Align buttons to the right
         children: [
           // Cancel Button
           TextButton(
             onPressed: _isSaving ? null : () { // Disable if saving
                // Cancel Edit Logic
                setState(() {
                   _isEditing = false; // Turn off edit mode
                   if (_currentProfile != null) {
                      _updateControllersFromProfile(_currentProfile!); // Reset form fields to original profile data
                      _currentProfile!.localImageFile = null; // Clear any picked image file
                   }
                });
             },
             child: const Text('Cancel'),
           ),
           const SizedBox(width: 12), // Spacing between buttons
           // Save Button
           ElevatedButton.icon(
             icon: _isSaving
                 ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: whiteColor)) // Show spinner when saving
                 : const Icon(Icons.save_alt_rounded, size: 20), // Show save icon otherwise
             label: Text(_isSaving ? 'Saving...' : 'Save Profile'), // Change label when saving
             onPressed: _isSaving ? null : _saveProfileChanges, // Disable if saving, otherwise call save function
           ),
         ],
       ),
     );
  }


  // --- Sample Menu Gallery (Unchanged from original, just used conditionally) ---
  Widget _buildSampleMenuGallery(BuildContext context, String sampleMenuUrls) {
    // Split the comma-separated URL string and filter for valid http/https URLs
    final List<String> urls = sampleMenuUrls.split(',')
                                            .map((url) => url.trim())
                                            .where((url) => url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://')))
                                            .toList();
    if (urls.isEmpty) return const SizedBox.shrink(); // Return empty if no valid URLs

    final textTheme = Theme.of(context).textTheme;
    const double galleryHeight = 110.0; // Fixed height for the gallery row
    const double imageSize = 90.0; // Size of each image thumbnail

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Gallery Title
          Padding( padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row( children: [
                Icon(Icons.menu_book_rounded, size: 20, color: Theme.of(context).listTileTheme.iconColor?.withOpacity(0.8)), // Use slightly dimmed icon color
                const SizedBox(width: 12), // Adjusted spacing
                Text("Sample Menu", style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)), // Use titleSmall
              ], ), ),
          // Horizontal Image List
          SizedBox( height: galleryHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal, // Make it scroll horizontally
              itemCount: urls.length,
              padding: const EdgeInsets.symmetric(horizontal: 4.0), // Padding around the list
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0), // Padding between images
                  child: SizedBox( width: imageSize, height: imageSize,
                    // Use the reusable image widget for each URL
                    child: CachedImageWithShimmer(
                        imageUrl: urls[index],
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.cover,
                        borderRadius: 8.0,
                        errorIcon: Icons.no_food_outlined,
                        iconSize: 30,
                        errorText: "Menu Item", // Text for error state
                    ),
                  ),
                 );
               },
             ),
           ),
        ],
       ),
     );
  }
}


// --- Orders Tab Widget (MODIFIED to filter for Meals & Add Rider Assignment) ---
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<Order>>? _ordersFuture;
  List<Order> _allFetchedOrders = []; // Holds ALL fetched orders
  List<Order> _mealOrders = []; // Holds only MEAL orders, sorted by date
  String _selectedFilter = 'All'; // Status filter for MEAL orders

  bool _didLoadOrders = false;

  // Define NEW possible order statuses relevant to rider assignment
  static const String statusPreparing = 'Preparing';
  static const String statusReadyForPickup = 'Ready for Pickup'; // For 'Any Rider'
  static const String statusAssigned = 'Assigned'; // For specific rider
  static const String statusShipped = 'Shipped'; // Renamed from original Shipped/Out for Delivery (Chef might mark this)
  static const String statusOutForDelivery = 'Out for Delivery'; // Rider marks this
  static const String statusDelivered = 'Delivered';
  static const String statusCancelled = 'Cancelled';
  static const String statusPending = 'Pending';
  static const String statusAccepted = 'Accepted'; // Might be intermediate before Preparing

  // List of statuses for filtering chips (Update with new statuses)
  // Ensure these exactly match the status strings used in API and logic
  final List<String> _orderStatuses = [
    'All', statusPending, statusAccepted, statusPreparing,
    statusReadyForPickup, statusAssigned, // Chef/Rider can interact with these
    statusOutForDelivery, // Likely set by Rider app
    statusDelivered, statusCancelled
  ];

  @override
  bool get wantKeepAlive => true; // Keep state

  @override
  void initState() {
    super.initState();
    // Moved loading logic to didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load orders only once
    if (!_didLoadOrders) {
      _didLoadOrders = true;
      _loadOrders();
    }
  }

  void _loadOrders() {
     if(mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
     // Reset lists and set loading state
     setState(() {
       _allFetchedOrders = [];
       _mealOrders = [];
       _ordersFuture = ApiService().fetchOrders(); // Fetch ALL orders using a new ApiService instance
     });


    _ordersFuture!.then((fetchedOrders) {
      if (mounted) {
        _allFetchedOrders = fetchedOrders; // Store all fetched

        // Filter for meals (order_type is 'meal' or null/empty - case insensitive)
        _mealOrders = _allFetchedOrders
            .where((order) => order.orderType?.toLowerCase() == 'meal' || order.orderType == null || order.orderType!.isEmpty)
            .toList();

        // Sort the filtered meal orders by date descending (most recent first)
        _mealOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

        setState(() {}); // Update UI with filtered & sorted list
      }
    }).catchError((error, stackTrace) {
      print("Error in _loadOrders (OrdersTab): $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading orders: $error');
        setState(() {
           _allFetchedOrders = []; // Clear lists on error
           _mealOrders = [];
           _ordersFuture = Future.error(error); // Set future to error state
        });
      }
    });
  }

  // --- Rider Assignment Logic ---
  // This is called when the "Ready for Pickup / Assign Rider" button is pressed
  Future<void> _handleReadyForShipping(Order order) async {
      if (!mounted) return;

      // Show the rider selection dialog
      final selectedRider = await showDialog<Rider?>(
          context: context,
          builder: (BuildContext context) {
              // Pass the ApiService instance or fetch within the dialog
              return _RiderSelectionDialog(apiService: ApiService(), orderId: order.orderId);
          },
      );

      // --- Handle the dialog result ---
      if (!mounted) return; // Check mounted again after await

      if (selectedRider != null) {
          // Specific Rider Selected
          print('Assigning Order ${order.orderId} to Rider ${selectedRider.id} (${selectedRider.name})');
          await _assignSpecificRider(order, selectedRider);
      } else {
          // "Any Rider" Selected (or dialog closed without selection)
          // We assume null return means "Any Rider" was chosen or dialog closed.
          print('Marking Order ${order.orderId} as Ready for Pickup (Any Rider)');
          await _markReadyForAnyRider(order);
      }
  }

  // Helper to call API for assigning a specific rider
  Future<void> _assignSpecificRider(Order order, Rider rider) async {
      final orderIndex = _findOrderIndex(order.orderId);
      if (orderIndex == -1) return; // Order not found in the current list

      final originalStatus = _mealOrders[orderIndex].orderStatus;
      final originalRiderId = _mealOrders[orderIndex].assignedRiderId;
      final originalRiderName = _mealOrders[orderIndex].assignedRiderName;
      // Find index in the full list too for consistency
      final allIndex = _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);


      // Optimistic UI Update
      setState(() {
          _mealOrders[orderIndex].orderStatus = statusAssigned; // Set status to Assigned
          _mealOrders[orderIndex].assignedRiderId = rider.id;
          _mealOrders[orderIndex].assignedRiderName = rider.name;
          // Update _allFetchedOrders as well
          if (allIndex != -1) {
              _allFetchedOrders[allIndex].orderStatus = statusAssigned;
              _allFetchedOrders[allIndex].assignedRiderId = rider.id;
              _allFetchedOrders[allIndex].assignedRiderName = rider.name;
          }
      });
       _showLoadingSnackbar("Assigning to ${rider.name}...");

      try {
          // Call the API to assign the rider and update status
          bool success = await ApiService.assignOrderToRider(order.orderId, rider.id, statusAssigned);
          _dismissLoadingSnackbar(); // Dismiss loading indicator

          if (mounted) {
              if (success) {
                  _showSuccessSnackbar('Order ${order.orderId} assigned to ${rider.name}.');
                  _showOrderNextStepDialog(statusAssigned); // Show guidance message
              } else {
                  _showErrorSnackbar('Failed to assign order ${order.orderId} to ${rider.name}.');
                  // Revert optimistic update on failure
                  setState(() {
                      _mealOrders[orderIndex].orderStatus = originalStatus;
                      _mealOrders[orderIndex].assignedRiderId = originalRiderId;
                      _mealOrders[orderIndex].assignedRiderName = originalRiderName;
                       if (allIndex != -1) {
                            _allFetchedOrders[allIndex].orderStatus = originalStatus;
                            _allFetchedOrders[allIndex].assignedRiderId = originalRiderId;
                            _allFetchedOrders[allIndex].assignedRiderName = originalRiderName;
                       }
                  });
              }
          }
      } catch (e) {
           _dismissLoadingSnackbar(); // Dismiss on error too
          print("Error assigning specific rider: $e");
          if (mounted) {
              _showErrorSnackbar('An error occurred while assigning the rider.');
              // Revert optimistic update on exception
               setState(() {
                    _mealOrders[orderIndex].orderStatus = originalStatus;
                    _mealOrders[orderIndex].assignedRiderId = originalRiderId;
                    _mealOrders[orderIndex].assignedRiderName = originalRiderName;
                    if (allIndex != -1) {
                       _allFetchedOrders[allIndex].orderStatus = originalStatus;
                       _allFetchedOrders[allIndex].assignedRiderId = originalRiderId;
                       _allFetchedOrders[allIndex].assignedRiderName = originalRiderName;
                    }
               });
          }
      }
  }

  // Helper to call API for marking ready for any rider
  Future<void> _markReadyForAnyRider(Order order) async {
      final orderIndex = _findOrderIndex(order.orderId);
      if (orderIndex == -1) return; // Order not found

      final originalStatus = _mealOrders[orderIndex].orderStatus;
      final originalRiderId = _mealOrders[orderIndex].assignedRiderId; // Should be null usually
      final originalRiderName = _mealOrders[orderIndex].assignedRiderName; // Should be null usually
       // Find index in the full list too
      final allIndex = _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);


      // Optimistic UI Update
      setState(() {
          _mealOrders[orderIndex].orderStatus = statusReadyForPickup; // Set status
          _mealOrders[orderIndex].assignedRiderId = null; // Ensure rider is cleared
          _mealOrders[orderIndex].assignedRiderName = null;
          // Update _allFetchedOrders as well
           if(allIndex != -1){
             _allFetchedOrders[allIndex].orderStatus = statusReadyForPickup;
             _allFetchedOrders[allIndex].assignedRiderId = null;
             _allFetchedOrders[allIndex].assignedRiderName = null;
           }
      });
      _showLoadingSnackbar("Marking order as ready...");


      try {
          // Use the general status update API for this action
          bool success = await ApiService.updateOrderStatus(order.orderId, statusReadyForPickup);
          _dismissLoadingSnackbar(); // Dismiss loading indicator

          if (mounted) {
              if (success) {
                  _showSuccessSnackbar('Order ${order.orderId} marked as Ready for Pickup.');
                   _showOrderNextStepDialog(statusReadyForPickup); // Show guidance message
              } else {
                  _showErrorSnackbar('Failed to mark order ${order.orderId} as Ready for Pickup.');
                  // Revert optimistic update on failure
                  setState(() {
                      _mealOrders[orderIndex].orderStatus = originalStatus;
                      // Revert rider fields just in case
                      _mealOrders[orderIndex].assignedRiderId = originalRiderId;
                      _mealOrders[orderIndex].assignedRiderName = originalRiderName;
                      if(allIndex != -1){
                        _allFetchedOrders[allIndex].orderStatus = originalStatus;
                        _allFetchedOrders[allIndex].assignedRiderId = originalRiderId;
                        _allFetchedOrders[allIndex].assignedRiderName = originalRiderName;
                      }
                  });
              }
          }
      } catch (e) {
           _dismissLoadingSnackbar(); // Dismiss on error too
          print("Error marking ready for any rider: $e");
          if (mounted) {
              _showErrorSnackbar('An error occurred while updating order status.');
              // Revert optimistic update on exception
               setState(() {
                  _mealOrders[orderIndex].orderStatus = originalStatus;
                  _mealOrders[orderIndex].assignedRiderId = originalRiderId;
                  _mealOrders[orderIndex].assignedRiderName = originalRiderName;
                    if(allIndex != -1){
                       _allFetchedOrders[allIndex].orderStatus = originalStatus;
                       _allFetchedOrders[allIndex].assignedRiderId = originalRiderId;
                       _allFetchedOrders[allIndex].assignedRiderName = originalRiderName;
                    }
               });
          }
      }
  }


  // General update status function (for Accept, Reject etc. - actions NOT involving rider selection)
  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return; // Order not found
    if(mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Clear previous messages

    final originalStatus = _mealOrders[orderIndex].orderStatus;
    // Find index in full list
    final allIndex = _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);

    // Optimistic update
    setState(() => _mealOrders[orderIndex].orderStatus = newStatus);
    if (allIndex != -1) { // Update full list too
        _allFetchedOrders[allIndex].orderStatus = newStatus;
    }
     _showLoadingSnackbar("Updating status to $newStatus...");


    try {
      // Call the general status update API
      bool success = await ApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar(); // Dismiss loading indicator

      if (mounted) {
          if (!success) {
            // Revert UI on failure
            setState(() => _mealOrders[orderIndex].orderStatus = originalStatus);
             if (allIndex != -1) _allFetchedOrders[allIndex].orderStatus = originalStatus;
            _showErrorSnackbar('Failed to update order ${order.orderId} status.');
          } else {
            // Show success and guidance
            _showSuccessSnackbar('Order ${order.orderId} status updated to $newStatus.');
            _showOrderNextStepDialog(newStatus); // Call the guidance dialog
             // Trigger rebuild just in case (though status change in setState should do it)
             setState(() {});
          }
      }
    } catch (e) {
       _dismissLoadingSnackbar(); // Dismiss on error
      print("Error in _updateSimpleOrderStatus: $e");
      if (mounted) {
        // Revert UI on exception
        setState(() => _mealOrders[orderIndex].orderStatus = originalStatus);
         if (allIndex != -1) _allFetchedOrders[allIndex].orderStatus = originalStatus;
        _showErrorSnackbar('An error occurred while updating order status.');
      }
    }
  }

  // Helper to find the index of an order in the _mealOrders list
  int _findOrderIndex(int orderId) {
      final index = _mealOrders.indexWhere((o) => o.orderId == orderId);
      if (index == -1) {
          print("Warning: Order $orderId not found in _mealOrders list for update.");
      }
      return index;
  }


  // Filter MEAL orders based on the selected status filter chip
  List<Order> _getFilteredMealOrders() {
    if (_selectedFilter == 'All') {
      // Return the full MEAL list (already sorted by date)
      return _mealOrders;
    }
    // Filter the already sorted MEAL list by status (case-insensitive)
    return _mealOrders
        .where((order) =>
            order.orderStatus.toLowerCase() == _selectedFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep state

    return FutureBuilder<List<Order>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        Widget body;
        final connectionState = snapshot.connectionState;
        // Use isLoading flag for clarity
        final bool isLoading = connectionState == ConnectionState.waiting;

        // --- Determine Body Widget based on State ---
        // Loading State (show shimmer only on initial load)
        if (isLoading && _mealOrders.isEmpty) {
           body = _buildOrdersShimmer();
        }
        // Error State (show error only if no data was previously loaded)
        else if (snapshot.hasError && _mealOrders.isEmpty) {
          body = _buildErrorState(snapshot.error ?? 'Unknown error loading orders.');
        }
        // Success/Loaded State (Future completed or has data from previous load)
        else {
          // Use the currently filtered MEAL orders
          final filteredOrders = _getFilteredMealOrders();

          if (_mealOrders.isEmpty && !isLoading) {
             // Initial load successful but no MEAL orders found
            body = _buildEmptyState('You have no meal orders yet.');
          } else if (filteredOrders.isEmpty && _mealOrders.isNotEmpty) {
             // Meal orders exist, but current status filter yields none
            body = _buildEmptyState('No meal orders match the filter "$_selectedFilter".');
          } else {
             // Meal orders exist and filter matches some (or 'All')
             // Display the list, using filteredOrders if a filter is active, or _mealOrders if 'All'
             body = _buildOrderList(filteredOrders.isNotEmpty ? filteredOrders : _mealOrders);
          }
        }
        // --- End Body Widget Determination ---

        // Build the overall structure: Filter Chips + Body
        return Column(
          children: [
            // Show filter chips if loading OR if there are any meal orders loaded
             _buildFilterChips(isLoading || _mealOrders.isNotEmpty),
            // The body determined above (Shimmer, Error, Empty, or List)
            Expanded(child: body),
          ],
        );
      },
    );
  }

   // Helper widget to build the list view part
   Widget _buildOrderList(List<Order> ordersToShow) {
     return RefreshIndicator(
       onRefresh: () async => _loadOrders(), // Reload orders on pull-to-refresh
       color: Theme.of(context).colorScheme.primary,
       child: ListView.builder(
         padding: const EdgeInsets.only(top: 8.0, bottom: 80.0), // Padding for FAB etc.
         physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable
         itemCount: ordersToShow.length,
         itemBuilder: (context, index) {
           final order = ordersToShow[index];
           // Pass the specific update functions for this tab to the card builder
           return _buildOrderCard(
              context,
              order,
              handleReadyForShipping: _handleReadyForShipping, // Pass the rider assignment trigger func
              updateSimpleStatus: _updateSimpleOrderStatus, // Pass the simple status update func
           );
         },
       ),
     );
   }

   // --- UI Helper Methods (Snackbar, Dialogs, Shimmer, Empty/Error states) ---
   void _showErrorSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, duration: const Duration(seconds: 4), )); }
   void _showSuccessSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Colors.green.shade600, )); }
   void _showLoadingSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Row(children: [const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(whiteColor)), const SizedBox(width: 16), Text(message)]), duration: const Duration(minutes: 1), // Show until dismissed
      backgroundColor: Colors.black87, )); }
   void _dismissLoadingSnackbar() { if (!mounted) return; ScaffoldMessenger.of(context).hideCurrentSnackBar(); }

   void _showOrderNextStepDialog(String newStatus) {
      if (!mounted) return;
      String title = "Status Updated";
      String message = "Order status changed to $newStatus.";

      // Customize message based on the new status
       switch (newStatus) {
          case _OrdersTabState.statusAccepted: // Use class prefix
              title = "Order Accepted!";
              message = "Great! Start preparing the order. You can mark it 'Ready' or 'Assign Rider' when done.";
              break;
          case _OrdersTabState.statusPreparing: // Use class prefix
              title = "Preparation Started";
              message = "Keep it up! Mark the order 'Ready' or 'Assign Rider' once it's ready.";
              break;
          case _OrdersTabState.statusReadyForPickup: // Use class prefix
              title = "Ready for Pickup!";
              message = "The order is now available for any rider to collect.";
              break;
          case _OrdersTabState.statusAssigned: // Use class prefix
              title = "Rider Assigned!";
              message = "The assigned rider has been notified to pick up the order.";
              break;
          case _OrdersTabState.statusOutForDelivery: // Use class prefix // This status might be set by the rider
              title = "Out for Delivery";
              message = "The rider is on their way to the customer.";
              break;
          case _OrdersTabState.statusDelivered: // Use class prefix
              title = "Order Delivered!";
              message = "Fantastic! The customer has received their order.";
              break;
          case _OrdersTabState.statusCancelled: // Use class prefix
              title = "Order Cancelled";
              message = "The order has been cancelled.";
              break;
           // Add case for 'Shipped' if chef can mark it?
           case _OrdersTabState.statusShipped: // Use class prefix
                title = "Order Shipped";
                message = "Order marked as shipped. The rider should update when out for delivery.";
                break;
           default:
                message = "Order status is now '$newStatus'.";
       }


      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    }
   Widget _buildOrdersShimmer() {
       final shimmerBase = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade300 : Colors.grey.shade700;
       final shimmerHighlight = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade100 : Colors.grey.shade500;
       return Shimmer.fromColors( baseColor: shimmerBase, highlightColor: shimmerHighlight,
         child: ListView.builder( padding: const EdgeInsets.only(top: 8.0, bottom: 80.0), itemCount: 5, // Show 5 shimmer items
           physics: const NeverScrollableScrollPhysics(), // Disable scroll for shimmer
           itemBuilder: (_, __) => Card( margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
               child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                 child: Row(children: [
                   // Shimmer Circle Avatar
                   Container(width: 44, height: 44, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(22))),
                   const SizedBox(width: 16),
                   // Shimmer Text Lines
                   Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                         Container(width: double.infinity, height: 18, color: whiteColor, margin: const EdgeInsets.only(bottom: 6)),
                         Container(width: MediaQuery.of(context).size.width * 0.4, height: 14, color: whiteColor),
                       ])),
                   const SizedBox(width: 16),
                   // Shimmer Chip
                   Container(width: 80, height: 25, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(15))),
                 ]),
               )),
         ),
       );
   }
   Widget _buildErrorState(Object error) {
     return Center( child: Padding( padding: const EdgeInsets.all(24.0),
       child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
           Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 50),
           const SizedBox(height: 16),
           Text( 'Error Loading Orders', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center, ),
           const SizedBox(height: 8),
           Text( error.toString(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, ),
           const SizedBox(height: 24),
           ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Retry'), onPressed: _loadOrders, )
         ],
       ),
     ));
   }
   Widget _buildEmptyState(String message) {
       return Center( child: Padding( padding: const EdgeInsets.all(24.0),
         child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
             Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
             const SizedBox(height: 16),
             Text( message, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, ),
             const SizedBox(height: 24),
             ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh'), onPressed: _loadOrders, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.grey[700],) )
           ],
         ),
       ));
   }


  // Builds the row of filter chips for order status
  Widget _buildFilterChips(bool showChips) {
    if (!showChips) return const SizedBox.shrink(); // Hide if no orders or still loading initially

    // Use the updated _orderStatuses list
    final statuses = _orderStatuses;
    final chipTheme = Theme.of(context).chipTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: SingleChildScrollView( // Allow horizontal scrolling if chips overflow
        scrollDirection: Axis.horizontal,
         physics: const BouncingScrollPhysics(), // Nice scroll physics
        child: Wrap( // Use Wrap if you prefer chips to wrap to next line (adjust parent Column/Row)
          spacing: 8.0, // Horizontal spacing between chips
          children: statuses.map((status) {
            final isSelected = _selectedFilter == status; // Check if this chip is selected
            return ChoiceChip(
              label: Text(status),
              selected: isSelected,
              onSelected: (selected) {
                // Update the filter when a chip is selected
                if (selected) setState(() => _selectedFilter = status);
              },
              // Styling based on selection state
              selectedColor: colorScheme.primary.withOpacity(0.15),
              backgroundColor: chipTheme.backgroundColor, // Use theme default background
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? colorScheme.primary : chipTheme.labelStyle?.color,
                fontSize: 13,
              ),
              side: isSelected
                  ? BorderSide(color: colorScheme.primary, width: 1) // Border for selected chip
                  : chipTheme.side ?? BorderSide(color: Colors.grey.shade300, width: 0.8), // Subtle border for unselected
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              visualDensity: VisualDensity.compact, // Make chips smaller
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- Order Card UI and Helpers ---
  // MODIFIED to pass specific callbacks and display rider info
   Widget _buildOrderCard(
        BuildContext context,
        Order order,
        { required Function(Order) handleReadyForShipping, // Callback for rider selection flow
          required Function(Order, String) updateSimpleStatus} // Callback for non-rider actions
    ) {
     final textTheme = Theme.of(context).textTheme;
     final colorScheme = Theme.of(context).colorScheme;
     // Format date/time based on locale
     final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a', Localizations.localeOf(context).toString());
     final statusColor = _getStatusColor(order.orderStatus); // Get color based on status
     final statusIcon = _getStatusIcon(order.orderStatus); // Get icon based on status

     return Card(
       clipBehavior: Clip.antiAlias, // Ensure corners are clipped
       child: ExpansionTile( // Makes the card expandable
         key: PageStorageKey<int>(order.orderId), // Helps preserve expanded state
         tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
         // Leading icon/avatar
         leading: CircleAvatar( backgroundColor: statusColor.withOpacity(0.15), child: Icon(statusIcon, color: statusColor, size: 22), ),
         // Title (Meal Name)
         title: Text( order.mealName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis,),
         // Subtitle (Order ID and Date)
         subtitle: Padding( padding: const EdgeInsets.only(top: 5.0), child: Text( '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}', style: textTheme.bodySmall, ), ),
         // Trailing Status Chip
         trailing: Chip(
             label: Text(order.orderStatus, overflow: TextOverflow.ellipsis,),
             backgroundColor: statusColor.withOpacity(0.15),
             labelStyle: TextStyle( color: statusColor, fontWeight: FontWeight.w600, fontSize: 11, ),
             padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
             visualDensity: VisualDensity.compact, // Make chip smaller
             side: BorderSide.none, // No border for the chip
         ),
         // Expansion arrow colors
         iconColor: colorScheme.primary,
         collapsedIconColor: Colors.grey[500],
         backgroundColor: colorScheme.surface, // Background when expanded
         collapsedBackgroundColor: colorScheme.surface, // Background when collapsed
         childrenPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0).copyWith(top: 0), // Padding for expanded content
         children: [
           const Divider(height: 1, thickness: 0.5),
           const SizedBox(height: 10),
           // Details shown when expanded
           _buildDetailRow(context, Icons.person_outline_rounded, 'Customer ID', order.userId?.toString() ?? 'N/A'),
           _buildDetailRow(context, Icons.storefront_outlined, 'Producer', order.producerName),
           _buildDetailRow(context, Icons.shopping_bag_outlined, 'Quantity', order.quantity.toString()),
           _buildDetailRow(context, Icons.payment_rounded, 'Payment', '${order.paymentStatus} (${order.totalPrice})'),
           _buildDetailRow(context, Icons.location_on_outlined, 'Delivery To', order.deliveryAddress),
           _buildDetailRow(context, Icons.restaurant_outlined, 'Ingredients Req.', order.ingredients),
           //_buildDetailRow(context, Icons.sticky_note_2_outlined, 'Order Type', order.orderType ?? 'Meal'), // Optionally show type
           _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
           // --- NEW: Show Assigned Rider ---
           if (order.assignedRiderId != null)
               _buildDetailRow(context, Icons.two_wheeler_rounded, 'Assigned Rider',
                  '${order.assignedRiderName ?? 'Rider ID: ${order.assignedRiderId}'}' // Show name or ID
               ),
           const SizedBox(height: 16),
           // Show action buttons based on status, passing the correct callbacks
            _buildActionButtons(context, order, handleReadyForShipping, updateSimpleStatus),
           const SizedBox(height: 8),
         ],
       ),
     );
   }

   // MODIFIED Action Buttons to handle new statuses and callbacks
   Widget _buildActionButtons(
       BuildContext context,
       Order order,
       Function(Order) handleReadyForShipping, // Callback for rider selection flow
       Function(Order, String) updateSimpleStatus) // Callback for non-rider actions
   {
      final currentStatus = order.orderStatus.toLowerCase();
      final colorScheme = Theme.of(context).colorScheme;
      return Padding( padding: const EdgeInsets.only(top: 8.0),
        child: Row( mainAxisAlignment: MainAxisAlignment.end, children: [
            // Accept Button (If Pending)
            if (currentStatus == statusPending.toLowerCase()) ...[
              TextButton.icon( icon: const Icon(Icons.check_circle_outline_rounded, size: 18), label: const Text('Accept'), style: TextButton.styleFrom(foregroundColor: Colors.green.shade700), onPressed: () => updateSimpleStatus(order, statusPreparing), ), // Use simple update -> Preparing
              const SizedBox(width: 8),
            ],
            // Ready for Pickup / Assign Rider Button (If Preparing or Accepted)
            if (currentStatus == statusPreparing.toLowerCase() || currentStatus == statusAccepted.toLowerCase()) ...[
               Tooltip( // Wrap with Tooltip
                 message: 'Mark Ready for Pickup or Assign Specific Rider',
                 child: TextButton.icon(
                     icon: const Icon(Icons.local_shipping_outlined, size: 18),
                     label: const Text('Ready/Assign'), // Consolidated button text
                     // tooltip: 'Mark Ready for Pickup or Assign Specific Rider', // Removed from here
                     style: TextButton.styleFrom(foregroundColor: readyForPickupColor), // Use specific color
                     onPressed: () => handleReadyForShipping(order), ), // <<< CALL RIDER ASSIGNMENT FLOW
               ),
               const SizedBox(width: 8),
            ],
            // Reject Button (For most active statuses before delivery/cancellation)
            // Added checks for Ready and Assigned statuses as well
            if (currentStatus != statusDelivered.toLowerCase() &&
                currentStatus != statusCancelled.toLowerCase() &&
                currentStatus != statusOutForDelivery.toLowerCase()
               )
              TextButton.icon( icon: const Icon(Icons.cancel_outlined, size: 18), label: const Text('Reject'), style: TextButton.styleFrom(foregroundColor: colorScheme.error), onPressed: () => _showRejectConfirmation(context, order, updateSimpleStatus), ), // Use simple update -> Cancelled
          ],
        ),
      );
   }

    // MODIFIED Reject Confirmation to use updateSimpleStatus
   void _showRejectConfirmation(BuildContext context, Order order, Function(Order, String) updateSimpleStatusCallback) {
      if (!mounted) return;
      showDialog( context: context, builder: (BuildContext dialogContext) {
          return AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text("Confirm Rejection"), content: Text("Reject Order #${order.orderId} (${order.mealName})?"),
            actions: <Widget>[
              TextButton( child: const Text("Cancel"), onPressed: () => Navigator.of(dialogContext).pop(), ),
              TextButton( child: Text("Reject Order", style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close dialog first
                  updateSimpleStatusCallback(order, statusCancelled); // <<< Call simple status update callback
                },
              ),
            ],
          );
        },
      );
   }

   // Helper to build detail rows consistently
   Widget _buildDetailRow(BuildContext context, IconData icon, String label, String? value) {
     // Don't build row if value is null or empty
     if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

     final textTheme = Theme.of(context).textTheme;
     return Padding( padding: const EdgeInsets.symmetric(vertical: 7.0),
       child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
           // Icon
           Icon(icon, size: 18, color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
           const SizedBox(width: 12),
           // Label and Value (using RichText for potential bolding)
           Expanded( child: RichText( text: TextSpan(style: textTheme.bodyMedium, children: [
                 TextSpan( text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w500)), // Bold label
                 TextSpan(text: value), // Regular value
               ])))
         ],
       ),
     );
   }

   // MODIFIED Status Colors & Icons to include new statuses
   Color _getStatusColor(String status) {
     // Use lowercase for case-insensitive comparison
     switch (status.toLowerCase()) {
       case 'pending': return Colors.orange.shade600;
       case 'accepted': return Colors.lightBlue.shade600; // Differentiate from Preparing
       case 'preparing': return Colors.blue.shade700; // Darker blue for Preparing
       case 'ready for pickup': return readyForPickupColor; // Use defined constant
       case 'assigned': return assignedColor; // Use defined constant
       case 'shipped': // Status set by Chef (maybe before pickup?)
       case 'out for delivery': return Colors.purple.shade500; // Status set by Rider
       case 'delivered': case 'completed': return Colors.green.shade600;
       case 'cancelled': case 'rejected': return Colors.red.shade500;
       default: return Colors.grey.shade600; // Default for unknown status
     }
   }
   IconData _getStatusIcon(String status) {
      // Use lowercase for case-insensitive comparison
     switch (status.toLowerCase()) {
       case 'pending': return Icons.hourglass_bottom_rounded;
       case 'accepted': return Icons.thumb_up_alt_outlined;
       case 'preparing': return Icons.soup_kitchen_rounded;
       case 'ready for pickup': return Icons.inventory_2_outlined; // Icon representing ready package
       case 'assigned': return Icons.person_pin_circle_outlined; // Icon representing assigned person
       case 'shipped': return Icons.local_shipping_outlined; // Chef marks shipped
       case 'out for delivery': return Icons.two_wheeler_rounded; // Rider is delivering
       case 'delivered': case 'completed': return Icons.check_circle_rounded;
       case 'cancelled': case 'rejected': return Icons.cancel_rounded;
       default: return Icons.help_outline_rounded; // Default for unknown status
     }
   }
}

// --- Rider Selection Dialog Widget (NEW) ---
class _RiderSelectionDialog extends StatefulWidget {
  final ApiService apiService;
  final int orderId; // Pass order ID for context if needed

  const _RiderSelectionDialog({
      required this.apiService,
      required this.orderId,
      // super.key, // Add super.key if using Flutter 3+
  });

  @override
  _RiderSelectionDialogState createState() => _RiderSelectionDialogState();
}

class _RiderSelectionDialogState extends State<_RiderSelectionDialog> {
  // Future<List<Rider>>? _ridersFuture; // Removed as it's unused. State managed by _isLoading, _errorMessage, _allRiders
  List<Rider> _allRiders = []; // Renamed from _availableRiders to hold all riders
  bool _isLoading = true; // Loading state flag
  String? _errorMessage; // Error message if fetching fails

  @override
  void initState() {
    super.initState();
    // Fetch riders when the dialog is initialized
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    // Set loading state and clear previous errors
    if (mounted) {
       setState(() {
         _isLoading = true;
         _errorMessage = null;
       });
    }

    try {
      // Fetch riders using the passed ApiService instance
      final riders = await widget.apiService.fetchAvailableRiders();
      // If successful and widget is still mounted, update state
      if (mounted) {
        setState(() {
          _allRiders = riders; // Assign to renamed list
          _isLoading = false;
        });
      }
    } catch (e) {
      // If error occurs and widget is still mounted, update state with error message
      print("Error fetching riders in dialog: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Error fetching riders: ${e.toString()}";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row( // Use Row for title and refresh button
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Assign Rider'),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRiders, // Call fetch riders method
            tooltip: 'Refresh Rider List',
            visualDensity: VisualDensity.compact, // Make button smaller
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      // Constrain content size to prevent dialog from becoming too large
      content: SizedBox(
        width: double.maxFinite, // Use available width
        // Limit height to prevent overflow, e.g., 40% of screen height
        height: MediaQuery.of(context).size.height * 0.4,
        child: _buildContent(), // Build content based on state
      ),
      actions: <Widget>[
        // Button to mark ready without assigning a specific rider
        TextButton(
          child: const Text("Mark Ready for Any Rider"),
          onPressed: () => Navigator.of(context).pop(true), // Return true signifies 'Mark Ready' action
        ),
        // Cancel button always closes the dialog and returns null
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.of(context).pop(null), // Return null signifies no selection/cancel
        ),
      ],
    );
  }

  // Helper to build the content of the dialog based on loading/error/data state
  Widget _buildContent() {
    // Show loading indicator
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Show error message if fetching failed
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
        )
      );
    }
    // Show message if no riders were found (changed from available riders)
    if (_allRiders.isEmpty) {
      return const Center(
          child: Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No riders found.", textAlign: TextAlign.center), // Updated message
          )
      );
    }

    // --- Display list of ALL riders ---
    // Removed the Column and "Any Rider" ListTile from here.
    // The "Mark Ready for Any Rider" button in actions handles that flow.
    return ListView.builder(
        // Removed Expanded and shrinkWrap as ListView is the direct child now
        itemCount: _allRiders.length,
        itemBuilder: (context, index) {
          final rider = _allRiders[index];
          // Use rider.isActive boolean field now
          final bool isAvailable = rider.isActive;
          // Set background colors based on availability
          final Color tileHighlightColor = isAvailable ? Colors.teal.shade50 : Colors.grey.shade200;
          final Color textColor = isAvailable ? Colors.black87 : Colors.grey.shade600;

          return Card( // Wrap each rider in a Card
              margin: const EdgeInsets.symmetric(vertical: 4),
              elevation: 1,
              // Use shape for rounded corners and color for highlight
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0), // Match Card's default or adjust
              ),
              color: tileHighlightColor, // Use the highlight color for the Card background
              child: ListTile(
                  leading: CircleAvatar(
                      // Adjust avatar background based on availability
                      backgroundColor: isAvailable ? primaryTeal.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      child: Icon(Icons.two_wheeler, color: isAvailable ? primaryTeal : Colors.grey, size: 20)
                  ),
                  title: Text(rider.name, style: TextStyle(color: textColor)),
                  // Display 'Active' or 'Inactive' based on the boolean field
                  subtitle: Text(isAvailable ? 'Status: Active' : 'Status: Inactive', style: TextStyle(color: textColor.withOpacity(0.8))),
                  trailing: isAvailable ? const Icon(Icons.chevron_right) : null, // Only show chevron if available
                  onTap: () {
                    if (isAvailable) {
                      // If available, pop immediately with the rider object
                      Navigator.of(context).pop(rider);
                    } else {
                      // If unavailable, show confirmation dialog
                      _confirmAssignUnavailableRider(rider);
                    }
                  },
                   dense: true, // Make list item compact
              ),
          );
        },
      );
}

// Show confirmation dialog when trying to assign an unavailable rider
Future<void> _confirmAssignUnavailableRider(Rider rider) async {
if (!mounted) return;
final bool? confirm = await showDialog<bool>(
  context: context,
  builder: (BuildContext dialogContext) {
    return AlertDialog(
      title: const Text('Confirm Assignment'),
      content: Text('Rider ${rider.name} is currently ${rider.status}. Assign anyway?'),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false), // Return false on cancel
        ),
        TextButton(
          child: const Text('Assign Anyway'),
          onPressed: () => Navigator.of(dialogContext).pop(true), // Return true on confirm
        ),
      ],
    );
  },
);

// If confirmed, pop the main dialog returning the rider
if (confirm == true) {
   if (!mounted) return; // Check mount status again after async gap
   Navigator.of(context).pop(rider);
}
}
}


// --- Gigs Tab Widget (MODIFIED to filter for Gigs & Add Rider Assignment) ---
class GigsTab extends StatefulWidget {
  const GigsTab({super.key});
  @override
  State<GigsTab> createState() => _GigsTabState();
}

 // --- Gigs Tab Widget (MODIFIED to filter for Gigs & Add Rider Assignment) ---
// ... (previous GigsTab code: StatefulWidget, constants, state variables, initState, didChangeDependencies, _loadOrders, _handleReadyForShipping, _assignSpecificRider, _markReadyForAnyRider) ...

 class _GigsTabState extends State<GigsTab>
    with AutomaticKeepAliveClientMixin {
  // Keep the state alive
  @override
  bool get wantKeepAlive => true;

  // State variables
  Future<List<Order>>? _ordersFuture; // Future for loading orders
  List<Order> _allFetchedOrders = []; // All orders fetched
  List<Order> _gigOrders = []; // Filtered list for Gigs
  bool _isLoading = false; // Loading indicator state
  String? _errorMessage; // Error message state

    // ... (state variables, initState, didChangeDependencies, _loadOrders) ... - Keep comments for reference
    // ... (_handleReadyForShipping, _assignSpecificRider, _markReadyForAnyRider) ... - Keep comments for reference

  // Placeholder for the order loading logic
  Future<void> _loadOrders() async {
    print("Placeholder: _loadOrders called");
    // TODO: Implement actual order loading logic for Gigs
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    // Simulating network delay
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      // Replace with actual API call and filtering for 'gig' type orders
      _allFetchedOrders = []; // Example: reset or fetch data
      _gigOrders = _allFetchedOrders.where((o) => o.orderType?.toLowerCase() == 'gig').toList();
      _isLoading = false;
    });
     _ordersFuture = Future.value(_gigOrders); // Update future
  }

  // Handles the 'Ready/Assign' action: Shows dialog, then assigns or marks ready.
  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return; // Check if widget is still mounted

    // Show the rider selection dialog and wait for the result
    final result = await showDialog<dynamic>( // Expect Rider, bool, or null
      context: context,
      barrierDismissible: false, // User must explicitly choose an action
      builder: (BuildContext context) {
        return _RiderSelectionDialog(
          apiService: ApiService(), // Pass the ApiService instance
          orderId: order.orderId, // Pass order ID if needed by dialog/API
        );
      },
    );

    // Handle the result from the dialog
    if (!mounted) return; // Check again after async gap

    if (result is Rider) {
      // A specific rider was selected, show confirmation dialog
      print("Specific rider selected: ${result.name}, showing confirmation...");
      await _showRiderAssignmentConfirmation(order, result); // Call confirmation dialog
    } else if (result == true) {
      // "Mark Ready for Any Rider" was selected
      print("Marking order ${order.orderId} as Ready for Any Rider");
      await _markReadyForAnyRider(order);
    } else {
      // Dialog was cancelled (result is null or unexpected)
      print("Rider selection cancelled or dialog returned unexpected value.");
      // Optionally show a message or do nothing
    }
  }

  // Placeholder: Assigns a specific rider to the order via API
  Future<void> _assignSpecificRider(Order order, Rider rider) async {
     print("Placeholder: Assigning rider ${rider.name} to order ${order.orderId}");
     // TODO: Implement API call to assign specific rider
     // Example: await ApiService.assignRiderToOrder(order.orderId, rider.id);
     // Update UI optimistically or after confirmation
     _updateSimpleOrderStatus(order, _OrdersTabState.statusAssigned); // Update status locally
     _showSuccessSnackbar("Rider ${rider.name} assigned to Gig ${order.orderId}.");
  }

  // Placeholder: Marks the order as ready for any rider via API
  Future<void> _markReadyForAnyRider(Order order) async {
    print("Placeholder: Marking order ${order.orderId} as Ready for Pickup");
    // TODO: Implement API call to update status to 'Ready for Pickup'
    // Example: await ApiService.updateOrderStatus(order.orderId, _OrdersTabState.statusReadyForPickup);
    // Update UI optimistically or after confirmation
    _updateSimpleOrderStatus(order, _OrdersTabState.statusReadyForPickup); // Update status locally
    _showSuccessSnackbar("Gig ${order.orderId} marked as Ready for Pickup by any rider.");
  }

  // NEW: Shows a confirmation dialog before assigning a specific rider
  Future<void> _showRiderAssignmentConfirmation(Order order, Rider rider) async {
    if (!mounted) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Assignment for Gig #${order.orderId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Prevent excessive height
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign rider:'),
              SizedBox(height: 8),
              Text('  Name: ${rider.name}', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('  Status: ${rider.isActive ? "Active" : "Inactive"}'), // Use isActive
              Text('  ID: ${rider.id}'),
              // Add any other relevant rider details here
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false), // Return false
            ),
            TextButton(
              child: const Text('Confirm Assignment'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () => Navigator.of(dialogContext).pop(true), // Return true
            ),
          ],
        );
      },
    );

    // If confirmed, proceed with the actual assignment
    if (confirm == true) {
      if (!mounted) return; // Check mount status again
      await _assignSpecificRider(order, rider);
    } else {
      print("Rider assignment cancelled by chef.");
      // Optionally show a snackbar message
      // _showInfoSnackbar("Rider assignment cancelled.");
    }
  }


  // Placeholder for rider selection dialog (called from _handleReadyForShipping)
 Future<void> _showRiderSelectionDialog(Order order) async {
   print("Placeholder: _showRiderSelectionDialog called for order ${order.orderId}");
   // TODO: Implement rider selection dialog
 }

// Handle simple status updates for Gigs (Accept, Reject)
  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return; // Gig not found
    if(mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Clear messages
    // Store original state
    final originalStatus = _gigOrders[orderIndex].orderStatus;
    final allIndex = _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);

    // Optimistic UI Update
    setState(() => _gigOrders[orderIndex].orderStatus = newStatus);
    if (allIndex != -1) _allFetchedOrders[allIndex].orderStatus = newStatus; // Update full list
    _showLoadingSnackbar("Updating Gig status to $newStatus...");

    try {
      // Call general status update API
      bool success = await ApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar(); // Dismiss loading indicator
      if (mounted) { // Check if widget is still mounted after async operation
          if (!success) {
            // Revert UI on failure
            setState(() => _gigOrders[orderIndex].orderStatus = originalStatus);
             if (allIndex != -1) _allFetchedOrders[allIndex].orderStatus = originalStatus;
            _showErrorSnackbar('Failed to update gig ${order.orderId} status.');
          } else {
            // Show success and guidance
            _showSuccessSnackbar('Gig ${order.orderId} status updated to $newStatus.');
            _showOrderNextStepDialog(newStatus); // Show guidance dialog (uses Gig context)
             setState(() {}); // Trigger rebuild to reflect change visually
          }
      }
    } catch (e) {
       _dismissLoadingSnackbar(); // Dismiss on error
      print("Error in _updateSimpleOrderStatus (Gigs): $e");
      if (mounted) { // Check mounted again
        // Revert UI on exception
        setState(() => _gigOrders[orderIndex].orderStatus = originalStatus);
         if (allIndex != -1) _allFetchedOrders[allIndex].orderStatus = originalStatus;
        _showErrorSnackbar('An error occurred while updating gig status.');
      }
    }
  }

 // Helper to find index in _gigOrders
  int _findOrderIndex(int orderId) {
      final index = _gigOrders.indexWhere((o) => o.orderId == orderId);
      if (index == -1) {
          print("Warning: Gig Order $orderId not found in _gigOrders list for update.");
      }
      return index;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep state across tab switches

    return FutureBuilder<List<Order>>(
      future: _ordersFuture, // The future that fetches orders
      builder: (context, snapshot) {
        Widget body;
        final connectionState = snapshot.connectionState;
        final bool isLoading = connectionState == ConnectionState.waiting;

        // --- Determine Body Widget based on State ---
        // Loading State (show shimmer only on initial load)
        if (isLoading && _gigOrders.isEmpty) {
           body = _buildOrdersShimmer(); // Reuse shimmer from OrdersTab
        }
        // Error State (show error only if no data was previously loaded)
        else if (snapshot.hasError && _gigOrders.isEmpty) {
          body = _buildErrorState(snapshot.error ?? 'Unknown error loading gigs.'); // Reuse error state
        }
        // Success/Loaded State
        else {
          // Use _gigOrders which is already filtered and sorted
          if (_gigOrders.isEmpty && !isLoading) {
            // Initial load successful but no GIG orders found
            body = _buildEmptyState('You have no active gigs.'); // Specific message for gigs
          } else {
            // Display the list of gigs using the loaded _gigOrders
             body = _buildGigList(_gigOrders);
          }
        }
        // --- End Body Widget Determination ---

        // Gigs tab doesn't have filter chips, just return the body
        return body;
      },
    );
  }

  // Helper widget to build the list view part for Gigs
  Widget _buildGigList(List<Order> gigsToShow) {
     return RefreshIndicator(
       onRefresh: () async => _loadOrders(), // Reload gigs on pull-to-refresh
       color: Theme.of(context).colorScheme.primary,
       child: ListView.builder(
         padding: const EdgeInsets.only(top: 8.0, bottom: 80.0), // Padding at top/bottom
         physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable
         itemCount: gigsToShow.length,
         itemBuilder: (context, index) {
           final order = gigsToShow[index];
           // Build the card using the shared card function, passing this tab's update callbacks
           return _buildOrderCard(
                context,
                order,
                handleReadyForShipping: _handleReadyForShipping, // Pass gig-specific assignment handler
                updateSimpleStatus: _updateSimpleOrderStatus, // Pass gig-specific simple update handler
            );
         },
       ),
     );
   }

   // --- UI Helper Methods (Snackbar, Dialogs, Shimmer, Empty/Error states, Order Card) ---
   // Reusing methods from OrdersTab, adapted for "Gigs" context where necessary

   void _showErrorSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, duration: const Duration(seconds: 4), )); }
   void _showSuccessSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Colors.green.shade600, )); }
   void _showLoadingSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Row(children: [const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(whiteColor)), const SizedBox(width: 16), Text(message)]), duration: const Duration(minutes: 1), backgroundColor: Colors.black87, )); }
   void _dismissLoadingSnackbar() { if (!mounted) return; ScaffoldMessenger.of(context).hideCurrentSnackBar(); }

   // Dialog specific to Gigs context
   void _showOrderNextStepDialog(String newStatus) {
      if (!mounted) return;
      String title = "Gig Status Updated";
      String message = "Gig status changed to $newStatus.";

      // Customize message based on the new status (Gig context)
       switch (newStatus) {
          case _OrdersTabState.statusAccepted: // Use class prefix
              title = "Gig Accepted!";
              message = "Great! Start preparing for the gig. Mark it 'Ready' or 'Assign Staff' when preparations are complete.";
              break;
          case _OrdersTabState.statusPreparing: // Use class prefix
              title = "Preparation Started";
              message = "Mark the gig 'Ready' or 'Assign Staff' once preparations are complete.";
              break;
          case _OrdersTabState.statusReadyForPickup: // Use class prefix // Keep name, but adjust message context
               title = "Gig Ready!";
               message = "The gig is now ready. Any assigned staff/rider can proceed.";
              break;
          case _OrdersTabState.statusAssigned: // Use class prefix
               title = "Staff/Rider Assigned!";
               message = "The assigned person has been notified for this gig.";
              break;
          case _OrdersTabState.statusOutForDelivery: // Use class prefix // Rename contextually
               title = "Gig In Progress";
               message = "The gig service is underway."; // Assuming rider/staff updates this
              break;
          case _OrdersTabState.statusDelivered: // Use class prefix // Rename contextually
               title = "Gig Completed!";
               message = "Fantastic! The gig has been successfully completed.";
              break;
          case _OrdersTabState.statusCancelled: // Use class prefix
               title = "Gig Cancelled";
               message = "The gig has been cancelled.";
              break;
           // Add case for 'Shipped' if it represents 'Service Started' for gigs
           case _OrdersTabState.statusShipped: // Use class prefix
               title = "Gig Service Started";
               message = "The service for this gig has begun.";
               break;
           default:
                message = "Gig status is now '$newStatus'.";
       }

      showDialog( context: context, builder: (BuildContext context) {
           return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(title),
                content: Text(message),
                actions: <Widget>[
                TextButton(
                    child: const Text("OK"),
                    onPressed: () => Navigator.of(context).pop(),
                ),
                ],
            );
      });
   }

   // Reuse Shimmer widget
   Widget _buildOrdersShimmer() {
      final shimmerBase = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade300 : Colors.grey.shade700;
      final shimmerHighlight = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade100 : Colors.grey.shade500;
      return Shimmer.fromColors( baseColor: shimmerBase, highlightColor: shimmerHighlight,
        child: ListView.builder( padding: const EdgeInsets.only(top: 8.0, bottom: 80.0), itemCount: 5,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (_, __) => Card( margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(22))),
                  const SizedBox(width: 16),
                  Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: double.infinity, height: 18, color: whiteColor, margin: const EdgeInsets.only(bottom: 6)),
                        Container(width: MediaQuery.of(context).size.width * 0.4, height: 14, color: whiteColor),
                      ])),
                  const SizedBox(width: 16),
                  Container(width: 80, height: 25, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(15))),
                ]),
              )),
        ),
      );
   }

   // Reuse Error state widget, adjusting text
   Widget _buildErrorState(Object error) {
     return Center( child: Padding( padding: const EdgeInsets.all(24.0),
       child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
           Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 50),
           const SizedBox(height: 16),
           Text( 'Error Loading Gigs', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center, ), // Changed text
           const SizedBox(height: 8),
           Text( error.toString(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, ),
           const SizedBox(height: 24),
           ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Retry'), onPressed: _loadOrders, ) // Calls GigsTab._loadOrders
         ],
       ),
     ));
   }

   // Reuse Empty state widget, adjusting icon and text
   Widget _buildEmptyState(String message) {
     return Center( child: Padding( padding: const EdgeInsets.all(24.0),
       child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
           Icon(Icons.work_off_outlined, size: 60, color: Colors.grey[400]), // Changed Icon for Gigs
           const SizedBox(height: 16),
           Text( message, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, ),
           const SizedBox(height: 24),
           ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh'), onPressed: _loadOrders, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.grey[700],) ) // Calls GigsTab._loadOrders
         ],
       ),
     ));
   }

   // Use the SAME card builder as OrdersTab, passing GigsTab's callbacks
   Widget _buildOrderCard(
        BuildContext context,
        Order order,
        { required Function(Order) handleReadyForShipping,
          required Function(Order, String) updateSimpleStatus}
    ) {
     final textTheme = Theme.of(context).textTheme;
     final colorScheme = Theme.of(context).colorScheme;
     final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a', Localizations.localeOf(context).toString());
     final statusColor = _getStatusColor(order.orderStatus); // Use shared status color function
     final statusIcon = _getStatusIcon(order.orderStatus); // Use shared status icon function

     return Card(
       clipBehavior: Clip.antiAlias,
       child: ExpansionTile(
         key: PageStorageKey<int>(order.orderId),
         tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
         leading: CircleAvatar( backgroundColor: statusColor.withOpacity(0.15), child: Icon(statusIcon, color: statusColor, size: 22), ),
         title: Text( order.mealName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis,), // Gig name/title
         subtitle: Padding( padding: const EdgeInsets.only(top: 5.0), child: Text( '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}', style: textTheme.bodySmall, ), ),
         trailing: Chip( label: Text(order.orderStatus, overflow: TextOverflow.ellipsis,), backgroundColor: statusColor.withOpacity(0.15), labelStyle: TextStyle( color: statusColor, fontWeight: FontWeight.w600, fontSize: 11, ), padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0), visualDensity: VisualDensity.compact, side: BorderSide.none, ),
         iconColor: colorScheme.primary,
         collapsedIconColor: Colors.grey[500],
         backgroundColor: colorScheme.surface,
         collapsedBackgroundColor: colorScheme.surface,
         childrenPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0).copyWith(top: 0),
         children: [
           const Divider(height: 1, thickness: 0.5),
           const SizedBox(height: 10),
           _buildDetailRow(context, Icons.person_outline_rounded, 'Customer ID', order.userId?.toString() ?? 'N/A'),
           _buildDetailRow(context, Icons.storefront_outlined, 'Producer', order.producerName),
           _buildDetailRow(context, Icons.event_seat_outlined, 'Quantity/Guests', order.quantity.toString()), // Icon/label for gig context
           _buildDetailRow(context, Icons.payment_rounded, 'Payment', '${order.paymentStatus} (${order.totalPrice})'),
           _buildDetailRow(context, Icons.location_on_outlined, 'Location', order.deliveryAddress), // Gig location
           _buildDetailRow(context, Icons.list_alt_rounded, 'Requirements', order.ingredients), // Changed icon/label
           _buildDetailRow(context, Icons.sticky_note_2_outlined, 'Order Type', order.orderType ?? 'Gig'), // Show type
           _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
           // Show Assigned Rider/Staff for Gigs too
           if (order.assignedRiderId != null)
               _buildDetailRow(context, Icons.two_wheeler_rounded, // Or Icons.badge_outlined for staff
                  'Assigned Staff/Rider',
                  '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}'
               ),
           const SizedBox(height: 16),
            _buildActionButtons(context, order, handleReadyForShipping, updateSimpleStatus), // Pass GigsTab callbacks
           const SizedBox(height: 8),
         ],
       ),
     );
   }

   // Use the SAME action buttons builder, adjusting labels/tooltips if needed for Gigs
   Widget _buildActionButtons(
       BuildContext context,
       Order order,
       Function(Order) handleReadyForShipping, // Callback for rider/staff assignment flow
       Function(Order, String) updateSimpleStatus) // Callback for simple status changes
   {
       final currentStatus = order.orderStatus.toLowerCase();
       final colorScheme = Theme.of(context).colorScheme;
       return Padding( padding: const EdgeInsets.only(top: 8.0),
         child: Row( mainAxisAlignment: MainAxisAlignment.end, children: [
             // Accept Gig
             // Action Buttons based on status (GIG SPECIFIC)
             if (currentStatus == _OrdersTabState.statusPending.toLowerCase()) ...[ // Use class prefix
               TextButton.icon( icon: const Icon(Icons.check_circle_outline_rounded, size: 18), label: const Text('Accept Gig'), style: TextButton.styleFrom(foregroundColor: Colors.green.shade700), onPressed: () => updateSimpleStatus(order, _OrdersTabState.statusPreparing), ), // Use class prefix // Use simple callback -> Preparing
               const SizedBox(width: 8),
             ],
             // Ready / Assign Staff/Rider Button (If Preparing or Accepted)
             if (currentStatus == _OrdersTabState.statusPreparing.toLowerCase() || currentStatus == _OrdersTabState.statusAccepted.toLowerCase()) ...[ // Use class prefix
               Tooltip( // Wrap with Tooltip
                 message: 'Mark Gig Ready or Assign Staff/Rider', // Tooltip message
                 child: TextButton.icon( icon: const Icon(Icons.people_alt_outlined, size: 18), // Icon more suitable for staff/team
                     label: const Text('Ready/Assign'),
                     // tooltip: 'Mark Gig Ready or Assign Staff/Rider', // Removed from here
                     style: TextButton.styleFrom(foregroundColor: readyForPickupColor), // Reuse color
                     onPressed: () => handleReadyForShipping(order), ), // <<< CALL RIDER/STAFF ASSIGNMENT FLOW
               ),
               const SizedBox(width: 8),
             ],
             // Reject Gig Button (Similar logic to OrdersTab)
             if (currentStatus != _OrdersTabState.statusDelivered.toLowerCase() && // Use class prefix
                 currentStatus != _OrdersTabState.statusCancelled.toLowerCase() && // Use class prefix
                 currentStatus != _OrdersTabState.statusOutForDelivery.toLowerCase() // Use class prefix // Assuming rider updates this
                )
               TextButton.icon( icon: const Icon(Icons.cancel_outlined, size: 18), label: const Text('Reject Gig'), style: TextButton.styleFrom(foregroundColor: colorScheme.error), onPressed: () => _showRejectConfirmation(context, order, updateSimpleStatus), ), // Use simple callback -> Cancelled
           ],
         ),
       );
    }


   // Use the SAME reject confirmation, adjusting text for "Gig"
   void _showRejectConfirmation(BuildContext context, Order order, Function(Order, String) updateSimpleStatusCallback) {
      if (!mounted) return;
      showDialog( context: context, builder: (BuildContext dialogContext) {
          // Adjust text slightly for "Gig"
          return AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), title: const Text("Confirm Rejection"), content: Text("Reject Gig #${order.orderId} (${order.mealName})?"),
            actions: <Widget>[
              TextButton( child: const Text("Cancel"), onPressed: () => Navigator.of(dialogContext).pop(), ),
              TextButton( child: Text("Reject Gig", style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close dialog first
                  updateSimpleStatusCallback(order, _OrdersTabState.statusCancelled); // Use class prefix // Call simple status update callback
                },
              ),
            ],
          );
        },
      );
   }

   // Use the SAME detail row builder
   Widget _buildDetailRow(BuildContext context, IconData icon, String label, String? value) {
     if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
     final textTheme = Theme.of(context).textTheme;
     return Padding( padding: const EdgeInsets.symmetric(vertical: 7.0),
       child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
           Icon(icon, size: 18, color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
           const SizedBox(width: 12),
           Expanded( child: RichText( text: TextSpan(style: textTheme.bodyMedium, children: [
                 TextSpan( text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
                 TextSpan(text: value),
               ])))
         ],
       ),
     );
   }

   // Use the SAME status color/icon helpers (defined globally or duplicated/imported)
    Color _getStatusColor(String status) {
        // Using the definition from OrdersTab
        switch (status.toLowerCase()) {
            case 'pending': return Colors.orange.shade600;
            case 'accepted': return Colors.lightBlue.shade600;
            case 'preparing': return Colors.blue.shade700;
            case 'ready for pickup': return readyForPickupColor;
            case 'assigned': return assignedColor;
            case 'shipped': // Might represent 'Service Started'
            case 'out for delivery': // Might represent 'In Progress'
                return Colors.purple.shade500;
            case 'delivered': case 'completed': return Colors.green.shade600; // Might represent 'Gig Completed'
            case 'cancelled': case 'rejected': return Colors.red.shade500;
            default: return Colors.grey.shade600;
        }
    }
    IconData _getStatusIcon(String status) {
        // Using the definition from OrdersTab, maybe adjust icons for Gig context
         switch (status.toLowerCase()) {
            case 'pending': return Icons.hourglass_bottom_rounded;
            case 'accepted': return Icons.thumb_up_alt_outlined;
            case 'preparing': return Icons.soup_kitchen_rounded; // Or Icons.construction for Gigs
            case 'ready for pickup': return Icons.inventory_2_outlined; // Or Icons.flag_circle_outlined for Gigs
            case 'assigned': return Icons.person_pin_circle_outlined; // Or Icons.badge_outlined for Gigs
            case 'shipped': // Might represent 'Service Started'
            case 'out for delivery': // Might represent 'In Progress'
                return Icons.local_shipping_rounded; // Or Icons.directions_run_outlined for Gigs
            case 'delivered': case 'completed': return Icons.check_circle_rounded; // Or Icons.celebration_outlined for Gigs
            case 'cancelled': case 'rejected': return Icons.cancel_rounded;
            default: return Icons.help_outline_rounded;
        }
    }
 } // End of _GigsTabState


// --- Products Tab Widget (Menu - MODIFIED for "Coming Soon") ---
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<MealProduct>>? _productsFuture;
  List<MealProduct> _products = [];
  // NOTE: Selection state is kept commented out as actions are "Coming Soon"
  // Set<String> _selectedProductIds = {};
  // Map<String, int> _mealQuantities = {};

  bool _didLoadProducts = false;

  @override
  bool get wantKeepAlive => true; // Keep state

  @override
  void initState() {
    super.initState();
    // Moved loading to didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load only once
    if (!_didLoadProducts) {
      _didLoadProducts = true;
      _loadProducts();
    }
  }

  void _loadProducts() {
     if(mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
     // Reset list and set loading state
    setState(() {
      _products = [];
      // _selectedProductIds = {}; // Reset selection if enabled
      // _mealQuantities = {}; // Reset quantities if enabled
      _productsFuture = ApiService.fetchProducts(); // Use static method
    });
    // Handle future result
    _productsFuture!.then((products) {
      if (mounted) {
        setState(() {
          _products = products;
          // Sort products alphabetically by name
          _products.sort((a, b) => a.mealName.compareTo(b.mealName));
        });
      }
    }).catchError((error, stackTrace) {
      print("Error in _loadProducts (ProductsTab): $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading menu items: $error');
        setState(() {
           _products = []; // Clear list on error
           _productsFuture = Future.error(error); // Set future to error state
        });
      }
    });
  }

  // --- "Coming Soon" Actions ---

  void _showComingSoonSnackbar(String featureName) {
     if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$featureName feature is Coming Soon!', style: const TextStyle(color: whiteColor)),
      backgroundColor: Theme.of(context).colorScheme.secondary, // Use theme secondary color
      duration: const Duration(seconds: 2),
    ));
  }

  // --- Add Product: Shows "Coming Soon" ---
  void _handleAddProduct() {
    _showComingSoonSnackbar("Adding new meals");
    // In future, show dialog: _showProductDialog();
  }

  // --- Edit Product: Shows "Coming Soon" ---
  void _handleEditProduct(MealProduct product) {
     _showComingSoonSnackbar("Editing meals");
    // In future, show dialog: _showProductDialog(productToEdit: product);
  }

   // --- Delete Product: Shows "Coming Soon" ---
  void _handleDeleteProduct(MealProduct product) {
     _showComingSoonSnackbar("Deleting meals");
    // In future, show confirmation: _confirmDeleteProduct(product);
  }

  // --- Toggle Selection: Shows "Coming Soon" (instead of actually selecting) ---
  void _handleToggleSelection(MealProduct product) {
    _showComingSoonSnackbar("Selecting meals for stock update");
    // --- Logic for actual selection (Commented Out) ---
    // setState(() {
    //    final mealId = product.mealId;
    //    final isSelected = _selectedProductIds.contains(mealId);
    //    if (isSelected) {
    //       _selectedProductIds.remove(mealId);
    //       _mealQuantities.remove(mealId);
    //    } else {
    //       _selectedProductIds.add(mealId);
    //       _mealQuantities[mealId] = 1; // Default quantity to 1 on selection
    //    }
    // });
    // --- End Selection Logic ---
  }

  // --- Update Stock Action: Shows "Coming Soon" ---
  Future<void> _handleUpdateStock() async {
     _showComingSoonSnackbar("Updating stock levels");
     // --- Logic for actual stock update (Commented Out) ---
     // final stockList = _selectedMealStock;
     // if (stockList.isEmpty) {
     //    _showErrorSnackbar("No meals selected to add to stock.");
     //    return;
     // }
     // _showLoadingSnackbar("Updating stock...");
     // final payload = jsonEncode({"stock": stockList}); // Assuming API expects {"stock": [{"meal_id": "...", "quantity": ...}]}
     // bool success = await ApiService.addMealsToChefStock(stockList.map((e) => e['meal_id'] as String).toList()); // Adjust based on API
     // _dismissLoadingSnackbar();
     // if (mounted) {
     //    if (success) {
     //      _showSuccessSnackbar("Selected meals added to stock.");
     //      setState(() { // Clear selection after success
     //         _selectedProductIds.clear();
     //         _mealQuantities.clear();
     //      });
     //    } else {
     //      _showErrorSnackbar("Failed to update stock. Please try again.");
     //    }
     // }
     // --- End Stock Update Logic ---
  }

  // --- Get Selected Stock (kept for structure, not used by Coming Soon) ---
   List<Map<String, dynamic>> get _selectedMealStock {
    // This getter remains but won't be effectively used by the FAB action
    return []; // Return empty as selection is disabled
    // --- Logic if selection were enabled ---
    // return _selectedProductIds
    //     .map((mealId) {
    //         final quantity = _mealQuantities[mealId] ?? 1; // Default to 1 if not found
    //         // You might need more details from the product itself here if the API requires it
    //         // final product = _products.firstWhere((p) => p.mealId == mealId, orElse: null);
    //         // if (product == null) return null;
    //         return {"meal_id": mealId, "quantity": quantity};
    //     })
    //     .whereType<Map<String, dynamic>>() // Filter out nulls if product check is added
    //     .toList();
    // --- End logic ---
   }


  @override
  Widget build(BuildContext context) {
    super.build(context); // Keep state

    return Scaffold(
      body: FutureBuilder<List<MealProduct>>(
        future: _productsFuture, // Future driving the builder
        builder: (context, snapshot) {
           final connectionState = snapshot.connectionState;
           final bool isLoading = connectionState == ConnectionState.waiting;

           // Loading State
           if (isLoading && _products.isEmpty) {
             return _buildProductsShimmer();
           }
           // Error State
           else if (snapshot.hasError && _products.isEmpty) {
             return _buildErrorState(snapshot.error ?? 'Unknown error loading menu.');
           }
           // Empty State
           else if (_products.isEmpty && !isLoading) {
             return _buildEmptyState('No menu items found. Add your first meal!');
           }
           // Success/Loaded State
           else {
             // Display the product list using loaded _products data
             return _buildProductList(_products);
           }
        },
      ),
      // Floating Action Button: Always show "Add Meal" but trigger "Coming Soon"
      floatingActionButton: FloatingActionButton.extended(
              onPressed: _handleAddProduct, // Triggers "Coming Soon" snackbar
              tooltip: 'Add New Meal (Coming Soon)',
              icon: const Icon(Icons.add_rounded),
              label: const Text("Add Meal"),
            ),
      // --- Old FAB logic (Commented out as selection/stock update is disabled) ---
      // floatingActionButton: _selectedProductIds.isEmpty
      //     ? FloatingActionButton.extended( /* Add Meal FAB */ )
      //     : FloatingActionButton.extended( /* Add to Stock FAB */ ),
    );
  }

   // Helper widget to build the product list view part
  Widget _buildProductList(List<MealProduct> productsToShow) {
     return RefreshIndicator(
       onRefresh: () async => _loadProducts(), // Reload on pull-to-refresh
       color: Theme.of(context).colorScheme.primary,
       child: ListView.builder(
         padding: const EdgeInsets.only(top: 8.0, bottom: 90.0), // Padding for FAB
         physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable
         itemCount: productsToShow.length,
         itemBuilder: (context, index) {
           final product = productsToShow[index];
           // final bool isSelected = _selectedProductIds.contains(product.mealId); // Use if selection enabled

           // Pass the "Coming Soon" handlers to the card
           return _buildProductCard(
              context,
              product,
              onEdit: () => _handleEditProduct(product), // "Coming Soon" handler
              onSelectToggle: () => _handleToggleSelection(product), // "Coming Soon" handler
              onDelete: () => _handleDeleteProduct(product), // "Coming Soon" handler
              isSelected: false, // Always show as not selected since feature is disabled
            );
         },
       ),
     );
   }

   // --- Helper methods (Snackbars, Shimmer, Empty/Error States) - Reuse from other tabs or original ---
    void _showErrorSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, duration: const Duration(seconds: 4), )); }
    void _showSuccessSnackbar(String message) { if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Colors.green.shade600, )); }
    void _showLoadingSnackbar(String message) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Row(children: [const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(whiteColor)), const SizedBox(width: 16), Text(message)]), duration: const Duration(minutes: 1), // Show until dismissed
        backgroundColor: Colors.black87, ));
    }
    void _dismissLoadingSnackbar() {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    // Shimmer for Products List
    Widget _buildProductsShimmer() {
        final shimmerBase = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade300 : Colors.grey.shade700;
        final shimmerHighlight = Theme.of(context).brightness == Brightness.light ? Colors.grey.shade100 : Colors.grey.shade500;
        return Shimmer.fromColors( baseColor: shimmerBase, highlightColor: shimmerHighlight,
          child: ListView.builder( padding: const EdgeInsets.only(top: 8.0, bottom: 90.0), itemCount: 4, // Show 4 shimmer items
            physics: const NeverScrollableScrollPhysics(), // Disable scroll
            itemBuilder: (_, __) => Card( margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Padding( padding: const EdgeInsets.all(12.0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Shimmer Image Placeholder
                    Container(width: 90, height: 90, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(8))),
                    const SizedBox(width: 16),
                    // Shimmer Text Placeholders
                    Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(width: double.infinity, height: 18, color: whiteColor, margin: const EdgeInsets.only(bottom: 6)),
                          Container(width: double.infinity, height: 14, color: whiteColor, margin: const EdgeInsets.only(bottom: 6)),
                          Container(width: MediaQuery.of(context).size.width * 0.25, height: 14, color: whiteColor, margin: const EdgeInsets.only(bottom: 8)),
                          Container(width: MediaQuery.of(context).size.width * 0.2, height: 18, color: whiteColor),
                        ])),
                    const SizedBox(width: 8),
                    // Shimmer Action Button Placeholders
                    Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(18))),
                      const SizedBox(height: 8),
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(18))),
                       const SizedBox(height: 8),
                        Container(width: 36, height: 36, decoration: BoxDecoration(color: whiteColor, borderRadius: BorderRadius.circular(18))),
                    ])
                  ]),
                )),
          ),
        );
    }
    // Error State for Products Tab
    Widget _buildErrorState(Object error) {
        return Center( child: Padding( padding: const EdgeInsets.all(24.0),
          child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.restaurant_menu_outlined, color: Theme.of(context).colorScheme.error, size: 50), // Menu icon for context
              const SizedBox(height: 16),
              Text( 'Error Loading Menu', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center, ),
              const SizedBox(height: 8),
              Text( error.toString(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, ),
              const SizedBox(height: 24),
              ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Retry'), onPressed: _loadProducts, ) // Retry calls _loadProducts
            ],
          ),
        ));
    }
    // Empty State for Products Tab
    Widget _buildEmptyState(String message) {
        return Center( child: Padding( padding: const EdgeInsets.all(24.0),
          child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.menu_book_rounded, size: 60, color: Colors.grey[400]), // Menu book icon
              const SizedBox(height: 16),
              Text( message, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center, ),
              const SizedBox(height: 10),
              // Add hint about the FAB being "Coming Soon"
              Text( "Use the '+' button below to add one (Coming Soon).", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]), textAlign: TextAlign.center, ),
               const SizedBox(height: 24),
               ElevatedButton.icon( icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh'), onPressed: _loadProducts, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.grey[700],) ) // Refresh calls _loadProducts
            ],
          ),
        ));
    }


  // --- Product Card (MODIFIED to use "Coming Soon" handlers and forced unselected state) ---
  Widget _buildProductCard(BuildContext context, MealProduct product, {
    required VoidCallback onEdit,
    required VoidCallback onSelectToggle,
    required VoidCallback onDelete,
    required bool isSelected, // Parameter kept, but value forced to false below
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    // Use appropriate currency formatting (e.g., UGX for Uganda Shilling)
    final formatCurrency = NumberFormat.currency( locale: 'en_UG', symbol: 'UGX ', decimalDigits: 0); // Adjust symbol/locale as needed
    // final bool displayAsSelected = false; // Force visual state to unselected

    return Card(
      clipBehavior: Clip.antiAlias,
      // --- Selection Visuals (Commented Out) ---
      // color: displayAsSelected ? colorScheme.primary.withOpacity(0.05) : null,
      // shape: displayAsSelected ? RoundedRectangleBorder(
      //   side: BorderSide(color: colorScheme.primary, width: 1.5),
      //   borderRadius: BorderRadius.circular(12),
      // ) : null,
      // --- End Selection Visuals ---
      child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Product Image
              SizedBox( width: 90, height: 90,
                child: CachedImageWithShimmer( // Use the reusable image widget
                    imageUrl: product.imageLink,
                    width: 90, height: 90,
                    borderRadius: 8.0, fit: BoxFit.cover,
                    errorIcon: Icons.restaurant_menu_outlined, // Placeholder icon
                    iconSize: 35, errorText: "No Image",
                 ),
              ),
              const SizedBox(width: 16),
              // Product Details (Name, Description, Price)
              Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text( product.mealName.isEmpty ? '(No Name)' : product.mealName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis, ),
                    const SizedBox(height: 5),
                    Text( product.mealDescription ?? 'No description.', style: textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis, ),
                    const SizedBox(height: 8),
                    Text( formatCurrency.format(product.price), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary), ),
                  ], ), ),
              const SizedBox(width: 8),
              // Action Buttons Column (Edit, Select, Delete)
              Column( mainAxisAlignment: MainAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  // Edit Button (Commented Out)
                  // _buildActionButton( context, icon: Icons.edit_outlined, tooltip: 'Edit Meal (Coming Soon)', color: colorScheme.secondary, onPressed: onEdit, ), // Calls _handleEditProduct
                  // const SizedBox(height: 8), // Commented out spacing
                  // Select/Deselect Button (Visually disabled, triggers Coming Soon)
                  _buildActionButton( context,
                    // Use unchecked icon always as selection is disabled
                    icon: Icons.radio_button_unchecked_rounded,
                    // icon: displayAsSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, // Use if selection enabled
                    tooltip: 'Select for Stock (Coming Soon)',
                    // Greyed out color as it's disabled
                    color: Colors.grey.shade400,
                    // color: displayAsSelected ? colorScheme.primary : Colors.grey.shade400, // Use if selection enabled
                    onPressed: onSelectToggle, // Calls _handleToggleSelection
                  ),
                   const SizedBox(height: 8),
                   // Delete Button (Commented Out)
                   // _buildActionButton( context, icon: Icons.delete_outline_rounded, tooltip: 'Delete Meal (Coming Soon)', color: colorScheme.error.withOpacity(0.7), onPressed: onDelete, ), // Calls _handleDeleteProduct
                ],
              )
            ],
          ),
        ),
    );
  }

  // Helper for consistent action buttons (Edit, Select, Delete)
  Widget _buildActionButton(BuildContext context, {required IconData icon, required String tooltip, required Color color, required VoidCallback onPressed}) {
    // Use SizedBox to constrain the button size for consistent layout
    return SizedBox( height: 36, width: 36,
      child: IconButton(
          icon: Icon(icon, size: 20), // Icon for the button
          color: color, // Color of the icon
          tooltip: tooltip, // Tooltip shown on hover/long press
          onPressed: onPressed, // Callback function when pressed
          visualDensity: VisualDensity.compact, // Reduce padding around the icon
          padding: EdgeInsets.zero, // Remove default padding
          splashRadius: 22, // Control the splash effect radius
      ),
    );
  }

} // End of _ProductsTabState