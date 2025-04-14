import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:intl/intl.dart';
import 'dart:convert'; // For jsonDecode, jsonEncode
import 'package:http/http.dart' as http; // Import the http package
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import flutter_dotenv
import 'package:cached_network_image/cached_network_image.dart'; // <<< IMPORT
import 'package:shimmer/shimmer.dart'; // <<< IMPORT

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
    'https://your-api.example.com'; // Provide a fallback

// --- Data Models (ChefProfile, Order, MealProduct) ---
class ChefProfile {
  final int chefid;
  final String name;
  final String? bio;
  final String? image; // URL
  final String? availability; // Comma-separated String
  final String? certifications; // Comma-separated String
  final String chefType;
  final int? experience; // Allow null
  final String? languages; // Comma-separated String
  final String? location;
  final String? minNotice;
  final String? price;
  final String? responseTime;
  final String? sampleMenu; // Comma-separated String URLs
  final String? specialties; // Comma-separated String
  final String? teamSize; // Allow null
  bool isActive; // Mutable for toggle example
  final String? equipment; // Comma-separated String

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
  });

  // --- Robust Factory Constructor ---
  factory ChefProfile.fromMockJson(Map<String, dynamic> json) {
    String? _joinListSafe(dynamic listData) {
      if (listData is List) {
        // Ensure all elements are strings before joining
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

    // Helper to check if a string is a valid HTTP/HTTPS URL
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
      // Return null if image is not a valid URL
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
      // Keep sampleMenu as a string, parsing happens in the UI
      sampleMenu: _getStringSafe(json['samplemenu']),
      specialties: _joinListSafe(json['specialties']),
      teamSize: _getStringSafe(json['teamsize']),
      // Ensure boolean parsing is safe
      isActive: json['is_active'] is bool
          ? json['is_active']
          : (json['is_active'] == 'true' || json['is_active'] == 1),
      equipment: _joinListSafe(json['equipment']),
    );
  }
}

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
  });

  // --- Robust Factory Constructor ---
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
    );
  }
}

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

  // --- Robust Factory Constructor ---
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

    // Use PascalCase keys for new API structure
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

// --- API Service (ApiService) ---

class ApiService {
  // NOTE: Ensure dotenv is loaded in main() before using ApiService
  static String apibaseurl = '';
  ApiService() {
    apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
        'https://your-api.example.com'; // Provide a fallback
  }

