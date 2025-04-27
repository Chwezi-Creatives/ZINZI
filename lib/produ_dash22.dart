import 'package:flutter/material.dart';
import 'package:zinzi2/app_drawer_unified.dart'; // Import the AppDrawer widget
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zinzi2/user_cache.dart'; // <<< IMPORT UserCache
import 'package:zinzi2/cache_config.dart'; // <<< IMPORT CacheConfig

// Inline Order class based on API data
class Order {
  final int orderId;
  final String mealName;
  final DateTime orderDate;
  final double totalPrice;
  final int quantity;
  final String orderStatus;
  final String? producerName; // Used as customer name in UI
  final String? deliveryAddress;
  final String? notes;
  final String? ingredients;
  final String? paymentStatus;

  Order({
    required this.orderId,
    required this.mealName,
    required this.orderDate,
    required this.totalPrice,
    required this.quantity,
    required this.orderStatus,
    this.producerName,
    this.deliveryAddress,
    this.notes,
    this.ingredients,
    this.paymentStatus,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double parseDouble(dynamic value) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return Order(
      orderId: parseInt(json['order_id']),
      mealName: json['meal_name'] as String? ??
          'Unknown Meal', // Handle potential null
      orderDate: DateTime.parse(json['order_date'] as String),
      totalPrice: parseDouble(json['total_price']),
      quantity: parseInt(json['quantity']),
      orderStatus: json['order_status'] as String,
      producerName: json['producer_name'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      notes: json['notes'] as String?,
      ingredients: json['ingredients'] as String?,
      paymentStatus: json['payment_status'] as String?,
    );
  }

  Order copyWith({
    int? orderId,
    String? mealName,
    DateTime? orderDate,
    double? totalPrice,
    int? quantity,
    String? orderStatus,
    String? producerName,
    String? deliveryAddress,
    String? notes,
    String? ingredients,
    String? paymentStatus,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      mealName: mealName ?? this.mealName,
      orderDate: orderDate ?? this.orderDate,
      totalPrice: totalPrice ?? this.totalPrice,
      quantity: quantity ?? this.quantity,
      orderStatus: orderStatus ?? this.orderStatus,
      producerName: producerName ?? this.producerName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      notes: notes ?? this.notes,
      ingredients: ingredients ?? this.ingredients,
      paymentStatus: paymentStatus ?? this.paymentStatus,
    );
  }

  static const String STATUS_PENDING = 'Pending';
  static const String STATUS_ACCEPTED = 'Accepted';
  static const String STATUS_PREPARING = 'Preparing';
  static const String STATUS_DISPATCHED = 'Dispatched';
  static const String STATUS_DELIVERED = 'Delivered';
  static const String STATUS_CANCELLED = 'Cancelled';
}

// Inline ProducerProfile class based on API data
class ProducerProfile {
  final int producerId;
  final String name;
  final String? email;
  final String? phoneNumber;
  final String? location;
  final String? image;
  final bool isActive;
  final DateTime registrationDate;
  final DateTime? lastLogin;
  final String? producerType;
  final double? rating;
  final String? reviews;
  final List<Map<String, dynamic>>? stock; // New field for stock

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
    this.stock,
  });

  factory ProducerProfile.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    List<Map<String, dynamic>>? parseStock(dynamic value) {
      if (value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) {
            return decoded.whereType<Map<String, dynamic>>().toList();
          }
        } catch (_) {}
      } else if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
      return null;
    }

    return ProducerProfile(
      producerId: parseInt(json['producer_id']),
      name: json['name'] as String,
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      location: json['location'] as String?,
      image: json['image'] as String?,
      isActive: json['is_active'] as bool,
      registrationDate: DateTime.parse(json['registration_date'] as String),
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'] as String)
          : null,
      producerType: json['producer_type'] as String?,
      rating: parseDouble(json['rating']),
      reviews: json['reviews'] as String?,
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
    DateTime? lastLogin,
    String? producerType,
    double? rating,
    String? reviews,
    List<Map<String, dynamic>>? stock, // Added stock to copyWith
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
      lastLogin: lastLogin ?? this.lastLogin,
      producerType: producerType ?? this.producerType,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
      stock: stock ?? this.stock, // Added stock to copyWith
    );
  }
}

// Inline Product class based on API data
class Product {
  final String produceId;
  final String produceName;
  final int? calories;
  final double? carbohydrates;
  final double? fats;
  final double? proteins;
  final int? unitGrams;
  final String? source;

  Product({
    required this.produceId,
    required this.produceName,
    this.calories,
    this.carbohydrates,
    this.fats,
    this.proteins,
    this.unitGrams,
    this.source,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return Product(
      produceId: json['produce_id'] as String,
      produceName:
          json['produce_name'] as String? ?? '', // Ensure name is not null
      calories: parseInt(json['calories']),
      carbohydrates: json['carbohydrates'] != null
          ? (json['carbohydrates'] as num).toDouble()
          : null,
      fats: json['fats'] != null ? (json['fats'] as num).toDouble() : null,
      proteins: json['proteins'] != null
          ? (json['proteins'] as num).toDouble()
          : null,
      unitGrams: parseInt(json['unit_grams']),
      source: json['source'] as String?,
    );
  }

  Product copyWith({
    String? produceId,
    String? produceName,
    int? calories,
    double? carbohydrates,
    double? fats,
    double? proteins,
    int? unitGrams,
    String? source,
  }) {
    return Product(
      produceId: produceId ?? this.produceId,
      produceName: produceName ?? this.produceName,
      calories: calories ?? this.calories,
      carbohydrates: carbohydrates ?? this.carbohydrates,
      fats: fats ?? this.fats,
      proteins: proteins ?? this.proteins,
      unitGrams: unitGrams ?? this.unitGrams,
      source: source ?? this.source,
    );
  }
}

class ProducerApiService {
  static final String apibaseurl =
      dotenv.env['API_BASE_URL-intranet'] ?? 'https://your-api.example.com';

  static Future<String?> _getProducerId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('producer_id');
    } catch (e) {
      print("Error accessing SharedPreferences for producer ID: $e");
      return null;
    }
  }

  static dynamic _handleApiResponse(dynamic responseData) {
    if (responseData is Map && responseData.containsKey('data')) {
      return responseData['data'];
    } else if (responseData is List) {
      return responseData;
    } else if (responseData is Map) {
      // If it's a map but no 'data' key, return the map itself (e.g., for single item responses)
      return responseData;
    }
    print(
        "API Warning: Unhandled response format. Expected List or Map (potentially with 'data' key). Got: ${responseData.runtimeType}");
    return null; // Return null or throw an exception based on required behavior
  }

  static Future<ProducerProfile> fetchProducerProfile() async {
    final producerId = await _getProducerId();
    if (producerId == null || producerId.isEmpty) {
      throw Exception('Producer ID not found. Please log in again.');
    }

    final Uri uri = Uri.parse('$apibaseurl/rr/rproducers/$producerId');
    print("Fetching producer profile from: $uri");

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        // Handle case where API might return a list with one item or the item directly
        Map<String, dynamic>? profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          profileMap = handledData[0] as Map<String, dynamic>;
        } else if (handledData is Map<String, dynamic>) {
          profileMap = handledData; // If API returns the object directly
        }

        if (profileMap == null) {
          throw Exception(
              'Failed to parse profile: Unexpected API response format or empty data.');
        }

        return ProducerProfile.fromJson(profileMap);
      } else {
        print(
            "Error fetching producer profile: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load producer profile (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching producer profile: $e");
      rethrow;
    }
  }

  static Future<List<Order>> fetchProducerOrders() async {
    final producerId = await _getProducerId();
    if (producerId == null || producerId.isEmpty) {
      throw Exception('Producer ID not found. Please log in again.');
    }

    final Uri uri = Uri.parse('$apibaseurl/rr/orders?producer_id=$producerId');
    print("Fetching producer orders from: $uri");

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic ordersList = _handleApiResponse(rawData);

        if (ordersList is List) {
          return ordersList
              .where((item) => item is Map<String, dynamic>)
              .map((item) => Order.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          print(
              "Orders API response format unexpected: Expected a List. Got: ${ordersList?.runtimeType}");
          return []; // Return empty list if format is wrong
        }
      } else {
        print(
            "Error fetching producer orders: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load orders (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching producer orders: $e");
      rethrow;
    }
  }

  static Future<List<Product>> fetchProducerProduce() async {
    final producerId = await _getProducerId();
    if (producerId == null || producerId.isEmpty) {
      throw Exception('Producer ID not found. Please log in again.');
    }

    // Assuming produce is general and not tied to a specific producer for listing
    final Uri uri = Uri.parse('$apibaseurl/rr/produce');
    print("Fetching all produce from: $uri");

    try {
      // Assuming GET for produce doesn't need authentication, adjust if needed
      final response = await http.get(uri, headers: _getReadHeaders());

      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic produceList = _handleApiResponse(rawData);

        if (produceList is List) {
          return produceList
              .where((item) => item is Map<String, dynamic>)
              .map((item) => Product.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          print(
              "Produce API response format unexpected: Expected a List. Got: ${produceList?.runtimeType}");
          return []; // Return empty list
        }
      } else {
        print(
            "Error fetching produce: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load produce (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("Exception fetching produce: $e");
      rethrow;
    }
  }

  static Map<String, String> _getReadHeaders() {
    // Basic headers for GET requests, adjust if auth is needed
    return {
      'Accept': 'application/json',
    };
  }

  static Map<String, String> _getWriteHeaders({bool requiresAuth = true}) {
    String? authToken = null; // TODO: Implement token retrieval if needed
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (requiresAuth && authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status');

    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
        body: jsonEncode({'order_status': newStatus}),
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

  static Future<bool> updateProducerStatus(
      int producerId, bool isActive) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/producers/$producerId/status');

    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
        body: jsonEncode({'is_active': isActive}),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating producer status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating producer status: $e");
      return false;
    }
  }

  static Future<bool> updateProducerProfile(int producerId,
      {required String name, String? phoneNumber, String? location}) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/producers/$producerId');

    Map<String, dynamic> payload = {
      'name': name,
      // Only include fields if they are not null AND not empty
      if (phoneNumber != null && phoneNumber.isNotEmpty)
        'phone_number': phoneNumber,
      if (location != null && location.isNotEmpty) 'location': location,
    };

    try {
      final response = await http.put(
        // Using PUT for full profile update
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating producer profile: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating producer profile: $e");
      return false;
    }
  }

  // --- Methods for Managing Individual Produce Items (Add, Update, Delete) ---

  static Future<Product?> addProduce(Map<String, dynamic> produceData) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/produce');

    try {
      // Prepare payload, ensuring correct types and removing nulls/empties
      final payload = {
        'produce_name': produceData['produce_name'] as String?, // Required
        'calories': int.tryParse(produceData['calories']?.toString() ?? ''),
        'proteins': double.tryParse(produceData['proteins']?.toString() ?? ''),
        'carbohydrates':
            double.tryParse(produceData['carbohydrates']?.toString() ?? ''),
        'fats': double.tryParse(produceData['fats']?.toString() ?? ''),
        'unit_grams': int.tryParse(produceData['unit_grams']?.toString() ?? ''),
        'source': produceData['source'] as String?,
      };
      // Remove null values before sending
      payload.removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty));

      // Validate required fields
      if (payload['produce_name'] == null ||
          (payload['produce_name'] as String).isEmpty) {
        print("Error adding produce: Produce name is required.");
        return null;
      }

      print("Adding produce with payload: ${jsonEncode(payload)}");

      final response = await http.post(
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        // Check for 201 Created
        final dynamic responseData = json.decode(response.body);
        final dynamic createdProduceData = _handleApiResponse(responseData);

        if (createdProduceData is Map<String, dynamic>) {
          return Product.fromJson(createdProduceData);
        } else {
          print(
              "Add produce succeeded but couldn't parse response body: ${response.body}");
          // Might need to fetch the item again if the response isn't the full object
          return null;
        }
      } else {
        print("Error adding produce: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Exception adding produce: $e");
      return null;
    }
  }

  static Future<bool> updateProduce(
      String produceId, Map<String, dynamic> produceData) async {
    if (produceId.isEmpty) {
      print("Error updating produce: Invalid Produce ID.");
      return false;
    }
    // Assuming the update endpoint uses the ID in the URL like /rr/produce/{produce_id}
    // Or potentially /rr/uproduce?produce_id=... as in the original - check API docs
    // Using the ?produce_id= format based on original code
    final Uri uri = Uri.parse('$apibaseurl/rr/uproduce?produce_id=$produceId');

    try {
      // Prepare payload similar to addProduce
      final payload = {
        'produce_name': produceData['produce_name'] as String?, // Required
        'calories': int.tryParse(produceData['calories']?.toString() ?? ''),
        'proteins': double.tryParse(produceData['proteins']?.toString() ?? ''),
        'carbohydrates':
            double.tryParse(produceData['carbohydrates']?.toString() ?? ''),
        'fats': double.tryParse(produceData['fats']?.toString() ?? ''),
        'unit_grams': int.tryParse(produceData['unit_grams']?.toString() ?? ''),
        'source': produceData['source'] as String?,
      };
      payload.removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty));

      // Validate required fields for update
      if (payload['produce_name'] == null ||
          (payload['produce_name'] as String).trim().isEmpty) {
        print("Error updating produce: Produce name cannot be empty.");
        return false;
      }

      print("Updating produce $produceId with payload: ${jsonEncode(payload)}");

      final response = await http.put(
        // Usually PUT for updates
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error updating produce $produceId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating produce $produceId: $e");
      return false;
    }
  }

  static Future<bool> deleteProduce(String produceId) async {
    if (produceId.isEmpty) {
      print("Error deleting produce: Invalid Produce ID.");
      return false;
    }
    // Assuming DELETE endpoint follows the same pattern as update
    final Uri uri = Uri.parse('$apibaseurl/rr/uproduce?produce_id=$produceId');

    try {
      final response = await http.delete(
        uri,
        headers: _getWriteHeaders(requiresAuth: true), // Assuming auth needed
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "Error deleting produce $produceId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception deleting produce $produceId: $e");
      return false;
    }
  }
}

