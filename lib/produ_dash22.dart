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
import 'package:provider/provider.dart'; // Added for NotificationProvider
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/app_drawer_unified.dart' as drawer; // Use prefix
import 'package:zinzi2/cache_config.dart'; // <<< IMPORT CacheConfig
import 'package:zinzi2/notifications/notification_provider.dart'; // Added import
import 'package:zinzi2/user_cache.dart'; // <<< IMPORT UserCache
import 'package:zinzi2/signup_or_Login.dart';
import 'package:zinzi2/utils/route_observer.dart';

// --- UI Constants ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700 (Matched ChefDash)
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color faintLightTeal = Color(0xFFE0F2F1); // Teal 50
const Color darkTeal = Color(0xFF004D40); // Teal 900
const Color whiteColor = Colors.white;
const Color textOnTeal = Colors.white;
const Color textOnWhite = Color(0xFF212121);
const Color subtleText = Color(0xFF757575);
const Color cardBackground = Color(0xFFF1F8F8); // Slightly off-white teal tint
const Color errorColor = Color(0xFFD32F2F);
const Color starColor = Color(0xFFFFC107); // Amber/Gold
const Color dividerColor = Color(0xFFE0E0E0);
const Color textFieldFillColor = Color(0xFFF5F5F5); // Matched ChefDash

// Status Colors (Centralized Definition)
final Color pendingColor = Colors.orange.shade600;
final Color acceptedColor = Colors.blue.shade600;
final Color preparingColor = Colors.deepPurple.shade400;
final Color readyForPickupColor = Colors.blueAccent; // Matched ChefDash
final Color assignedColor = Colors.blueGrey.shade600; // For assigned rider
final Color dispatchedColor = primaryTeal; // For dispatched/shipped
final Color outForDeliveryColor = Colors.purple.shade500; // Matched ChefDash
final Color deliveredColor = Colors.green.shade600;
final Color completedColor = Colors.green.shade700; // Slightly darker green
final Color cancelledColor = Colors.red.shade600;
final Color defaultStatusColor = Colors.grey.shade600;

const Color actionButtonBackground = Color(0xFFE0F2F1); // Faint light teal
const Color actionButtonForeground = darkTeal;
const Color destructiveButtonBackground = Color(0xFFFFEBEE); // Light red
const Color destructiveButtonForeground = Color(0xFFC62828); // Darker red
const String placeholderImagePath =
    'assets/images/placeholder_avatar.png'; // Ensure this asset exists

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

// --- Data Models ---

// Order Model (Unified)
class Order {
  final int orderId;
  final String mealName; // Product name
  final DateTime orderDate;
  final double totalPrice; // Use double for price
  final int quantity;
  String orderStatus; // Mutable
  final String? customerName; // Customer (from Producer or Customer field)
  final String? deliveryAddress;
  final String? notes;
  final String? ingredients; // Added from original
  final String? paymentStatus;
  int? assignedRiderId;
  String? assignedRiderName;

  Order({
    required this.orderId,
    required this.mealName,
    required this.orderDate,
    required this.totalPrice,
    required this.quantity,
    required this.orderStatus,
    this.customerName,
    this.deliveryAddress,
    this.notes,
    this.ingredients,
    this.paymentStatus,
    this.assignedRiderId,
    this.assignedRiderName,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    // Normalize status: always trim and lowercase for consistency
    String orderStatus = (json['order_status'] != null)
        ? (json['order_status'] as String).trim().toLowerCase()
        : '';
    DateTime parsedDate;
    try {
      // Prioritize standard ISO 8601 parsing first
      parsedDate = DateTime.parse(json['order_date'] as String);
    } catch (e) {
      // Fallback for Flask's default format if ISO fails
      try {
        final apiDateFormat =
            DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
        parsedDate =
            apiDateFormat.parseUtc(json['order_date'] as String).toLocal();
      } catch (e2) {
        print(
            "[ProducerDash] Error parsing date: ${json['order_date']} - $e - $e2. Using current time.");
        parsedDate = DateTime.now(); // Final fallback
      }
    }

    try {
      final order = Order(
        orderId: _parseInt(json['order_id']),
        mealName: _getStringSafe(json['product_name']) ?? 'Unknown Product',
        orderDate: parsedDate,
        totalPrice: _parseDouble(json['total_price']),
        quantity: _parseInt(json['quantity']),
        orderStatus:
            _getStringSafe(json['order_status']) ?? Order.STATUS_PENDING,
        paymentStatus: _getStringSafe(json['payment_status']),
        notes: _getStringSafe(json['notes']),
        deliveryAddress: _getStringSafe(json['delivery_address']),
        // Prefer customer_name if available, fallback to producer_name
        customerName: _getStringSafe(json['customer_name']) ??
            _getStringSafe(json['producer_name']),
        ingredients: _getStringSafe(json['ingredients']),
        assignedRiderId: _parseIntNullable(json['assigned_rider_id'] ??
            json['transporter_id']), // Check multiple keys
        assignedRiderName: _getStringSafe(json['assigned_rider_name']),
      );
      return order;
    } catch (e, stack) {
      print('[ProducerDash] Order parsing error: $e\n$stack');
      rethrow;
    }
  }

  Order copyWith({
    int? orderId,
    String? mealName,
    DateTime? orderDate,
    double? totalPrice,
    int? quantity,
    String? orderStatus,
    String? customerName,
    String? deliveryAddress,
    String? notes,
    String? ingredients,
    String? paymentStatus,
    ValueGetter<int?>? assignedRiderId,
    ValueGetter<String?>? assignedRiderName,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      mealName: mealName ?? this.mealName,
      orderDate: orderDate ?? this.orderDate,
      totalPrice: totalPrice ?? this.totalPrice,
      quantity: quantity ?? this.quantity,
      orderStatus: orderStatus ?? this.orderStatus,
      customerName: customerName ?? this.customerName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      notes: notes ?? this.notes,
      ingredients: ingredients ?? this.ingredients,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      assignedRiderId:
          assignedRiderId != null ? assignedRiderId() : this.assignedRiderId,
      assignedRiderName: assignedRiderName != null
          ? assignedRiderName()
          : this.assignedRiderName,
    );
  }

  // Standardized Status Constants (Ensure these match API expectations)
  static const String STATUS_PENDING = 'Pending';
  static const String STATUS_ACCEPTED = 'Accepted';
  static const String STATUS_PREPARING = 'Preparing';
  static const String STATUS_READY_FOR_PICKUP = 'Ready for Pickup';
  static const String STATUS_ASSIGNED = 'Assigned';
  static const String STATUS_DISPATCHED = 'Dispatched'; // Rider picks up
  static const String STATUS_OUT_FOR_DELIVERY =
      'Out for Delivery'; // Rider delivering
  static const String STATUS_DELIVERED = 'Delivered'; // Rider confirms
  static const String STATUS_COMPLETED = 'Completed'; // Final state
  static const String STATUS_CANCELLED = 'Cancelled';
}

// ProducerProfile Model (Unified)
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
  final String? reviews; // Changed from int to String
  final String? userType;
  final bool? isEmailVerified;
  final List<Map<String, dynamic>>?
      stock; // [{"produce_id": "...", "quantity": ...}]
  File? localImageFile; // For editing

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

  // Used for saving to cache
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
      // Convert stock to JSON string if API expects string, otherwise keep as list
      'stock': stock,
    };
  }

  // Used for sending updates to API
  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'phone_number': phoneNumber,
      'location': location,
      // Image handled separately
      'is_active': isActive, // Include status in update? Or separate endpoint?
      // Other fields like producerType, rating, reviews likely not updated here
      'stock': stock, // Include updated stock list
    }..removeWhere((key, value) => value == null);
  }

  factory ProducerProfile.fromJson(Map<String, dynamic> json) {
    try {
      // Helper to parse stock robustly
      List<Map<String, dynamic>>? parseStock(dynamic value) {
        if (value == null) return null;
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is List) {
              return decoded.whereType<Map<String, dynamic>>().toList();
            }
          } catch (e) {
            print("[ProducerDash] Error decoding stock JSON string: $e");
          }
        } else if (value is List) {
          return value.whereType<Map<String, dynamic>>().toList();
        }
        print(
            "[ProducerDash] Warning: Unexpected stock format: ${value.runtimeType}. Returning null.");
        return null;
      }

      DateTime? parseDate(String? dateString) {
        if (dateString == null || dateString.isEmpty) return null;
        try {
          return DateTime.parse(dateString);
        } catch (e) {
          print("[ProducerDash] Error parsing date string '$dateString': $e");
          return null;
        }
      }

      final profile = ProducerProfile(
        producerId: _parseInt(json['producer_id']),
        name: _getStringSafe(json['name']) ?? 'Unknown Producer',
        email: _getStringSafe(json['email']),
        phoneNumber: _getStringSafe(json['phone_number']),
        location: _getStringSafe(json['location']),
        image: _getStringSafe(json['image']),
        isActive: _parseBoolSafe(json['is_active']),
        registrationDate:
            parseDate(json['registration_date']) ?? DateTime.now(), // Fallback
        lastLogin: parseDate(json['last_login']),
        producerType: _getStringSafe(json['producer_type']),
        rating: _parseDoubleNullable(json['rating']),
        reviews: _getStringSafe(json['reviews']), // Parse reviews as string
        userType: _getStringSafe(json['user_type']),
        isEmailVerified: _parseBoolSafe(json['is_email_verified']),
        stock: parseStock(json['stock']),
      );
      return profile;
    } catch (e, stack) {
      print('[ProducerDash] Profile parsing error: $e\n$stack');
      rethrow;
    }
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
    ValueGetter<String?>? reviews, // Use String? getter
    String? userType,
    bool? isEmailVerified,
    ValueGetter<List<Map<String, dynamic>>?>? stock,
    ValueGetter<File?>? localImageFile, // Allow updating local file
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
      localImageFile:
          localImageFile != null ? localImageFile() : this.localImageFile,
    );
  }
}

// Product Model (Unified)
class Product {
  final String produceId; // Ensure this is the primary key from API
  final String produceName;
  final int? calories;
  final double? carbohydrates;
  final double? fats;
  final double? proteins;
  final int? unitGrams;
  final String? source; // E.g., URL for nutritional info

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
    try {
      // Use 'produce_id' as the primary identifier
      final produceId = _getStringSafe(json['produce_id']);
      if (produceId == null || produceId.isEmpty) {
        throw FormatException(
            "Missing or invalid 'produce_id' in Product JSON: $json");
      }

      final product = Product(
        produceId: produceId,
        produceName: _getStringSafe(json['produce_name']) ??
            '', // Ensure name is not null
        calories: _parseIntNullable(json['calories']),
        carbohydrates: _parseDoubleNullable(json['carbohydrates']),
        fats: _parseDoubleNullable(json['fats']),
        proteins: _parseDoubleNullable(json['proteins']),
        unitGrams: _parseIntNullable(json['unit_grams']),
        source: _getStringSafe(json['source']),
      );
      return product;
    } catch (e, stack) {
      print('[ProducerDash] Product parsing error: $e\n$stack');
      rethrow; // Re-throw to indicate parsing failure
    }
  }

  Product copyWith({
    String? produceId,
    String? produceName,
    ValueGetter<int?>? calories,
    ValueGetter<double?>? carbohydrates,
    ValueGetter<double?>? fats,
    ValueGetter<double?>? proteins,
    ValueGetter<int?>? unitGrams,
    ValueGetter<String?>? source,
  }) {
    return Product(
      produceId: produceId ?? this.produceId,
      produceName: produceName ?? this.produceName,
      calories: calories != null ? calories() : this.calories,
      carbohydrates:
          carbohydrates != null ? carbohydrates() : this.carbohydrates,
      fats: fats != null ? fats() : this.fats,
      proteins: proteins != null ? proteins() : this.proteins,
      unitGrams: unitGrams != null ? unitGrams() : this.unitGrams,
      source: source != null ? source() : this.source,
    );
  }
}

// Rider/Transporter Model (Unified)
class Rider {
  final int id;
  final String name;
  final String
      status; // Original status string from API (e.g., 'available', 'busy')
  final bool
      isActive; // Derived boolean for simpler UI logic (e.g., from 'is_active' field or status string)

  Rider({
    required this.id,
    required this.name,
    required this.status,
    required this.isActive,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    // Prefer specific rider/transporter keys, fallback to generic 'id'/'name'
    final riderId = _parseIntNullable(
        json['rider_id'] ?? json['transporter_id'] ?? json['id']);
    final riderName = _getStringSafe(
        json['name'] ?? json['rider_name'] ?? json['transporter_name']);

    if (riderId == null || riderId == 0) {
      print(
          "[ProducerDash] Warning: Rider ID is missing or invalid in JSON: $json");
      // Optionally throw an error or return a default/placeholder Rider
      // For now, defaulting to ID 0 and handling it later if needed
    }

    return Rider(
      id: riderId ?? 0, // Default to 0 if null
      name: riderName ?? 'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown',
      // Use _parseBoolSafe for robust boolean parsing from 'is_active' field
      isActive: _parseBoolSafe(json['is_active']),
    );
  }
}

// --- Unified API Service ---
class ProducerApiService {
  // Use a static final getter for the base URL
  static final String _apibaseurl =
      dotenv.env['API_BASE_URL-intranet'] ?? 'https://your-api.example.com';

  // Helper to get Producer ID from SharedPreferences
  static Future<String?> _getProducerId() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to get producer_id as string first, fall back to int for backward compatibility
    return prefs.getString('producer_id') ??
        prefs.getInt('producer_id')?.toString();
  }