  // --- Get Chef ID from SharedPreferences ---
  static Future<String?> _getChefId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      // **IMPORTANT**: Ensure 'chef_user_id' is the correct key
      return prefs.getString('chef_user_id');
    } catch (e) {
      print("Error accessing SharedPreferences: $e");
      return null;
    }
  }

  // Add/update chef's stock (structure matches producer dashboard, but uses meal_id)
  // Add/update chef's stock (now uses chefId in path and PATCH)
  Future<bool> updateChefStock(String payload) async {
    final chefId = await _getChefId(); // Get the chef ID
    if (chefId == null || chefId.isEmpty) {
      print("Error: Chef ID not found for updateChefStock.");
      return false;
    }
    // **VERIFY**: Endpoint structure /rr/chefs/{chefId}/stock
    final url = '$apibaseurl/rr/chefs/$chefId/stock'; // <<< Corrected endpoint
    print("Updating stock for chef $chefId at: $url");

    try {
      final response = await http.patch(
        // <<< Changed to PATCH
        Uri.parse(url),
        headers:
            _getWriteHeaders(), // Use helper for headers (includes Content-Type)
        body: payload,
      );
      // Allow 200 (OK) or 204 (No Content) for successful updates
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating chef stock for $chefId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating chef stock: $e");
      return false;
    }
  }

  // --- Handle Dynamic API Response ---
  static dynamic _handleApiResponse(dynamic responseData) {
    if (responseData is List) {
      return responseData; // Already a list
    } else if (responseData is Map && responseData.containsKey('data')) {
      if (responseData['data'] is List) {
        return responseData['data']; // Extract list from 'data' key
      } else {
        print("API Warning: Response has 'data' key but value is not a List.");
        return responseData['data']; // Return single object under 'data'
      }
    } else if (responseData is Map && responseData.containsKey('All_Meals')) {
      // Handle specific structure for fetchProducts
      if (responseData['All_Meals'] is List) {
        return responseData['All_Meals'];
      } else {
        print(
            "API Warning: Response has 'All_Meals' key but value is not a List.");
        return null;
      }
    } else if (responseData is Map) {
      // Assume it's the single object itself (e.g., profile)
      return responseData;
    }
    print(
        "API Warning: Unhandled response format. Expected List or Map (potentially with 'data' or 'All_Meals' key). Got: ${responseData.runtimeType}");
    return null;
  }

  // --- Fetch Chef Profile ---
  Future<ChefProfile> fetchChefProfile() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }

    // **VERIFY**: Use the exact endpoint and parameter name
    final Uri uri = Uri.parse('$apibaseurl/rr/rchefs?chef_id=$chefId');
    print("Fetching profile from: $uri");

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        if (handledData == null) {
          throw Exception(
              'Failed to parse profile: Unexpected API response format after handling.');
        }

        Map<String, dynamic> profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          // If API returns a list for a single profile, take the first item
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception(
                'Failed to parse profile: Expected a map inside the list.');
          }
        } else if (handledData is Map<String, dynamic>) {
          profileMap = handledData;
        } else {
          throw Exception(
              'Failed to parse profile: Result is not a usable Map or List.');
        }

        return ChefProfile.fromMockJson(
            profileMap); // Use the robust model parser
      } else {
        print(
            "Error fetching profile: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load chef profile (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching profile: $e");
      // Rethrow specific exception types if needed, otherwise wrap
      if (e is Exception) rethrow;
      throw Exception('Failed to load chef profile: $e');
    }
  }

  // --- Fetch Orders for the Chef ---
  Future<List<Order>> fetchOrders() async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      throw Exception('Chef ID not found. Please log in again.');
    }

    // **VERIFY**: Use the exact endpoint and parameter name
    // Note: The previous code used 'chefid=' here, but 'chef_id=' for profile. Verify consistency.
    final Uri uri = Uri.parse(
        '$apibaseurl/rr/orders?chefid=$chefId'); // Using 'chefid' as in original
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
                  return Order.fromMockJson(jsonItem); // Use robust parser
                } else {
                  print(
                      "API Warning: Skipping non-map item in orders list: $jsonItem");
                  return null;
                }
              })
              .whereType<Order>() // Filter out nulls
              .toList();
        } else {
          print(
              "Orders API response format unexpected: Expected a List after handling. Got: ${ordersList?.runtimeType}");
          // If the API might sometimes return an empty object instead of list:
          if (ordersList == null || (ordersList is Map && ordersList.isEmpty)) {
            return []; // Return empty list
          }
          throw Exception(
              'Failed to parse orders: Unexpected API response format');
        }
      } else {
        print("Error fetching orders: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load orders (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching orders: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load orders: $e');
    }
  }

  // --- Fetch Products/Meals for the Chef ---
  static Future<List<MealProduct>> fetchProducts() async {
    final Uri uri = Uri.parse('$apibaseurl/rr/meals');
    print("Fetching products/menu from: $uri");

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        // Expect structure like {"data": [...]}
        List<dynamic>? menuList;
        if (rawData is Map<String, dynamic> && rawData.containsKey('data')) {
          menuList = rawData['data'];
        } else if (rawData is List) {
          menuList = rawData;
        } else {
          menuList = _handleApiResponse(rawData);
        }

        if (menuList is List) {
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
              "Products API response format unexpected: Expected a List after handling 'data'. Got: ${menuList?.runtimeType}");
          if (menuList == null || (menuList is Map && (menuList?.isEmpty ?? true))) {
            return [];
          }
          throw Exception(
              'Failed to parse products: Unexpected API response format');
        }
      } else {
        print(
            "Error fetching products: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load products (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching products: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load products: $e');
    }
  }

  // --- Helper Function for Write Headers (Add Auth if needed) ---
  static Map<String, String> _getWriteHeaders({bool requiresAuth = true}) {
    // TODO: Implement logic to get the auth token if required
    String? authToken = null; // Replace with actual token retrieval

    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (requiresAuth && authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  // --- Update Chef's Active Status ---
  static Future<bool> updateProfileStatus(int chefId, bool isActive) async {
    // **VERIFY**: Endpoint and method (PATCH/PUT?)
    final Uri uri =
        Uri.parse('$apibaseurl/rr/chefs/$chefId/status'); // Assuming PATCH

    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(<String, bool>{
          // **VERIFY**: Key name expected by API ('is_active', 'status', etc.)
          'is_active': isActive,
        }),
      );

      // Allow 200 (OK) or 204 (No Content) as success
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

  // --- Update Order Status ---
  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    // **VERIFY**: Endpoint and method (PATCH/PUT?)
    final Uri uri =
        Uri.parse('$apibaseurl/rr/orders/$orderId/status'); // Assuming PATCH

    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(<String, String>{
          // **VERIFY**: Key name expected by API ('order_status', 'status', etc.)
          'order_status': newStatus,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating order status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating order status: $e");
      return false;
    }
  }

  // --- Add a New Product/Meal ---
  static Future<MealProduct?> addProduct(
      Map<String, dynamic> productData) async {
    // **VERIFY**: Endpoint (POST?), does it need chefId? Original didn't use it here.
    final chefId =
        await _getChefId(); // Get chefId anyway, might be needed for auth/data
    if (chefId == null || chefId.isEmpty) {
      print(
          "Warning: Chef ID not found, but proceeding to add product endpoint.");
      // Proceed if API doesn't require chef_id in URL/body and relies on auth
    }
    // Example endpoint, adjust as needed. Original used /rr/chefs/$chefId/menu?
    // Let's try the general meals endpoint assuming POST creates one for the authenticated chef.
    final Uri uri = Uri.parse('$apibaseurl/rr/meals'); // <<< ADJUST if needed

    try {
      // Clean data
      productData.removeWhere((key, value) =>
          value == null ||
          (value is String && value.isEmpty)); // Remove null and empty strings
      // Safely parse price just before sending
      if (productData.containsKey('price') && productData['price'] is String) {
        productData['price'] = double.tryParse(productData['price']) ?? 0.0;
      } else if (!productData.containsKey('price')) {
        productData['price'] = 0.0; // Default price if missing
      }
      // **VERIFY**: Keys in productData match API spec

      print("Adding product with data: ${jsonEncode(productData)}");

      final response = await http.post(
        uri,
        headers: _getWriteHeaders(), // Assumes auth might be needed
        body: jsonEncode(productData),
      );

      if (response.statusCode == 201) {
        // HTTP 201 Created
        final Map<String, dynamic>? jsonData = json.decode(response.body);
        if (jsonData != null) {
          // Check if response contains the created object directly or nested
          final Map<String, dynamic>? createdProductData =
              _handleApiResponse(jsonData) as Map<String, dynamic>?;
          if (createdProductData != null) {
            return MealProduct.fromMockJson(createdProductData);
          } else {
            print(
                "Error adding product: Could not parse created product data from response.");
            return null; // Or handle differently if API returns only ID/success message
          }
        } else {
          print("Error adding product: Empty response body on success.");
          return null; // Or indicate success without object
        }
      } else {
        print("Error adding product: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Exception adding product: $e");
      return null;
    }
  }

  // --- Update an Existing Product/Meal ---
  static Future<bool> updateProduct(
      String mealId, Map<String, dynamic> productData) async {
    if (mealId.isEmpty || mealId.toLowerCase() == 'n/a_id') {
      print("Error updating product: Invalid Meal ID provided.");
      return false;
    }
    // **VERIFY**: Endpoint (PUT/PATCH?) and structure /rr/menu/{mealId}?
    // Assuming API uses /rr/meals/{mealId} for consistency
    final Uri uri =
        Uri.parse('$apibaseurl/rr/meals/$mealId'); // <<< ADJUST if needed

    try {
      productData.removeWhere((key, value) =>
          value == null); // Keep empty strings if they mean "clear field"
      // Safely parse price
      if (productData.containsKey('price') && productData['price'] is String) {
        productData['price'] = double.tryParse(productData['price']) ?? 0.0;
      }
      // **VERIFY**: Keys match API spec. Ensure all required fields for PUT are present.

      print("Updating product $mealId with data: ${jsonEncode(productData)}");

      // Using PUT - assumes replacing the entire resource
      final response = await http.put(
        // Or http.patch if API supports partial updates
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode(productData),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating product $mealId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating product $mealId: $e");
      return false;
    }
  }

  // --- Delete a Product/Meal ---
  static Future<bool> deleteProduct(String mealId) async {
    if (mealId.isEmpty || mealId.toLowerCase() == 'n/a_id') {
      print("Error deleting product: Invalid Meal ID provided.");
      return false;
    }
    // **VERIFY**: Endpoint (DELETE?) /rr/menu/{mealId}?
    // Assuming API uses /rr/meals/{mealId} for consistency
    final Uri uri =
        Uri.parse('$apibaseurl/rr/meals/$mealId'); // <<< ADJUST if needed

    try {
      final response = await http.delete(
        uri,
        headers: _getWriteHeaders(), // May need auth
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        // OK or No Content
        return true;
      } else {
        print(
            "Error deleting product $mealId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception deleting product $mealId: $e");
      return false;
    }
  }

  // --- Add selected meals to chef's stock ---
  static Future<bool> addMealsToChefStock(List<String> mealIds) async {
    final chefId = await _getChefId();
    if (chefId == null || chefId.isEmpty) {
      print("Error: Chef ID not found for addMealsToChefStock.");
      return false;
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/chefs?chef_id=$chefId');
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(),
        body: jsonEncode({
          "add_to_stock": mealIds,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error adding meals to stock: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception in addMealsToChefStock: $e");
      return false;
    }
  }
}

// +++ REUSABLE IMAGE WIDGET +++
class CachedImageWithShimmer extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;
  final double iconSize;
  final String? errorText; // Optional text for error state

  const CachedImageWithShimmer({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
    this.errorIcon = Icons.image_not_supported_outlined, // Default error icon
    this.iconSize = 35,
    this.errorText,
  });

  // Google Drive Link Conversion Helper
  String? _getDirectImageLink(String? url) {
    if (url == null ||
        url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      // print("Invalid initial URL: $url");
      return null;
    }
    if (url.contains('drive.google.com')) {
      try {
        Uri uri = Uri.parse(url);
        String? fileId;

        // Format: /file/d/FILE_ID/...
        if (uri.pathSegments.contains('d')) {
          int idIndex = uri.pathSegments.indexOf('d');
          if (idIndex >= 0 && idIndex + 1 < uri.pathSegments.length) {
            fileId = uri.pathSegments[idIndex + 1];
          }
        }
        // Format: ?id=FILE_ID or open?id=FILE_ID
        else if (uri.queryParameters.containsKey('id')) {
          fileId = uri.queryParameters['id'];
        }

        if (fileId != null && fileId.isNotEmpty && !fileId.contains('/')) {
          // Remove potential extra query params sometimes included in share links
          fileId = fileId.split('&').first;
          // print("Extracted GDrive ID: $fileId from URL: $url");
          return 'https://drive.google.com/uc?export=view&id=$fileId';
        } else {
          // print("Could not extract valid File ID from GDrive URL: $url (segments: ${uri.pathSegments}, query: ${uri.queryParameters})");
        }
      } catch (e) {
        print("Error parsing GDrive URL: $url - $e");
      }
      return null; // Failed to parse GDrive link or extract ID
    }
    // print("Using non-GDrive URL: $url");
    return url; // Not a GDrive link
  }

  @override
  Widget build(BuildContext context) {
    final String? processedUrl = _getDirectImageLink(imageUrl);
    // Use theme background/surface colors for shimmer for better theme adherence
    final shimmerBase = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade300
        : Colors.grey.shade700;
    final shimmerHighlight = Theme.of(context).brightness == Brightness.light
        ? Colors.grey.shade100
        : Colors.grey.shade500;

    if (processedUrl == null || processedUrl.isEmpty) {
      // If URL is invalid after processing, show error state immediately
      return _buildErrorWidget(context, shimmerBase, shimmerHighlight);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
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
                    // Use cardColor or a theme-appropriate background
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
              ),
          errorWidget: (context, url, error) {
            print(
                "CachedNetworkImage Error: Failed to load $url - $error"); // Log image loading errors
            return _buildErrorWidget(context, shimmerBase, shimmerHighlight);
          }),
    );
  }

  // Helper to build the error widget consistently
  Widget _buildErrorWidget(
      BuildContext context, Color baseColor, Color highlightColor) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor
            .withOpacity(0.2), // Less opaque background for error state
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        // Use Column for icon + text
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
                errorText!,
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
// +++ END REUSABLE IMAGE WIDGET +++

// --- Main Application Widget ---
class ChefDash88new extends StatelessWidget {
  const ChefDash88new({super.key});

  @override
  Widget build(BuildContext context) {
    // Define core colors
    const Color primaryTeal = Color(0xFF00796B);
    const Color lightTeal = Color(0xFFB2DFDB);
    const Color lighterTeal = Color(0xFFE0F2F1);
    const Color darkTeal = Color(0xFF004D40);
    const Color accentTeal = Color(0xFF009688);
    const Color whiteColor = Colors.white;
    const Color lightBackgroundColor = Color(0xFFF5F5F5);
    const Color cardBackgroundColor = whiteColor;
    const Color primaryTextColor = darkTeal;
    const Color secondaryTextColor = Color(0xFF455A64);
    const Color subtleTextColor = Color(0xFF757575);
    const Color iconColor = primaryTeal;
    const Color dividerColor = lightTeal;

    return MaterialApp(
      title: 'Chef Dashboard',
      theme: ThemeData(
          // --- Color Scheme ---
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryTeal,
            primary: primaryTeal,
            secondary: accentTeal,
            background: lightBackgroundColor,
            surface: cardBackgroundColor,
            onPrimary: whiteColor,
            onSecondary: whiteColor,
            onBackground: primaryTextColor,
            onSurface: primaryTextColor,
            error: Colors.redAccent[700]!,
            onError: whiteColor,
            brightness: Brightness.light,
          ),
          // --- Component Themes ---
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
            color: cardBackgroundColor,
          ),
          chipTheme: ChipThemeData(
            backgroundColor: lighterTeal,
            labelStyle:
                TextStyle(color: primaryTextColor, fontWeight: FontWeight.w500),
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            side: BorderSide.none,
            elevation: 0,
          ),
          listTileTheme: ListTileThemeData(
            iconColor: iconColor,
            titleTextStyle: TextStyle(
              fontWeight: FontWeight.w500,
              color: primaryTextColor,
              fontSize: 16,
            ),
            subtitleTextStyle: TextStyle(
              color: secondaryTextColor,
              fontSize: 13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          textTheme: TextTheme(
            headlineSmall: TextStyle(
                fontWeight: FontWeight.bold,
                color: darkTeal,
                fontSize: 22,
                letterSpacing: 0.2),
            titleLarge: TextStyle(
                fontWeight: FontWeight.w600, color: darkTeal, fontSize: 18),
            titleMedium: TextStyle(
                fontWeight: FontWeight.w600,
                color: primaryTextColor,
                fontSize: 16),
            titleSmall: TextStyle(
                fontWeight: FontWeight.w500,
                color: primaryTextColor,
                fontSize: 14),
            bodyLarge:
                TextStyle(color: primaryTextColor, fontSize: 16, height: 1.4),
            bodyMedium:
                TextStyle(color: secondaryTextColor, fontSize: 14, height: 1.4),
            bodySmall:
                TextStyle(color: subtleTextColor, fontSize: 12, height: 1.3),
            labelLarge: TextStyle(
              color: whiteColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.8,
            ),
            labelMedium: TextStyle(
              color: primaryTeal,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
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
            fillColor: Colors.teal.shade50.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: lightTeal, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: primaryTeal, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            labelStyle:
                TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
            floatingLabelStyle:
                TextStyle(color: primaryTeal, fontWeight: FontWeight.w600),
            hintStyle: TextStyle(color: subtleTextColor),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                elevation: 2,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.5)),
          ),
          dividerTheme: DividerThemeData(
            color: dividerColor,
            thickness: 0.8,
            space: 24,
          ),
          iconTheme: const IconThemeData(
            color: iconColor,
            size: 22,
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: primaryTeal,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 4,
          )),
      home: const ChefDashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Main Dashboard Screen (with Tabs) ---
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chef Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline_rounded), text: 'Profile'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ProfileTab(),
          OrdersTab(),
          ProductsTab(),
        ],
      ),
    );
  }
}