class ProducerDash22 extends StatefulWidget {
  const ProducerDash22({Key? key}) : super(key: key);

  @override
  _ProducerDash22State createState() => _ProducerDash22State();
}

class _ProducerDash22State extends State<ProducerDash22> {
  // --- Caching for Producer Profile ---
  static ProducerProfile? _profileCache;
  static DateTime? _profileCacheTimestamp;
  static const String _profileCacheKey = 'producer_profile_cache';
  static const String _profileCacheTimestampKey =
      'producer_profile_cache_timestamp';

  // Load cache from UserCache
  static Future<void> _loadProfileCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_profileCacheKey);
    final timestampData = await UserCache.getData(_profileCacheTimestampKey);

    if (cachedData is Map<String, dynamic> && timestampData is String) {
      try {
        _profileCache = ProducerProfile.fromJson(
            cachedData); // Assuming fromJson works for cached data
        _profileCacheTimestamp = DateTime.parse(timestampData);
      } catch (e) {
        print("Error parsing cached producer profile: $e");
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
  static Future<void> _saveProfileCacheToPrefs(ProducerProfile profile) async {
    // Convert profile to a suitable Map for JSON encoding if needed
    // Assuming ProducerProfile has a toJson method or can be directly encoded
    // For simplicity, we'll cache the result of toJson() if available, or just the map from fromJson
    // Let's assume ProducerProfile.toJson() exists or we can use the map from fromJson
    // For now, we'll just save the map we got from the API fetch.
    // A dedicated toJson() method in ProducerProfile would be ideal.
    // For now, let's assume we can convert it back to a map.
    // If ProducerProfile.fromJson works, we might need a toJson() that produces compatible JSON
    // Let's assume we can use the original JSON map if we stored it, or create a new one.
    // For simplicity, let's assume we can convert the profile back to a map.
    // If ProducerProfile.toJson() exists, use it. Otherwise, manually create a map.
    // Assuming ProducerProfile has a toJson() method:
    // Map<String, dynamic> cacheableProfile = profile.toJson(); // Assuming toJson exists

    // If no toJson(), manually create a map (less ideal, might miss fields)
    Map<String, dynamic> cacheableProfile = {
      'producer_id': profile.producerId,
      'name': profile.name,
      'email': profile.email,
      'phone_number': profile.phoneNumber,
      'location': profile.location,
      'image': profile.image,
      'is_active': profile.isActive,
      'registration_date': profile.registrationDate.toIso8601String(),
      'last_login': profile.lastLogin?.toIso8601String(),
      'producer_type': profile.producerType,
      'rating': profile.rating,
      'reviews': profile.reviews,
      'stock': profile.stock, // Include stock in cache
    };

    await UserCache.saveData(_profileCacheKey, cacheableProfile);
    await UserCache.saveData(
        _profileCacheTimestampKey, DateTime.now().toIso8601String());
    _profileCache = profile; // Update in-memory cache
    _profileCacheTimestamp = DateTime.now();
  }
  // --- End Caching ---

  int _currentIndex = 0;
  ProducerProfile? _profile;
  List<Order> _orders = [];
  List<Product> _produce = []; // List of ALL available produce
  bool _isLoading = true; // General loading indicator
  bool _isLoadingProfile = true; // Specific loading for profile
  String _profileFetchError = ''; // Specific error for profile

  // Track selected produce for stock
  Set<String> _selectedProduceIds = {};
  // Track quantities for each selected produce (produceId -> quantity)
  Map<String, int> _produceQuantities = {}; // Use int, default to 0 later

  // --- START: Applied Fix ---

  // Ensure stock items have valid names and handle quantities
  List<Map<String, dynamic>> get _selectedProduceStock {
    final selectedProducts = _produce
        .where((p) => _selectedProduceIds.contains(p.produceId))
        .toList();
    return selectedProducts
        .where((p) =>
            p.produceId.isNotEmpty &&
            p.produceName.isNotEmpty &&
            p.produceName.trim().isNotEmpty)
        .toList()
        .map((p) => {
              "produce_id": p.produceId,
              "Name": p.produceName.trim(),
              "quantity": _produceQuantities[p.produceId] ?? 0,
            })
        .toList();
  }

  // State for image upload and location loading
  bool _isUploadingProfileImage = false;
  bool _isLoadingLocation = false;
  String? _uploadedProfileImageUrl;

  // Upload to Imgur (Ensure IMGUR_CLIENT_ID is in .env)
  Future<String> _uploadImageToImgur(File image) async {
    final imgurClientID = dotenv.env['IMGUR_CLIENT_ID'] ?? '';
    if (imgurClientID.isEmpty)
      throw Exception('Imgur Client ID not configured.');
    final uploadUrl = 'https://api.imgur.com/3/image';
    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = 'Client-ID $imgurClientID';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    final response = await request.send();
    final responseData = await http.Response.fromStream(response);
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(responseData.body);
      return jsonResponse['data']['link'];
    } else {
      print("Imgur Upload Error: ${responseData.body}");
      throw Exception(
          'Failed to upload image. Status Code: ${response.statusCode}');
    }
  }

  // Pick and upload profile image to Imgur
  Future<void> _pickAndUploadProfileImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _isUploadingProfileImage = true);
    try {
      final url = await _uploadImageToImgur(File(picked.path));
      setState(() {
        _uploadedProfileImageUrl = url;
        if (_profile != null) _profile = _profile!.copyWith(image: url);
      });
      _showSuccessSnackbar('Profile image updated!');
    } catch (e) {
      _showErrorSnackBar('Image upload failed: $e');
    } finally {
      setState(() => _isUploadingProfileImage = false);
    }
  }

  // Get current location and reverse geocode
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
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
          desiredAccuracy: LocationAccuracy.high);
      String displayAddress =
          "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      try {
        final apiUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http.get(Uri.parse(apiUrl));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        }
      } catch (e) {
        print("Reverse geocoding failed: $e");
      }
      setState(() {
        _profileLocationController.text = displayAddress;
      });
      _showSuccessSnackbar('Location Acquired!');
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _updateProducerStock() async {
    if (_profile == null) {
      _showErrorSnackBar('Profile not loaded. Cannot update stock.');
      return;
    }

    // Get the prepared list using the getter
    final stockList = _selectedProduceStock;

    // Check if any valid items were selected
    if (stockList.isEmpty) {
      _showErrorSnackBar(
          'Please select at least one valid produce item to update stock.');
      return;
    }

    // // Optional: Double-check validation (getter should handle this)
    // for (var item in stockList) {
    //   if (item['Name'] == null || item['Name'].trim().isEmpty) {
    //     _showErrorSnackBar('Error: An item with an invalid name was selected.');
    //     return;
    //   }
    //    if (item['quantity'] == null || item['quantity'] < 0) {
    //     _showErrorSnackBar('Error: An item has an invalid quantity.');
    //     return;
    //    }
    // }

    // Show loading indicator potentially
    _showLoadingSnackbar('Updating stock...');

    // Construct the payload the API expects (e.g., {"stock": [...]})
    final payload = jsonEncode({"stock": stockList});
    print("Updating stock with payload: $payload");

    try {
      final response = await http.patch(
        // Use PATCH as per original code
        Uri.parse(
            '${ProducerApiService.apibaseurl}/rr/producers/${_profile!.producerId}'),
        headers: {
          'Content-Type': 'application/json'
        }, // Add auth headers if needed
        body: payload,
      );

      _dismissLoadingSnackbar(); // Dismiss loading indicator

      if (response.statusCode == 200 || response.statusCode == 204) {
        // Check for 200 or 204 No Content
        _showSuccessSnackbar('Stock updated successfully.');

        // Refresh profile data to get the updated stock from the backend
        try {
          final updatedProfile =
              await ProducerApiService.fetchProducerProfile();
          if (mounted) {
            setState(() {
              _profile = updatedProfile;
              // Optionally re-sync UI selections based on updated profile stock if needed
              _syncSelectionFromProfile();
            });
          }
        } catch (e) {
          if (mounted) {
            _showErrorSnackBar(
                'Stock updated, but failed to refresh profile: $e');
          }
        }
      } else {
        // Try to parse error message from response body
        String errorMsg = 'Unknown error';
        try {
          final errorBody = jsonDecode(response.body);
          errorMsg =
              errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
          errorMsg = response.body; // Use raw body if JSON parsing fails
        }
        _showErrorSnackBar(
            'Failed to update stock (Code: ${response.statusCode}): $errorMsg');
        print("Stock update failed: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      _dismissLoadingSnackbar(); // Dismiss loading indicator
      if (mounted) {
        _showErrorSnackBar('Error connecting to server: $e');
      }
      print("Exception updating stock: $e");
    }
  }

  // --- END: Applied Fix ---

  String _error = '';
  bool _isEditingProfile = false;
  String? _editingProduceId; // For editing individual produce items, not stock
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  late TextEditingController _profileLocationController;

  // Controllers for the produce editing form (not stock management)
  TextEditingController? _produceNameController;
  TextEditingController? _produceCaloriesController;
  TextEditingController? _produceProteinsController;
  TextEditingController? _produceCarbsController;
  TextEditingController? _produceFatsController;
  TextEditingController? _produceUnitGramsController;
  TextEditingController? _produceSourceController;

  // --- UI Constants --- (Keep existing constants)
  static const Color primaryTeal = Color(0xFF009688);
  static const Color lightTeal = Color(0xFFB2DFDB);
  static const Color faintLightTeal = Color(0xFFE0F2F1);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color whiteColor = Colors.white;
  static const Color textOnTeal = Colors.white;
  static const Color textOnWhite = Color(0xFF212121);
  static const Color subtleText = Color(0xFF757575);
  static const Color cardBackground =
      Color(0xFFF1F8F8); // Slightly off-white teal tint
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color starColor = Color(0xFFFFC107); // Amber/Gold
  static const Color dividerColor = Color(0xFFE0E0E0);
  static final Color pendingColor = Colors.orange.shade600;
  static final Color acceptedColor = Colors.blue.shade600;
  static final Color preparingColor = Colors.deepPurple.shade400;
  static final Color dispatchedColor = primaryTeal;
  static final Color deliveredColor = Colors.green.shade600;
  static final Color cancelledColor = Colors.red.shade600;
  static final Color defaultStatusColor = Colors.grey.shade600;
  static const Color actionButtonBackground =
      Color(0xFFE0F2F1); // Faint light teal
  static const Color actionButtonForeground = darkTeal;
  static const Color destructiveButtonBackground =
      Color(0xFFFFEBEE); // Light red
  static const Color destructiveButtonForeground =
      Color(0xFFC62828); // Darker red
  static const String placeholderImagePath =
      'assets/images/placeholder_avatar.png'; // Ensure this asset exists

  // Form Keys
  final GlobalKey<FormState> _produceFormKey =
      GlobalKey<FormState>(); // For adding/editing produce item
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _profileNameController = TextEditingController();
    _profilePhoneController = TextEditingController();
    _profileLocationController = TextEditingController();
    // Initial data fetch is now in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch data only if it hasn't been loaded yet or if dependencies change
    // Added checks to prevent multiple fetches on rebuilds unless needed
    if (_isLoading && _profile == null && _orders.isEmpty && _produce.isEmpty) {
      _fetchAllData();
    }
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _profileLocationController.dispose();
    _disposeProduceEditControllers();
    super.dispose();
  }

  void _disposeProduceEditControllers() {
    _produceNameController?.dispose();
    _produceCaloriesController?.dispose();
    _produceProteinsController?.dispose();
    _produceCarbsController?.dispose();
    _produceFatsController?.dispose();
    _produceUnitGramsController?.dispose();
    _produceSourceController?.dispose();
    _produceNameController = null;
    _produceCaloriesController = null;
    _produceProteinsController = null;
    _produceCarbsController = null;
    _produceFatsController = null;
    _produceUnitGramsController = null;
    _produceSourceController = null;
  }

  // Combined cache load and background fetch for Producer Profile
  Future<void> _initializeProducerProfile() async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true; // Start profile loading
        _profileFetchError = '';
      });
    }

    // 1. Load from cache
    await _loadProfileCacheFromPrefs();

    // 2. Display cached data immediately if available
    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) <
              CacheConfig.profileCacheDuration; // Use correct duration

      if (cacheIsValid) {
        print("ProducerDash: Displaying valid cached profile.");
        setState(() {
          _profile = _profileCache;
          _isLoadingProfile = false; // Stop profile loading indicator
        });
      } else {
        print("ProducerDash: Cached profile expired, will fetch fresh data.");
        // Keep showing stale cache while fetching, but indicate background loading
        setState(() {
          _profile = _profileCache; // Show stale data
          _isLoadingProfile = true; // Indicate background loading
        });
      }
    } else if (mounted) {
      print("ProducerDash: No cached profile found, fetching...");
      // No cache, ensure loading is true
      setState(() {
        _isLoadingProfile = true;
      });
    }

    // 3. Fetch fresh data in the background (regardless of cache state)
    await _fetchProducerProfileAndUpdate();
  }

  // Separate function to fetch Producer Profile and update state/cache
  Future<void> _fetchProducerProfileAndUpdate() async {
    try {
      final profile = await ProducerApiService.fetchProducerProfile();
      if (mounted) {
        print("ProducerDash: Fetched fresh producer profile data.");
        await _saveProfileCacheToPrefs(profile); // Save fresh data to cache
        setState(() {
          _profile = profile;
          _isLoadingProfile = false; // Done loading
          _profileFetchError = ''; // Clear any previous error
        });
      }
    } catch (error, stackTrace) {
      print("Error fetching fresh producer profile: $error\n$stackTrace");
      if (mounted) {
        // Only show error if there's no cached data to display
        if (_profile == null) {
          setState(() {
            _profileFetchError = 'Failed to load profile: $error';
            _isLoadingProfile = false; // Stop loading
          });
          _showErrorSnackBar(
              'Error loading profile: $error'); // Use existing snackbar
        } else {
          // Keep showing cached data, log error silently or show subtle indicator
          print(
              "ProducerDash: Failed to fetch fresh profile, showing cached version. Error: $error");
          setState(() {
            _isLoadingProfile = false; // Ensure loading indicator stops
          });
        }
      }
    }
  }

  // Modified _fetchAllData to only fetch orders and produce, and trigger profile fetch
  Future<void> _fetchAllData() async {
    if (!mounted) return;
    // Ensure isLoading is true only when starting the fetch for orders/produce
    // Profile loading is managed by _isLoadingProfile
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    _error = ''; // General error for orders/produce
    _cancelAllEdits(); // Cancel any ongoing edits before refresh

    // Trigger profile initialization/fetch (cache-first)
    _initializeProducerProfile(); // Don't await this

    try {
      // Fetch orders and produce concurrently
      final results = await Future.wait([
        ProducerApiService.fetchProducerOrders(),
        ProducerApiService
            .fetchProducerProduce(), // Fetch the global list of produce
      ], eagerError: true); // Stop on first error

      // Process results if mounted
      if (mounted) {
        final fetchedOrders = results[0] as List<Order>;
        final fetchedProduce = results[1] as List<Product>;

        setState(() {
          _orders = fetchedOrders;
          _produce = fetchedProduce; // Store the master list of produce

          _sortOrders(); // Sort orders after fetching
          // Sort produce list alphabetically by name
          _produce.sort((a, b) => a.produceName
              .toLowerCase()
              .compareTo(b.produceName.toLowerCase()));

          // Sync the selection UI state (_selectedProduceIds, _produceQuantities)
          // based on the fetched profile's stock.
          _syncSelectionFromProfile();

          _isLoading = false;
          _error = '';
        });
      }
    } catch (e, stackTrace) {
      debugPrint("Error fetching dashboard data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error =
              'Failed to load data. Please check your connection and try again.';
          // Clear potentially stale data on error
          _profile = null;
          _orders = [];
          _produce = [];
          _selectedProduceIds.clear();
          _produceQuantities.clear();
        });
      }
    }
  }

  // Helper to initialize selections based on profile stock
  void _syncSelectionFromProfile() {
    _selectedProduceIds.clear();
    _produceQuantities.clear();
    if (_profile?.stock != null) {
      for (var stockItem in _profile!.stock!) {
        final String? produceId = stockItem['produce_id']?.toString();
        final int? quantity =
            int.tryParse(stockItem['quantity']?.toString() ?? '');

        // Check if the produce ID from stock exists in our master _produce list
        if (produceId != null &&
            produceId.isNotEmpty &&
            _produce.any((p) => p.produceId == produceId)) {
          _selectedProduceIds.add(produceId);
          _produceQuantities[produceId] =
              quantity ?? 0; // Default to 0 if quantity is missing/invalid
        } else {
          print(
              "Warning: Stock item with ID '$produceId' not found in master produce list.");
        }
      }
    }
    // Ensure quantities map only contains keys present in selected IDs
    _produceQuantities
        .removeWhere((key, value) => !_selectedProduceIds.contains(key));
  }

  void _sortOrders() {
    _orders.sort((a, b) {
      int statusCompare = _statusPriority(a.orderStatus)
          .compareTo(_statusPriority(b.orderStatus));
      if (statusCompare != 0) return statusCompare;
      // If status is the same, sort by newest first
      return b.orderDate.compareTo(a.orderDate);
    });
  }

  int _statusPriority(String status) {
    // Lower number = higher priority (appears first)
    switch (status) {
      case Order.STATUS_PENDING:
        return 0;
      case Order.STATUS_ACCEPTED:
        return 1;
      case Order.STATUS_PREPARING:
        return 2;
      case Order.STATUS_DISPATCHED:
        return 3;
      case Order.STATUS_DELIVERED:
        return 4;
      case Order.STATUS_CANCELLED:
        return 5;
      default:
        return 6; // Unknown statuses last
    }
  }

  Future<void> _handleOrderAction(Order order, String action) async {
    debugPrint('Action "$action" triggered for Order ID: ${order.orderId}');
    String? newStatus;
    switch (action) {
      case 'Accept':
        newStatus = Order.STATUS_ACCEPTED;
        break;
      case 'Prepare':
        newStatus = Order.STATUS_PREPARING;
        break;
      case 'Dispatch':
        newStatus = Order.STATUS_DISPATCHED;
        break;
      case 'Cancel':
        // Optional: Add confirmation dialog for cancellation
        newStatus = Order.STATUS_CANCELLED;
        break;
    }

    if (newStatus != null && newStatus != order.orderStatus) {
      _showLoadingSnackbar('Updating order #${order.orderId}...');
      try {
        bool success = await ProducerApiService.updateOrderStatus(
            order.orderId, newStatus);
        _dismissLoadingSnackbar();
        if (!mounted) return;

        if (success) {
          _updateLocalOrderState(order.orderId, newStatus);
          setState(() {}); // Force UI refresh for expanded/collapsed state
          _showSuccessSnackbar(
              'Order #${order.orderId} updated to $newStatus.');
          _showOrderNextStepDialog(newStatus);
        } else {
          _showErrorSnackBar(
              'Failed to update order #${order.orderId}. Please try again.');
        }
      } catch (e) {
        _dismissLoadingSnackbar();
        debugPrint("Error updating order status via API: $e");
        if (mounted) {
          _showErrorSnackBar('Error updating order: $e');
        }
      }
    } else {
      debugPrint(
          "No status change needed for action '$action' on order ${order.orderId}.");
    }
  }

  void _showOrderNextStepDialog(String newStatus) {
    String message;
    String title;
    IconData icon;
    switch (newStatus) {
      case Order.STATUS_ACCEPTED:
        title = "Order Accepted";
        message =
            "You have accepted the order. Next, start preparing the meal when ready.";
        icon = Icons.check_circle_outline;
        break;
      case Order.STATUS_PREPARING:
        title = "Order Preparing";
        message =
            "You are now preparing the order. Mark as dispatched when ready for delivery.";
        icon = Icons.restaurant_menu_outlined;
        break;
      case Order.STATUS_DISPATCHED:
        title = "Order Dispatched";
        message = "Order is on its way! Await delivery confirmation.";
        icon = Icons.local_shipping_outlined;
        break;
      case Order.STATUS_DELIVERED:
        title = "Order Delivered";
        message = "Order has been delivered. Await customer feedback.";
        icon = Icons.done_all;
        break;
      case Order.STATUS_CANCELLED:
        title = "Order Cancelled";
        message = "Order has been cancelled.";
        icon = Icons.cancel_outlined;
        break;
      default:
        title = "Order Updated";
        message = "Order status updated.";
        icon = Icons.info_outline;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: primaryTeal),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _updateLocalOrderState(int orderId, String newStatus) {
    if (!mounted) return;
    setState(() {
      int index = _orders.indexWhere((o) => o.orderId == orderId);
      if (index != -1) {
        // Update the order object immutably
        _orders[index] = _orders[index].copyWith(orderStatus: newStatus);
        _sortOrders(); // Re-sort list after status change
      }
    });
  }

  // --- Profile Edit Methods ---
  void _handleEditProfile() {
    if (_profile == null || !mounted) return;
    debugPrint('Edit Profile Action Triggered');
    setState(() {
      _isEditingProfile = true;
      // Initialize controllers with current profile data
      _profileNameController.text = _profile!.name;
      _profilePhoneController.text = _profile!.phoneNumber ?? '';
      _profileLocationController.text = _profile!.location ?? '';
    });
  }

  Future<void> _saveProfileChanges() async {
    if (_profile == null || !mounted || !_isEditingProfile) return;
    // Validate the form before proceeding
    if (_profileFormKey.currentState?.validate() ?? false) {
      debugPrint('Save Profile Changes Action Triggered');
      _showLoadingSnackbar('Saving profile...');

      try {
        // Get trimmed values from controllers
        final String name = _profileNameController.text.trim();
        final String? phone = _profilePhoneController.text.trim().isEmpty
            ? null
            : _profilePhoneController.text.trim();
        final String? location = _profileLocationController.text.trim().isEmpty
            ? null
            : _profileLocationController.text.trim();

        bool success = await ProducerApiService.updateProducerProfile(
          _profile!.producerId,
          name: name,
          phoneNumber: phone,
          location: location,
        );
        _dismissLoadingSnackbar();
        if (!mounted) return;

        if (success) {
          // Update local profile state immutably
          setState(() {
            _profile = _profile!.copyWith(
              name: name,
              phoneNumber: phone,
              location: location,
              image: _uploadedProfileImageUrl ?? _profile!.image,
            );
            _isEditingProfile = false; // Exit editing mode
          });
          _showSuccessSnackbar('Profile updated successfully.');
        } else {
          _showErrorSnackBar(
              'Failed to save profile changes. Please try again.');
        }
      } catch (e) {
        debugPrint("Error saving profile via API: $e");
        _dismissLoadingSnackbar();
        if (mounted) {
          _showErrorSnackBar('An error occurred while saving profile: $e');
        }
      }
    } else {
      debugPrint('Profile form validation failed.');
      _showSnackbar('Please fix errors in the profile form.', isError: true);
    }
  }

  void _cancelProfileEdit() {
    if (!mounted) return;
    debugPrint('Cancel Profile Edit Action Triggered');
    setState(() {
      _isEditingProfile =
          false; // Just exit editing mode, don't revert unsaved changes visually yet
    });
  }

  Future<void> _handleToggleActiveStatus(bool newStatus) async {
    if (_profile == null || !mounted || _isEditingProfile)
      return; // Prevent during edit
    debugPrint(
        'Toggle Active Status Action Triggered: New Status = $newStatus');
    _showLoadingSnackbar('Updating status...'); // Use loading snackbar

    try {
      bool success = await ProducerApiService.updateProducerStatus(
          _profile!.producerId, newStatus);
      _dismissLoadingSnackbar(); // Dismiss loading snackbar
      if (!mounted) return;

      if (success) {
        // Update local profile state immutably
        setState(() {
          _profile = _profile!.copyWith(isActive: newStatus);
        });
        final statusText = newStatus ? "Active" : "Offline";
        String message = 'Profile status updated to $statusText.';
        if (!newStatus)
          message += '\nCustomers may not see you in search results.';
        _showSuccessSnackbar(message);
      } else {
        // Revert the switch visually if the API call failed
        setState(() {}); // Trigger rebuild to show original state
        _showErrorSnackBar('Failed to update status. Please try again.');
      }
    } catch (e) {
      debugPrint("Error toggling active status via API: $e");
      _dismissLoadingSnackbar(); // Dismiss loading snackbar
      if (mounted) {
        setState(() {}); // Revert visual state on error
        _showErrorSnackBar('An error occurred while updating status: $e');
      }
    }
  }

  // --- Methods for Adding/Editing/Deleting Individual Produce Items ---
  // Note: These manage the master list of _produce, not the producer's stock selection
  void _handleAddProduce() {
    if (_editingProduceId != null || !mounted || _isEditingProfile)
      return; // Prevent conflicts
    debugPrint('Add Produce Action Triggered');
    // Create a temporary ID for the new item until saved
    final newId = 'TEMP_${DateTime.now().millisecondsSinceEpoch}';
    final newProduct =
        Product(produceId: newId, produceName: ''); // Start with empty name

    // Initialize controllers for the new item
    _initializeProduceEditControllers(newProduct);

    setState(() {
      // Add the new product temporarily to the list to show the edit form
      // It might be better to show the form in a dialog or separate screen
      // But following the pattern, we add it and enter edit mode
      _produce.add(newProduct);
      _produce.sort((a, b) =>
          a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
      _editingProduceId = newId; // Enter edit mode for the new item
      // Scroll to the new item if possible (needs ScrollController)
    });
    _showSnackbar('Fill in the details for the new produce item.',
        isError: false);
  }

  void _handleEditProduce(Product product) {
    if (!mounted || _isEditingProfile) return; // Prevent conflicts
    debugPrint('Edit Produce Action Triggered for ID: ${product.produceId}');
    _cancelAllEdits(exceptProduceId: product.produceId); // Cancel other edits

    // Initialize controllers with the product's data
    _initializeProduceEditControllers(product);

    setState(() {
      _editingProduceId = product.produceId; // Enter edit mode
    });
  }

  void _initializeProduceEditControllers(Product product) {
    _produceNameController = TextEditingController(text: product.produceName);
    _produceCaloriesController =
        TextEditingController(text: product.calories?.toString() ?? '');
    _produceProteinsController =
        TextEditingController(text: product.proteins?.toStringAsFixed(1) ?? '');
    _produceCarbsController = TextEditingController(
        text: product.carbohydrates?.toStringAsFixed(1) ?? '');
    _produceFatsController =
        TextEditingController(text: product.fats?.toStringAsFixed(1) ?? '');
    _produceUnitGramsController =
        TextEditingController(text: product.unitGrams?.toString() ?? '');
    _produceSourceController =
        TextEditingController(text: product.source ?? '');
  }

  Future<void> _saveProduceChanges() async {
    if (_editingProduceId == null || !mounted) return;
    // Validate the produce form
    if (_produceFormKey.currentState?.validate() ?? false) {
      final String idToSave = _editingProduceId!;
      final int index = _produce.indexWhere((p) => p.produceId == idToSave);
      if (index == -1) {
        // Should not happen if ID is valid
        _cancelProduceEdit();
        return;
      }

      final bool isNewItem = idToSave.startsWith('TEMP_');

      // Prepare payload from controllers
      Map<String, dynamic> payload = {
        'produce_name': _produceNameController?.text.trim(),
        'calories': _produceCaloriesController?.text.trim(),
        'proteins': _produceProteinsController?.text.trim(),
        'carbohydrates': _produceCarbsController?.text.trim(),
        'fats': _produceFatsController?.text.trim(),
        'unit_grams': _produceUnitGramsController?.text.trim(),
        'source': _produceSourceController?.text.trim(),
      };
      // No need to remove nulls here, API service does it

      debugPrint('Saving Produce Changes for ID: $idToSave (New: $isNewItem)');
      _showLoadingSnackbar('Saving produce...');

      try {
        if (isNewItem) {
          // Add new produce item via API
          Product? addedProduct = await ProducerApiService.addProduce(payload);
          _dismissLoadingSnackbar();
          if (!mounted) return;

          if (addedProduct != null) {
            // Replace the temporary item with the real one from API response
            setState(() {
              _produce.removeAt(index); // Remove TEMP item
              _produce.add(addedProduct); // Add real item
              _produce.sort((a, b) => a.produceName
                  .toLowerCase()
                  .compareTo(b.produceName.toLowerCase())); // Re-sort
              _editingProduceId = null; // Exit edit mode
              _disposeProduceEditControllers(); // Clean up controllers
            });
            _showSuccessSnackbar('Added "${addedProduct.produceName}".');
          } else {
            // If add failed, remove the temporary item
            _showErrorSnackBar('Failed to add produce item. Please try again.');
            setState(() {
              _produce.removeAt(index); // Remove TEMP item on failure
              _editingProduceId = null;
              _disposeProduceEditControllers();
            });
          }
        } else {
          // Update existing produce item via API
          bool success =
              await ProducerApiService.updateProduce(idToSave, payload);
          _dismissLoadingSnackbar();
          if (!mounted) return;

          if (success) {
            // Create updated product object locally
            final updatedProduct = _produce[index].copyWith(
              produceName: _produceNameController?.text.trim() ??
                  _produce[index].produceName,
              calories:
                  int.tryParse(_produceCaloriesController?.text.trim() ?? ''),
              proteins: double.tryParse(
                  _produceProteinsController?.text.trim() ?? ''),
              carbohydrates:
                  double.tryParse(_produceCarbsController?.text.trim() ?? ''),
              fats: double.tryParse(_produceFatsController?.text.trim() ?? ''),
              unitGrams:
                  int.tryParse(_produceUnitGramsController?.text.trim() ?? ''),
              source: _produceSourceController?.text.trim().isNotEmpty == true
                  ? _produceSourceController?.text.trim()
                  : null,
            );
            // Update the list and exit edit mode
            setState(() {
              _produce[index] = updatedProduct; // Update item in list
              _produce.sort((a, b) => a.produceName
                  .toLowerCase()
                  .compareTo(b.produceName.toLowerCase())); // Re-sort
              _editingProduceId = null; // Exit edit mode
              _disposeProduceEditControllers(); // Clean up controllers
            });
            _showSuccessSnackbar('Updated "${updatedProduct.produceName}".');
          } else {
            _showErrorSnackBar(
                'Failed to update "${payload['produce_name'] ?? 'produce item'}". Please try again.');
            // Optionally keep edit mode open on failure
            // setState(() { _editingProduceId = null; _disposeProduceEditControllers(); });
          }
        }
      } catch (e) {
        debugPrint("Error saving produce via API: $e");
        _dismissLoadingSnackbar();
        if (mounted) {
          _showErrorSnackBar('An error occurred while saving produce: $e');
          // Handle TEMP item removal on exception if needed
          if (isNewItem) {
            setState(() {
              if (index >= 0 &&
                  index < _produce.length &&
                  _produce[index].produceId == idToSave) {
                _produce.removeAt(index);
              }
              _editingProduceId = null;
              _disposeProduceEditControllers();
            });
          }
        }
      }
    } else {
      debugPrint('Produce form validation failed.');
      _showSnackbar('Please fix errors in the produce form.', isError: true);
    }
  }

  void _cancelProduceEdit() {
    if (!mounted) return;
    debugPrint('Cancel Produce Edit Action Triggered');
    final String? idToCancel = _editingProduceId;
    setState(() {
      _editingProduceId = null; // Exit edit mode
      _disposeProduceEditControllers(); // Clean up controllers

      // If cancelling a *new* item (TEMP_ id), remove it from the list
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary new produce item on cancel.");
      }
      // No visual reversion needed for existing items, just exit edit mode
    });
  }

  void _handleDeleteProduce(Product product) {
    // Prevent deletion while editing profile or another produce item
    if (!mounted ||
        _isEditingProfile ||
        (_editingProduceId != null && _editingProduceId != product.produceId))
      return;
    debugPrint('Delete Produce Action Triggered for ID: ${product.produceId}');

    // If it's a temporary item being edited, just cancel the edit
    if (product.produceId.startsWith('TEMP_')) {
      _cancelProduceEdit();
      return;
    }

    // Show confirmation dialog for permanent items
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: whiteColor.withOpacity(0.95),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: errorColor),
              SizedBox(width: 10),
              Text('Confirm Deletion'),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete "${product.produceName}" from the system?\nThis cannot be undone.',
            style: const TextStyle(color: subtleText),
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(foregroundColor: subtleText),
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: 16),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: destructiveButtonBackground,
                foregroundColor: destructiveButtonForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(); // Close the dialog
                _performDeleteProduce(product); // Perform the deletion
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _performDeleteProduce(Product product) async {
    _showLoadingSnackbar('Deleting "${product.produceName}"...');
    try {
      bool success = await ProducerApiService.deleteProduce(product.produceId);
      _dismissLoadingSnackbar();
      if (!mounted) return;

      if (success) {
        final deletedName = product.produceName;
        // Remove the item from the local list
        setState(() {
          _produce.removeWhere((p) => p.produceId == product.produceId);
          // Also remove from selection if it was selected
          if (_selectedProduceIds.contains(product.produceId)) {
            _selectedProduceIds.remove(product.produceId);
            _produceQuantities.remove(product.produceId);
          }
        });
        _showSuccessSnackbar('Deleted "$deletedName".');
      } else {
        _showErrorSnackBar(
            'Failed to delete "${product.produceName}". Please try again.');
      }
    } catch (e) {
      debugPrint("Error deleting produce via API: $e");
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackBar('An error occurred while deleting: $e');
      }
    }
  }

  // Helper to cancel any active editing modes (profile or produce)
  void _cancelAllEdits({String? exceptProduceId}) {
    if (!mounted) return;
    bool didCancel = false;

    if (_isEditingProfile) {
      _isEditingProfile = false;
      didCancel = true;
    }
    if (_editingProduceId != null && _editingProduceId != exceptProduceId) {
      // If cancelling a TEMP item edit, remove it
      if (_editingProduceId!.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == _editingProduceId);
        debugPrint("Removed temporary produce item due to action/switch.");
      }
      _editingProduceId = null;
      _disposeProduceEditControllers();
      didCancel = true;
    }

    // Trigger a rebuild if any edit was cancelled to reflect the change
    if (didCancel) {
      setState(() {});
      debugPrint("Cancelled active edits due to action/switch.");
    }
  }

  // --- Snackbar Helpers ---
  void _showSnackbar(String message,
      {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar(); // Hide previous snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
              color: isError
                  ? whiteColor
                  : textOnTeal), // Adjust text color based on type
          textAlign: TextAlign.center,
        ),
        backgroundColor: isError
            ? errorColor.withOpacity(0.9)
            : primaryTeal.withOpacity(0.9),
        duration: Duration(seconds: durationSeconds),
        behavior: SnackBarBehavior.floating, // Floating looks nicer
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        elevation: 4.0,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    _showSnackbar(message,
        isError: true, durationSeconds: 4); // Longer duration for errors
  }

  void _showSuccessSnackbar(String message) {
    _showSnackbar(message, isError: false);
  }

  // Loading Snackbar (non-dismissible by swipe)
  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .removeCurrentSnackBar(); // Remove any previous ones
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18, // Slightly larger spinner
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            ),
            const SizedBox(width: 15),
            Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.8), // Darker background
        duration: const Duration(minutes: 1), // Long duration, dismiss manually
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(
            vertical: 20.0, horizontal: 50.0), // Centered more
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25.0)), // More rounded
      ),
    );
  }

  void _dismissLoadingSnackbar() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  // --- Build Method and UI Widgets ---
  @override
  Widget build(BuildContext context) {
    // Determine AppBar Avatar Image
    // Use _profile and _isLoadingProfile for profile image
    ImageProvider? appBarAvatarImage;
    if (_isLoadingProfile || _profile == null) {
      appBarAvatarImage =
          const AssetImage(placeholderImagePath); // Placeholder while loading
    } else if (_profile!.image != null && _profile!.image!.isNotEmpty) {
      try {
        // Validate URL before creating NetworkImage
        Uri.parse(_profile!.image!);
        appBarAvatarImage = NetworkImage(_profile!.image!);
      } catch (e) {
        debugPrint("Invalid URL format for AppBar image: ${_profile!.image}");
        appBarAvatarImage =
            const AssetImage(placeholderImagePath); // Fallback on error
      }
    } else {
      appBarAvatarImage =
          const AssetImage(placeholderImagePath); // Default placeholder
    }

    return Scaffold(
      // Add the standard drawer
      drawer: const AppDrawer(),
      backgroundColor: whiteColor, // Solid white background
      appBar: AppBar(
        backgroundColor: primaryTeal,
        elevation: 2.0, // Subtle shadow
        iconTheme: const IconThemeData(color: textOnTeal), // White icons
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(
              color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: false, // Align title left (common practice)
        actions: [
          // Profile Avatar in AppBar
          if (!_isLoadingProfile &&
              _profile != null) // Show only when profile is loaded
            Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: lightTeal.withOpacity(0.5),
                child: _profile!.image != null && _profile!.image!.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: _profile!.image!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.teal.withOpacity(0.1),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.teal),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Icon(Icons.person, color: Colors.grey, size: 24),
              ),
            ),
          // Logout Button (Example action)
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: textOnTeal),
            tooltip: 'Logout',
            onPressed: () {
              // TODO: Implement actual logout logic
              debugPrint("Logout tapped");
              _showSnackbar('Logout action simulated.', isError: false);
              // Example: Navigator.pushReplacementNamed(context, '/login');
            },
          ),
          const SizedBox(width: 8), // Spacing
        ],
      ),
      // Body with Background Image
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            // Use a subtle background if desired
            image: AssetImage(
                "assets/images/soft.jpg"), // Ensure this asset exists
            fit: BoxFit.cover,
            // Apply a filter to make text readable
            colorFilter: ColorFilter.mode(
                Color(0xE6FFFFFF), BlendMode.dstATop), // Lighten image
          ),
        ),
        child: _buildBodyContent(), // Main content based on state
      ),
      // Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          // Only change state if a different tab is tapped
          if (index != _currentIndex && mounted) {
            _cancelAllEdits(); // Cancel edits when switching tabs
            setState(() => _currentIndex = index);
          }
        },
        backgroundColor:
            whiteColor.withOpacity(0.98), // Slightly transparent white
        selectedItemColor: primaryTeal, // Color for selected item
        unselectedItemColor:
            subtleText.withOpacity(0.9), // Color for unselected items
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed, // Ensure all labels are visible
        elevation: 8.0, // Shadow for separation
        items: [
          _buildBottomNavItem(Icons.account_circle_outlined,
              Icons.account_circle, 'Profile', 0),
          _buildBottomNavItem(
              Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 1),
          // Changed icon and label for Produce/Stock management
          _buildBottomNavItem(
              Icons.inventory_2_outlined, Icons.inventory_2, 'Stock', 2),
        ],
      ),
      // Floating Action Button (Contextual)
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat, // Standard position
    );
  }

  // Helper for building BottomNavigationBarItems with active state handling
  BottomNavigationBarItem _buildBottomNavItem(
      IconData icon, IconData activeIcon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavItemIcon(icon, isSelected),
      activeIcon: _buildNavItemIcon(isSelected ? activeIcon : icon,
          isSelected), // Use filled icon when active
      label: label,
    );
  }

  // Helper for styling the nav item icon (adds background circle when selected)
  Widget _buildNavItemIcon(IconData iconData, bool isSelected) {
    final icon = Icon(
      iconData,
      color: isSelected ? primaryTeal : subtleText.withOpacity(0.8),
      size: 24, // Standard size
    );
    if (isSelected) {
      // Add a subtle background highlight when selected
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: lightTeal.withOpacity(0.25),
          shape: BoxShape.circle,
        ),
        child: icon,
      );
    } else {
      // Ensure consistent sizing for unselected icons
      return SizedBox(width: 32, height: 32, child: Center(child: icon));
    }
  }

  // Dynamically set AppBar title based on current tab and editing state
  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return _isEditingProfile ? 'Edit Profile' : 'Producer Profile';
      case 1:
        return 'Manage Orders';
      case 2:
        // Title depends on whether editing a specific produce item or viewing stock list
        return _editingProduceId != null
            ? (_editingProduceId!.startsWith("TEMP_")
                ? 'Add Produce Item'
                : 'Edit Produce Item')
            : 'Manage Stock & Produce';
      default:
        return 'Producer Dashboard';
    }
  }

  // Determine which FAB to show based on the current tab and editing state
  Widget? _buildFloatingActionButton() {
    // No FAB when editing profile or a specific produce item
    if (_isEditingProfile || _editingProduceId != null) return null;

    switch (_currentIndex) {
      case 0: // Profile Tab
        // Show FAB only when profile is loaded and not loading
        return FloatingActionButton.small(
          onPressed: (_profile == null || _isLoadingProfile)
              ? null
              : _handleEditProfile,
          tooltip: 'Edit Profile',
          backgroundColor: (_profile == null || _isLoadingProfile)
              ? Colors.grey
              : primaryTeal,
          foregroundColor: textOnTeal,
          child: const Icon(Icons.edit_outlined, size: 20),
          heroTag: 'fab_profile_edit', // Unique tag
        );
      case 1: // Orders Tab
        return null; // No FAB needed for orders list
      case 2: // Produce/Stock Tab
        // Show "Update Stock" FAB only if items are selected, otherwise show "Add Produce" FAB
        if (_selectedProduceIds.isNotEmpty) {
          // Show Update Stock FAB when items are selected
          return FloatingActionButton.extended(
            onPressed:
                _updateProducerStock, // Calls method which checks if empty
            tooltip: 'Update Stock Levels',
            icon: const Icon(Icons.update),
            label: const Text("Update Stock"),
            backgroundColor: darkTeal, // Use darkTeal to differentiate
            foregroundColor: textOnTeal,
            heroTag: 'fab_stock_update', // Unique tag
          );
        } else {
          // Show Add Produce FAB if no stock items are selected
          return FloatingActionButton(
            onPressed: _handleAddProduce,
            tooltip: 'Add New Produce Item',
            backgroundColor: primaryTeal, // Use primaryTeal for Add
            foregroundColor: textOnTeal,
            child: const Icon(Icons.add),
            heroTag: 'fab_produce_add', // Unique tag
          );
        }
      default:
        return null;
    }
  }

  // Main content switcher based on loading, error, or current tab index
  Widget _buildBodyContent() {
    if (_isLoading) {
      return Container(
        color: Colors.transparent, // Let background show through
        child:
            const Center(child: CircularProgressIndicator(color: primaryTeal)),
      );
    }
    if (_error.isNotEmpty) {
      return Container(
        color: Colors.transparent, // Let background show through
        child: _buildErrorView(), // Show error message and retry button
      );
    }
    // Use IndexedStack to keep state of inactive tabs
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildProfileTab(),
        _buildOrdersTab(),
        _buildProduceTab(), // Manages both stock selection and produce item editing
      ],
    );
  }

  // Widget to display when there's an error loading data
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Card(
          color: whiteColor.withOpacity(0.9), // Semi-transparent card
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Fit content
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: errorColor, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error, // Display the specific error message
                  style: const TextStyle(color: textOnWhite, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: textOnTeal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _fetchAllData, // Retry fetching data
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Profile Tab UI ---
  Widget _buildProfileTab() {
    if (_profile == null) {
      return _buildEmptyState(
        'Profile Unavailable',
        'Could not load profile details.',
        icon: Icons.person_off_outlined,
      );
    }

    final profile = _profile!;
    final dateFormat = DateFormat('MMM d, yyyy, hh:mm a');

    ImageProvider profileAvatarImage;
    if (profile.image != null && profile.image!.isNotEmpty) {
      try {
        Uri.parse(profile.image!);
        profileAvatarImage = NetworkImage(profile.image!);
      } catch (e) {
        debugPrint("Invalid URL format for profile image: ${profile.image}");
        profileAvatarImage = const AssetImage(placeholderImagePath);
      }
    } else {
      profileAvatarImage = const AssetImage(placeholderImagePath);
    }

    // --- Info Card Helper ---
    Widget infoCard(
        {required IconData icon,
        required String label,
        required String value,
        int maxLines = 3}) {
      return Card(
        elevation: 0.5,
        margin: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: primaryTeal, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: darkTeal)),
                    const SizedBox(height: 2),
                    Text(
                      value.isEmpty ? 'Not provided' : value,
                      style: const TextStyle(
                          fontSize: 13, color: subtleText, height: 1.4),
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // --- Profile Header ---
    Widget profileHeader = Card(
      elevation: 2.0,
      color: cardBackground.withOpacity(0.95),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: lightTeal.withOpacity(0.5),
              backgroundImage: profileAvatarImage,
              onBackgroundImageError: (exception, stackTrace) {
                debugPrint('Error loading profile network image: $exception');
              },
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: darkTeal)),
                  if (profile.producerType != null &&
                      profile.producerType!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(profile.producerType!,
                          style:
                              const TextStyle(fontSize: 14, color: subtleText)),
                    ),
                  if (profile.rating != null && profile.rating! > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: starColor, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            profile.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textOnWhite),
                          ),
                          if (profile.reviews != null &&
                              profile.reviews!.isNotEmpty &&
                              profile.reviews!.toLowerCase() != 'none') ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${profile.reviews} reviews)',
                              style: const TextStyle(
                                  fontSize: 12, color: subtleText),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // --- Active Status Card ---
    Widget activeStatusCard = Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SwitchListTile(
          value: profile.isActive,
          onChanged: _isEditingProfile ? null : _handleToggleActiveStatus,
          title: const Text('Active Status',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 16, color: darkTeal)),
          subtitle: Text(
            profile.isActive
                ? 'Visible to customers'
                : 'Not visible to customers',
            style: const TextStyle(fontSize: 13, color: subtleText),
          ),
          secondary: Icon(
            profile.isActive
                ? Icons.check_circle_outline_rounded
                : Icons.power_settings_new_outlined,
            color: profile.isActive
                ? Colors.green.shade600
                : Colors.orange.shade700,
            size: 28,
          ),
          activeColor: primaryTeal,
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade200,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );

    // --- Info Cards Grid ---
    List<Widget> infoCards = [
      infoCard(
          icon: Icons.info_outline_rounded,
          label: 'Bio',
          value: profile.producerType ?? ''),
      infoCard(
          icon: Icons.star_outline_rounded,
          label: 'Specialties',
          value: profile.reviews ?? ''),
      infoCard(icon: Icons.timer_outlined, label: 'Experience', value: 'N/A'),
      infoCard(icon: Icons.language_rounded, label: 'Languages', value: 'N/A'),
      infoCard(
          icon: Icons.calendar_today_rounded,
          label: 'Availability',
          value: 'N/A'),
      infoCard(
          icon: Icons.verified_user_outlined,
          label: 'Certifications',
          value: 'N/A'),
      infoCard(
          icon: Icons.attach_money_rounded,
          label: 'Base Price/Fee',
          value: 'N/A'),
      infoCard(
          icon: Icons.schedule_rounded, label: 'Response Time', value: 'N/A'),
      infoCard(
          icon: Icons.menu_book_rounded, label: 'Sample Menu', value: 'N/A'),
      infoCard(
          icon: Icons.build_circle_outlined, label: 'Equipment', value: 'N/A'),
      infoCard(
          icon: Icons.location_on_outlined,
          label: 'Location',
          value: profile.location ?? ''),
      infoCard(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: profile.phoneNumber ?? ''),
      infoCard(
          icon: Icons.email_outlined,
          label: 'Email',
          value: profile.email ?? ''),
    ];

    // --- Main Layout ---
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        profileHeader,
        activeStatusCard,
        // Info cards grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: infoCards,
        ),
        if (_isEditingProfile) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelProfileEdit,
                child:
                    const Text('Cancel', style: TextStyle(color: subtleText)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  foregroundColor: textOnTeal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _saveProfileChanges,
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (!_isEditingProfile) const SizedBox(height: 80),
      ],
    );
  }

  // Helper to build reusable section cards in the profile tab
  Widget _buildProfileSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
      elevation: 1.0, // Subtle elevation
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      color: whiteColor.withOpacity(0.9), // Semi-transparent white background
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                Icon(icon, color: primaryTeal, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: darkTeal),
                ),
              ],
            ),
            const Divider(
                height: 16, thickness: 0.8, color: dividerColor), // Separator
            // Section Content
            ...children.map((child) => Padding(
                  padding: const EdgeInsets.only(
                      bottom: 4.0), // Consistent padding between items
                  child: child,
                )),
          ],
        ),
      ),
    );
  }

  // Helper for displaying a static detail item (label: value)
  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align text top if value wraps
        children: [
          Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)),
          const SizedBox(width: 10),
          // Fixed width for label for alignment
          SizedBox(
            width: 85, // Adjust width as needed
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textOnWhite,
                  fontSize: 13),
            ),
          ),
          // Expanded value field
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: TextStyle(
                color: value.isEmpty ? subtleText.withOpacity(0.7) : subtleText,
                fontSize: 13,
              ),
              softWrap: true, // Allow wrapping
            ),
          ),
        ],
      ),
    );
  }

  // Helper for creating an editable TextFormField item in the profile edit form
  Widget _buildEditableItem(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 6.0), // Slightly more padding for input fields
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18, color: primaryTeal.withOpacity(0.9)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36), // Ensure space for icon
          isDense: true, // Compact field
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            // Style for when not focused
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            // Style for when focused
            borderRadius: BorderRadius.circular(8.0),
            borderSide: const BorderSide(color: primaryTeal, width: 1.5),
          ),
          labelStyle: const TextStyle(color: subtleText, fontSize: 13),
          floatingLabelStyle:
              const TextStyle(color: primaryTeal), // Label style when focused
        ),
        style: const TextStyle(
            color: textOnWhite, fontSize: 13), // Input text style
        maxLines: maxLines,
        keyboardType: keyboardType,
        // Optional: Add specific validation for phone/email if needed
        validator: (value) {
          if (label.contains('Phone') && value != null && value.isNotEmpty) {
            // Basic phone format check (allows digits, spaces, -, +, ())
            if (!RegExp(r'^[\d\s\-+()]+$').hasMatch(value)) {
              return 'Invalid phone format';
            }
          }
          // Add other validations if required (e.g., email format)
          return null; // Return null if valid
        },
        autovalidateMode:
            AutovalidateMode.onUserInteraction, // Validate on change
      ),
    );
  }

  // Helper for the Active Status switch
  Widget _buildActiveStatusToggle(bool isActive) {
    return SwitchListTile(
      value: isActive,
      onChanged: _isEditingProfile
          ? null
          : _handleToggleActiveStatus, // Disable toggle during profile edit
      title: Text(
        isActive ? 'Account Active' : 'Account Offline',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: _isEditingProfile
              ? subtleText
              : textOnWhite, // Dim text if disabled
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        // Add a subtitle explaining the status
        isActive ? 'Visible to customers' : 'Hidden from search results',
        style: TextStyle(fontSize: 11, color: subtleText.withOpacity(0.8)),
      ),
      secondary: Icon(
        isActive
            ? Icons.check_circle_outline_rounded
            : Icons.power_settings_new_outlined,
        size: 18,
        color: isActive
            ? (_isEditingProfile
                ? lightTeal.withOpacity(0.5)
                : primaryTeal) // Dim icon if disabled
            : subtleText,
      ),
      activeColor: primaryTeal, // Color of the switch thumb when on
      activeTrackColor:
          lightTeal.withOpacity(0.6), // Color of the track when on
      inactiveThumbColor: subtleText.withOpacity(0.8),
      inactiveTrackColor: Colors.grey.shade300,
      dense: true, // Make it more compact
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      controlAffinity:
          ListTileControlAffinity.leading, // Place switch on the left
    );
  }

  // --- Orders Tab UI ---
  Widget _buildOrdersTab() {
    // Use RefreshIndicator for pull-to-refresh functionality
    return RefreshIndicator(
      onRefresh: _fetchAllData, // Call fetch data on pull
      color: primaryTeal, // Spinner color
      backgroundColor: whiteColor, // Background of spinner container
      child: Container(
        color: Colors.transparent, // Let background show through
        // Use ListView for scrollability, even if content fits screen
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              16.0, 16.0, 16.0, 80.0), // Padding including bottom for FAB
          physics:
              const AlwaysScrollableScrollPhysics(), // Ensure scrollability for refresh
          children: [
            // Optional: Summary Section
            _buildSummarySection(),
            if (_orders.isNotEmpty)
              const SizedBox(height: 24), // Spacing if orders exist
            // Orders List Section
            _buildOrdersListSection(),
          ],
        ),
      ),
    );
  }

  // Helper to build the summary card at the top of the Orders tab
  Widget _buildSummarySection() {
    if (_orders.isEmpty)
      return const SizedBox.shrink(); // Don't show if no orders

    // Calculate summary counts
    int pendingOrders =
        _orders.where((o) => o.orderStatus == Order.STATUS_PENDING).length;
    int activeOrders = _orders
        .where((o) => [
              Order.STATUS_ACCEPTED,
              Order.STATUS_PREPARING,
              Order.STATUS_DISPATCHED
            ].contains(o.orderStatus))
        .length;
    // Example: Calculate total revenue for delivered orders today (more complex)
    // double revenueToday = _orders.where((o) => o.orderStatus == Order.STATUS_DELIVERED && isToday(o.orderDate)).fold(0.0, (sum, item) => sum + item.totalPrice);

    return Card(
      elevation: 1.0,
      color: primaryTeal.withOpacity(0.9), // Use primary color for summary card
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceAround, // Distribute items evenly
          children: [
            _buildSummaryItem('Pending', pendingOrders.toString(),
                Icons.pending_actions_outlined),
            _buildSummaryItem('In Progress', activeOrders.toString(),
                Icons.local_shipping_outlined), // Icon for active orders
            _buildSummaryItem('Total Today', _orders.length.toString(),
                Icons.list_alt_outlined), // Example: Total orders today
            // _buildSummaryItem('Revenue', 'ugx ${revenueToday.toStringAsFixed(2)}', Icons.attach_money),
          ],
        ),
      ),
    );
  }

  // Helper for individual items within the summary card
  Widget _buildSummaryItem(String title, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: whiteColor.withOpacity(0.9), size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: whiteColor),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(
              fontSize: 11,
              color: lightTeal,
              letterSpacing: 0.5), // Lighter text for title
        ),
      ],
    );
  }

  // Helper to build the list of order items
  Widget _buildOrdersListSection() {
    if (_orders.isEmpty) {
      // Show an empty state message if there are no orders
      return _buildEmptyState(
        'No Orders Yet',
        'New customer orders will appear here.',
        icon: Icons.receipt_long_outlined,
      );
    }
    // Use ListView.builder for efficiency if list can be long
    return ListView.builder(
      shrinkWrap: true, // Important inside another ListView
      physics:
          const NeverScrollableScrollPhysics(), // Disable scrolling for the inner list
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        // Add padding between order cards
        return Padding(
          padding:
              EdgeInsets.only(bottom: (index == _orders.length - 1) ? 0 : 12.0),
          child: _buildOrderItem(_orders[index]), // Build each order item card
        );
      },
    );
  }

  // --- Produce/Stock Tab UI ---
  Widget _buildProduceTab() {
    // This tab handles both viewing/selecting stock and adding/editing produce items
    return RefreshIndicator(
      onRefresh: _fetchAllData,
      color: primaryTeal,
      backgroundColor: whiteColor,
      child: Container(
        color: Colors.transparent, // Let background show through
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              16.0, 16.0, 16.0, 80.0), // Padding + space for FAB
          physics:
              const AlwaysScrollableScrollPhysics(), // Ensure scrollable for refresh
          children: [
            // Conditional UI: Show edit form or the list
            if (_editingProduceId != null)
              _buildProduceEditSection() // Show form for adding/editing a produce item
            else
              _buildStockSelectionSection(), // Show list for selecting stock

            // Add extra space at the bottom if the edit form is shown
            if (_editingProduceId != null) const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // Section for selecting stock quantities
  Widget _buildStockSelectionSection() {
    if (_produce.isEmpty && !_isLoading) {
      // Show empty state if no produce items exist in the system yet
      return _buildEmptyState(
        'No Produce Items Found',
        'Tap the (+) button below to add the first produce item to the system.',
        icon: Icons.eco_outlined,
      );
    }

    // Use the _buildProduceList provided in the fix for stock selection
    return _buildProduceList();
  }

  // Section for adding/editing a specific produce item
  Widget _buildProduceEditSection() {
    if (_editingProduceId == null)
      return const SizedBox.shrink(); // Should not happen

    // Find the product being edited (could be a TEMP one)
    final productToEdit = _produce
        .firstWhere((p) => p.produceId == _editingProduceId, orElse: () {
      // Fallback if somehow the ID is invalid - cancel edit
      print("Error: Product with ID $_editingProduceId not found for editing.");
      // Schedule cancellation after build
      WidgetsBinding.instance.addPostFrameCallback((_) => _cancelProduceEdit());
      return Product(
          produceId: 'invalid',
          produceName: 'Error'); // Temporary invalid product
    });

    if (productToEdit.produceId == 'invalid')
      return const SizedBox.shrink(); // Don't build if fallback triggered

    // Show the edit form for this product
    return _buildProduceEditForm(productToEdit);
  }

  // --- START: Applied Fix (_buildProduceList) ---
  // Builds the list of produce for stock selection
  Widget _buildProduceList() {
    if (_produce.isEmpty) {
      return _buildEmptyState("No Produce Available",
          "Add produce items first using the (+) button.",
          icon: Icons.inventory_2_outlined);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align content left
      children: [
        // Optional: Add a title for this section
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            "Select Available Stock",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: darkTeal),
          ),
        ),
        // Use Card for better visual grouping
        Card(
          elevation: 1.5,
          color: whiteColor.withOpacity(0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 8.0), // Padding inside card
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _produce.length,
              itemBuilder: (context, index) {
                final product = _produce[index];
                final bool isSelected =
                    _selectedProduceIds.contains(product.produceId);
                final bool isValidProduct = product.produceName.isNotEmpty &&
                    product.produceName.trim().isNotEmpty;

                return Column(
                  children: [
                    CheckboxListTile(
                      title: Text(
                        isValidProduct
                            ? product.produceName
                            : 'Unnamed Produce',
                        style: TextStyle(
                          fontSize: 14, // Slightly smaller font
                          color: isValidProduct
                              ? textOnWhite
                              : Colors.grey.shade600, // Grey out invalid items
                          decoration: isValidProduct
                              ? null
                              : TextDecoration
                                  .lineThrough, // Strike through invalid
                        ),
                      ),
                      value: isSelected,
                      // Disable checkbox if product name is invalid
                      onChanged: isValidProduct
                          ? (bool? selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedProduceIds.add(product.produceId);
                                  // Default quantity to 1 only if it doesn't exist yet
                                  _produceQuantities.putIfAbsent(
                                      product.produceId, () => 1);
                                } else {
                                  _selectedProduceIds.remove(product.produceId);
                                  _produceQuantities.remove(product
                                      .produceId); // Remove quantity when deselected
                                }
                              });
                            }
                          : null, // Disable onChanged for invalid items
                      controlAffinity: ListTileControlAffinity
                          .leading, // Checkbox on the left
                      dense: true, // Make tile more compact
                      activeColor: primaryTeal, // Color of the checkbox
                      // Optional: Add a subtle visual cue for invalid items besides text style
                      tileColor: isValidProduct
                          ? null
                          : Colors.grey.shade100.withOpacity(0.5),
                    ),
                    // Show quantity input only if item is selected AND valid
                    if (isSelected && isValidProduct)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 56.0,
                            right: 16.0,
                            bottom: 12.0,
                            top: 0.0), // Indent quantity input, adjust padding
                        child: Row(
                          children: [
                            const Text("Quantity:",
                                style:
                                    TextStyle(fontSize: 13, color: subtleText)),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 80, // Slightly wider input field
                              height: 40, // Explicit height
                              child: TextFormField(
                                // Use a key based on produceId to ensure state is preserved correctly
                                key: ValueKey(product.produceId),
                                initialValue: _produceQuantities[
                                            product.produceId]
                                        ?.toString() ??
                                    '1', // Default initial value to '1' if selected
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 10),
                                  border: OutlineInputBorder(),
                                  // Optional: Add suffix text like "units" or "kg" if applicable
                                  // suffixText: "units",
                                  hintText: "0", // Hint for quantity
                                  hintStyle: TextStyle(fontSize: 13),
                                ),
                                style: const TextStyle(
                                    fontSize: 14, color: textOnWhite),
                                // Only allow digits
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                onChanged: (val) {
                                  // Update the quantity in the map, ensuring it's non-negative
                                  setState(() {
                                    final parsed = int.tryParse(val) ??
                                        0; // Default to 0 if parsing fails
                                    _produceQuantities[product.produceId] =
                                        parsed >= 0
                                            ? parsed
                                            : 0; // Store non-negative value
                                  });
                                },
                                // Basic validation for the quantity field
                                validator: (val) {
                                  if (val == null || val.isEmpty)
                                    return 'Enter #'; // Short error message
                                  final num = int.tryParse(val);
                                  if (num == null || num < 0)
                                    return 'Invalid'; // Short error message
                                  return null; // Valid
                                },
                                autovalidateMode: AutovalidateMode
                                    .onUserInteraction, // Validate as user types
                              ),
                            ),
                            const Spacer(), // Push buttons to the right if needed
                            // Optional: Add quick +/- buttons
                            /*
                             IconButton(
                               icon: Icon(Icons.remove_circle_outline, size: 20, color: errorColor.withOpacity(0.7)),
                               padding: EdgeInsets.zero,
                               constraints: BoxConstraints(),
                               onPressed: () {
                                 setState(() {
                                   int currentQty = _produceQuantities[product.produceId] ?? 0;
                                   if (currentQty > 0) {
                                     _produceQuantities[product.produceId] = currentQty - 1;
                                     // Need to update TextFormField controller if using one explicitly
                                   }
                                 });
                               },
                             ),
                             IconButton(
                               icon: Icon(Icons.add_circle_outline, size: 20, color: primaryTeal),
                               padding: EdgeInsets.zero,
                               constraints: BoxConstraints(),
                               onPressed: () {
                                  setState(() {
                                     int currentQty = _produceQuantities[product.produceId] ?? 0;
                                    _produceQuantities[product.produceId] = currentQty + 1;
                                     // Need to update TextFormField controller if using one explicitly
                                  });
                               },
                             ),
                             */
                          ],
                        ),
                      ),
                    // Add divider between items inside the card, except for the last one
                    if (index < _produce.length - 1)
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: dividerColor.withOpacity(0.5)),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24), // Space before the button
        // Center the update button - REMOVED, now handled by FAB
        // const SizedBox(height: 20), // Bottom padding after button - REMOVED

        // Optional: Add a section to view/manage the master produce list
        Divider(height: 40, thickness: 1, color: dividerColor),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Manage Produce Items",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: darkTeal),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: primaryTeal),
              tooltip: "Add New Produce Item",
              onPressed:
                  _handleAddProduce, // FAB also does this, but good to have here too
            )
          ],
        ),
        const SizedBox(height: 12),
        _buildMasterProduceListForEditing(), // Display the list of all produce items for editing/deleting
      ],
    );
  }
  // --- END: Applied Fix (_buildProduceList) ---

  // Helper to display the list of *all* produce items (master list) for editing/deleting
  // This is shown below the stock selection on the same tab
  Widget _buildMasterProduceListForEditing() {
    if (_produce.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text("No produce items defined in the system yet.",
            textAlign: TextAlign.center, style: TextStyle(color: subtleText)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _produce.length,
      itemBuilder: (context, index) {
        final product = _produce[index];
        // Don't show the item if it's currently being edited inline (form is shown instead)
        if (product.produceId == _editingProduceId) {
          return const SizedBox
              .shrink(); // Hide item, form is visible elsewhere
        }
        return Padding(
          padding:
              EdgeInsets.only(bottom: (index == _produce.length - 1) ? 0 : 8.0),
          child: _buildProduceItem(
              product), // Build the display card for the produce item
        );
      },
    );
  }

  // Builds the display card for a single produce item in the master list
  Widget _buildProduceItem(Product product) {
    final bool isTemp = product.produceId.startsWith('TEMP_');
    return Card(
      elevation: 1.0,
      color: isTemp
          ? Colors.yellow.shade100.withOpacity(0.7)
          : whiteColor.withOpacity(0.9), // Highlight temporary items
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(color: primaryTeal.withOpacity(0.3), width: 0.8),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        title: Text(
          product.produceName.isEmpty
              ? (isTemp ? 'New Item (Editing...)' : 'Unnamed Produce')
              : product.produceName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: product.produceName.isEmpty ? subtleText : textOnWhite,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            // Show some nutritional info or placeholder
            product.calories != null
                ? '${product.calories} kcal${product.unitGrams != null ? ' / ${product.unitGrams}g' : ''}'
                : (isTemp ? '...' : 'Nutritional info missing'),
            style: TextStyle(fontSize: 11, color: subtleText.withOpacity(0.8)),
          ),
        ),
        trailing: isTemp
            ? const SizedBox(
                width: 40,
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2))) // Indicate saving/loading
            : Row(
                // Action buttons for existing items
                mainAxisSize: MainAxisSize.min,
                children: [
                  // IconButton( // Commented out edit button
                  //   icon: const Icon(Icons.edit_outlined, size: 20),
                  //   color: actionButtonForeground, // Use defined color
                  //   tooltip: 'Edit Item Details',
                  //   padding: EdgeInsets.zero,
                  //   constraints: const BoxConstraints(), // Compact button
                  //    onPressed: () => _handleEditProduce(product), // Open edit form
                  // ),
                  // const SizedBox(width: 4), // Space between buttons
                  // IconButton( // Commented out delete button
                  //   icon: const Icon(Icons.delete_outline, size: 20),
                  //   color: destructiveButtonForeground, // Use defined color
                  //   tooltip: 'Delete Item',
                  //   padding: EdgeInsets.zero,
                  //    constraints: const BoxConstraints(), // Compact button
                  //   onPressed: () => _handleDeleteProduce(product), // Show delete confirmation
                  // ),
                ],
              ),
        // Allow tapping the whole tile to edit as well
        onTap: isTemp ? null : () => _handleEditProduce(product),
      ),
    );
  }

  // Builds the form for adding or editing a produce item's details
  Widget _buildProduceEditForm(Product product) {
    final bool isNewItem = product.produceId.startsWith('TEMP_');
    return Card(
      elevation: 3.0, // More elevation for the edit form
      color: whiteColor.withOpacity(0.98), // Near solid white
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: primaryTeal, width: 1.5) // Highlight border
          ),
      margin: const EdgeInsets.only(bottom: 16.0), // Margin below the form
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _produceFormKey, // Use the form key for validation
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Take minimum space
            children: [
              // Form Title
              Text(
                isNewItem
                    ? 'Add New Produce Item'
                    : 'Edit "${product.produceName}"',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal),
              ),
              const SizedBox(height: 16),

              // Name Field (Required)
              TextFormField(
                controller: _produceNameController,
                decoration: _inputDecoration(
                    'Produce Name *'), // Use helper for decoration
                style: const TextStyle(fontSize: 14, color: textOnWhite),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Name is required'
                    : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 12),

              // Nutritional Fields (Optional, Number Inputs)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _produceCaloriesController,
                      decoration: _inputDecoration('Calories (kcal)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateOptionalNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _produceUnitGramsController,
                      decoration: _inputDecoration('Unit (g)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validateOptionalNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _produceProteinsController,
                      decoration: _inputDecoration('Proteins (g)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        _decimalInputFormatter(1)
                      ], // Allow 1 decimal place
                      validator: _validateOptionalNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _produceCarbsController,
                      decoration: _inputDecoration('Carbs (g)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalInputFormatter(1)],
                      validator: _validateOptionalNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _produceFatsController,
                      decoration: _inputDecoration('Fats (g)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalInputFormatter(1)],
                      validator: _validateOptionalNumber,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Source URL (Optional, URL Input)
              TextFormField(
                controller: _produceSourceController,
                decoration: _inputDecoration('Source URL (optional)'),
                style: const TextStyle(fontSize: 14, color: textOnWhite),
                keyboardType: TextInputType.url,
                maxLines: 1, // Keep URL field single line
                validator: (value) {
                  // Optional URL validation
                  if (value != null && value.isNotEmpty) {
                    final parsedUri = Uri.tryParse(value);
                    if (parsedUri == null || !parsedUri.isAbsolute) {
                      return 'Invalid URL format';
                    }
                  }
                  return null;
                },
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 20),

              // Action Buttons (Cancel/Save)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _cancelProduceEdit, // Cancel edit action
                    child: const Text('Cancel',
                        style: TextStyle(color: subtleText)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(isNewItem
                        ? 'Add Item'
                        : 'Save Changes'), // Dynamic button label
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: textOnTeal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _saveProduceChanges, // Save changes via API
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper for consistent InputDecoration in forms
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      isDense: true,
      labelStyle: const TextStyle(color: subtleText, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: primaryTeal),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: const BorderSide(color: primaryTeal, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(color: dividerColor.withOpacity(0.8)),
      ),
    );
  }

  // Helper for validating optional number fields
  String? _validateOptionalNumber(String? value) {
    if (value != null && value.isNotEmpty) {
      // Allow integers or decimals
      if (double.tryParse(value) == null) {
        return 'Invalid #'; // Short error message
      }
      if (double.parse(value) < 0) {
        return '>= 0'; // Must be non-negative
      }
    }
    return null; // Valid (empty or a valid non-negative number)
  }

  // Helper to create a regex formatter for decimal numbers
  TextInputFormatter _decimalInputFormatter(int decimalPlaces) {
    String dp = decimalPlaces > 0 ? '{0,$decimalPlaces}' : '';
    return FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d' + dp));
  }

  // Widget to display when a list (Orders, Produce) is empty
  Widget _buildEmptyState(String title, String subtitle,
      {required IconData icon}) {
    return Center(
      child: Padding(
        // Add padding to give space around the empty state message
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, // Take minimum vertical space
          children: [
            Icon(
              icon,
              size: 64,
              color: subtleText.withOpacity(0.5), // Muted icon color
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textOnWhite),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: subtleText),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- Order Item Card UI ---
  Widget _buildOrderItem(Order order) {
    final DateFormat dateFormat =
        DateFormat('MMM d, hh:mm a'); // Consistent date format
    final statusColor =
        _getStatusColor(order.orderStatus); // Get color based on status

    // Use Card + ExpansionTile for a collapsible order item
    return Card(
      margin: EdgeInsets.zero, // Use padding in the parent ListView instead
      elevation: 1.5,
      color: whiteColor.withOpacity(0.9), // Semi-transparent card background
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        // Add a side border colored based on status
        side: BorderSide(color: statusColor.withOpacity(0.4), width: 1),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(
            12.0, 8.0, 12.0, 8.0), // Padding for the collapsed tile
        childrenPadding:
            EdgeInsets.zero, // Padding will be added inside the children list
        expandedAlignment: Alignment.topLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: subtleText, // Color for expand/collapse icon
        collapsedIconColor: subtleText,
        // Leading: Status Icon
        leading: Tooltip(
          message: order.orderStatus, // Show status on hover/long-press
          child: CircleAvatar(
            radius: 18,
            backgroundColor: statusColor
                .withOpacity(0.15), // Faint background color based on status
            child: Icon(
              _getStatusIcon(order.orderStatus), // Get icon based on status
              color: statusColor, // Icon color based on status
              size: 18,
            ),
          ),
        ),
        // Title: Meal Name
        title: Text(
          order.mealName,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Subtitle: Order ID and Date
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3.0),
          child: Text(
            '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}', // Show local time
            style: const TextStyle(fontSize: 12, color: subtleText),
          ),
        ),
        // Trailing: Price and Quantity
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat.currency(symbol: 'UGX ', decimalDigits: 2)
                  .format(order.totalPrice), // Format price as currency
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: darkTeal, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${order.quantity} item${order.quantity > 1 ? 's' : ''}', // Pluralize 'item' correctly
              style: const TextStyle(fontSize: 11, color: subtleText),
            ),
          ],
        ),
        // Expanded Children: Order Details and Actions
        children: [
          Divider(height: 1, color: dividerColor.withOpacity(0.7)), // Separator
          Padding(
            padding: const EdgeInsets.all(12.0), // Padding for expanded content
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display various order details using a helper
                _buildOrderDetailItem(
                    'Producer',
                    order.producerName ??
                        'Unknown'), // Assuming producerName holds customer name here
                _buildOrderDetailItem('Status', order.orderStatus,
                    color: statusColor), // Show status with color
                _buildOrderDetailItem(
                    'Payment', order.paymentStatus ?? 'Unknown'),
                if (order.notes != null && order.notes!.isNotEmpty)
                  _buildOrderDetailItem('Notes', order.notes!),
                if (order.deliveryAddress != null &&
                    order.deliveryAddress!.isNotEmpty)
                  _buildOrderDetailItem('Delivery', order.deliveryAddress!),
                if (order.ingredients != null &&
                    order.ingredients!
                        .isNotEmpty) // Example: Show ingredients if available
                  _buildOrderDetailItem('Ingredients', order.ingredients!),
                const SizedBox(height: 12), // Spacing before actions
                // Action Buttons
                _buildOrderActions(order), // Build buttons based on status
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build a detail row (Label: Value) in the expanded order view
  Widget _buildOrderDetailItem(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed width label for alignment
          SizedBox(
            width: 80, // Adjust as needed
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: textOnWhite),
            ),
          ),
          // Expanded value that can wrap
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color ??
                    subtleText, // Use provided color or default subtle text
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build the action buttons for an order based on its status
  Widget _buildOrderActions(Order order) {
    List<String> availableActions = _getAvailableActions(order.orderStatus);
    if (availableActions.isEmpty) {
      return const SizedBox.shrink(); // No actions available
    }

    // Use Wrap to allow buttons to flow to the next line if needed
    return Wrap(
      spacing: 8.0, // Horizontal space between buttons
      runSpacing: 8.0, // Vertical space between button rows
      alignment: WrapAlignment.end, // Align buttons to the right
      children: availableActions.map((action) {
        bool isDestructive =
            action == 'Cancel'; // Style cancel button differently
        return ElevatedButton(
          onPressed: () =>
              _handleOrderAction(order, action), // Trigger action handler
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive
                ? destructiveButtonBackground
                : actionButtonBackground,
            foregroundColor: isDestructive
                ? destructiveButtonForeground
                : actionButtonForeground,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            elevation: 0, // Flat button style
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: Text(action),
        );
      }).toList(),
    );
  }

  // Logic to determine available actions based on current order status
  List<String> _getAvailableActions(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return ['Accept', 'Cancel'];
      case Order.STATUS_ACCEPTED:
        return ['Prepare', 'Cancel'];
      case Order.STATUS_PREPARING:
        return ['Dispatch']; // Assuming producer dispatches directly
      case Order.STATUS_DISPATCHED:
        // Maybe add "Track" or similar if tracking is implemented
        return []; // No actions typically after dispatch by producer
      case Order.STATUS_DELIVERED:
      case Order.STATUS_CANCELLED:
        return []; // No actions on completed or cancelled orders
      default:
        return []; // No actions for unknown status
    }
  }

  // --- Status Color and Icon Helpers ---
  Color _getStatusColor(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return pendingColor;
      case Order.STATUS_ACCEPTED:
        return acceptedColor;
      case Order.STATUS_PREPARING:
        return preparingColor;
      case Order.STATUS_DISPATCHED:
        return dispatchedColor;
      case Order.STATUS_DELIVERED:
        return deliveredColor;
      case Order.STATUS_CANCELLED:
        return cancelledColor;
      default:
        return defaultStatusColor;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return Icons.pending_actions_outlined;
      case Order.STATUS_ACCEPTED:
        return Icons.check_circle_outline_rounded;
      case Order.STATUS_PREPARING:
        return Icons.kitchen_outlined; // Represents preparation
      case Order.STATUS_DISPATCHED:
        return Icons.local_shipping_outlined;
      case Order.STATUS_DELIVERED:
        return Icons.done_all_rounded;
      case Order.STATUS_CANCELLED:
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline_rounded; // Icon for unknown status
    }
  }
} // End of _ProducerDash22State class