  // Helper to get Producer ID from SharedPreferences
  static Future<int?> _getProducerIdInt() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to get producer_id as string first, fall back to int for backward compatibility
    return _parseInt(prefs.getString('producer_id')) ??
        prefs.getInt('producer_id');
  }

  // Handles nested 'data' key or direct list/map, more robustly
  static dynamic _handleApiResponse(dynamic responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded.containsKey('data')) {
        return decoded['data']; // Prioritize nested 'data'
      }
      // Return the decoded body directly if it's a list or map (and no 'data' key)
      if (decoded is List || decoded is Map) {
        return decoded;
      }
      print(
          "[ProducerDash] API response format warning: Decoded type is ${decoded.runtimeType}");
      return null; // Indicate unexpected decoded format
    } catch (e) {
      print("[ProducerDash] API response JSON decoding error: $e");
      return null; // Indicate decoding failure
    }
  }

  // Standard Read Headers
  static Future<Map<String, String>> _getReadHeaders(
      {bool requiresAuth = false}) async {
    Map<String, String> headers = {'Accept': 'application/json'};
    if (requiresAuth) {
      // Allow read headers to also carry auth if needed
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        print(
            "[ProducerDash] Warning: Auth required for read but no access token found.");
      }
    }
    return headers;
  }

  // Standard Write Headers (with optional auth)
  static Future<Map<String, String>> _getWriteHeaders(
      {bool requiresAuth = true}) async {
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
        print(
            "[ProducerDash] Warning: Auth required but no access token found.");
      }
    }
    return headers;
  }

  // --- Profile Methods ---
  static Future<ProducerProfile> fetchProducerProfile() async {
    final producerId = await _getProducerId();
    if (producerId == null) {
      // Log the error for debugging
      print('[ProducerDash] No producer ID found in SharedPreferences');
      // Show more detailed error message
      throw Exception(
          'Producer session expired or not logged in. Please log in again.');
    }

    print('[ProducerDash] Using producer ID: $producerId');

    // Using /rr/rproducers/{id} - assuming 'r' prefix means 'read'
    final Uri uri = Uri.parse('$_apibaseurl/rr/rproducers/$producerId');
    print("[ProducerDash] Fetching profile: $uri");

    try {
      // Assuming profile fetch might need auth, pass requiresAuth: true
      final response = await http.get(uri,
          headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);

        Map<String, dynamic>? profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          // API might return list containing one producer object
          if (handledData[0] is Map<String, dynamic>) {
            profileMap = handledData[0];
          } else {
            throw Exception('API response list item is not a valid map.');
          }
        } else if (handledData is Map<String, dynamic>) {
          // API might return the producer object directly
          if (handledData.containsKey('producer_id')) {
            // Check for a key field
            profileMap = handledData;
          } else {
            throw Exception(
                'API response map missing expected keys for profile. Body: ${response.body}');
          }
        }

        if (profileMap == null) {
          throw Exception(
              'Producer profile not found or invalid format in API response. Body: ${response.body}');
        }
        return ProducerProfile.fromJson(profileMap);
      } else {
        throw Exception(
            'Failed to fetch producer profile (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print('[ProducerDash] Profile fetch error: $e\n$stack');
      rethrow;
    }
  }

  // Update Producer Active Status
  static Future<bool> updateProducerStatus(
      int producerId, bool isActive) async {
    // Using PATCH /rr/producers/{id}/status - assuming this endpoint exists
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId/status');
    print(
        "[ProducerDash] Updating status for $producerId to $isActive at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
        body: jsonEncode({'is_active': isActive}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Error updating producer status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating producer status: $e");
      return false;
    }
  }

  // Update Producer Profile Text Fields
  static Future<bool> updateProducerProfile(int producerId,
      {required String name, String? phoneNumber, String? location}) async {
    // Using PUT or PATCH to /rr/producers/{id} - Assuming partial updates allowed with PATCH
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId');
    print("[ProducerDash] Updating profile for $producerId at $uri");
    Map<String, dynamic> payload = {
      'name': name, // Name is required
      if (phoneNumber != null && phoneNumber.isNotEmpty)
        'phone_number': phoneNumber,
      if (location != null && location.isNotEmpty) 'location': location,
    };
    payload.removeWhere((key, value) => value == null); // Clean payload
    print("[ProducerDash] Update payload: ${jsonEncode(payload)}");
    try {
      final response = await http.patch(
        // Use PATCH for partial update
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Error updating producer profile: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating producer profile: $e");
      return false;
    }
  }

  // Update Producer Profile Image (Placeholder - requires backend implementation)
  static Future<String?> updateProducerProfileImage(
      int producerId, File imageFile) async {
    // This needs a backend endpoint that accepts multipart/form-data
    final Uri uri = Uri.parse(
        '$_apibaseurl/rr/producers/$producerId/image'); // Example endpoint
    print("[ProducerDash] Uploading profile image for $producerId to $uri");

    try {
      var request = http.MultipartRequest('POST', uri); // Or PUT/PATCH
      request.headers.addAll(await _getWriteHeaders()); // Add auth headers
      request.files.add(await http.MultipartFile.fromPath(
        'profile_image', // Field name expected by backend
        imageFile.path,
        // contentType: MediaType('image', 'jpeg'), // Optional: Specify content type
      ));
      // request.fields['producer_id'] = producerId.toString(); // Add other fields if needed

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        // Extract the new image URL from the response (adjust key as needed)
        final newImageUrl = responseData['imageUrl'] ?? responseData['image'];
        print("[ProducerDash] Image upload successful. New URL: $newImageUrl");
        return newImageUrl;
      } else {
        print(
            "[ProducerDash] Error uploading image: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("[ProducerDash] Exception uploading image: $e");
      return null;
    }
  }

  // --- Order Methods ---
  static Future<List<Order>> fetchProducerOrders() async {
    final producerId = await _getProducerId();
    if (producerId == null) {
      throw Exception('Producer ID not found. Please log in again.');
    }
    // Using GET /rr/orders?producer_id={id} - common pattern for filtering
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders?producer_id=$producerId');
    print("[ProducerDash] Fetching orders: $uri");
    try {
      // Assuming orders fetch needs auth
      final response = await http.get(uri,
          headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Order> orders = handledData
              .map<Order>((orderJson) => Order.fromJson(orderJson))
              .toList();
          print("[ProducerDash] Fetched ${orders.length} orders");
          return orders;
        } else {
          print(
              '[ProducerDash] Orders response format error: expected List, got ${handledData?.runtimeType}. Response body: ${response.body}');
          // FIX: Throw exception instead of returning empty list on format error
          throw Exception(
              'API response for orders was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception(
            'Failed to load orders (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print('[ProducerDash] Orders fetch error: $e\n$stack');
      rethrow;
    }
  }

  // Update Order Status (Simple: Accept, Prepare, Cancel, Ready for Pickup)
  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    // Using PATCH /rr/orders/{id}/status
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    print(
        "[ProducerDash] Updating order $orderId status to $newStatus at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: await _getWriteHeaders(),
        body: jsonEncode({'order_status': newStatus}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Order status update failed: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Order status update error: $e");
      return false;
    }
  }

  // Assign Order to Specific Rider
  static Future<bool> assignOrderToRider(
      int orderId, int riderId, String newStatus) async {
    // Using PATCH /rr/orders/{id}/status, sending rider ID
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    print(
        "[ProducerDash] Assigning order $orderId to rider $riderId, status $newStatus at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: await _getWriteHeaders(),
        body: jsonEncode(<String, dynamic>{
          'order_status': newStatus,
          'transporter_id': riderId, // Key for rider ID
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Error assigning order: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception assigning order: $e");
      return false;
    }
  }

  // --- Rider Methods ---
  static Future<List<Rider>> fetchAvailableRiders() async {
    // Using GET /rr/transporters - assumes this returns all riders/transporters
    final Uri uri = Uri.parse('$_apibaseurl/rr/transporters');
    print("[ProducerDash] Fetching available riders from: $uri");
    try {
      // Assuming riders fetch needs auth
      final response = await http.get(uri,
          headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Rider> riders = handledData
              .map<Rider?>((jsonItem) {
                // Use Rider? to handle parsing errors gracefully
                try {
                  return Rider.fromJson(jsonItem);
                } catch (e) {
                  print(
                      "[ProducerDash] Skipping invalid rider item: $jsonItem - Error: $e");
                  return null; // Skip item if parsing fails
                }
              })
              .whereType<Rider>() // Filter out nulls
              .toList();
          print("[ProducerDash] Fetched ${riders.length} riders.");
          return riders;
        } else {
          print(
              "[ProducerDash] Riders API response format unexpected: Expected List, got ${handledData?.runtimeType}. Response body: ${response.body}");
          // FIX: Throw exception instead of returning empty list on format error
          throw Exception(
              'API response for riders was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception(
            'Failed to load riders (Status code: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print("[ProducerDash] Exception fetching riders: $e\n$stack");
      rethrow;
    }
  }

  // --- Produce and Stock Methods ---
  static Future<List<Product>> fetchProducerProduce() async {
    // GET /rr/produce - fetches MASTER list of all produce items
    final Uri uri = Uri.parse('$_apibaseurl/rr/produce');
    print("[ProducerDash] Fetching master produce list: $uri");
    try {
      // Assuming produce list might need auth
      final response = await http.get(uri,
          headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Product> produce = handledData
              .map<Product>((prodJson) => Product.fromJson(prodJson))
              .toList();
          print(
              "[ProducerDash] Fetched ${produce.length} produce items from master list.");
          return produce;
        } else {
          print(
              '[ProducerDash] Produce response format error: expected List, got ${handledData?.runtimeType}. Response body: ${response.body}');
          // FIX: Throw exception instead of returning empty list on format error
          throw Exception(
              'API response for produce was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception(
            'Failed to fetch produce (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print('[ProducerDash] Produce fetch error: $e\n$stack');
      rethrow;
    }
  }

  // Update Producer's Stock List
  static Future<bool> updateProducerStock(
      int producerId, List<Map<String, dynamic>> stockList) async {
    // PATCH /rr/producers/{id} - Updating the 'stock' field
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId');
    print("[ProducerDash] Updating stock for producer $producerId at $uri");
    // API expects {"stock": [{"produce_id": "...", "quantity": ...}, ...]}
    final payload = jsonEncode({"stock": stockList});
    print("[ProducerDash] Stock update payload: $payload");
    try {
      final response = await http.patch(
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
        body: payload,
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print("Stock update failed: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Exception updating stock: $e");
      return false;
    }
  }

  // Add New Produce Item to Master List
  static Future<Product?> addProduce(Map<String, dynamic> produceData) async {
    // POST /rr/produce
    final Uri uri = Uri.parse('$_apibaseurl/rr/produce');
    print("[ProducerDash] Adding new produce item at $uri");
    try {
      // Prepare payload, parsing types safely
      final payload = {
        'produce_name': _getStringSafe(produceData['produce_name']),
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': _getStringSafe(produceData['source']),
      };
      payload.removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty));

      if (payload['produce_name'] == null ||
          (payload['produce_name'] as String).isEmpty) {
        print("[ProducerDash] Error adding produce: Produce name is required.");
        return null;
      }
      print("[ProducerDash] Add produce payload: ${jsonEncode(payload)}");

      final response = await http.post(
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        // Expect 201 Created
        final dynamic createdProduceData = _handleApiResponse(response.body);
        if (createdProduceData is Map<String, dynamic>) {
          return Product.fromJson(createdProduceData);
        } else {
          print(
              "[ProducerDash] Add produce succeeded but couldn't parse response body: ${response.body}");
          return null;
        }
      } else {
        print(
            "[ProducerDash] Error adding produce: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("[ProducerDash] Exception adding produce: $e");
      return null;
    }
  }

  // Update Existing Produce Item in Master List
  static Future<bool> updateProduce(
      String produceId, Map<String, dynamic> produceData) async {
    if (produceId.isEmpty) {
      print("[ProducerDash] Error updating produce: Invalid Produce ID.");
      return false;
    }
    // PUT /rr/uproduce?produce_id={id} - Endpoint from original code
    final Uri uri = Uri.parse('$_apibaseurl/rr/uproduce?produce_id=$produceId');
    print("[ProducerDash] Updating produce item $produceId at $uri");
    try {
      // Prepare payload similar to addProduce
      final payload = {
        'produce_name': _getStringSafe(produceData['produce_name']),
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': _getStringSafe(produceData['source']),
      };
      payload.removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty));

      if (payload['produce_name'] == null ||
          (payload['produce_name'] as String).trim().isEmpty) {
        print(
            "[ProducerDash] Error updating produce: Produce name cannot be empty.");
        return false;
      }
      print("[ProducerDash] Update produce payload: ${jsonEncode(payload)}");

      final response = await http.put(
        // Using PUT as per original endpoint structure
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Error updating produce $produceId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating produce $produceId: $e");
      return false;
    }
  }

  // Delete Produce Item from Master List
  static Future<bool> deleteProduce(String produceId) async {
    if (produceId.isEmpty) {
      print("[ProducerDash] Error deleting produce: Invalid Produce ID.");
      return false;
    }
    // DELETE /rr/uproduce?produce_id={id} - Endpoint from original code
    final Uri uri = Uri.parse('$_apibaseurl/rr/uproduce?produce_id=$produceId');
    print("[ProducerDash] Deleting produce item $produceId at $uri");
    try {
      final response = await http.delete(
        uri,
        headers: await _getWriteHeaders(), // Assumes auth needed
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        print(
            "[ProducerDash] Error deleting produce $produceId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception deleting produce $produceId: $e");
      return false;
    }
  }
}

// --- Main Widget State ---
class ProducerDash22 extends StatefulWidget {
  // Helper for serializing Order for cache (since Order may not have toJson)
  static Map<String, dynamic> _serializeOrder(dynamic order) {
    if (order == null) return {};
    // Try toJson if it exists
    if (order is Map<String, dynamic>) return order;
    if (order is Order) {
      // Check specific type
      // Manually construct JSON from Order properties
      return {
        'order_id': order.orderId,
        'product_name': order.mealName, // Match JSON key from Order.fromJson
        'order_date': order.orderDate.toIso8601String(),
        'total_price': order.totalPrice,
        'quantity': order.quantity,
        'order_status': order.orderStatus,
        'customer_name': order.customerName,
        'delivery_address': order.deliveryAddress,
        'notes': order.notes,
        'ingredients': order.ingredients,
        'payment_status': order.paymentStatus,
        'assigned_rider_id': order.assignedRiderId,
        'assigned_rider_name': order.assignedRiderName,
      };
    }
    if (order is dynamic && order.toJson != null) {
      try {
        return order.toJson();
      } catch (_) {}
    }
    // Fallback if not Order or doesn't have toJson (less ideal)
    print(
        "[ProducerDash] Warning: Could not serialize order of type ${order.runtimeType}");
    return {}; // Or throw error
  }

  // Helper for serializing Product for cache (since Product may not have toJson)
  static Map<String, dynamic> _serializeProduct(dynamic product) {
    if (product == null) return {};
    if (product is Map<String, dynamic>) return product;
    if (product is Product) {
      // Check specific type
      // Manually construct JSON from Product properties
      return {
        'produce_id': product.produceId,
        'produce_name': product.produceName,
        'calories': product.calories,
        'carbohydrates': product.carbohydrates,
        'fats': product.fats,
        'proteins': product.proteins,
        'unit_grams': product.unitGrams,
        'source': product.source,
      };
    }
    if (product is dynamic && product.toJson != null) {
      try {
        return product.toJson();
      } catch (_) {}
    }
    print(
        "[ProducerDash] Warning: Could not serialize product of type ${product.runtimeType}");
    return {};
  }

  /// Preload producer dashboard cache for splash screen (no UI, no context needed)
  static Future<void> preloadCacheForSplash() async {
    // --- Profile Cache ---
    const String profileKey = 'producer_profile';
    const String profileTsKey = 'producer_profile_cache_timestamp';
    const String ordersKey = 'producer_orders';
    const String ordersTsKey = 'producer_orders_cache_timestamp';
    const String produceKey = 'producer_produce';
    const String produceTsKey = 'producer_produce_cache_timestamp';
    final now = DateTime.now();

    // --- Profile ---
    final cachedProfile = await UserCache.getData(profileKey);
    final cachedProfileTs = await UserCache.getData(profileTsKey);
    bool profileCacheValid = false;
    if (cachedProfile != null && cachedProfileTs != null) {
      final cacheTime =
          DateTime.tryParse(cachedProfileTs as String); // Ensure cast
      if (cacheTime != null && now.difference(cacheTime).inMinutes < 15) {
        profileCacheValid = true;
      }
    }
    if (!profileCacheValid) {
      try {
        final profile = await ProducerApiService.fetchProducerProfile();
        await UserCache.saveData(profileKey, profile.toJson());
        await UserCache.saveData(profileTsKey, now.toIso8601String());
      } catch (e) {
        print('[Splash][ProducerDash] profile preload error: $e');
      }
    } else {
      print(
          '[Splash][ProducerDash] profile preload skipped: Cache still valid.');
    }

    // --- Orders ---
    final cachedOrders = await UserCache.getData(ordersKey);
    final cachedOrdersTs = await UserCache.getData(ordersTsKey);
    bool ordersCacheValid = false;
    if (cachedOrders is List && cachedOrdersTs is String) {
      final cacheTime = DateTime.tryParse(cachedOrdersTs);
      if (cacheTime != null && now.difference(cacheTime).inMinutes < 15) {
        ordersCacheValid = true;
      }
    }
    if (!ordersCacheValid) {
      try {
        final orders = await ProducerApiService.fetchProducerOrders();
        final ordersJson = orders.map((o) => _serializeOrder(o)).toList();
        await UserCache.saveData(ordersKey, ordersJson);
        await UserCache.saveData(ordersTsKey, now.toIso8601String());
      } catch (e) {
        print('[Splash][ProducerDash] orders preload error: $e');
      }
    } else {
      print(
          '[Splash][ProducerDash] orders preload skipped: Cache still valid.');
    }

    // --- Produce ---
    final cachedProduce = await UserCache.getData(produceKey);
    final cachedProduceTs = await UserCache.getData(produceTsKey);
    bool produceCacheValid = false;
    if (cachedProduce is List && cachedProduceTs is String) {
      final cacheTime = DateTime.tryParse(cachedProduceTs);
      if (cacheTime != null && now.difference(cacheTime).inMinutes < 15) {
        produceCacheValid = true;
      }
    }
    if (!produceCacheValid) {
      try {
        final produce = await ProducerApiService.fetchProducerProduce();
        final produceJson = produce.map((p) => _serializeProduct(p)).toList();
        await UserCache.saveData(produceKey, produceJson);
        await UserCache.saveData(produceTsKey, now.toIso8601String());
      } catch (e) {
        print('[Splash][ProducerDash] produce preload error: $e');
      }
    } else {
      print(
          '[Splash][ProducerDash] produce preload skipped: Cache still valid.');
    }
  }

  const ProducerDash22({super.key});

  @override
  State<ProducerDash22> createState() => _ProducerDash22State();
}

class _ProducerDash22State extends State<ProducerDash22> with WidgetsBindingObserver, RouteAware {
  // --- State fields ---
  int _currentIndex = 0;
  ProducerProfile? _profile;
  List<Order> _orders = [];
  List<Product> _produce = []; // Holds the MASTER list of all produce items
  // Rider list not stored globally, fetched on demand by dialog
  bool _isLoading = true; // Combined loading for initial fetch
  bool _isLoadingProfile = false;
  bool _isLoadingOrders = false;
  bool _isLoadingProduce = false;
  String _error = ''; // General error message for combined fetch
  String _profileFetchError = '';

  // Stock Management State
  Set<String> _selectedProduceIds = {};
  Map<String, int> _produceQuantities = {};

  // Profile Editing State
  bool _isEditingProfile = false;
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  late TextEditingController _profileLocationController;
  bool _isLoadingLocation = false;
  bool _isUploadingProfileImage = false;
  String?
      _uploadedProfileImageUrl; // Only used if upload returns URL immediately

  // Produce Item Editing State
  String? _editingProduceId;
  TextEditingController? _produceNameController;
  TextEditingController? _produceCaloriesController;
  TextEditingController? _produceProteinsController;
  TextEditingController? _produceCarbsController;
  TextEditingController? _produceFatsController;
  TextEditingController? _produceUnitGramsController;
  TextEditingController? _produceSourceController;

  // Caching State (In-memory for simplicity, persistence done via ApiService methods)
  ProducerProfile? _profileCache;
  DateTime? _profileCacheTimestamp;

  // Form Keys
  final GlobalKey<FormState> _produceFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();

  // Polling & State Management
  Timer? _pollingTimer;
  bool _isRefreshing = false; // Tracks manual refresh or polling refresh
  bool _isRouteActive = false; // Tracks if the current route is active

  // Notification Provider (Added)
  late final NotificationProvider notificationProvider;

  @override
  void initState() {
    super.initState();
    // Initialize text controllers
    _profileNameController = TextEditingController();
    _profilePhoneController = TextEditingController();
    _profileLocationController = TextEditingController();

    // Get notification provider instance
    notificationProvider =
        Provider.of<NotificationProvider>(context, listen: false);
        
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initial data fetch
    _fetchAllData();

    // Initial route check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isRouteActive = ModalRoute.of(context)?.isCurrent ?? false;
        if (_currentIndex == 1 && _isRouteActive) {
          _startPolling();
        }
      }
    });

    // Listen for notification refreshes
    notificationProvider.addListener(_handleNotificationRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      final routeObserver = RouteObserverProvider.of(context);
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _updateRouteStatus(true);
  }

  @override
  void didPopNext() {
    _updateRouteStatus(true);
  }
  
  @override
  void didPushNext() {
    _updateRouteStatus(false);
  }
  
  @override
  void didPop() {
    _updateRouteStatus(false);
  }
  
  void _updateRouteStatus(bool isActive) {
    if (!mounted) return;
    
    setState(() {
      _isRouteActive = isActive;
    });
    
    if (isActive && _currentIndex == 1) {
      _startPolling();
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  @override
  void dispose() {
    // Cancel any active polling
    _pollingTimer?.cancel();
    
    // Dispose controllers
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _profileLocationController.dispose();
    _disposeProduceEditControllers();

    // Remove notification listener
    notificationProvider.removeListener(_handleNotificationRefresh);
    
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
  
  // Route handling methods are implemented above
  
  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to the foreground
      if (_isRouteActive && _currentIndex == 1) {
        _startPolling();
        // Do an immediate fetch to get fresh data
        _fetchOrdersAndProduce();
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to the background
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  // Handles refresh triggered by notification
  void _handleNotificationRefresh() {
    print("[ProducerDash] Received notification refresh trigger.");
    if (!_isRefreshing && mounted) {
      _fetchAllData(forceRefresh: true); // Force refresh data on notification
    }
  }

  // Starts the periodic timer for fetching orders
  // Handle tab changes to control polling
  void _onTabChanged(int newIndex) {
    setState(() {
      _currentIndex = newIndex;
    });
    
    if (newIndex == 1 && _isRouteActive) {
      // Switched to orders tab and route is active
      _startPolling();
    } else {
      // Switched away from orders tab or route is not active
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  void _startPolling() {
    // Don't start polling if not on orders tab or route is not active
    if (_currentIndex != 1 || !_isRouteActive) {
      return;
    }
    
    // Cancel any existing timer
    _pollingTimer?.cancel();
    
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // Only poll if:
      // 1. Widget is still mounted
      // 2. On orders tab
      // 3. Route is currently active
      // 4. Not currently editing profile or produce
      // 5. Not already refreshing
      if (mounted && 
          _currentIndex == 1 && 
          _isRouteActive &&
          !_isEditingProfile &&
          !_isRefreshing &&
          _editingProduceId == null) {
        print("[ProducerDash] Polling for new orders...");
        _fetchOrdersAndProduce(forceRefresh: false);
      } else if (!_isRouteActive || _currentIndex != 1) {
        // If we're no longer on the orders tab or route is not active, stop polling
        timer.cancel();
      }
    });
    
    print("[ProducerDash] Started polling for orders");
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

  // --- Data Fetching and Initialization ---
  Future<void> _fetchAllData({bool forceRefresh = false}) async {
    if (!mounted || _isRefreshing) return; // Prevent concurrent refreshes
    setState(() {
      _isLoading = true; // Show combined loading indicator
      _isRefreshing = true; // Mark as refreshing
      _error = '';
      if (forceRefresh) {
        _cancelAllEdits(); // Cancel edits only on forced manual refresh
      }
    });

    try {
      await Future.wait([
        _initializeProducerProfile(forceRefresh: forceRefresh),
        _fetchOrdersAndProduce(forceRefresh: forceRefresh),
      ]);
      if (mounted) {
        _syncSelectionFromProfile(); // Sync stock after data is loaded
      }
    } catch (e, stackTrace) {
      debugPrint("[ProducerDash] Error fetching all data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _error = 'Failed to load data. Please check connection.';
          // Clear potentially stale data on major error
          _profile = null;
          _orders = [];
          _produce = [];
          _selectedProduceIds.clear();
          _produceQuantities.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // Hide combined indicator
          _isRefreshing = false; // Refresh complete
        });
      }
    }
  }

  // Fetches Orders and Produce (Master List)
  Future<void> _fetchOrdersAndProduce({bool forceRefresh = false}) async {
    // --- Cache Keys ---
    const String ordersKey = 'producer_orders';
    const String ordersTsKey = 'producer_orders_cache_timestamp';
    const String produceKey = 'producer_produce';
    const String produceTsKey = 'producer_produce_cache_timestamp';
    final now = DateTime.now();

    if (mounted) {
      setState(() {
        _isLoadingOrders = true;
        _isLoadingProduce = true;
      });
    }

    bool loadedFromCache = false;
    List<Order>? cachedOrdersData;
    List<Product>? cachedProduceData;

    // 1. Load from cache unless forcing refresh
    if (!forceRefresh) {
      final cachedOrdersJson = await UserCache.getData(ordersKey);
      final cachedOrdersTs = await UserCache.getData(ordersTsKey);
      final cachedProduceJson = await UserCache.getData(produceKey);
      final cachedProduceTs = await UserCache.getData(produceTsKey);
      bool ordersCacheValid = false, produceCacheValid = false;

      if (cachedOrdersJson is List && cachedOrdersTs is String) {
        final cacheTime = DateTime.tryParse(cachedOrdersTs);
        if (cacheTime != null) {
          try {
            cachedOrdersData = (cachedOrdersJson)
                .map((orderJson) =>
                    Order.fromJson(orderJson as Map<String, dynamic>))
                .toList();
            ordersCacheValid = true;
          } catch (e) {
            print("[ProducerDash] Error parsing cached orders: $e");
          }
        }
      }
      if (cachedProduceJson is List && cachedProduceTs is String) {
        final cacheTime = DateTime.tryParse(cachedProduceTs);
        if (cacheTime != null) {
          try {
            cachedProduceData = (cachedProduceJson)
                .map((prodJson) =>
                    Product.fromJson(prodJson as Map<String, dynamic>))
                .toList();
            produceCacheValid = true;
          } catch (e) {
            print("[ProducerDash] Error parsing cached produce: $e");
          }
        }
      }

      if (mounted && (ordersCacheValid || produceCacheValid)) {
        setState(() {
          if (ordersCacheValid && cachedOrdersData != null) {
            _orders = cachedOrdersData!;
            _sortOrders();
          }
          if (produceCacheValid && cachedProduceData != null) {
            _produce = cachedProduceData!;
            _produce.sort((a, b) => a.produceName
                .toLowerCase()
                .compareTo(b.produceName.toLowerCase()));
          }
          _isLoadingOrders =
              !ordersCacheValid; // Only keep loading if this specific cache was invalid/missing
          _isLoadingProduce = !produceCacheValid;
        });
        loadedFromCache = ordersCacheValid &&
            produceCacheValid; // Consider loaded from cache if both were valid initially
      }
    }

    // 2. Always fetch fresh data in background and update cache/UI
    try {
      final results = await Future.wait([
        ProducerApiService.fetchProducerOrders(),
        ProducerApiService.fetchProducerProduce(),
      ], eagerError: true);

      if (mounted) {
        final fetchedOrders = results[0] as List<Order>;
        final fetchedProduce = results[1] as List<Product>;
        setState(() {
          _orders = fetchedOrders;
          _produce = fetchedProduce;
          _sortOrders();
          _produce.sort((a, b) => a.produceName
              .toLowerCase()
              .compareTo(b.produceName.toLowerCase()));
          _isLoadingOrders = false;
          _isLoadingProduce = false;
        });
        // Save to cache
        await UserCache.saveData(
            ordersKey,
            fetchedOrders
                .map((o) => ProducerDash22._serializeOrder(o))
                .toList());
        await UserCache.saveData(ordersTsKey, now.toIso8601String());
        await UserCache.saveData(
            produceKey,
            fetchedProduce
                .map((p) => ProducerDash22._serializeProduct(p))
                .toList());
        await UserCache.saveData(produceTsKey, now.toIso8601String());
      }
    } catch (e) {
      print("[ProducerDash] Error fetching orders/produce: $e");
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
          _isLoadingProduce = false;
          // Only set general error if there was no successfully loaded cached data for these items
          if (!loadedFromCache && _profileFetchError.isEmpty) {
            // Check loadedFromCache for these specific items
            // If _orders or _produce are empty (because cache load failed or was invalid)
            // and now the fetch failed, it's an error for these sections.
            if (_orders.isEmpty || _produce.isEmpty) {
              _error =
                  _error.isEmpty ? 'Failed to load orders/produce.' : _error;
            }
          }
        });
        // If some data was loaded from cache, show a non-blocking error
        if (loadedFromCache || _orders.isNotEmpty || _produce.isNotEmpty) {
          // If any data is present (cache or partial fetch)
          _showErrorSnackBar('Showing available data.');
        }
      }
    }
  }

  // Combined cache load and background fetch for Producer Profile
  Future<void> _initializeProducerProfile({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true;
        _profileFetchError = '';
      });
    }

    // 1. Load from cache unless forcing refresh
    if (!forceRefresh) {
      await _loadProfileCacheFromPrefs();
    } else {
      _profileCache = null;
      _profileCacheTimestamp = null;
    }

    // 2. Display cached data immediately if available and valid
    bool shouldFetchFresh = true;
    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) <
              CacheConfig.profileCacheDuration;

      if (cacheIsValid && !forceRefresh) {
        print("ProducerDash: Displaying valid cached profile.");
        setState(() {
          _profile = _profileCache;
          _updateControllersFromProfile(_profile!); // Update controllers
          _isLoadingProfile = false;
        });
        shouldFetchFresh = false;
      } else {
        print(
            "ProducerDash: Cached profile ${forceRefresh ? 'ignored (force refresh)' : 'expired'}, will fetch fresh data.");
        setState(() {
          _profile = _profileCache; // Show stale data while fetching
          if (_profile != null)
            _updateControllersFromProfile(
                _profile!); // Update controllers if profile not null
        });
      }
    } else if (mounted) {
      print(
          "ProducerDash: No cached profile found${forceRefresh ? ' (force refresh)' : ''}, fetching...");
    }

    // 3. Fetch fresh data if needed
    if (shouldFetchFresh && mounted) {
      print("ProducerDash: Fetching fresh profile data...");
      await _fetchProducerProfileAndUpdate();
    } else if (mounted && !shouldFetchFresh) {
      // If we didn't fetch fresh (valid cache), ensure loading indicator is off
      if (_isLoadingProfile) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  // Separate function to fetch Producer Profile and update state/cache
  Future<void> _fetchProducerProfileAndUpdate() async {
    try {
      final profile = await ProducerApiService.fetchProducerProfile();
      if (mounted) {
        print(
            "ProducerDash: Fetched fresh producer profile data successfully.");
        await _saveProfileCacheToPrefs(profile, DateTime.now());
        setState(() {
          _profile = profile;
          _updateControllersFromProfile(profile); // Update controllers
          _isLoadingProfile = false;
          _profileFetchError = '';
          _syncSelectionFromProfile(); // Sync stock after profile fetch
        });
      }
    } catch (error, stackTrace) {
      print(
          "[ProducerDash] Error fetching fresh producer profile: $error\n$stackTrace");
      if (mounted) {
        final errorMsg =
            'Failed to load profile. Please check your connection.'; // Generic message
        setState(() {
          _profileFetchError =
              errorMsg; // Store specific error for profile section
          _isLoadingProfile = false;
          // Only set general error if no cached profile is available AND no other general error exists
          if (_profile == null && _error.isEmpty) {
            _error = errorMsg;
          }
        });
        if (_profile == null) {
          // If no profile data at all (not even cache)
          _showErrorSnackBar('Error loading profile data.');
        } else {
          // Cached profile exists, but refresh failed
          _showInfoSnackbar(
              "Couldn't update profile, showing last known data.");
        }
      }
    }
  }

  // Load profile from UserCache
  Future<void> _loadProfileCacheFromPrefs() async {
    print("[ProducerDash] Loading profile cache from Prefs...");
    final cachedJson = await UserCache.getData('producer_profile');
    final timestampStr =
        await UserCache.getData('producer_profile_cache_timestamp');
    if (cachedJson is Map<String, dynamic>) {
      try {
        _profileCache = ProducerProfile.fromJson(cachedJson);
        print("[ProducerDash] Profile cache loaded.");
      } catch (e, stack) {
        print('[ProducerDash] Cache parse error: $e\n$stack');
        _profileCache = null;
        await UserCache.removeData('producer_profile');
        await UserCache.removeData('producer_profile_cache_timestamp');
      }
    } else {
      _profileCache = null;
      print("[ProducerDash] No valid profile cache found in Prefs.");
    }
    if (timestampStr is String) {
      _profileCacheTimestamp = DateTime.tryParse(timestampStr);
    } else {
      _profileCacheTimestamp = null;
    }
  }

  // Save profile to UserCache
  Future<void> _saveProfileCacheToPrefs(
      ProducerProfile profile, DateTime timestamp) async {
    print("[ProducerDash] Saving profile to cache...");
    await UserCache.saveData('producer_profile', profile.toJson());
    await UserCache.saveData(
        'producer_profile_cache_timestamp', timestamp.toIso8601String());
    _profileCache = profile; // Update in-memory cache as well
    _profileCacheTimestamp = timestamp;
    print("[ProducerDash] Profile saved to cache.");
  }

  // Update text controllers from profile data
  void _updateControllersFromProfile(ProducerProfile profile) {
    _profileNameController.text = profile.name;
    _profilePhoneController.text = profile.phoneNumber ?? '';
    _profileLocationController.text = profile.location ?? '';
    // Note: Stock (_selectedProduceIds, _produceQuantities) synced separately by _syncSelectionFromProfile
    // Note: Produce edit controllers (_produceNameController etc.) handled when entering edit mode
  }

  // Sort orders by date only (newest first)
  void _sortOrders() {
    _orders.sort((a, b) {
      // Sort by newest first
      return b.orderDate.compareTo(a.orderDate);
    });
  }

  // Sync stock selection UI from profile data
  void _syncSelectionFromProfile() {
    if (_profile == null) {
      print("[ProducerDash] Cannot sync stock selection: Profile not loaded.");
      return;
    }
    print("[ProducerDash] Syncing stock selection from profile data...");
    final newSelectedIds = <String>{};
    final newQuantities = <String, int>{};

    if (_profile!.stock != null && _profile!.stock!.isNotEmpty) {
      for (var stockItem in _profile!.stock!) {
        final produceId = _getStringSafe(stockItem['produce_id']);
        final quantity = _parseIntNullable(stockItem['quantity']);

        if (produceId != null &&
            produceId.isNotEmpty &&
            quantity != null &&
            quantity >= 0) {
          if (_produce.any((p) => p.produceId == produceId)) {
            newSelectedIds.add(produceId);
            newQuantities[produceId] = quantity;
          } else {
            print(
                "[ProducerDash] Warning: Stock item ID '$produceId' not found in master produce list during sync.");
          }
        } else {
          print(
              "[ProducerDash] Warning: Invalid stock item found during sync: $stockItem");
        }
      }
    } else {
      print(
          "[ProducerDash] Profile stock is null or empty. Clearing selections.");
    }

    // Update state only if changes occurred
    if (!mounted) return; // Check mount status before setState
    if (newSelectedIds != _selectedProduceIds ||
        newQuantities != _produceQuantities) {
      print(
          "[ProducerDash] Stock sync updated state: ${newSelectedIds.length} items selected.");
      setState(() {
        _selectedProduceIds = newSelectedIds;
        _produceQuantities = newQuantities;
      });
    } else {
      print("[ProducerDash] Stock sync completed, no changes detected.");
    }
  }

  // --- Order Action Handlers (Adapted from ChefDash) ---

  // Handles simple status updates (Accept, Prepare, Cancel)
  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;

    // Optimistic UI Update
    setState(() {
      _orders[orderIndex].orderStatus = newStatus;
      // Clear rider if status reverts to non-assigned state
      if ([
        Order.STATUS_ACCEPTED,
        Order.STATUS_PREPARING,
        Order.STATUS_CANCELLED
      ].contains(newStatus)) {
        _orders[orderIndex] = _orders[orderIndex].copyWith(
          assignedRiderId: () => null,
          assignedRiderName: () => null,
        );
      }
      _sortOrders();
    });
    _showLoadingSnackbar("Updating status to $newStatus...");

    try {
      bool success =
          await ProducerApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      if (!mounted) return;

      if (success) {
        _showSuccessSnackbar(
            'Order ${order.orderId} status updated to $newStatus.');
        _showOrderNextStepDialog(newStatus);
      } else {
        _showErrorSnackBar('Failed to update order ${order.orderId} status.');
        setState(() {
          // Revert UI
          _orders[orderIndex].orderStatus = originalStatus;
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error updating simple order status: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred updating status.');
        setState(() {
          // Revert UI
          _orders[orderIndex].orderStatus = originalStatus;
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    }
  }

  // Handles "Ready/Assign" action, triggering rider selection
  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _RiderSelectionDialog(
            orderId: order.orderId); // Use the producer's rider dialog
      },
    );

    if (!mounted) return;

    if (result is Rider) {
      print(
          "Rider ${result.name} selected for Order ${order.orderId}. Showing confirmation...");
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      print("Marking Order ${order.orderId} as Ready for Pickup (Any Rider)");
      await _markReadyForAnyRider(order);
    } else {
      print("Rider assignment cancelled or dialog closed.");
    }
  }

  // Shows confirmation dialog before assigning a specific rider
  Future<void> _showRiderAssignmentConfirmation(
      Order order, Rider rider) async {
    if (!mounted) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Confirm Assignment for Order #${order.orderId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign this order to rider:'),
              const SizedBox(height: 8),
              Text('  Name: ${rider.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  '  Status: ${rider.isActive ? "Active" : "Inactive"} (${rider.status})'),
              Text('  ID: ${rider.id}'),
              if (!rider.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Warning: Rider is currently inactive.',
                      style: TextStyle(color: Colors.orange.shade800)),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text(
                  rider.isActive ? 'Confirm Assignment' : 'Assign Anyway',
                  style: TextStyle(color: primaryTeal)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (!mounted) return;
      print(
          "Confirmation received. Assigning Order ${order.orderId} to Rider ${rider.id} (${rider.name})");
      await _assignSpecificRider(order, rider); // Proceed with assignment
    } else {
      print("Rider assignment cancelled by user.");
      _showInfoSnackbar("Rider assignment cancelled.");
    }
  }

  // Calls API to assign a specific rider (after confirmation)
  Future<void> _assignSpecificRider(Order order, Rider rider) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;

    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;

    // Optimistic UI Update
    setState(() {
      _orders[orderIndex] = _orders[orderIndex].copyWith(
        orderStatus: Order.STATUS_ASSIGNED, // Set status to Assigned
        assignedRiderId: () => rider.id,
        assignedRiderName: () => rider.name,
      );
      _sortOrders();
    });
    _showLoadingSnackbar("Assigning to ${rider.name}...");

    try {
      bool success = await ProducerApiService.assignOrderToRider(
          order.orderId, rider.id, Order.STATUS_ASSIGNED);
      _dismissLoadingSnackbar();
      if (!mounted) return;

      if (success) {
        _showSuccessSnackbar(
            'Order ${order.orderId} assigned to ${rider.name}.');
        _showOrderNextStepDialog(Order.STATUS_ASSIGNED);
      } else {
        _showErrorSnackBar(
            'Failed to assign order ${order.orderId} to ${rider.name}.');
        setState(() {
          // Revert UI
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            orderStatus: originalStatus,
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error assigning specific rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while assigning the rider.');
        setState(() {
          // Revert UI
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            orderStatus: originalStatus,
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    }
  }

  // Calls API to mark ready for any rider
  Future<void> _markReadyForAnyRider(Order order) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;

    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;

    // Optimistic UI Update
    setState(() {
      _orders[orderIndex] = _orders[orderIndex].copyWith(
        orderStatus: Order.STATUS_READY_FOR_PICKUP,
        assignedRiderId: () => null, // Clear rider
        assignedRiderName: () => null,
      );
      _sortOrders();
    });
    _showLoadingSnackbar("Marking order as ready...");

    try {
      bool success = await ProducerApiService.updateOrderStatus(
          order.orderId, Order.STATUS_READY_FOR_PICKUP);
      _dismissLoadingSnackbar();
      if (!mounted) return;

      if (success) {
        _showSuccessSnackbar(
            'Order ${order.orderId} marked as Ready for Pickup.');
        _showOrderNextStepDialog(Order.STATUS_READY_FOR_PICKUP);
      } else {
        _showErrorSnackBar(
            'Failed to mark order ${order.orderId} as Ready for Pickup.');
        setState(() {
          // Revert UI
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            orderStatus: originalStatus,
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error marking ready for any rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while updating order status.');
        setState(() {
          // Revert UI
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            orderStatus: originalStatus,
            assignedRiderId: () => originalRiderId,
            assignedRiderName: () => originalRiderName,
          );
          _sortOrders();
        });
      }
    }
  }

  // Handles reject confirmation and calls simple status update
  void _showRejectConfirmation(Order order) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Confirm Rejection"),
          content: Text(
              "Reject Order #${order.orderId} (${order.mealName})? This cannot be undone."),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text("Reject Order", style: TextStyle(color: errorColor)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _updateSimpleOrderStatus(
                    order, Order.STATUS_CANCELLED); // Call update
              },
            ),
          ],
        );
      },
    );
  }

  // Helper to find the index of an order in the _orders list
  int _findOrderIndex(int orderId) {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index == -1) {
      print(
          "[ProducerDash] Warning: Order $orderId not found in _orders list for update.");
    }
    return index;
  }

  // --- Profile Edit Handlers ---
  void _handleEditProfile() {
    if (_profile == null || !mounted) return;
    debugPrint('Edit Profile Action Triggered');
    setState(() {
      _isEditingProfile = true;
      _updateControllersFromProfile(
          _profile!); // Ensure controllers match current profile
      _uploadedProfileImageUrl =
          null; // Clear any previously uploaded URL placeholder
      _profile!.localImageFile = null; // Clear local file selection
    });
  }

  Future<void> _saveProfileChanges() async {
    if (_profile == null || !mounted || !_isEditingProfile) return;
    if (_profileFormKey.currentState?.validate() ?? false) {
      debugPrint('Save Profile Changes Action Triggered');
      _showLoadingSnackbar('Saving profile...');
      setState(() =>
          _isUploadingProfileImage = true); // Show image loading indicator

      try {
        String? finalImageUrl =
            _profile!.image; // Start with existing image URL

        // 1. Upload new image if selected
        if (_profile!.localImageFile != null) {
          print("Uploading new profile image...");
          final newImageUrl =
              await ProducerApiService.updateProducerProfileImage(
                  _profile!.producerId, _profile!.localImageFile!);
          if (newImageUrl != null) {
            finalImageUrl = newImageUrl; // Update URL if upload successful
            print("Image upload success. New URL: $newImageUrl");
          } else {
            // Handle image upload failure (optional: stop save or warn user)
            print("Image upload failed. Continuing with text updates.");
            _showErrorSnackBar(
                'Failed to upload profile image. Text changes will still be saved.');
            // Keep original finalImageUrl
          }
        }

        // 2. Update text fields via API
        final String name = _profileNameController.text.trim();
        final String? phone = _profilePhoneController.text.trim().isEmpty
            ? null
            : _profilePhoneController.text.trim();
        final String? location = _profileLocationController.text.trim().isEmpty
            ? null
            : _profileLocationController.text.trim();

        bool textUpdateSuccess = await ProducerApiService.updateProducerProfile(
          _profile!.producerId,
          name: name,
          phoneNumber: phone,
          location: location,
        );
        // NOTE: Stock updates are handled separately via the Stock tab FAB

        // 3. Handle results
        if (mounted) {
          setState(
              () => _isUploadingProfileImage = false); // Hide image indicator
          _dismissLoadingSnackbar();

          if (textUpdateSuccess) {
            // If text update succeeded, update local profile object with new data
            // *before* forcing a refresh, so UI updates instantly even if refresh fails
            setState(() {
              _profile = _profile!.copyWith(
                name: name,
                phoneNumber: phone ??
                    _profile!.phoneNumber, // Keep old if new is null/empty
                location: location ?? _profile!.location,
                image: finalImageUrl, // Update image URL from upload result
                localImageFile: () =>
                    null, // Clear local file after successful process
              );
              _isEditingProfile = false; // Exit edit mode
            });
            _showSuccessSnackbar('Profile updated successfully.');
            // Force a full refresh from the server to ensure consistency
            await _initializeProducerProfile(forceRefresh: true);
          } else {
            _showErrorSnackBar('Failed to save profile text changes.');
            // Optionally, keep editing mode open or attempt partial refresh
          }
        }
      } catch (e) {
        debugPrint("Error saving profile: $e");
        if (mounted) {
          setState(() =>
              _isUploadingProfileImage = false); // Hide indicator on error
          _dismissLoadingSnackbar();
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
      _isEditingProfile = false;
      if (_profile != null) {
        _updateControllersFromProfile(_profile!); // Reset controllers
        _profile!.localImageFile = null; // Clear local image selection
      }
      _profileFormKey.currentState?.reset(); // Reset validation state
    });
  }

  Future<void> _handleToggleActiveStatus(bool newStatus) async {
    if (_profile == null || !mounted || _isEditingProfile) return;
    debugPrint(
        'Toggle Active Status Action Triggered: New Status = $newStatus');

    final originalStatus = _profile!.isActive;
    // Optimistic UI update
    setState(() => _profile = _profile!.copyWith(isActive: newStatus));
    _showLoadingSnackbar('Updating status...');

    try {
      bool success = await ProducerApiService.updateProducerStatus(
          _profile!.producerId, newStatus);
      _dismissLoadingSnackbar();
      if (!mounted) return;

      if (success) {
        _showSuccessSnackbar(
            'Profile status updated to ${newStatus ? "Active" : "Offline"}.');
        // Save the updated profile (with new status) to cache
        if (_profile != null) {
          // Ensure profile is not null
          await _saveProfileCacheToPrefs(_profile!, DateTime.now());
        }
      } else {
        // Revert UI on failure
        setState(() => _profile = _profile!.copyWith(isActive: originalStatus));
        _showErrorSnackBar('Failed to update status.');
      }
    } catch (e) {
      debugPrint("Error toggling active status via API: $e");
      _dismissLoadingSnackbar();
      if (mounted) {
        // Revert UI on exception
        setState(() => _profile = _profile!.copyWith(isActive: originalStatus));
        _showErrorSnackBar('An error occurred updating status: $e');
      }
    }
  }

  // Profile Image Picking
  Future<void> _pickAndUploadProfileImage() async {
    if (!_isEditingProfile || !mounted) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        if (mounted) {
          setState(() {
            _profile =
                _profile?.copyWith(localImageFile: () => File(pickedFile.path));
          });
          // Actual upload happens in _saveProfileChanges
        }
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackBar("Could not pick image: $e");
    }
  }

  // --- Stock and Produce Item Management Handlers ---

  void _handleAddProduce() {
    if (_editingProduceId != null || !mounted || _isEditingProfile) return;
    debugPrint('Add Produce Action Triggered');
    final newId = 'TEMP_${DateTime.now().millisecondsSinceEpoch}';
    final newProduct = Product(produceId: newId, produceName: '');
    _initializeProduceEditControllers(newProduct); // Initialize controllers
    setState(() {
      _produce.add(newProduct); // Add temporary item to list
      _produce.sort((a, b) =>
          a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
      _editingProduceId = newId; // Enter edit mode for this item
    });
    _showInfoSnackbar('Fill in details for the new produce item.');
  }

  void _handleEditProduce(Product product) {
    if (!mounted || _isEditingProfile) return;
    debugPrint('Edit Produce Action Triggered for ID: ${product.produceId}');
    _cancelAllEdits(exceptProduceId: product.produceId); // Cancel other edits
    _initializeProduceEditControllers(product); // Initialize controllers
    setState(() => _editingProduceId = product.produceId); // Enter edit mode
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
    if (_produceFormKey.currentState?.validate() ?? false) {
      final String idToSave = _editingProduceId!;
      final int index = _produce.indexWhere((p) => p.produceId == idToSave);
      if (index == -1) {
        _cancelProduceEdit();
        return;
      } // Should not happen

      final bool isNewItem = idToSave.startsWith('TEMP_');
      // Create payload from controllers
      Map<String, dynamic> payload = {
        'produce_name': _produceNameController?.text.trim(),
        'calories': _produceCaloriesController?.text.trim(),
        'proteins': _produceProteinsController?.text.trim(),
        'carbohydrates': _produceCarbsController?.text.trim(),
        'fats': _produceFatsController?.text.trim(),
        'unit_grams': _produceUnitGramsController?.text.trim(),
        'source': _produceSourceController?.text.trim(),
      };

      debugPrint('Saving Produce Changes for ID: $idToSave (New: $isNewItem)');
      _showLoadingSnackbar('Saving produce...');
      try {
        if (isNewItem) {
          Product? addedProduct = await ProducerApiService.addProduce(payload);
          _dismissLoadingSnackbar();
          if (mounted) {
            if (addedProduct != null) {
              setState(() {
                _produce.removeAt(index); // Remove TEMP
                _produce.add(addedProduct); // Add real item from API response
                _produce.sort((a, b) => a.produceName
                    .toLowerCase()
                    .compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null; // Exit edit mode
                _disposeProduceEditControllers();
              });
              _showSuccessSnackbar('Added "${addedProduct.produceName}".');
            } else {
              _showErrorSnackBar('Failed to add produce.');
              // Remove TEMP on failure to prevent orphaned edit form
              setState(() {
                _produce.removeAt(index);
                _editingProduceId = null;
                _disposeProduceEditControllers();
              });
            }
          }
        } else {
          // Update existing item
          bool success =
              await ProducerApiService.updateProduce(idToSave, payload);
          _dismissLoadingSnackbar();
          if (mounted) {
            if (success) {
              // Update local list immutably using copyWith
              final updatedProduct = _produce[index].copyWith(
                produceName: payload['produce_name'],
                calories: () => _parseIntNullable(payload['calories']),
                proteins: () => _parseDoubleNullable(payload['proteins']),
                carbohydrates: () =>
                    _parseDoubleNullable(payload['carbohydrates']),
                fats: () => _parseDoubleNullable(payload['fats']),
                unitGrams: () => _parseIntNullable(payload['unit_grams']),
                source: () => payload['source'],
              );
              setState(() {
                _produce[index] = updatedProduct;
                _produce.sort((a, b) => a.produceName
                    .toLowerCase()
                    .compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null; // Exit edit mode
                _disposeProduceEditControllers();
              });
              _showSuccessSnackbar('Updated "${updatedProduct.produceName}".');
            } else {
              _showErrorSnackBar(
                  'Failed to update "${payload['produce_name'] ?? 'produce'}".');
              // Keep edit mode open on failure? Or cancel? Current: Keep open.
            }
          }
        }
      } catch (e) {
        debugPrint("Error saving produce via API: $e");
        _dismissLoadingSnackbar();
        if (mounted) {
          _showErrorSnackBar('An error occurred saving produce: $e');
          if (isNewItem) {
            // Clean up TEMP item on exception
            setState(() {
              _produce.removeAt(index);
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
      _disposeProduceEditControllers(); // Dispose controllers
      // If cancelling a *new* unsaved item, remove it from the list
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary new produce item on cancel.");
      }
    });
  }

  void _handleProdDeleteuce(Product product) {
    if (!mounted ||
        _isEditingProfile ||
        (_editingProduceId != null && _editingProduceId != product.produceId))
      return;
    debugPrint('Delete Produce Action Triggered for ID: ${product.produceId}');
    // If trying to delete a temporary item, just cancel the edit
    if (product.produceId.startsWith('TEMP_')) {
      _cancelProduceEdit();
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: whiteColor.withOpacity(0.95),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: errorColor),
            SizedBox(width: 10),
            Text('Confirm Deletion')
          ]),
          content: Text(
              'Permanently delete "${product.produceName}" from the system?\nThis also removes it from your stock. This cannot be undone.',
              style: const TextStyle(color: subtleText)),
          actions: <Widget>[
            TextButton(
                style: TextButton.styleFrom(foregroundColor: subtleText),
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(ctx).pop()),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: 16),
              label: const Text('Delete'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: destructiveButtonBackground,
                  foregroundColor: destructiveButtonForeground,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                Navigator.of(ctx).pop(); // Close dialog
                _performDeleteProduce(product); // Call delete function
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
      if (mounted) {
        if (success) {
          final deletedName = product.produceName;
          setState(() {
            // Remove from master list
            _produce.removeWhere((p) => p.produceId == product.produceId);
            // Remove from current stock selection
            _selectedProduceIds.remove(product.produceId);
            _produceQuantities.remove(product.produceId);
            // Exit edit mode if this was the item being edited
            if (_editingProduceId == product.produceId) {
              _editingProduceId = null;
              _disposeProduceEditControllers();
            }
          });
          _showSuccessSnackbar('Deleted "$deletedName".');
          // Optionally trigger a stock update API call if needed after delete
          // _updateProducerStock(); // Or prompt user
        } else {
          _showErrorSnackBar('Failed to delete "${product.produceName}".');
        }
      }
    } catch (e) {
      debugPrint("Error deleting produce via API: $e");
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackBar('An error occurred deleting: $e');
      }
    }
  }

  // Updates the producer's stock via API call (Triggered by FAB)
  Future<void> _updateProducerStock() async {
    if (_profile == null) {
      _showErrorSnackBar('Profile not loaded. Cannot update stock.');
      return;
    }
    // Prepare stock list: [{"produce_id": ..., "quantity": ...}]
    final stockList = _selectedProduceIds
        .map((id) {
          final quantity = _produceQuantities[id];
          // Only include items with a valid ID and non-negative quantity
          if (quantity != null && quantity >= 0) {
            return {'produce_id': id, 'quantity': quantity};
          }
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    // Optional: Check if stockList is identical to profile.stock to avoid unnecessary calls
    // This requires careful comparison of the lists/maps.

    _showLoadingSnackbar('Updating stock...');
    try {
      bool success = await ProducerApiService.updateProducerStock(
          _profile!.producerId, stockList);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Stock updated successfully.');
          // Refresh profile to get latest stock state from backend
          await _initializeProducerProfile(forceRefresh: true);
          // No need to call _syncSelectionFromProfile here, as the refresh will trigger it.
        } else {
          _showErrorSnackBar('Failed to update stock. Please try again.');
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackBar('Error connecting to server: $e');
      }
      print("Exception updating stock: $e");
    }
  }

  // Helper to cancel any active editing modes
  void _cancelAllEdits({String? exceptProduceId}) {
    if (!mounted) return;
    bool didCancel = false;
    if (_isEditingProfile) {
      _isEditingProfile = false;
      didCancel = true;
    }
    if (_editingProduceId != null && _editingProduceId != exceptProduceId) {
      final idToCancel = _editingProduceId;
      _editingProduceId = null;
      _disposeProduceEditControllers();
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary produce item due to action/switch.");
      }
      didCancel = true;
    }
    if (didCancel) {
      setState(() {});
      debugPrint("Cancelled active edits due to action/switch.");
    }
  }

  // --- Location Fetching ---
  Future<void> _getCurrentLocation() async {
    if (!_isEditingProfile || !mounted) return; // Only fetch when editing
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Location permissions permanently denied. Please enable in settings.');
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15) // Add timeout
          );
      String displayAddress =
          "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}"; // Fallback

      // Reverse Geocode (Optional, using geocode.maps.co - check terms)
      try {
        final apiUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
          _showInfoSnackbar('Could not fetch readable address.');
        }
      } catch (e) {
        print("Reverse geocoding failed: $e");
        _showInfoSnackbar('Could not fetch readable address.');
      }

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

  // --- Snackbar Helpers ---
  void _showSnackbar(String message,
      {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message,
              style: TextStyle(color: isError ? whiteColor : textOnTeal),
              textAlign: TextAlign.center),
          backgroundColor: isError
              ? errorColor.withOpacity(0.9)
              : primaryTeal.withOpacity(0.9),
          duration: Duration(seconds: durationSeconds),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          elevation: 2.0,
        ),
      );
  }

  void _showErrorSnackBar(String message) =>
      _showSnackbar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackbar(String message) =>
      _showSnackbar(message, isError: false);
  void _showInfoSnackbar(String message) =>
      _showSnackbar(message, isError: false, durationSeconds: 2);

  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white)),
            const SizedBox(width: 15),
            Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
          backgroundColor: Colors.black.withOpacity(0.8),
          duration: const Duration(minutes: 1), // Show until dismissed
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
        ),
      );
  }

  void _dismissLoadingSnackbar() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  // Show guidance dialog after order status update
  void _showOrderNextStepDialog(String newStatus) {
    if (!mounted) return;
    String message;
    String title;
    IconData icon;
    switch (newStatus) {
      case 'accepted': // Order.STATUS_ACCEPTED.toLowerCase()
        title = "Order Accepted";
        message = "Start preparing the order. Mark 'Ready/Assign' when done.";
        icon = Icons.check_circle_outline;
        break;
      case 'preparing': // Order.STATUS_PREPARING.toLowerCase()
        title = "Order Preparing";
        message = "Mark 'Ready/Assign' once ready.";
        icon = Icons.kitchen_outlined;
        break;
      case 'ready for pickup': // Order.STATUS_READY_FOR_PICKUP.toLowerCase()
        title = "Ready for Pickup";
        message = "Order is now available for any rider to collect.";
        icon = Icons.inventory_2_outlined;
        break;
      case 'assigned': // Order.STATUS_ASSIGNED.toLowerCase()
        title = "Rider Assigned";
        message = "The assigned rider has been notified to pick up the order.";
        icon = Icons.person_pin_circle_outlined;
        break;
      case 'dispatched': // Order.STATUS_DISPATCHED.toLowerCase()
        title = "Order Dispatched";
        message = "Order marked as dispatched.";
        icon = Icons.local_shipping_outlined;
        break;
      case 'out for delivery': // Order.STATUS_OUT_FOR_DELIVERY.toLowerCase()
        title = "Out for Delivery";
        message = "Rider is en route.";
        icon = Icons.two_wheeler_rounded;
        break;
      case 'delivered': // Order.STATUS_DELIVERED.toLowerCase()
        title = "Order Delivered";
        message = "Order completed successfully.";
        icon = Icons.done_all;
        break;
      case 'completed': // Order.STATUS_COMPLETED.toLowerCase()
        title = "Order Completed";
        message = "Order is marked as completed.";
        icon = Icons.celebration_outlined;
        break;
      case 'cancelled': // Order.STATUS_CANCELLED.toLowerCase()
        title = "Order Cancelled";
        message = "Order has been cancelled.";
        icon = Icons.cancel_outlined;
        break;
      default:
        title = "Order Updated";
        message = "Order status updated to '$newStatus'.";
        icon = Icons.info_outline;
    }
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Row(children: [
                Icon(icon, color: primaryTeal),
                const SizedBox(width: 8),
                Text(title)
              ]),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("OK"))
              ],
            ));
  }

  // --- Build Method and UI Widgets ---
  @override
  Widget build(BuildContext context) {
    // Determine AppBar Avatar Image
    ImageProvider? appBarAvatarImage;
    if (_isLoadingProfile && _profile == null) {
      appBarAvatarImage = const AssetImage(placeholderImagePath);
    } else if (_profile?.image != null && _profile!.image!.isNotEmpty) {
      try {
        Uri.parse(_profile!.image!); // Validate URL
        appBarAvatarImage = CachedNetworkImageProvider(_profile!.image!);
      } catch (e) {
        debugPrint("Invalid URL for AppBar image: ${_profile!.image}");
        appBarAvatarImage = const AssetImage(placeholderImagePath);
      }
    } else {
      appBarAvatarImage = const AssetImage(placeholderImagePath);
    }

    return Scaffold(
      drawer: drawer.AppDrawer(
          invokedBy: 'producer_dashboard'), // Use the unified drawer
      backgroundColor: Colors.grey[100], // Light background
      appBar: AppBar(
        backgroundColor: primaryTeal,
        elevation: 2.0,
        iconTheme: const IconThemeData(color: textOnTeal),
        title: Text(_getAppBarTitle(),
            style: const TextStyle(
                color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: false,
        actions: [
          // Refresh Button
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: whiteColor,
                      strokeWidth: 2,
                    ))
                : const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed:
                _isRefreshing ? null : () => _fetchAllData(forceRefresh: true),
          ),
          // Profile Avatar in AppBar
          if (!_isLoadingProfile && _profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: lightTeal.withOpacity(0.5),
                backgroundImage: appBarAvatarImage,
                onBackgroundImageError: (exception, stackTrace) {
                  debugPrint("Error loading app bar avatar: $exception");
                },
                child: appBarAvatarImage is AssetImage
                    ? const Icon(Icons.person, color: Colors.grey, size: 24)
                    : null,
              ),
            ),
          // Logout Button (Placeholder Action)
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: textOnTeal),
            tooltip: 'Logout',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final keys = prefs.getKeys();
              final patterns = [RegExp(r'_id\b'), RegExp(r'_user_type\b')];
              for (final key in keys) {
                if (patterns.any((p) => p.hasMatch(key))) {
                  await prefs.remove(key);
                }
              }
              // UserCache.clearAll() removed; logout already clears relevant keys. // Also clear UserCache
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SignUpOrLoginPage()),
                  (Route<dynamic> route) => false,
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBodyContent(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index != _currentIndex && mounted) {
            _cancelAllEdits(); // Cancel edits when switching tabs
            setState(() => _currentIndex = index);
            _onTabChanged(index); // Handle tab change for polling
          }
        },
        backgroundColor: whiteColor.withOpacity(0.98),
        selectedItemColor: primaryTeal,
        unselectedItemColor: subtleText.withOpacity(0.9),
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 8.0,
        items: [
          _buildBottomNavItem(Icons.account_circle_outlined,
              Icons.account_circle, 'Profile', 0),
          _buildBottomNavItem(
              Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 1),
          _buildBottomNavItem(
              Icons.inventory_2_outlined, Icons.inventory_2, 'Stock', 2),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // Build Bottom Nav Item
  BottomNavigationBarItem _buildBottomNavItem(
      IconData icon, IconData activeIcon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavItemIcon(isSelected ? activeIcon : icon, isSelected),
      label: label,
    );
  }

  // Build Icon for Bottom Nav
  Widget _buildNavItemIcon(IconData iconData, bool isSelected) {
    final icon = Icon(
      iconData,
      color: isSelected ? primaryTeal : subtleText.withOpacity(0.8),
      size: 24,
    );
    return SizedBox(width: 32, height: 32, child: Center(child: icon));
  }

  // Get AppBar Title based on current tab and edit state
  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return _isEditingProfile ? 'Edit Profile' : 'Producer Profile';
      case 1:
        return 'Manage Orders';
      case 2:
        return _editingProduceId != null
            ? (_editingProduceId!.startsWith("TEMP_")
                ? 'Add Produce Item'
                : 'Edit Produce Item')
            : 'Manage Stock & Produce';
      default:
        return 'Producer Dashboard';
    }
  }

  // Build Floating Action Button based on current tab and state
  Widget? _buildFloatingActionButton() {
    // No FAB during profile or produce editing
    if (_isEditingProfile || _editingProduceId != null) return null;

    switch (_currentIndex) {
      case 0: // Profile Tab -> Edit FAB
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
          heroTag: 'fab_profile_edit', // Unique heroTag
        );
      case 1: // Orders Tab -> No FAB
        return null;
      case 2: // Produce/Stock Tab -> Update Stock or Add Produce FAB
        if (_selectedProduceIds.isNotEmpty) {
          // Show Update Stock if items are selected
          return FloatingActionButton.extended(
            onPressed: _updateProducerStock,
            tooltip: 'Update Stock Levels',
            icon: const Icon(Icons.update),
            label: const Text("Update Stock"),
            backgroundColor: darkTeal,
            foregroundColor: textOnTeal,
            heroTag: 'fab_stock_update', // Unique heroTag
          );
        } else {
          // Show Add Produce if no items are selected
          return FloatingActionButton(
            onPressed: _handleAddProduce,
            tooltip: 'Add New Produce Item',
            backgroundColor: primaryTeal,
            foregroundColor: textOnTeal,
            child: const Icon(Icons.add),
            heroTag: 'fab_produce_add', // Unique heroTag
          );
        }
      default:
        return null;
    }
  }

  // Build Body Content based on loading/error state and current tab index
  Widget _buildBodyContent() {
    // Initial combined loading state for the whole page
    if (_isLoading &&
        _profile == null &&
        _orders.isEmpty &&
        _produce.isEmpty &&
        _error.isEmpty &&
        _profileFetchError.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    // If there's a general error and no profile data, show full error view
    if (_error.isNotEmpty && _profile == null) {
      return _buildErrorView();
    }
    // If there's only a profile fetch error but no general error, and no profile data
    if (_profileFetchError.isNotEmpty && _error.isEmpty && _profile == null) {
      return _buildProfileErrorView(); // Show profile-specific error if it's the only one and profile is null
    }

    // If loading is complete or some data (even cached) is available, show tabs
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildProfileTab(),
        _buildOrdersTab(),
        _buildProduceTab(),
      ],
    );
  }

  // Build General Error View
  Widget _buildErrorView() {
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              color: whiteColor.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: errorColor, size: 48),
                      const SizedBox(height: 16),
                      Text(
                          _error.isNotEmpty
                              ? _error
                              : "An unknown error occurred.",
                          style:
                              const TextStyle(color: textOnWhite, fontSize: 16),
                          textAlign: TextAlign.center),
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
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: () => _fetchAllData(
                            forceRefresh: true), // Force refresh on retry
                      ),
                    ],
                  )),
            )));
  }

  // --- Profile Tab UI ---
  Widget _buildProfileTab() {
    // Show loading specifically for profile if it's still loading and no cached data shown
    if (_isLoadingProfile && _profile == null) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    // Show error specific to profile fetch if it occurred and no cached data
    if (_profileFetchError.isNotEmpty && _profile == null) {
      return _buildProfileErrorView();
    }
    // If profile is loaded (or cache is available)
    if (_profile != null) {
      return _isEditingProfile
          ? _buildProfileEditView(_profile!)
          : _buildProfileDisplayView(_profile!);
    }
    // Fallback empty state if no profile, no error, no loading (should be rare if _error is set properly)
    return _buildEmptyState(
      'Profile Unavailable',
      'Could not load profile details. Pull down to refresh.',
      icon: Icons.person_off_outlined,
    );
  }

  // Build Profile Specific Error View
  Widget _buildProfileErrorView() {
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              color: whiteColor.withOpacity(0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                  padding: const EdgeInsets.all(25.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_off_outlined,
                          color: errorColor, size: 48),
                      const SizedBox(height: 16),
                      Text("Error Loading Profile",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textOnWhite)),
                      const SizedBox(height: 8),
                      Text(
                        _profileFetchError.isNotEmpty
                            ? _profileFetchError
                            : "Could not load profile.",
                        style: const TextStyle(color: subtleText, fontSize: 14),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryTeal,
                            foregroundColor: textOnTeal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: () => _initializeProducerProfile(
                            forceRefresh: true), // Retry fetching profile
                      ),
                    ],
                  )),
            )));
  }

  // Build Profile Display View
  Widget _buildProfileDisplayView(ProducerProfile profile) {
    final dateFormat = DateFormat('MMM d, yyyy, hh:mm a');
    final profileAvatarImage =
        (profile.image != null && profile.image!.isNotEmpty)
            ? CachedNetworkImageProvider(profile.image!)
            : const AssetImage(placeholderImagePath) as ImageProvider;

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Profile Header Card
          Card(
            elevation: 2.0,
            color: cardBackground.withOpacity(0.95),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0)),
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 20.0, horizontal: 16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: lightTeal.withOpacity(0.5),
                      backgroundImage: profileAvatarImage,
                      onBackgroundImageError: (_, __) =>
                          debugPrint('Error loading profile network image'),
                      child: profileAvatarImage is AssetImage
                          ? const Icon(Icons.person,
                              size: 40, color: Colors.grey)
                          : null,
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
                                    style: const TextStyle(
                                        fontSize: 14, color: subtleText))),
                          if (profile.rating != null && profile.rating! > 0)
                            Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(children: [
                                  const Icon(Icons.star_rounded,
                                      color: starColor, size: 18),
                                  const SizedBox(width: 4),
                                  Text(profile.rating!.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              textOnWhite)), // Assuming textOnWhite is dark enough for cardBackground
                                  if (profile.reviews != null &&
                                      profile.reviews!.isNotEmpty &&
                                      profile.reviews!.toLowerCase() !=
                                          'none') ...[
                                    const SizedBox(width: 6),
                                    Text('(${profile.reviews} reviews)',
                                        style: const TextStyle(
                                            fontSize: 12, color: subtleText)),
                                  ],
                                ])),
                        ])),
                  ],
                )),
          ),
          // Active Status Card
          Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SwitchListTile(
                  value: profile.isActive,
                  onChanged:
                      _isEditingProfile ? null : _handleToggleActiveStatus,
                  title: const Text('Active Status',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: darkTeal)),
                  subtitle: Text(
                      profile.isActive
                          ? 'Visible to customers'
                          : 'Not currently visible',
                      style: const TextStyle(fontSize: 13, color: subtleText)),
                  secondary: Icon(
                      profile.isActive
                          ? Icons.check_circle_outline_rounded
                          : Icons.power_settings_new_outlined,
                      color: profile.isActive
                          ? Colors.green.shade600
                          : Colors.orange.shade700,
                      size: 28),
                  activeColor: primaryTeal,
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.grey.shade200,
                  contentPadding: EdgeInsets.zero,
                )),
          ),
          // Info Section
          _buildProfileSectionCard(
              title: 'Contact & Details',
              icon: Icons.info_outline_rounded,
              children: [
                _buildDetailItem(Icons.email_outlined, 'Email', profile.email),
                _buildDetailItem(
                    Icons.phone_outlined, 'Phone', profile.phoneNumber),
                _buildDetailItem(
                    Icons.location_on_outlined, 'Location', profile.location),
                _buildDetailItem(Icons.calendar_today_rounded, 'Registered',
                    dateFormat.format(profile.registrationDate)),
                if (profile.lastLogin != null)
                  _buildDetailItem(Icons.access_time_rounded, 'Last Login',
                      dateFormat.format(profile.lastLogin!)),
                if (profile.isEmailVerified != null)
                  _buildDetailItem(Icons.verified_outlined, 'Email Verified',
                      profile.isEmailVerified! ? 'Yes' : 'No'),
                _buildDetailItem(Icons.person_outline_rounded, 'User Type',
                    profile.userType),
                _buildDetailItem(Icons.category_outlined, 'Producer Type',
                    profile.producerType),
              ]),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  // Build Profile Edit View
  Widget _buildProfileEditView(ProducerProfile profile) {
    // Determine image to display: local file > uploaded temp > network > placeholder
    ImageProvider displayImage;
    if (profile.localImageFile != null) {
      displayImage = FileImage(profile.localImageFile!);
    } else if (_uploadedProfileImageUrl != null) {
      displayImage = CachedNetworkImageProvider(_uploadedProfileImageUrl!);
    } else if (profile.image != null && profile.image!.isNotEmpty) {
      displayImage = CachedNetworkImageProvider(profile.image!);
    } else {
      displayImage = const AssetImage(placeholderImagePath);
    }

    return Form(
      key: _profileFormKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Profile Image Handling
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: lightTeal.withOpacity(0.3),
                  backgroundImage: displayImage,
                  onBackgroundImageError: (_, __) {}, // Handle errors silently
                  child: _isUploadingProfileImage
                      ? const CircularProgressIndicator(color: primaryTeal)
                      : null,
                ),
                Material(
                  color: primaryTeal,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickAndUploadProfileImage,
                    child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.camera_alt,
                            color: whiteColor, size: 20)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Editable Fields
          _buildEditableItem(_profileNameController, 'Producer Name *',
              Icons.person_outline_rounded,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null),
          _buildEditableItem(
              _profilePhoneController, 'Phone Number', Icons.phone_outlined,
              keyboardType: TextInputType.phone),
          _buildEditableItem(_profileLocationController,
              'Location / Service Area', Icons.location_on_outlined,
              maxLines: 2),
          // Location Fetch Button
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 40),
            child: TextButton.icon(
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              icon: _isLoadingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                  _isLoadingLocation ? 'Fetching...' : 'Get Current Location'),
              style: TextButton.styleFrom(
                  foregroundColor: primaryTeal,
                  textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 24),
          // Action Buttons
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: _cancelProfileEdit,
                child:
                    const Text('Cancel', style: TextStyle(color: subtleText)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8))),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: _isUploadingProfileImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: whiteColor))
                  : const Icon(Icons.save_outlined, size: 18),
              label:
                  Text(_isUploadingProfileImage ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  foregroundColor: textOnTeal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: _isUploadingProfileImage
                  ? null
                  : _saveProfileChanges, // Disable while saving/uploading
            ),
          ]),
          const SizedBox(height: 80), // Space for bottom nav/FAB
        ],
      ),
    );
  }

  // Build Profile Section Card
  Widget _buildProfileSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
        elevation: 1.0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        color: whiteColor.withOpacity(0.9),
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: primaryTeal, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: darkTeal))
            ]),
            const Divider(height: 16, thickness: 0.8, color: dividerColor),
            ...children.map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0), child: child)),
          ]),
        ));
  }

  // Build Profile Detail Item Row
  Widget _buildDetailItem(IconData icon, String label, String? value) {
    final displayValue =
        (value == null || value.trim().isEmpty) ? 'Not provided' : value;
    final displayColor = (value == null || value.trim().isEmpty)
        ? subtleText.withOpacity(0.7)
        : subtleText;

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)),
          const SizedBox(width: 10),
          SizedBox(
              width: 90,
              child: Text('$label:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textOnWhite,
                      fontSize: 13))),
          Expanded(
              child: Text(displayValue,
                  style: TextStyle(color: displayColor, fontSize: 13),
                  softWrap: true)),
        ]));
  }

  // Build Editable Item Row (TextFormField)
  Widget _buildEditableItem(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1,
      TextInputType keyboardType = TextInputType.text,
      String? Function(String?)? validator}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon:
                Icon(icon, size: 18, color: primaryTeal.withOpacity(0.9)),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: dividerColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(color: dividerColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
            labelStyle: const TextStyle(color: subtleText, fontSize: 13),
            floatingLabelStyle: const TextStyle(color: primaryTeal),
            errorStyle: const TextStyle(fontSize: 11, color: errorColor),
          ),
          style: const TextStyle(color: textOnWhite, fontSize: 13),
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ));
  }

  // --- Orders Tab UI ---
  Widget _buildOrdersTab() {
    // Show loading if orders are being fetched and list is currently empty
    if (_isLoadingOrders && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    // If there's a general error (and not just a profile fetch error that's handled in profile tab)
    // and orders list is empty, show the general error view for this tab too.
    if (_error.isNotEmpty && _profileFetchError.isEmpty && _orders.isEmpty) {
      return _buildErrorView(); // Or a more specific "Could not load orders"
    }

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_orders.isNotEmpty)
            _buildOrdersListSection()
          else if (!_isLoadingOrders &&
              _error
                  .isEmpty) // Show empty state only when not loading AND no error for this section
            _buildEmptyState(
              'No Orders Yet',
              'New customer orders will appear here.',
              icon: Icons.receipt_long_outlined,
            )
          // If still loading but list became empty (e.g. refresh returned empty), or if there's an error
          // but we don't want to show the big error view if some other data is fine.
          // The initial _isLoadingOrders check above handles the very first load.
          // This else is for subsequent states or if _error is set for orders specifically.
          else if (_error.isNotEmpty &&
              _orders.isEmpty) // If specific error for orders, show it
            _buildErrorView() // Could be more specific like "Failed to load orders"
          // Implicitly, if _isLoadingOrders is false, _orders is empty, and _error is empty, the empty state is shown.
          // If _isLoadingOrders is true and _orders is empty, loader is shown.
        ],
      ),
    );
  }

  // Build Orders List Section
  Widget _buildOrdersListSection() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: (index == _orders.length - 1) ? 0 : 12.0),
          child: _buildOrderItem(_orders[index]),
        );
      },
    );
  }

  // Build Individual Order Item Card
  Widget _buildOrderItem(Order order) {
    final DateFormat dateFormat = DateFormat('MMM d, hh:mm a');
    final statusColor = _getStatusColor(order.orderStatus);
    final statusIcon = _getStatusIcon(order.orderStatus);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      color: whiteColor.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(color: statusColor.withOpacity(0.4), width: 1),
      ),
      child: ExpansionTile(
        key: PageStorageKey<int>(order.orderId), // Preserve expanded state
        tilePadding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 8.0),
        childrenPadding: EdgeInsets.zero,
        expandedAlignment: Alignment.topLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: subtleText,
        collapsedIconColor: subtleText,
        leading: Tooltip(
          message: order.orderStatus,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(statusIcon, color: statusColor, size: 18),
          ),
        ),
        title: Text(
          order.mealName,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3.0),
          child: Text(
            '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
            style: const TextStyle(fontSize: 12, color: subtleText),
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat.currency(symbol: 'UGX ', decimalDigits: 0)
                  .format(order.totalPrice),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: darkTeal, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text('${order.quantity} item${order.quantity > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 11, color: subtleText)),
          ],
        ),
        children: [
          Divider(height: 1, color: dividerColor.withOpacity(0.7)),
          Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrderDetailItem(
                      'Customer', order.customerName ?? 'Unknown'),
                  _buildOrderDetailItem('Status', order.orderStatus,
                      color: statusColor),
                  _buildOrderDetailItem(
                      'Payment', order.paymentStatus ?? 'Unknown'),
                  if (order.notes != null && order.notes!.isNotEmpty)
                    _buildOrderDetailItem('Notes', order.notes!),
                  if (order.deliveryAddress != null &&
                      order.deliveryAddress!.isNotEmpty)
                    _buildOrderDetailItem(
                        'Delivery To', order.deliveryAddress!),
                  if (order.assignedRiderId != null)
                    _buildOrderDetailItem('Assigned Rider',
                        '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}',
                        color: assignedColor),
                  const SizedBox(height: 12),
                  _buildOrderActions(order), // Action buttons
                ],
              )),
        ],
      ),
    );
  }

  // Build Order Detail Item Row
  Widget _buildOrderDetailItem(String label, String value, {Color? color}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 80,
              child: Text('$label:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: textOnWhite))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 12, color: color ?? subtleText),
                  softWrap: true)),
        ]));
  }

  // Build Order Action Buttons based on status
  Widget _buildOrderActions(Order order) {
    // DEBUG: Print order ID and status to diagnose status mismatches
    // Remove or comment out after debugging
    // ignore: avoid_print
    print(
        '[OrderActions] Order ${order.orderId} status: "${order.orderStatus}"');
    List<Widget> buttons = [];
    String status = order.orderStatus;

    // Common Reject/Cancel action
    bool canCancel = ![
      Order.STATUS_DELIVERED.toLowerCase(),
      Order.STATUS_COMPLETED.toLowerCase(),
      Order.STATUS_CANCELLED.toLowerCase(),
      Order.STATUS_OUT_FOR_DELIVERY.toLowerCase(),
      Order.STATUS_DISPATCHED.toLowerCase(),
    ].contains(status.toLowerCase()); // Normalize status to lowercase
    if (canCancel) {
      buttons.add(_actionButton('Cancel', () => _showRejectConfirmation(order),
          isDestructive: true));
    }

    switch (status.toLowerCase()) {
      // Normalize status to lowercase for all logic
      case 'pending':
        buttons.add(_actionButton(
            'Accept', () => _updateSimpleOrderStatus(order, 'accepted')));
        break;
      case 'accepted':
      case 'preparing':
        buttons.add(_actionButton(
            'Ready / Assign', () => _handleReadyForShipping(order),
            isPrimary: true));
        break;
      case 'ready for pickup': // Order.STATUS_READY_FOR_PICKUP.toLowerCase()
        buttons.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Waiting for rider...",
                style: TextStyle(
                    fontSize: 12,
                    color: subtleText,
                    fontStyle: FontStyle.italic))));
        buttons.add(_actionButton(
            'Assign Specific', () => _handleReadyForShipping(order)));
        break;
      case 'assigned': // Order.STATUS_ASSIGNED.toLowerCase()
        buttons.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Rider Assigned",
                style: TextStyle(
                    fontSize: 12,
                    color: assignedColor,
                    fontWeight: FontWeight.w500))));
        // Allow re-assignment? (Could add button here)
        break;
      // No more producer actions after assignment/dispatch typically
      case 'dispatched': // Order.STATUS_DISPATCHED.toLowerCase()
      case 'out for delivery': // Order.STATUS_OUT_FOR_DELIVERY.toLowerCase()
      case 'delivered': // Order.STATUS_DELIVERED.toLowerCase()
      case 'completed': // Order.STATUS_COMPLETED.toLowerCase()
      case 'cancelled': // Order.STATUS_CANCELLED.toLowerCase()
      default:
        break; // No actions
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.end,
      children: buttons,
    );
  }

  // Build Styled Action Button
  Widget _actionButton(String label, VoidCallback onPressed,
      {bool isPrimary = false, bool isDestructive = false}) {
    Color bgColor = actionButtonBackground;
    Color fgColor = actionButtonForeground;
    if (isPrimary) {
      bgColor = primaryTeal;
      fgColor = textOnTeal;
    } else if (isDestructive) {
      bgColor = destructiveButtonBackground;
      fgColor = destructiveButtonForeground;
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: isPrimary ? 1 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  // --- Produce/Stock Tab UI ---
  Widget _buildProduceTab() {
    if (_isLoadingProduce && _produce.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty && _profileFetchError.isEmpty && _produce.isEmpty) {
      // Check if general error and no specific profile error, and produce list is empty
      return _buildErrorView(); // Or a more specific "Could not load produce"
    }

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Show edit form or stock list
          if (_editingProduceId != null)
            _buildProduceEditSection()
          else
            _buildStockSelectionSection(),

          // Spacer at bottom if editing form is shown
          if (_editingProduceId != null) const SizedBox(height: 100),
        ],
      ),
    );
  }

  // Build Stock Selection Section
  Widget _buildStockSelectionSection() {
    if (_produce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      // Show empty state only if not loading, no error, and list is truly empty
      return _buildEmptyState(
        'No Produce Items Found',
        'Tap the (+) button below to add the first produce item.',
        icon: Icons.eco_outlined,
      );
    }
    // If there's an error specific to produce or a general error and produce is empty
    if (_error.isNotEmpty && _produce.isEmpty) {
      return _buildErrorView(); // Or a more specific "Failed to load produce"
    }
    return _buildProduceListForStock(); // Refined list builder for stock
  }

  // Build Produce Edit Section (Form)
  Widget _buildProduceEditSection() {
    if (_editingProduceId == null) return const SizedBox.shrink();
    // Find the product being edited (could be TEMP or existing)
    final productToEdit = _produce
        .firstWhere((p) => p.produceId == _editingProduceId, orElse: () {
      print("Error: Product with ID $_editingProduceId not found for editing.");
      WidgetsBinding.instance.addPostFrameCallback((_) => _cancelProduceEdit());
      return Product(produceId: 'invalid', produceName: 'Error'); // Placeholder
    });
    if (productToEdit.produceId == 'invalid')
      return const SizedBox.shrink(); // Return empty if not found
    return _buildProduceEditForm(productToEdit);
  }

  // Build the List for Selecting Stock and Quantities
  Widget _buildProduceListForStock() {
    final availableProduce =
        _produce.where((p) => !p.produceId.startsWith('TEMP_')).toList();

    if (availableProduce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      // Check again to ensure context after _produce might have changed
      return _buildEmptyState("No Produce Items Defined",
          "Add produce items using the (+) button first.",
          icon: Icons.inventory_2_outlined);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Select Available Stock",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkTeal)),
              if (_selectedProduceIds.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedProduceIds.clear();
                    _produceQuantities.clear();
                  }),
                  child: Text("Clear All",
                      style: TextStyle(fontSize: 12, color: subtleText)),
                )
            ],
          ),
        ),
        Card(
          elevation: 1.5,
          color: whiteColor.withOpacity(0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: availableProduce.length,
                itemBuilder: (context, index) {
                  final product = availableProduce[index];
                  final bool isSelected =
                      _selectedProduceIds.contains(product.produceId);
                  return Column(children: [
                    CheckboxListTile(
                      title: Text(product.produceName,
                          style: TextStyle(fontSize: 14, color: textOnWhite)),
                      subtitle: product.unitGrams != null
                          ? Text(
                              "${product.calories ?? '-'} kcal / ${product.unitGrams}g",
                              style: TextStyle(fontSize: 11, color: subtleText))
                          : null,
                      value: isSelected,
                      onChanged: (bool? selected) => setState(() {
                        if (selected == true) {
                          _selectedProduceIds.add(product.produceId);
                          _produceQuantities.putIfAbsent(
                              product.produceId, () => 1); // Default to 1
                        } else {
                          _selectedProduceIds.remove(product.produceId);
                          _produceQuantities.remove(product.produceId);
                        }
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      activeColor: primaryTeal,
                      secondary: IconButton(
                        icon: Icon(Icons.edit_note_outlined,
                            size: 20, color: subtleText),
                        tooltip: 'Edit Produce Item Details',
                        onPressed: () => _handleEditProduce(
                            product), // Allow editing from stock list
                      ),
                    ),
                    // Quantity input shown only when selected
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 56.0, right: 16.0, bottom: 12.0),
                        child: Row(children: [
                          const Text("Quantity:",
                              style:
                                  TextStyle(fontSize: 13, color: subtleText)),
                          const SizedBox(width: 12),
                          SizedBox(
                              width: 80,
                              height: 40,
                              child: TextFormField(
                                key: ValueKey(product
                                    .produceId), // Ensure widget rebuilds correctly
                                initialValue:
                                    _produceQuantities[product.produceId]
                                            ?.toString() ??
                                        '1',
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 10),
                                    border: OutlineInputBorder(),
                                    hintText: "0",
                                    hintStyle: TextStyle(fontSize: 13)),
                                style: const TextStyle(
                                    fontSize: 14, color: textOnWhite),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                onChanged: (val) => setState(() {
                                  final parsed = int.tryParse(val) ?? 0;
                                  _produceQuantities[product.produceId] =
                                      parsed >= 0 ? parsed : 0;
                                }),
                                validator: (v) => (v == null ||
                                        v.isEmpty ||
                                        (int.tryParse(v) ?? -1) < 0)
                                    ? 'Invalid'
                                    : null,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                              )),
                          const Spacer(),
                          // Delete button removed to restrict deletion access for producers.
                        ]),
                      ),
                    if (index < availableProduce.length - 1)
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: dividerColor.withOpacity(0.5)),
                  ]);
                },
              )),
        ),
        // Update Stock button moved to FAB
      ],
    );
  }

  // Build the Form for Adding/Editing a Produce Item
  Widget _buildProduceEditForm(Product product) {
    final bool isNewItem = product.produceId.startsWith('TEMP_');
    return Card(
      elevation: 3.0,
      color: whiteColor.withOpacity(0.98),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: primaryTeal, width: 1.5)),
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
              key: _produceFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      isNewItem
                          ? 'Add New Produce Item'
                          : 'Edit "${product.produceName}"',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: darkTeal)),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _produceNameController,
                      decoration: _inputDecoration('Produce Name *'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _produceCaloriesController,
                            decoration: _inputDecoration('Calories (kcal)'),
                            style: const TextStyle(
                                fontSize: 14, color: textOnWhite),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: _validateOptionalNumber,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextFormField(
                            controller: _produceUnitGramsController,
                            decoration: _inputDecoration('Unit (g)'),
                            style: const TextStyle(
                                fontSize: 14, color: textOnWhite),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: _validateOptionalNumber,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _produceProteinsController,
                            decoration: _inputDecoration('Proteins (g)'),
                            style: const TextStyle(
                                fontSize: 14, color: textOnWhite),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [_decimalInputFormatter(1)],
                            validator: _validateOptionalNumber,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextFormField(
                            controller: _produceCarbsController,
                            decoration: _inputDecoration('Carbs (g)'),
                            style: const TextStyle(
                                fontSize: 14, color: textOnWhite),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [_decimalInputFormatter(1)],
                            validator: _validateOptionalNumber,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextFormField(
                            controller: _produceFatsController,
                            decoration: _inputDecoration('Fats (g)'),
                            style: const TextStyle(
                                fontSize: 14, color: textOnWhite),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [_decimalInputFormatter(1)],
                            validator: _validateOptionalNumber,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction)),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _produceSourceController,
                      decoration: _inputDecoration('Source URL (optional)'),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      keyboardType: TextInputType.url,
                      maxLines: 1,
                      validator: (v) => (v != null &&
                              v.isNotEmpty &&
                              (Uri.tryParse(v) == null ||
                                  !Uri.tryParse(v)!.isAbsolute))
                          ? 'Invalid URL'
                          : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Spacer(), // Push other buttons right
                    TextButton(
                        onPressed: _cancelProduceEdit,
                        child: const Text('Cancel',
                            style: TextStyle(color: subtleText)),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8))),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(isNewItem ? 'Add Item' : 'Save Changes'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryTeal,
                          foregroundColor: textOnTeal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      onPressed: _saveProduceChanges,
                    ),
                  ]),
                ],
              ))),
    );
  }

  // Input Decoration Helper for Produce Form
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
          borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide(color: dividerColor.withOpacity(0.8))),
      errorStyle: const TextStyle(fontSize: 11, color: errorColor),
    );
  }

  // Validator for Optional Numeric Fields
  String? _validateOptionalNumber(String? value) {
    if (value != null && value.isNotEmpty) {
      if (double.tryParse(value) == null) return 'Invalid #';
      if (double.parse(value) < 0) return '>= 0';
    }
    return null;
  }

  // Input Formatter for Decimal Numbers
  TextInputFormatter _decimalInputFormatter(int decimalPlaces) {
    String dp = decimalPlaces > 0 ? '{0,$decimalPlaces}' : '';
    return FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d' + dp));
  }

  // Build Empty State Widget
  Widget _buildEmptyState(String title, String subtitle,
      {required IconData icon}) {
    return Center(
        child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: subtleText.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textOnWhite),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(subtitle,
                    style: const TextStyle(fontSize: 14, color: subtleText),
                    textAlign: TextAlign.center),
                // Optional: Add a refresh button to empty states
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.grey[700],
                    elevation: 0,
                  ),
                  onPressed: () => _fetchAllData(forceRefresh: true),
                ),
              ],
            )));
  }

  // --- Status Color and Icon Helpers ---
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      // Normalize status to lowercase for all logic
      case Order.STATUS_PENDING:
        return pendingColor;
      case 'accepted': // Order.STATUS_ACCEPTED.toLowerCase()
        return acceptedColor;
      case 'preparing': // Order.STATUS_PREPARING.toLowerCase()
        return preparingColor;
      case 'ready for pickup': // Order.STATUS_READY_FOR_PICKUP.toLowerCase()
        return readyForPickupColor;
      case 'assigned': // Order.STATUS_ASSIGNED.toLowerCase()
        return assignedColor;
      case 'dispatched': // Order.STATUS_DISPATCHED.toLowerCase()
        return dispatchedColor;
      case 'out for delivery': // Order.STATUS_OUT_FOR_DELIVERY.toLowerCase()
        return outForDeliveryColor;
      case 'delivered': // Order.STATUS_DELIVERED.toLowerCase()
        return deliveredColor;
      case 'completed': // Order.STATUS_COMPLETED.toLowerCase()
        return completedColor;
      case 'cancelled': // Order.STATUS_CANCELLED.toLowerCase()
        return cancelledColor;
      default:
        return defaultStatusColor;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      // Normalize status to lowercase for all logic
      case Order.STATUS_PENDING:
        return Icons.pending_actions_outlined;
      case 'accepted': // Order.STATUS_ACCEPTED.toLowerCase()
        return Icons.check_circle_outline_rounded;
      case 'preparing': // Order.STATUS_PREPARING.toLowerCase()
        return Icons.kitchen_outlined;
      case 'ready for pickup': // Order.STATUS_READY_FOR_PICKUP.toLowerCase()
        return Icons.inventory_2_outlined;
      case 'assigned': // Order.STATUS_ASSIGNED.toLowerCase()
        return Icons.person_pin_circle_outlined;
      case 'dispatched': // Order.STATUS_DISPATCHED.toLowerCase()
        return Icons.local_shipping_outlined;
      case 'out for delivery': // Order.STATUS_OUT_FOR_DELIVERY.toLowerCase()
        return Icons.two_wheeler_rounded;
      case 'delivered': // Order.STATUS_DELIVERED.toLowerCase()
        return Icons.done_all_rounded;
      case 'completed': // Order.STATUS_COMPLETED.toLowerCase()
        return Icons.celebration_outlined;
      case 'cancelled': // Order.STATUS_CANCELLED.toLowerCase()
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline_rounded;
    }
  }
} // End of _ProducerDash22State