// --- Profile Tab Widget ---
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin {
  Future<ChefProfile>? _profileFuture;
  bool _isLoadingStatus = false;
  ChefProfile? _currentProfile;

  bool _didLoadProfile = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadProfile) {
      _didLoadProfile = true;
      _loadProfile();
    }
  }

  void _loadProfile() {
    // Clear previous error messages immediately
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _currentProfile = null; // Clear current profile while loading
      final apiService = ApiService();
      _profileFuture = apiService.fetchChefProfile();
    });
    _profileFuture!.then((profile) {
      if (mounted) setState(() => _currentProfile = profile);
    }).catchError((error, stackTrace) {
      print("Error in _loadProfile: $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading profile: $error');
        setState(
            () => _currentProfile = null); // Ensure profile is null on error
      }
    });
  }

  Future<void> _toggleActiveStatus(bool newValue) async {
    if (_currentProfile == null) return;
    // Dismiss previous snackbars
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _isLoadingStatus = true);
    final originalStatus = _currentProfile!.isActive;
    // Optimistic UI update
    setState(() => _currentProfile!.isActive = newValue);

    try {
      bool success = await ApiService.updateProfileStatus(
          _currentProfile!.chefid, newValue);
      if (mounted) {
        if (!success) {
          setState(() => _currentProfile!.isActive = originalStatus); // Revert
          _showErrorSnackbar('Failed to update status. Please try again.');
        } else {
          _showSuccessSnackbar('Status updated successfully.');
        }
      }
    } catch (e) {
      print("Error in _toggleActiveStatus: $e");
      if (mounted) {
        setState(() =>
            _currentProfile!.isActive = originalStatus); // Revert on exception
        _showErrorSnackbar('An error occurred while updating status.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  void _showErrorSnackbar(String message) {
    // Ensure we're not showing multiple error bars
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.onError)),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 4), // Show longer
    ));
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.green.shade600,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChefProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        // Handle loading state explicitly
        if (snapshot.connectionState == ConnectionState.waiting ||
            (_currentProfile == null &&
                !snapshot.hasError &&
                !snapshot.hasData)) {
          // Show shimmer placeholders while loading profile data
          return _buildProfileShimmer();
        }
        // Handle error state
        else if (snapshot.hasError) {
          return _buildErrorState(snapshot.error ?? 'Unknown error');
        }
        // Handle success state (data is available and _currentProfile is set)
        else if (snapshot.hasData && _currentProfile != null) {
          final profile = _currentProfile!;
          return RefreshIndicator(
            onRefresh: () async => _loadProfile(),
            color: Theme.of(context).colorScheme.primary,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              physics:
                  const AlwaysScrollableScrollPhysics(), // Ensure refresh works even if content fits screen
              children: [
                _buildProfileHeader(context, profile),
                const SizedBox(height: 20),
                _buildActiveStatusToggle(context, profile),
                const SizedBox(height: 20),
                _buildProfileDetailsCard(context, profile),
                const SizedBox(height: 20),
              ],
            ),
          );
        }
        // Fallback / Empty state (should be rare if loading/error handled)
        else {
          return _buildEmptyState('No profile data found.');
        }
      },
    );
  }

  // --- Shimmer Placeholder for Profile ---
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
        children: [
          // Shimmer Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(45),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: MediaQuery.of(context).size.width * 0.5,
                        height: 24,
                        color: Colors.white),
                    const SizedBox(height: 8),
                    Container(
                        width: MediaQuery.of(context).size.width * 0.3,
                        height: 18,
                        color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Shimmer Toggle
          Container(
            width: double.infinity,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 20),
          // Shimmer Details Card
          Container(
            width: double.infinity,
            height: 400,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    // Use previously defined _buildErrorState, maybe add specific icon
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.error, size: 50),
          const SizedBox(height: 16),
          Text(
            'Error Loading Profile',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadProfile,
          )
        ],
      ),
    ));
  }

  Widget _buildEmptyState(String message) {
    // Use previously defined _buildEmptyState
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded, color: Colors.grey[400], size: 60),
          const SizedBox(height: 16),
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Reload'),
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.grey[700],
              ))
        ],
      ),
    ));
  }

  // --- Profile Header with Cached Image ---
  Widget _buildProfileHeader(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Use CachedImageWithShimmer
        SizedBox(
          width: 90,
          height: 90,
          child: CachedImageWithShimmer(
            imageUrl: profile.image,
            width: 90,
            height: 90,
            borderRadius: 45, // Circular
            fit: BoxFit.cover,
            errorIcon: Icons.person_rounded,
            iconSize: 45,
            errorText: "No Pic",
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(profile.name, style: textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(profile.chefType,
                  style: textTheme.titleMedium
                      ?.copyWith(color: colorScheme.secondary)),
              // TODO: Add Rating display if available
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveStatusToggle(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        title: Text('Profile Active', style: textTheme.titleMedium),
        subtitle: Text(
            profile.isActive
                ? 'Visible to customers'
                : 'Not visible to customers',
            style: textTheme.bodySmall),
        value: profile.isActive,
        onChanged: _isLoadingStatus ? null : _toggleActiveStatus,
        secondary: _isLoadingStatus
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(
                profile.isActive
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: profile.isActive
                    ? Colors.green.shade600
                    : Colors.orange.shade700,
                size: 28,
              ),
        activeColor: colorScheme.primary,
        inactiveThumbColor: Colors.grey.shade400,
        inactiveTrackColor: Colors.grey.shade200,
      ),
    );
  }

  // --- Profile Details Card with Sample Menu Gallery ---
  Widget _buildProfileDetailsCard(BuildContext context, ChefProfile profile) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
              child: Text('Chef Details', style: textTheme.titleLarge),
            ),
            const Divider(),
            _buildInfoListTile(
                context, Icons.info_outline_rounded, 'Bio', profile.bio,
                isExpandable: true),
            _buildInfoListTile(context, Icons.star_outline_rounded,
                'Specialties', profile.specialties),

            // --- SAMPLE MENU GALLERY ---
            if (profile.sampleMenu != null && profile.sampleMenu!.isNotEmpty)
              _buildSampleMenuGallery(context, profile.sampleMenu!),
            // --- If no sample menu, optionally show placeholder text ---
            // else
            //   _buildInfoListTile(context, Icons.menu_book_rounded, 'Sample Menu', 'Not provided'),
            // --- END SAMPLE MENU ---

            _buildInfoListTile(
                context,
                Icons.timer_outlined,
                'Experience',
                profile.experience != null
                    ? '${profile.experience} years'
                    : null),
            _buildInfoListTile(
                context,
                Icons.attach_money_rounded,
                'Est. Price',
                profile.price != null ? '\$${profile.price}' : null),
            _buildInfoListTile(context, Icons.schedule_rounded, 'Min. Notice',
                profile.minNotice),
            _buildInfoListTile(context, Icons.access_time_rounded,
                'Response Time', profile.responseTime),
            _buildInfoListTile(context, Icons.language_rounded, 'Languages',
                profile.languages),
            _buildInfoListTile(context, Icons.build_circle_outlined,
                'Equipment', profile.equipment),
            _buildInfoListTile(context, Icons.calendar_today_rounded,
                'Availability', profile.availability),
            _buildInfoListTile(context, Icons.verified_user_outlined,
                'Certifications', profile.certifications),
            _buildInfoListTile(context, Icons.location_on_outlined, 'Location',
                profile.location),
            _buildInfoListTile(context, Icons.group_outlined, 'Team Size',
                profile.teamSize ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  // --- Horizontal Sample Menu Gallery Widget ---
  Widget _buildSampleMenuGallery(BuildContext context, String sampleMenuUrls) {
    final List<String> urls = sampleMenuUrls
        .split(',') // Split by comma
        .map((url) => url.trim()) // Remove leading/trailing whitespace
        .where((url) =>
            url.isNotEmpty &&
            (url.startsWith('http://') ||
                url.startsWith('https://'))) // Basic URL validation
        .toList();

    if (urls.isEmpty) {
      // Optionally show a message if the string existed but had no valid URLs
      // return _buildInfoListTile(context, Icons.menu_book_rounded, 'Sample Menu', 'No valid image URLs provided');
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    const double galleryHeight = 110.0; // Adjust height as needed
    const double imageSize = 90.0; // Size of each image (width & height)

    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 12.0), // Add vertical spacing like other list tiles
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title, aligned like ListTile titles
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(
              // Use Row to include icon
              children: [
                Icon(Icons.menu_book_rounded,
                    size: 24, color: Theme.of(context).listTileTheme.iconColor),
                const SizedBox(
                    width: 16), // Match ListTile leading padding roughly
                Text("Sample Menu",
                    style: textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // The horizontal list
          SizedBox(
            height: galleryHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              // Add horizontal padding to the ListView itself for start/end spacing
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              itemBuilder: (context, index) {
                return Padding(
                  // Padding between items
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: SizedBox(
                    // Constrain image size
                    width: imageSize,
                    height: imageSize,
                    child: CachedImageWithShimmer(
                      // Use reusable widget
                      imageUrl: urls[index], // Pass the parsed URL
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.cover,
                      borderRadius: 8.0,
                      errorIcon: Icons.no_food_outlined, // Specific error icon
                      iconSize: 30,
                      errorText: "Menu Item", // Optional text
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

  // --- Standard Info ListTile (modified to handle null value gracefully) ---
  Widget _buildInfoListTile(
      BuildContext context, IconData icon, String label, String? value,
      {bool isExpandable = false}) {
    // If value is null or empty, show "Not provided" or similar, instead of hiding
    final displayValue = (value == null || value.isEmpty || value == 'N/A')
        ? 'Not provided'
        : value;
    final bool hasRealValue = displayValue != 'Not provided';

    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      leading: Icon(icon,
          size: 24, color: Theme.of(context).listTileTheme.iconColor),
      title: Text(label,
          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        displayValue,
        // Make "Not provided" text greyed out
        style: textTheme.bodyMedium?.copyWith(
            height: 1.4,
            color:
                hasRealValue ? textTheme.bodyMedium?.color : Colors.grey[500]),
        // Only allow expansion if there's real value and isExpandable is true
        maxLines: (isExpandable && hasRealValue) ? null : 3,
        overflow: (isExpandable && hasRealValue)
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      onTap: (isExpandable && hasRealValue)
          ? () {
              showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        title: Text(label),
                        content: SingleChildScrollView(
                            child: Text(value!,
                                style: textTheme
                                    .bodyMedium)), // Use value! as we know it's not null here
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Close'))
                        ],
                      ));
            }
          : null,
      // Only show trailing icon if expandable and has real value
      trailing: (isExpandable && hasRealValue)
          ? Icon(Icons.open_in_full_rounded, size: 18, color: Colors.grey[400])
          : null,
    );
  }
}

// --- Orders Tab Widget ---
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<Order>>? _ordersFuture;
  List<Order> _orders = [];
  String _selectedFilter = 'All';

  bool _didLoadOrders = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadOrders) {
      _didLoadOrders = true;
      _loadOrders();
    }
  }

  void _loadOrders() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _orders = []; // Clear orders while loading
      final apiService = ApiService();
      _ordersFuture = apiService.fetchOrders();
    });
    _ordersFuture!.then((orders) {
      if (mounted) {
        setState(() {
          _orders = orders;
          _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
        });
      }
    }).catchError((error, stackTrace) {
      print("Error in _loadOrders (OrdersTab): $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading orders: $error');
        setState(() => _orders = []); // Ensure list is empty on error
      }
    });
  }

  Future<void> _updateOrderStatus(Order order, String newStatus) async {
    int orderIndex = _orders.indexWhere((o) => o.orderId == order.orderId);
    if (orderIndex == -1) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final originalStatus = _orders[orderIndex].orderStatus;
    // Optimistic update
    setState(() => _orders[orderIndex].orderStatus = newStatus);

    try {
      bool success =
          await ApiService.updateOrderStatus(order.orderId, newStatus);
      if (!success && mounted) {
        setState(
            () => _orders[orderIndex].orderStatus = originalStatus); // Revert
        _showErrorSnackbar('Failed to update order ${order.orderId} status.');
      } else if (success && mounted) {
        _showSuccessSnackbar(
            'Order ${order.orderId} status updated to $newStatus.');
        _showOrderNextStepDialog(newStatus); // Call the guidance dialog
        // Consider only local update or selective reload based on filter
        // For simplicity, full reload ensures consistency
        // _loadOrders(); // Uncomment if full reload is desired after update
      }
    } catch (e) {
      print("Error in _updateOrderStatus: $e");
      if (mounted) {
        setState(() => _orders[orderIndex].orderStatus =
            originalStatus); // Revert on exception
        _showErrorSnackbar('An error occurred while updating order status.');
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.onError)),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.green.shade600,
    ));
  }

  // --- Copied from Producer Dash: Show Guidance Dialog ---
  void _showOrderNextStepDialog(String newStatus) {
    String message;
    String title;
    IconData icon;
    // Use theme colors
    final primaryColor = Theme.of(context).colorScheme.primary;

    switch (newStatus) {
      // Adjust cases based on Chef workflow if different from Producer
      case 'Accepted': // Assuming Chef accepts directly
        title = "Order Accepted";
        message =
            "You have accepted the order. Next, start preparing the meal when ready.";
        icon = Icons.check_circle_outline;
        break;
      case 'Preparing':
        title = "Order Preparing";
        message =
            "You are now preparing the order. Mark as dispatched when ready for delivery.";
        icon = Icons.restaurant_menu_outlined;
        break;
      case 'Shipped': // Assuming Chef marks as shipped/ready for pickup
      case 'Out for Delivery': // Handle both possibilities
        title = "Order Ready/Shipped";
        message =
            "Order is ready for pickup or on its way! Await delivery confirmation.";
        icon = Icons.local_shipping_outlined;
        break;
      case 'Delivered': // Or 'Completed'
      case 'Completed':
        title = "Order Completed";
        message = "Order has been completed/delivered.";
        icon = Icons.done_all;
        break;
      case 'Cancelled': // Or 'Rejected'
      case 'Rejected':
        title = "Order Cancelled/Rejected";
        message = "Order has been cancelled or rejected.";
        icon = Icons.cancel_outlined;
        break;
      default:
        title = "Order Updated";
        message = "Order status updated to $newStatus.";
        icon = Icons.info_outline;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(icon, color: primaryColor),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // --- End Copied Dialog ---
  List<Order> _getFilteredOrders() {
    if (_selectedFilter == 'All') return _orders;
    return _orders
        .where((order) =>
            order.orderStatus.toLowerCase() == _selectedFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Order>>(
      future: _ordersFuture,
      builder: (context, snapshot) {
        Widget body;
        // Loading State
        if (snapshot.connectionState == ConnectionState.waiting ||
            (_orders.isEmpty && !snapshot.hasError && !snapshot.hasData)) {
          // Show Shimmer for Orders List
          body = _buildOrdersShimmer();
        }
        // Error State
        else if (snapshot.hasError) {
          body = _buildErrorState(snapshot.error ?? 'Unknown error');
        }
        // Success State (even if _orders is empty after filtering)
        else {
          final filteredOrders = _getFilteredOrders();
          if (_orders.isEmpty) {
            body = _buildEmptyState(
                'You have no orders yet.'); // Message if initial load finds none
          } else if (filteredOrders.isEmpty) {
            body = _buildEmptyState(
                'No orders match the filter "$_selectedFilter".'); // Message if filter finds none
          } else {
            body = RefreshIndicator(
              onRefresh: () async => _loadOrders(),
              color: Theme.of(context).colorScheme.primary,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8.0, bottom: 80.0),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filteredOrders.length,
                itemBuilder: (context, index) {
                  final order = filteredOrders[index];
                  return _buildOrderCard(context, order);
                },
              ),
            );
          }
        }

        // Structure with Filter Chips + Body
        return Column(
          children: [
            // Only show filter chips if there are orders loaded initially
            if (_orders.isNotEmpty ||
                snapshot.connectionState == ConnectionState.waiting)
              _buildFilterChips(),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  // --- Shimmer Placeholder for Orders List ---
  Widget _buildOrdersShimmer() {
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
        itemCount: 5, // Show a few shimmer cards
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          height: 18,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.4,
                          height: 14,
                          color: Colors.white),
                    ])),
                const SizedBox(width: 16),
                Container(
                    width: 80,
                    height: 25,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15))),
              ]),
            )),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error, size: 50),
          const SizedBox(height: 16),
          Text(
            'Error Loading Orders',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadOrders,
          )
        ],
      ),
    ));
  }

  Widget _buildEmptyState(String message) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Optional: Add a refresh button even when empty, depending on UX preference
          // ElevatedButton.icon(icon: const Icon(Icons.refresh_rounded, size: 20), label: const Text('Refresh'), onPressed: _loadOrders, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.grey[700],))
        ],
      ),
    ));
  }

  Widget _buildFilterChips() {
    final statuses = [
      'All',
      'Pending',
      'Preparing',
      'Shipped',
      'Delivered',
      'Cancelled'
    ];
    // Use shimmer for chips if orders are still loading
    if (_ordersFuture == null ||
        (_orders.isEmpty && !(ModalRoute.of(context)?.isCurrent ?? false))) {
      // Check if current route before accessing ModalRoute
      final shimmerBase = Theme.of(context).brightness == Brightness.light
          ? Colors.grey.shade300
          : Colors.grey.shade700;
      final shimmerHighlight = Theme.of(context).brightness == Brightness.light
          ? Colors.grey.shade100
          : Colors.grey.shade500;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
        child: Shimmer.fromColors(
          baseColor: shimmerBase,
          highlightColor: shimmerHighlight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
                spacing: 8.0,
                children: List.generate(
                    5,
                    (_) => Container(
                        width: 80,
                        height: 32,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20))))),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
              selectedColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.2),
              backgroundColor: Theme.of(context).chipTheme.backgroundColor,
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).chipTheme.labelStyle?.color,
              ),
              side: isSelected
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary, width: 1)
                  : Theme.of(context).chipTheme.side,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Order order) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a',
        Localizations.localeOf(context).toString());
    final statusColor = _getStatusColor(order.orderStatus);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<int>(order.orderId),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.15),
          child: Icon(_getStatusIcon(order.orderStatus),
              color: statusColor, size: 22),
        ),
        title: Text(
          order.mealName,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5.0),
          child: Text(
            '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
            style: textTheme.bodySmall,
          ),
        ),
        trailing: Chip(
          label: Text(order.orderStatus),
          backgroundColor: statusColor.withOpacity(0.15),
          labelStyle: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
        ),
        iconColor: colorScheme.primary,
        collapsedIconColor: Colors.grey[500],
        backgroundColor: colorScheme.surface,
        collapsedBackgroundColor: colorScheme.surface,
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
                .copyWith(top: 0),
        children: [
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          _buildDetailRow(context, Icons.person_outline_rounded, 'Customer ID',
              order.userId?.toString() ?? 'N/A'),
          _buildDetailRow(context, Icons.storefront_outlined, 'Producer',
              order.producerName),
          _buildDetailRow(context, Icons.shopping_bag_outlined, 'Quantity',
              order.quantity.toString()),
          _buildDetailRow(context, Icons.payment_rounded, 'Payment',
              '${order.paymentStatus} (\$${order.totalPrice})'),
          _buildDetailRow(context, Icons.location_on_outlined, 'Delivery To',
              order.deliveryAddress),
          _buildDetailRow(context, Icons.restaurant_outlined,
              'Ingredients Req.', order.ingredients),
          _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
          const SizedBox(height: 16),
          if (order.orderStatus.toLowerCase() == 'pending' ||
              order.orderStatus.toLowerCase() == 'preparing')
            _buildActionButtons(context, order),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Order order) {
    final currentStatus = order.orderStatus.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (currentStatus == 'pending') ...[
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Accept'),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.green.shade700),
              onPressed: () => _updateOrderStatus(order, 'Preparing'),
            ),
            const SizedBox(width: 8),
          ],
          if (currentStatus == 'preparing') ...[
            TextButton.icon(
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('Mark Shipped'),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.blue.shade700),
              onPressed: () => _updateOrderStatus(order, 'Shipped'),
            ),
            const SizedBox(width: 8),
          ],
          TextButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Reject'),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            onPressed: () => _showRejectConfirmation(context, order),
          ),
        ],
      ),
    );
  }

  void _showRejectConfirmation(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Confirm Rejection"),
          content: Text("Reject Order #${order.orderId} (${order.mealName})?"),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text("Reject Order",
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _updateOrderStatus(order, 'Cancelled');
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.shade600;
      case 'preparing':
        return Colors.blue.shade600;
      case 'shipped':
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
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_bottom_rounded;
      case 'preparing':
        return Icons.soup_kitchen_rounded;
      case 'shipped':
      case 'out for delivery':
        return Icons.local_shipping_rounded;
      case 'delivered':
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

// --- Products Tab Widget (Menu) ---
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab>
    with AutomaticKeepAliveClientMixin {
  Future<List<MealProduct>>? _productsFuture;
  List<MealProduct> _products = [];
  Set<String> _selectedProductIds = {}; // Track selected products for stock
  Map<String, int> _mealQuantities =
      {}; // Track quantities for each selected meal (mealId -> quantity)
  String? _editingProductId; // Track which product is being edited (by mealId)

  // Producer-style stock getter for chefs (uses meal_id)
  List<Map<String, dynamic>> get _selectedMealStock {
    final selectedMeals =
        _products.where((p) => _selectedProductIds.contains(p.mealId)).toList();
    return selectedMeals
        .where((p) =>
            p.mealId.isNotEmpty &&
            p.mealName.isNotEmpty &&
            p.mealName.trim().isNotEmpty)
        .toList()
        .map((p) => {
              "meal_id": p.mealId,
              "Name": p.mealName.trim(),
              "quantity": _mealQuantities[p.mealId] ?? 0,
            })
        .toList();
  }

  // Producer-style stock update for chefs
  Future<void> _updateChefStock() async {
    final stockList = _selectedMealStock;
    if (stockList.isEmpty) {
      _showErrorSnackbar(
          "Please select at least one valid meal to update stock.");
      return;
    }
    _showLoadingSnackbar("Updating stock...");
    final payload = jsonEncode({"stock": stockList});
    bool success = false;
    final apiService = ApiService();
    try {
      // You may need to update this endpoint to match your backend
      final response = await apiService.updateChefStock(payload);
      success = response;
    } catch (e) {
      print("Error updating chef stock: $e");
      success = false;
    }
    _dismissLoadingSnackbar();
    if (success) {
      setState(() {
        _selectedProductIds.clear();
        _mealQuantities.clear();
      });
      _showSuccessSnackbar("Selected meals added to stock!");
    } else {
      _showErrorSnackbar("Failed to add meals to stock. Please try again.");
    }
  }

  // (Old _selectedMealStock removed, now using the new version above)

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
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      _products = []; // Clear products while loading
      _productsFuture = ApiService.fetchProducts();
    });
    _productsFuture!.then((products) {
      if (mounted) {
        setState(() {
          _products = products;
          _products.sort((a, b) => a.mealName.compareTo(b.mealName));
        });
      }
    }).catchError((error, stackTrace) {
      print("Error in _loadProducts (ProductsTab): $error\n$stackTrace");
      if (mounted) {
        _showErrorSnackbar('Error loading menu items: $error');
        setState(() => _products = []); // Ensure list is empty on error
      }
    });
  }

  // Robust add logic: create a temporary product, add to list, enter edit mode
  void _handleAddProduct() {
    if (_editingProductId != null) return; // Prevent multiple edits at once
    final newId = 'TEMP_${DateTime.now().millisecondsSinceEpoch}';
    final newProduct = MealProduct(
      mealId: newId,
      mealName: '',
      mealDescription: '',
      imageLink: '',
      price: 0.0,
      ingredients: '',
      prepTime: '',
      skillLevel: '',
      mealCategory: '',
      complementaryDishes: '',
      dietaryPreference: '',
      allergies: '',
    );
    setState(() {
      _products.insert(0, newProduct); // Add to top for visibility
      _editingProductId = newId;
    });
    _showProductDialog(
      productToEdit: newProduct,
      onDialogClose: (MealProduct? savedProduct) {
        setState(() {
          if (savedProduct != null) {
            // Replace temp with real product if saved
            final idx = _products.indexWhere((p) => p.mealId == newId);
            if (idx != -1) _products[idx] = savedProduct;
          } else {
            // Remove temp if cancelled
            _products.removeWhere((p) => p.mealId == newId);
          }
          _editingProductId = null;
        });
      },
    );
  }

  void _showEditProductDialog(MealProduct product) {
    _showProductDialog(productToEdit: product);
  }

  void _showProductDialog({
    MealProduct? productToEdit,
    void Function(MealProduct? savedProduct)? onDialogClose,
  }) {
    final bool isEditing = productToEdit != null;
    final formKey = GlobalKey<FormState>();
    final nameController =
        TextEditingController(text: productToEdit?.mealName ?? '');
    final descriptionController =
        TextEditingController(text: productToEdit?.mealDescription ?? '');
    final priceController = TextEditingController(
        text: productToEdit != null
            ? productToEdit.price.toStringAsFixed(2)
            : '');
    final ingredientsController =
        TextEditingController(text: productToEdit?.ingredients ?? '');
    final imageLinkController = TextEditingController(
        text: productToEdit?.imageLink ?? ''); // Added for image link
    bool dialogClosed = false; // Prevent double-calling onDialogClose

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final textTheme = Theme.of(context).textTheme;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(isEditing ? "Edit Meal" : "Add New Meal",
              style: textTheme.titleLarge),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Meal Name*'),
                    style: textTheme.bodyLarge,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Meal name is required'
                        : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    decoration:
                        const InputDecoration(labelText: 'Description*'),
                    style: textTheme.bodyMedium,
                    maxLines: 3,
                    minLines: 1,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Description is required'
                        : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price*',
                      prefixText: '\$ ',
                    ),
                    style: textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Price is required';
                      if (double.tryParse(value) == null)
                        return 'Invalid number format';
                      if (double.parse(value) < 0)
                        return 'Price cannot be negative';
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ingredientsController,
                    decoration: const InputDecoration(
                        labelText: 'Ingredients',
                        hintText: 'e.g., Flour, Sugar, Eggs'),
                    style: textTheme.bodyMedium,
                    textInputAction: TextInputAction.next,
                  ), // Changed to next
                  const SizedBox(height: 12),
                  // Added Image Link Field
                  TextFormField(
                    controller: imageLinkController,
                    decoration: const InputDecoration(
                        labelText: 'Image URL (Optional)',
                        hintText: 'https://... or Google Drive link'),
                    style: textTheme.bodyMedium,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                if (!dialogClosed && onDialogClose != null) {
                  dialogClosed = true;
                  onDialogClose(null); // Cancelled
                }
                if (!dialogClosed && onDialogClose != null) {
                  dialogClosed = true;
                  // If adding, pass the new MealProduct; if editing, pass null (list is already updated)
                  if (!isEditing) {
                    final savedProduct = MealProduct(
                      mealId: productToEdit?.mealId ?? '',
                      mealName: nameController.text,
                      mealDescription: descriptionController.text,
                      imageLink: imageLinkController.text,
                      price: double.tryParse(priceController.text) ?? 0.0,
                      ingredients: ingredientsController.text,
                      prepTime: '',
                      skillLevel: '',
                      mealCategory: '',
                      complementaryDishes: '',
                      dietaryPreference: '',
                      allergies: '',
                    );
                    onDialogClose(savedProduct);
                  } else {
                    onDialogClose(null);
                  }
                }
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text(isEditing ? "Save Changes" : "Add Meal"),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final productData = {
                    'name': nameController.text,
                    'description': descriptionController.text,
                    'price': priceController.text,
                    'ingredients': ingredientsController.text.isNotEmpty
                        ? ingredientsController.text
                        : null,
                    // Include image_link if provided
                    'image_link': imageLinkController.text.isNotEmpty
                        ? imageLinkController.text
                        : null,
                  };
                  Navigator.of(context).pop();
                  _showLoadingSnackbar(
                      isEditing ? 'Saving changes...' : 'Adding meal...');
                  try {
                    if (isEditing) {
                      bool success = await ApiService.updateProduct(
                          productToEdit!.mealId, productData);
                      _dismissLoadingSnackbar();
                      if (success && mounted) {
                        _showSuccessSnackbar('${nameController.text} updated!');
                        _loadProducts();
                      } else if (mounted) {
                        _showErrorSnackbar(
                            'Failed to update ${nameController.text}.');
                      }
                    } else {
                      MealProduct? addedProduct =
                          await ApiService.addProduct(productData);
                      _dismissLoadingSnackbar();
                      if (addedProduct != null && mounted) {
                        _showSuccessSnackbar('${addedProduct.mealName} added!');
                        _loadProducts();
                      } else if (mounted) {
                        _showErrorSnackbar('Failed to add meal.');
                      }
                    }
                  } catch (e) {
                    print("Error during product add/update: $e");
                    _dismissLoadingSnackbar();
                    if (mounted) {
                      _showErrorSnackbar('An error occurred.');
                    }
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteProduct(MealProduct product) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Confirm Deletion"),
          content: Text("Delete '${product.mealName}'? This cannot be undone."),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text("Delete",
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                _showLoadingSnackbar('Deleting ${product.mealName}...');
                try {
                  bool success = await ApiService.deleteProduct(product.mealId);
                  _dismissLoadingSnackbar();
                  if (success && mounted) {
                    _showSuccessSnackbar('${product.mealName} deleted.');
                    setState(() => _products
                        .removeWhere((p) => p.mealId == product.mealId));
                  } else if (mounted) {
                    _showErrorSnackbar('Failed to delete ${product.mealName}.');
                  }
                } catch (e) {
                  print("Error during product delete: $e");
                  _dismissLoadingSnackbar();
                  if (mounted) {
                    _showErrorSnackbar('An error occurred while deleting.');
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Add to Stock FAB (shows only if at least one product is selected)
  Widget _buildAddToStockFAB() {
    if (_selectedProductIds.isEmpty) return SizedBox.shrink();
    return FloatingActionButton.extended(
      onPressed: _handleAddToStock,
      icon: Icon(Icons.add_shopping_cart),
      label: Text("Add to Stock"),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
    );
  }

  // Handler for Add to Stock action
  void _handleAddToStock() async {
    final selectedProducts =
        _products.where((p) => _selectedProductIds.contains(p.mealId)).toList();
    final stockList = _selectedMealStock;
    if (stockList.isEmpty) {
      _showErrorSnackbar(
          "Please select at least one valid meal to update stock.");
      return;
    }
    _showLoadingSnackbar("Adding selected meals to stock...");
    final payload = jsonEncode({"stock": stockList});
    bool success = false;
    final apiService = ApiService();
    try {
      // You may need to update this endpoint to match your backend
      final response = await apiService.updateChefStock(payload);
      success = response;
    } catch (e) {
      print("Error updating chef stock: $e");
      success = false;
    }
    _dismissLoadingSnackbar();
    if (success) {
      setState(() {
        _selectedProductIds.clear();
      });
      _showSuccessSnackbar("Selected meals added to stock!");
    } else {
      _showErrorSnackbar("Failed to add meals to stock. Please try again.");
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.onError)),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.green.shade600,
    ));
  }

  void _showLoadingSnackbar(String message) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 16),
          Text(message)
        ],
      ),
      duration: const Duration(seconds: 60),
    ));
  }

  void _dismissLoadingSnackbar() {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<MealProduct>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          // Loading State
          if (snapshot.connectionState == ConnectionState.waiting ||
              (_products.isEmpty && !snapshot.hasError && !snapshot.hasData)) {
            return _buildProductsShimmer(); // Show shimmer list
          }
          // Error State
          else if (snapshot.hasError) {
            return _buildErrorState(snapshot.error ?? 'Unknown error');
          }
          // Empty State (after loading)
          else if (_products.isEmpty) {
            // Check _products directly after future completes
            return _buildEmptyState(
                'No menu items found. Add your first meal!');
          }
          // Success State
          else {
            return RefreshIndicator(
              onRefresh: () async => _loadProducts(),
              color: Theme.of(context).colorScheme.primary,
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8.0, bottom: 90.0),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return _buildProductCard(context, product);
                },
              ),
            );
          }
        },
      ),
      floatingActionButton: _selectedProductIds.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _handleAddProduct,
              tooltip: 'Add New Meal',
              icon: const Icon(Icons.add_rounded),
              label: const Text("Add Meal"),
            )
          : _buildAddToStockFAB(),
    );
  }

  // --- Shimmer Placeholder for Products List ---
  Widget _buildProductsShimmer() {
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
        itemCount: 4, // Show a few shimmer cards
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                          width: double.infinity,
                          height: 18,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: double.infinity,
                          height: 14,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 6)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.25,
                          height: 14,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 8)),
                      Container(
                          width: MediaQuery.of(context).size.width * 0.2,
                          height: 18,
                          color: Colors.white),
                    ])),
                const SizedBox(width: 8),
                Column(children: [
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18))),
                  const SizedBox(height: 8),
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18))),
                ])
              ]),
            )),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu_outlined,
              color: Theme.of(context).colorScheme.error,
              size: 50), // Changed Icon
          const SizedBox(height: 16),
          Text(
            'Error Loading Menu',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
            onPressed: _loadProducts,
          )
        ],
      ),
    ));
  }

  Widget _buildEmptyState(String message) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Text("Use the '+' button to add one.", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),),
        ],
      ),
    ));
  }

  // --- Product Card with Cached Image ---
  Widget _buildProductCard(BuildContext context, MealProduct product) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final formatCurrency = NumberFormat.currency(
        locale: Localizations.localeOf(context).toString(),
        symbol: '\$',
        decimalDigits: 2);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {/* TODO: Implement product detail view? */},
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Use CachedImageWithShimmer
              SizedBox(
                width: 90,
                height: 90,
                child: CachedImageWithShimmer(
                  imageUrl: product.imageLink,
                  width: 90,
                  height: 90,
                  borderRadius: 8.0,
                  fit: BoxFit.cover,
                  errorIcon: Icons.restaurant_menu_outlined, // Specific icon
                  iconSize: 35,
                  errorText: "No Image", // Text for error
                ),
              ),
              const SizedBox(width: 16),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.mealName,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      product.mealDescription ?? 'No description.',
                      style: textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatCurrency.format(product.price),
                      style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action Buttons
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit Meal',
                    color: colorScheme.secondary,
                    onPressed: () => _showEditProductDialog(product),
                  ),
                  const SizedBox(height: 8),
                  // Tick/untick button for selection
                  _buildActionButton(
                    context,
                    icon: _selectedProductIds.contains(product.mealId)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    tooltip: _selectedProductIds.contains(product.mealId)
                        ? 'Deselect'
                        : 'Select for Stock',
                    color: _selectedProductIds.contains(product.mealId)
                        ? colorScheme.primary
                        : colorScheme.secondary,
                    onPressed: () {
                      setState(() {
                        if (_selectedProductIds.contains(product.mealId)) {
                          _selectedProductIds.remove(product.mealId);
                        } else {
                          _selectedProductIds.add(product.mealId);
                        }
                      });
                    },
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // Helper for consistent action buttons on the card
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
      ),
    );
  }
} // End of _ProductsTabState