// --- Rider Selection Dialog ---
class _RiderSelectionDialog extends StatefulWidget {
  final int orderId;
  // Removed ApiService parameter, using static methods now

  const _RiderSelectionDialog({required this.orderId});

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
      // Use static method from ProducerApiService
      final riders = await ProducerApiService.fetchAvailableRiders();
      if (mounted) {
        riders.sort((a, b) {
          // Sort: Active first, then alphabetically
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
      print("[ProducerDash] Error fetching riders in dialog: $e");
      if (mounted) {
        setState(() {
          _errorMessage =
              "Error fetching riders: ${e.toString().split('Body:')[0]}";
          _isLoading = false;
        }); // Shorten error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Assign Rider'),
        IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchRiders,
            tooltip: 'Refresh Rider List',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.5,
        child: _buildContent(),
      ),
      actions: <Widget>[
        TextButton(
            child: const Text("Mark Ready for Any Rider"),
            onPressed: () => Navigator.of(context).pop(true)), // Return true
        TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(null)), // Return null
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_errorMessage != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_errorMessage!,
                    style: TextStyle(color: errorColor),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                ElevatedButton(
                    onPressed: _fetchRiders, child: const Text("Retry"))
              ])));
    }
    if (_allRiders.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("No riders found.", textAlign: TextAlign.center)));
    }

    return ListView.builder(
      itemCount: _allRiders.length,
      itemBuilder: (context, index) {
        final rider = _allRiders[index];
        final bool isAvailable = rider.isActive;
        final Color tileColor = isAvailable
            ? Theme.of(context).dialogBackgroundColor
            : Colors.grey.shade200;
        // Use textOnWhite for text color in dialog for better readability
        final Color textColor = isAvailable
            ? textOnWhite
            : Colors.grey
                .shade600; // Assuming textOnWhite is appropriate for dialog
        final Color iconColor =
            isAvailable ? primaryTeal : Colors.grey.shade500;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: isAvailable ? 1 : 0.5,
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
            subtitle: Text(
                isAvailable
                    ? 'Status: Active (${rider.status})'
                    : 'Status: Inactive (${rider.status})',
                style:
                    TextStyle(color: textColor.withOpacity(0.7), fontSize: 11)),
            trailing: isAvailable
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.block, color: Colors.grey, size: 18),
            onTap: () {
              // Pop immediately with the rider object (confirmation happens outside)
              Navigator.of(context).pop(rider);
            },
            dense: true,
          ),
        );
      },
    );
  }
}
