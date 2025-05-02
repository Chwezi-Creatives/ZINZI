import 'dart:async';

import 'package:flutter/material.dart';
// ignore: library_prefixes
import 'package:zinzi2/app_drawer_unified.dart' as drawer; // Use prefix
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart'; // For shimmer effect

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zinzi2/user_cache.dart'; // <<< IMPORT UserCache
import 'package:zinzi2/cache_config.dart'; // <<< IMPORT CacheConfig

// --- UI Constants ---
const Color primaryTeal = Color(0xFF009688);
const Color lightTeal = Color(0xFFB2DFDB);
const Color faintLightTeal = Color(0xFFE0F2F1);
const Color darkTeal = Color(0xFF00695C);
const Color whiteColor = Colors.white;
const Color textOnTeal = Colors.white;
const Color textOnWhite = Color(0xFF212121);
const Color subtleText = Color(0xFF757575);
const Color cardBackground = Color(0xFFF1F8F8); // Slightly off-white teal tint
const Color errorColor = Color(0xFFD32F2F);
const Color starColor = Color(0xFFFFC107); // Amber/Gold
const Color dividerColor = Color(0xFFE0E0E0);

// Status Colors (Centralized Definition)
final Color pendingColor = Colors.orange.shade600;
final Color acceptedColor = Colors.blue.shade600;
final Color preparingColor = Colors.deepPurple.shade400;
final Color dispatchedColor = primaryTeal; // Or Ready for Pickup color
final Color deliveredColor = Colors.green.shade600;
final Color cancelledColor = Colors.red.shade600;
final Color defaultStatusColor = Colors.grey.shade600;
final Color assignedColor = Colors.blueGrey.shade600; // For assigned rider

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

// Helper to parse boolean safely (Used in Rider and ProducerProfile)
bool _parseBoolSafe(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true' || value == '1';
  if (value is int) return value == 1;
  return false;
}

// --- Data Models ---

// Inline Order class based on API data
class Order {
  final int orderId;
  final String mealName; // Sometimes product name
  final DateTime orderDate;
  final double totalPrice;
  final int quantity;
  String orderStatus; // Mutable
  final String? customerName; // Assuming producerName can be customer name
  final String? deliveryAddress;
  final String? notes;
  final String? ingredients;
  final String? paymentStatus;
  int? assignedRiderId; // Added for assigning riders
  String? assignedRiderName; // Added for displaying assigned rider name

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
    DateTime parsedDate;
    try {
      // Prioritize standard ISO 8601 parsing first
      parsedDate = DateTime.parse(json['order_date'] as String);
    } catch (e) {
      // Fallback for Flask's default format if ISO fails
      try {
        final apiDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
        parsedDate = apiDateFormat.parseUtc(json['order_date'] as String).toLocal();
      } catch (e2) {
        print("[ProducerDash] Error parsing date: ${json['order_date']} - $e - $e2. Using current time.");
        parsedDate = DateTime.now(); // Final fallback
      }
    }

    try {
      final order = Order(
        orderId: _parseInt(json['order_id']),
        mealName: _getStringSafe(json['product_name']) ?? 'Unknown Product', // Handle potential null
        orderDate: parsedDate,
        totalPrice: _parseDouble(json['total_price']),
        quantity: _parseInt(json['quantity']),
        orderStatus: _getStringSafe(json['order_status']) ?? Order.STATUS_PENDING,
        paymentStatus: _getStringSafe(json['payment_status']),
        notes: _getStringSafe(json['notes']),
        deliveryAddress: _getStringSafe(json['delivery_address']),
        customerName: _getStringSafe(json['producer_name']) ?? _getStringSafe(json['customer_name']), // Try producer or customer name
        ingredients: _getStringSafe(json['ingredients']),
        assignedRiderId: _parseIntNullable(json['assigned_rider_id'] ?? json['transporter_id']), // Check multiple keys
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
    ValueGetter<int?>? assignedRiderId, // Use ValueGetter for nullable fields
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
      assignedRiderId: assignedRiderId != null ? assignedRiderId() : this.assignedRiderId,
      assignedRiderName: assignedRiderName != null ? assignedRiderName() : this.assignedRiderName,
    );
  }

  // Standardized Status Constants
  static const String STATUS_PENDING = 'Pending';
  static const String STATUS_ACCEPTED = 'Accepted'; // Producer Accepts
  static const String STATUS_PREPARING = 'Preparing'; // Producer Prepares (Optional step)
  static const String STATUS_READY_FOR_PICKUP = 'Ready for Pickup'; // Producer Marks Ready for ANY Rider
  static const String STATUS_ASSIGNED = 'Assigned'; // Producer Assigns SPECIFIC Rider
  static const String STATUS_DISPATCHED = 'Dispatched'; // Can mean "Ready" or "Shipped" depending on context
  static const String STATUS_OUT_FOR_DELIVERY = 'Out for Delivery'; // Set by Rider
  static const String STATUS_DELIVERED = 'Delivered'; // Set by Rider/Producer
  static const String STATUS_CANCELLED = 'Cancelled'; // Set by Producer/System
  static const String STATUS_COMPLETED = 'Completed'; // Often synonymous with Delivered
}

// Inline ProducerProfile class
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
  final String? userType;
  final bool? isEmailVerified;
  final List<Map<String, dynamic>>? stock; // Stock field

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
      'stock': stock, // Include stock in JSON serialization
    };
  }

  factory ProducerProfile.fromJson(Map<String, dynamic> json) {
    try {
      List<Map<String, dynamic>>? parseStock(dynamic value) {
        if (value == null) return null; // Keep null if API sends null
        if (value is String) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is List) {
              // Ensure items are Maps
              return decoded.whereType<Map<String, dynamic>>().toList();
            }
          } catch (e) {
            print("[ProducerDash] Error decoding stock JSON string: $e");
          }
        } else if (value is List) {
          // Ensure items are Maps
          return value.whereType<Map<String, dynamic>>().toList();
        }
        print("[ProducerDash] Warning: Unexpected stock format: ${value.runtimeType}. Returning null.");
        return null; // Return null if format is unexpected
      }

      final profile = ProducerProfile(
        producerId: _parseInt(json['producer_id']),
        name: _getStringSafe(json['name']) ?? 'Unknown Producer',
        email: _getStringSafe(json['email']),
        phoneNumber: _getStringSafe(json['phone_number']),
        location: _getStringSafe(json['location']),
        image: _getStringSafe(json['image']),
        isActive: _parseBoolSafe(json['is_active']),
        registrationDate: json['registration_date'] != null
            ? DateTime.parse(json['registration_date'] as String)
            : DateTime.now(), // Default to current time if null
        lastLogin: json['last_login'] != null
            ? DateTime.parse(json['last_login'] as String)
            : null,
        producerType: _getStringSafe(json['producer_type']),
        rating: _parseDoubleNullable(json['rating']),
        reviews: _getStringSafe(json['reviews']),
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
    ValueGetter<DateTime?>? lastLogin, // Allow setting to null
    String? producerType,
    ValueGetter<double?>? rating, // Allow setting to null
    String? reviews,
    String? userType,
    bool? isEmailVerified,
    ValueGetter<List<Map<String, dynamic>>?>? stock, // Allow setting to null
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
      reviews: reviews ?? this.reviews,
      userType: userType ?? this.userType,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      stock: stock != null ? stock() : this.stock,
    );
  }
}

// Inline Product class
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
    try {
      // Ensure 'produce_id' exists and is a string
      final produceId = _getStringSafe(json['produce_id']);
      if (produceId == null || produceId.isEmpty) {
         throw FormatException("Missing or invalid 'produce_id' in Product JSON: $json");
      }

      final product = Product(
        produceId: produceId,
        produceName: _getStringSafe(json['produce_name']) ?? '', // Ensure name is not null
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
    ValueGetter<int?>? calories, // Use ValueGetter for nullable
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
      carbohydrates: carbohydrates != null ? carbohydrates() : this.carbohydrates,
      fats: fats != null ? fats() : this.fats,
      proteins: proteins != null ? proteins() : this.proteins,
      unitGrams: unitGrams != null ? unitGrams() : this.unitGrams,
      source: source != null ? source() : this.source,
    );
  }
}

// Inline Rider/Transporter Model (Copied from ChefDash)
class Rider {
  final int id;
  final String name;
  final String status; // Keep original status string if needed elsewhere
  final bool isActive; // NEW: Field for availability based on 'is_active'

  Rider({
    required this.id,
    required this.name,
    required this.status,
    required this.isActive,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    return Rider(
      id: _parseIntNullable(json['rider_id'] ?? json['transporter_id'] ?? json['id']) ?? 0,
      name: _getStringSafe(json['name'] ?? json['rider_name'] ?? json['transporter_name']) ?? 'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown',
      isActive: _parseBoolSafe(json['is_active']),
    );
  }
}

// --- API Service ---
class ProducerApiService {
  static final String apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://your-api.example.com';

  static Future<String?> _getProducerId() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getString('producer_id');
    } catch (e) {
      print("[ProducerDash] SharedPreferences error: $e");
      return null;
    }
  }

  // Handles potential nested 'data' key or direct list/map
  static dynamic _handleApiResponse(dynamic responseData) {
    if (responseData is Map && responseData.containsKey('data')) {
      return responseData['data'];
    } else if (responseData is List) {
      return responseData; // Already a list
    } else if (responseData is Map) {
      // If it's a map but no 'data' key, return the map itself
      return responseData;
    }
    print("[ProducerDash] API response format warning: Got ${responseData.runtimeType}");
    return null; // Indicate unexpected format
  }

  static Map<String, String> _getReadHeaders() {
    return {'Accept': 'application/json'};
  }

  static Map<String, String> _getWriteHeaders({bool requiresAuth = false}) { // Default to false unless specific call needs it
    String? authToken; // Implement actual token retrieval if needed
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    if (requiresAuth && authToken != null && authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  // --- Profile Methods ---
  static Future<ProducerProfile> fetchProducerProfile() async {
    final producerId = await _getProducerId();
    if (producerId == null || producerId.isEmpty) {
      throw Exception('Producer ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/rproducers/$producerId');
    print("[ProducerDash] Fetching profile: $uri");

    try {
      final response = await http.get(uri, headers: _getReadHeaders());
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        Map<String, dynamic>? profileMap;
        if (handledData is List && handledData.isNotEmpty) {
          profileMap = handledData[0] as Map<String, dynamic>;
        } else if (handledData is Map<String, dynamic>) {
           // Check if it's the actual profile map (e.g., has 'producer_id')
          if (handledData.containsKey('producer_id')) {
            profileMap = handledData;
          } else {
            // Handle cases where 'data' might contain a map but not the profile itself
             print("[ProducerDash] Warning: Profile map missing expected 'producer_id' key.");
             throw Exception('Failed to parse profile: API response map missing key.');
          }
        }

        if (profileMap == null) {
           print('[ProducerDash] ERROR: Producer profile data is null after handling response.');
           throw Exception('Producer profile not found in API response.');
        }

        return ProducerProfile.fromJson(profileMap);
      } else {
        print('[ProducerDash] Profile fetch failed: ${response.statusCode} ${response.body}');
        throw Exception('Failed to fetch producer profile (Status: ${response.statusCode}).');
      }
    } catch (e, stack) {
      print('[ProducerDash] Profile fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateProducerStatus(int producerId, bool isActive) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/producers/$producerId/status');
    print("[ProducerDash] Updating status for $producerId to $isActive at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode({'is_active': isActive}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
         print("[ProducerDash] Status update successful.");
        return true;
      } else {
        print("[ProducerDash] Error updating producer status: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating producer status: $e");
      return false;
    }
  }

  static Future<bool> updateProducerProfile(int producerId,
      {required String name, String? phoneNumber, String? location}) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/producers/$producerId');
     print("[ProducerDash] Updating profile for $producerId at $uri");
    Map<String, dynamic> payload = {
      'name': name, // Name is required
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
      if (location != null && location.isNotEmpty) 'location': location,
    };
     print("[ProducerDash] Update payload: ${jsonEncode(payload)}");
    try {
      final response = await http.put( // Assuming PUT for full/partial update
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        print("[ProducerDash] Profile update successful.");
        return true;
      } else {
        print("[ProducerDash] Error updating producer profile: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating producer profile: $e");
      return false;
    }
  }

  // --- Order Methods ---
  static Future<List<Order>> fetchProducerOrders() async {
    final producerId = await _getProducerId();
    if (producerId == null || producerId.isEmpty) {
      throw Exception('Producer ID not found. Please log in again.');
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/orders?producer_id=$producerId');
    print("[ProducerDash] Fetching orders: $uri");

    try {
      final response = await http.get(uri, headers: _getReadHeaders());
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        if (handledData is List) {
          final List<Order> orders = handledData
              .map<Order>((orderJson) => Order.fromJson(orderJson))
              .toList();
          print("[ProducerDash] Fetched ${orders.length} orders");
          return orders;
        } else {
          print('[ProducerDash] Orders response format error: expected List, got ${handledData.runtimeType}');
          return []; // Return empty list if format is wrong
        }
      } else {
        print('[ProducerDash] Orders fetch failed: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e, stack) {
      print('[ProducerDash] Orders fetch error: $e\n$stack');
      return [];
    }
  }

  // Update Order Status (For Accept, Prepare, Cancel, Ready for Pickup)
  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status');
    print("[ProducerDash] Updating order $orderId status to $newStatus at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode({'order_status': newStatus}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
         print("[ProducerDash] Order status update successful.");
        return true;
      } else {
        print("[ProducerDash] Order status update failed: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Order status update error: $e");
      return false;
    }
  }

  // Assign Order to Specific Rider
  static Future<bool> assignOrderToRider(int orderId, int riderId, String newStatus) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status'); // Assume same endpoint
    print("[ProducerDash] Assigning order $orderId to rider $riderId, status $newStatus at $uri");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode(<String, dynamic>{
          'order_status': newStatus,
          'transporter_id': riderId, // Ensure API expects this key
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        print("[ProducerDash] Rider assignment successful.");
        return true;
      } else {
        print("[ProducerDash] Error assigning order: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception assigning order: $e");
      return false;
    }
  }

  // --- Rider Methods ---
  static Future<List<Rider>> fetchAvailableRiders() async {
    final Uri uri = Uri.parse('$apibaseurl/rr/transporters'); // Endpoint for riders/transporters
    print("[ProducerDash] Fetching available riders from: $uri");
    try {
      final response = await http.get(uri, headers: _getReadHeaders());
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic riderList = _handleApiResponse(rawData);

        if (riderList is List) {
          if (riderList.isEmpty) {
             print("[ProducerDash] No riders found.");
             return [];
          }
          final List<Rider> riders = riderList
              .map((jsonItem) {
                if (jsonItem is Map<String, dynamic>) {
                  return Rider.fromJson(jsonItem);
                } else {
                  print("[ProducerDash] API Warning: Skipping non-map item in riders list: $jsonItem");
                  return null;
                }
              })
              .whereType<Rider>()
              .toList();
           print("[ProducerDash] Fetched ${riders.length} riders.");
           return riders;
        } else {
          print("[ProducerDash] Riders API response format unexpected: Expected List, got ${riderList?.runtimeType}");
          return [];
        }
      } else {
        print("[ProducerDash] Error fetching riders: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load riders (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print("[ProducerDash] Exception fetching riders: $e");
      if (e is Exception) rethrow;
      throw Exception('Failed to load riders: $e');
    }
  }

  // --- Produce and Stock Methods ---
  static Future<List<Product>> fetchProducerProduce() async {
    // This fetches the MASTER LIST of all possible produce items
    final Uri uri = Uri.parse('$apibaseurl/rr/produce');
    print("[ProducerDash] Fetching master produce list: $uri");
    try {
      final response = await http.get(uri, headers: _getReadHeaders());
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic handledData = _handleApiResponse(rawData);

        if (handledData is List) {
          final List<Product> produce = handledData
              .map<Product>((prodJson) => Product.fromJson(prodJson))
              .toList();
          print("[ProducerDash] Fetched ${produce.length} produce items from master list.");
          return produce;
        } else {
          print('[ProducerDash] Produce response format error: expected List, got ${handledData.runtimeType}');
          return [];
        }
      } else {
        print('[ProducerDash] Produce fetch failed: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e, stack) {
      print('[ProducerDash] Produce fetch error: $e\n$stack');
      return [];
    }
  }

  // Updates the producer's stock list (PATCH request to producer profile)
  static Future<bool> updateProducerStock(int producerId, List<Map<String, dynamic>> stockList) async {
     final Uri uri = Uri.parse('$apibaseurl/rr/producers/$producerId');
     print("[ProducerDash] Updating stock for producer $producerId at $uri");
     // API expects {"stock": [{"produce_id": "...", "quantity": ...}, ...]}
     final payload = jsonEncode({"stock": stockList});
     print("[ProducerDash] Stock update payload: $payload");
     try {
       final response = await http.patch( // Use PATCH for partial update
         uri,
         headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
         body: payload,
       );
       if (response.statusCode == 200 || response.statusCode == 204) {
         print("[ProducerDash] Stock update successful.");
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


  // Adds a new produce item to the master list
  static Future<Product?> addProduce(Map<String, dynamic> produceData) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/produce');
    print("[ProducerDash] Adding new produce item at $uri");
    try {
      final payload = {
        'produce_name': produceData['produce_name'] as String?,
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': produceData['source'] as String?,
      };
      payload.removeWhere((key, value) => value == null || (value is String && value.isEmpty));

      if (payload['produce_name'] == null || (payload['produce_name'] as String).isEmpty) {
        print("[ProducerDash] Error adding produce: Produce name is required.");
        return null;
      }
      print("[ProducerDash] Add produce payload: ${jsonEncode(payload)}");

      final response = await http.post(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        final dynamic responseData = json.decode(response.body);
        final dynamic createdProduceData = _handleApiResponse(responseData);
        if (createdProduceData is Map<String, dynamic>) {
           print("[ProducerDash] Add produce successful, received created item.");
          return Product.fromJson(createdProduceData);
        } else {
           print("[ProducerDash] Add produce succeeded but couldn't parse response body: ${response.body}");
          return null;
        }
      } else {
        print("[ProducerDash] Error adding produce: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("[ProducerDash] Exception adding produce: $e");
      return null;
    }
  }

  // Updates an existing produce item in the master list
  static Future<bool> updateProduce(String produceId, Map<String, dynamic> produceData) async {
    if (produceId.isEmpty) {
      print("[ProducerDash] Error updating produce: Invalid Produce ID.");
      return false;
    }
    // Assuming PUT to /rr/uproduce?produce_id={id} based on original code
    final Uri uri = Uri.parse('$apibaseurl/rr/uproduce?produce_id=$produceId');
     print("[ProducerDash] Updating produce item $produceId at $uri");
    try {
      final payload = {
        'produce_name': produceData['produce_name'] as String?,
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': produceData['source'] as String?,
      };
      payload.removeWhere((key, value) => value == null || (value is String && value.isEmpty));

      if (payload['produce_name'] == null || (payload['produce_name'] as String).trim().isEmpty) {
        print("[ProducerDash] Error updating produce: Produce name cannot be empty.");
        return false;
      }
       print("[ProducerDash] Update produce payload: ${jsonEncode(payload)}");

      final response = await http.put(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
         print("[ProducerDash] Update produce successful.");
        return true;
      } else {
        print("[ProducerDash] Error updating produce $produceId: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("[ProducerDash] Exception updating produce $produceId: $e");
      return false;
    }
  }

  // Deletes a produce item from the master list
  static Future<bool> deleteProduce(String produceId) async {
    if (produceId.isEmpty) {
      print("[ProducerDash] Error deleting produce: Invalid Produce ID.");
      return false;
    }
    // Assuming DELETE to /rr/uproduce?produce_id={id} based on original code
    final Uri uri = Uri.parse('$apibaseurl/rr/uproduce?produce_id=$produceId');
     print("[ProducerDash] Deleting produce item $produceId at $uri");
    try {
      final response = await http.delete(
        uri,
        headers: _getWriteHeaders(requiresAuth: false), // Adjust auth if needed
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
         print("[ProducerDash] Delete produce successful.");
        return true;
      } else {
        print("[ProducerDash] Error deleting produce $produceId: ${response.statusCode} ${response.body}");
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
  const ProducerDash22({super.key}); // Removed static key

  @override
  State<ProducerDash22> createState() => _ProducerDash22State();
}

class _ProducerDash22State extends State<ProducerDash22> {
  // --- State fields ---
  int _currentIndex = 0;
  ProducerProfile? _profile;
  List<Order> _orders = [];
  List<Product> _produce = []; // Holds the MASTER list of all produce items
  List<Rider> _riders = []; // Holds available riders (fetched on demand)
  bool _isLoading = true; // Combined loading for initial fetch
  bool _isLoadingProfile = false; // Specific loading for profile
  bool _isLoadingOrders = false;  // Specific loading for orders
  bool _isLoadingProduce = false; // Specific loading for produce master list
  String _error = ''; // General error message for combined fetch
  String _profileFetchError = ''; // Specific error for profile fetch

  // Stock Management State (Tracks producer's CURRENT stock based on master list)
  Set<String> _selectedProduceIds = {}; // IDs of produce items the producer has in stock
  Map<String, int> _produceQuantities = {}; // Quantity for each selected stock item

  // Profile Editing State
  bool _isEditingProfile = false;
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  late TextEditingController _profileLocationController;
  bool _isLoadingLocation = false; // For location fetching
  bool _isUploadingProfileImage = false; // For image upload
  String? _uploadedProfileImageUrl; // Temp storage for uploaded URL

  // Produce Item Editing State (For managing the MASTER list)
  String? _editingProduceId; // ID of the produce item being added/edited
  TextEditingController? _produceNameController;
  TextEditingController? _produceCaloriesController;
  TextEditingController? _produceProteinsController;
  TextEditingController? _produceCarbsController;
  TextEditingController? _produceFatsController;
  TextEditingController? _produceUnitGramsController;
  TextEditingController? _produceSourceController;

  // Caching State
  ProducerProfile? _profileCache;
  DateTime? _profileCacheTimestamp;

  // Form Keys
  final GlobalKey<FormState> _produceFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _profileNameController = TextEditingController();
    _profilePhoneController = TextEditingController();
    _profileLocationController = TextEditingController();
    // Fetch data when the widget initializes
    _fetchAllData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This is generally called after initState.
    // We already call _fetchAllData in initState, so may not need it here
    // unless dependencies change significantly.
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
    // Set controllers to null after disposing
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
    if (!mounted) return;
    setState(() {
      _isLoading = true; // Show combined loading indicator
      _error = '';
      _cancelAllEdits(); // Cancel edits before refresh
    });

    try {
      // Fetch profile (cache-first) and other data concurrently
      await Future.wait([
        _initializeProducerProfile(forceRefresh: forceRefresh),
        _fetchOrdersAndProduce(forceRefresh: forceRefresh),
      ]);

      // Check mount status again after async operations
      if (mounted) {
         // Sync stock selection after all data (profile and produce) is fetched
         _syncSelectionFromProfile();
         setState(() {
           _isLoading = false; // Hide combined loading indicator
         });
      }
    } catch (e, stackTrace) {
      debugPrint("[ProducerDash] Error fetching all data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load data. Please check connection.';
          // Clear potentially stale data
          _profile = null;
          _orders = [];
          _produce = [];
          _selectedProduceIds.clear();
          _produceQuantities.clear();
        });
      }
    }
  }

  // Fetches Orders and Produce (Master List)
  Future<void> _fetchOrdersAndProduce({bool forceRefresh = false}) async {
    // Simple fetch for now, caching could be added similarly to profile if needed
    try {
      if (!mounted) return;
      setState(() {
        _isLoadingOrders = true;
        _isLoadingProduce = true;
      });

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
          _produce.sort((a, b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
          _isLoadingOrders = false;
          _isLoadingProduce = false;
        });
      }
    } catch (e) {
      print("[ProducerDash] Error fetching orders/produce: $e");
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
          _isLoadingProduce = false;
           // Set general error or specific errors if needed
          _error = _error.isEmpty ? 'Failed to load orders/produce.' : _error;
        });
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
       // If forcing refresh, clear the in-memory cache variables
      _profileCache = null;
      _profileCacheTimestamp = null;
    }

    // 2. Display cached data immediately if available and valid
    bool shouldFetchFresh = true; // Assume we need to fetch unless cache is valid
    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!) < CacheConfig.profileCacheDuration;

      if (cacheIsValid && !forceRefresh) {
        print("ProducerDash: Displaying valid cached profile.");
        setState(() {
          _profile = _profileCache;
          _isLoadingProfile = false; // Stop indicator, data is valid
        });
        shouldFetchFresh = false; // Don't fetch fresh if cache is valid
      } else {
         print("ProducerDash: Cached profile ${forceRefresh ? 'ignored (force refresh)' : 'expired'}, will fetch fresh data.");
        // Keep showing stale cache while fetching
        setState(() {
          _profile = _profileCache; // Show stale data
        });
      }
    } else if (mounted) {
       print("ProducerDash: No cached profile found${forceRefresh ? ' (force refresh)' : ''}, fetching...");
    }

    // 3. Fetch fresh data if needed
    if (shouldFetchFresh && mounted) {
       print("ProducerDash: Fetching fresh profile data...");
      await _fetchProducerProfileAndUpdate();
    } else if (mounted) {
       // If we didn't fetch fresh (valid cache), ensure loading indicator is off
       if (!_isLoadingProfile) { // Double-check if it's already off
         setState(() => _isLoadingProfile = false);
       }
    }
  }

  // Separate function to fetch Producer Profile and update state/cache
  Future<void> _fetchProducerProfileAndUpdate() async {
    try {
      final profile = await ProducerApiService.fetchProducerProfile();
      if (mounted) {
        print("ProducerDash: Fetched fresh producer profile data successfully.");
        await _saveProfileCacheToPrefs(profile, DateTime.now());
        setState(() {
          _profile = profile;
          _isLoadingProfile = false; // Done loading profile
          _profileFetchError = '';
           // Sync stock selection AFTER profile is fetched/updated
          _syncSelectionFromProfile();
        });
      }
    } catch (error, stackTrace) {
      print("[ProducerDash] Error fetching fresh producer profile: $error\n$stackTrace");
      if (mounted) {
        final errorMsg = 'Failed to load profile: $error';
        setState(() {
          _profileFetchError = errorMsg;
          _isLoadingProfile = false; // Stop profile loading
           // If there's no cached profile either, set the general error
          if (_profile == null) {
             _error = _error.isEmpty ? errorMsg : _error;
          }
        });
         // Show snackbar only if no profile data is available at all
        if (_profile == null) {
          _showErrorSnackBar('Error loading profile.');
        }
      }
    }
  }

  Future<void> _loadProfileCacheFromPrefs() async {
     print("[ProducerDash] Loading profile cache from Prefs...");
    final cachedJson = await UserCache.getData('producer_profile');
    final timestampStr = await UserCache.getData('producer_profile_cache_timestamp');
    if (cachedJson is Map<String, dynamic>) { // Check type
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
    if (timestampStr is String) { // Check type
      _profileCacheTimestamp = DateTime.tryParse(timestampStr);
    } else {
      _profileCacheTimestamp = null;
    }
  }

  Future<void> _saveProfileCacheToPrefs(ProducerProfile profile, DateTime timestamp) async {
     print("[ProducerDash] Saving profile to cache...");
    await UserCache.saveData('producer_profile', profile.toJson());
    await UserCache.saveData('producer_profile_cache_timestamp', timestamp.toIso8601String());
     print("[ProducerDash] Profile saved to cache.");
  }

  void _sortOrders() {
    _orders.sort((a, b) {
      int statusCompare = _statusPriority(a.orderStatus).compareTo(_statusPriority(b.orderStatus));
      if (statusCompare != 0) return statusCompare;
      return b.orderDate.compareTo(a.orderDate); // Newest first if status same
    });
  }

  int _statusPriority(String status) {
    switch (status) {
      case Order.STATUS_PENDING: return 0;
      case Order.STATUS_ACCEPTED: return 1;
      case Order.STATUS_PREPARING: return 2;
      case Order.STATUS_READY_FOR_PICKUP: return 3; // Added
      case Order.STATUS_ASSIGNED: return 4;          // Added
      case Order.STATUS_DISPATCHED: return 5;        // Shifted
      case Order.STATUS_OUT_FOR_DELIVERY: return 6;  // Added
      case Order.STATUS_DELIVERED: return 7;         // Shifted
      case Order.STATUS_COMPLETED: return 8;         // Added
      case Order.STATUS_CANCELLED: return 9;         // Shifted
      default: return 10;
    }
  }

  // Helper to sync UI selections (_selectedProduceIds, _produceQuantities) from profile stock
  void _syncSelectionFromProfile() {
    if (_profile == null) {
      print("[ProducerDash] Cannot sync stock selection: Profile not loaded.");
      return; // Can't sync if profile isn't loaded
    }
    print("[ProducerDash] Syncing stock selection from profile data...");
    final newSelectedIds = <String>{};
    final newQuantities = <String, int>{};

    if (_profile!.stock != null && _profile!.stock!.isNotEmpty) {
      for (var stockItem in _profile!.stock!) {
        // Ensure 'produce_id' and 'quantity' exist and are valid types
        final produceId = _getStringSafe(stockItem['produce_id']);
        final quantity = _parseIntNullable(stockItem['quantity']);

        if (produceId != null && produceId.isNotEmpty && quantity != null && quantity >= 0) {
          // Check if this produce ID exists in the master list (_produce)
          if (_produce.any((p) => p.produceId == produceId)) {
            newSelectedIds.add(produceId);
            newQuantities[produceId] = quantity;
          } else {
             print("[ProducerDash] Warning: Stock item ID '$produceId' not found in master produce list during sync.");
          }
        } else {
           print("[ProducerDash] Warning: Invalid stock item found during sync: $stockItem");
        }
      }
    } else {
      print("[ProducerDash] Profile stock is null or empty. Clearing selections.");
    }

    // Update state only if changes occurred to avoid unnecessary rebuilds
    if (newSelectedIds != _selectedProduceIds || newQuantities != _produceQuantities) {
       print("[ProducerDash] Stock sync updated state: ${newSelectedIds.length} items selected.");
      setState(() {
        _selectedProduceIds = newSelectedIds;
        _produceQuantities = newQuantities;
      });
    } else {
       print("[ProducerDash] Stock sync completed, no changes detected.");
    }
  }

  // --- Order Action Handlers (Including Rider Assignment) ---

  // Handles simple status updates like Accept, Prepare, Cancel
  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return; // Order not found
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final originalStatus = _orders[orderIndex].orderStatus;
    // Optimistic UI Update
    setState(() {
      _orders[orderIndex].orderStatus = newStatus;
       // Clear rider if status reverts to non-assigned state
       if ([Order.STATUS_ACCEPTED, Order.STATUS_PREPARING, Order.STATUS_CANCELLED].contains(newStatus)) {
           _orders[orderIndex] = _orders[orderIndex].copyWith(
             assignedRiderId: () => null,
             assignedRiderName: () => null,
           );
       }
      _sortOrders(); // Re-sort after status change
    });
    _showLoadingSnackbar("Updating status to $newStatus...");

    try {
      bool success = await ProducerApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (!success) {
          _showErrorSnackBar('Failed to update order ${order.orderId} status.');
          setState(() { // Revert UI on failure
            _orders[orderIndex].orderStatus = originalStatus;
            _sortOrders();
          });
        } else {
          _showSuccessSnackbar('Order ${order.orderId} status updated to $newStatus.');
          _showOrderNextStepDialog(newStatus); // Show guidance
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error updating simple order status: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred updating status.');
        setState(() { // Revert UI on exception
          _orders[orderIndex].orderStatus = originalStatus;
          _sortOrders();
        });
      }
    }
  }

  // Handles the "Ready/Assign" action, triggering the rider selection flow
  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _RiderSelectionDialog(orderId: order.orderId); // Pass ID
      },
    );

    if (!mounted) return;

    if (result is Rider) {
      print("Rider ${result.name} selected for Order ${order.orderId}. Showing confirmation...");
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      print("Marking Order ${order.orderId} as Ready for Pickup (Any Rider)");
      await _markReadyForAnyRider(order);
    } else {
      print("Rider assignment cancelled or dialog closed.");
    }
  }

  // Shows confirmation dialog before assigning a specific rider
  Future<void> _showRiderAssignmentConfirmation(Order order, Rider rider) async {
    if (!mounted) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Confirm Assignment for Order #${order.orderId}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign this order to rider:'),
              const SizedBox(height: 8),
              Text('  Name: ${rider.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('  Status: ${rider.isActive ? "Active" : "Inactive"} (${rider.status})'), // Show isActive and original status string
              Text('  ID: ${rider.id}'),
              if (!rider.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Warning: Rider is currently inactive.', style: TextStyle(color: Colors.orange.shade800)),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text(rider.isActive ? 'Confirm Assignment' : 'Assign Anyway', style: TextStyle(color: primaryTeal)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      if (!mounted) return;
      print("Confirmation received. Assigning Order ${order.orderId} to Rider ${rider.id} (${rider.name})");
      await _assignSpecificRider(order, rider); // Proceed with assignment
    } else {
      print("Rider assignment cancelled by user.");
      _showInfoSnackbar("Rider assignment cancelled.");
    }
  }

  // Calls API to assign a specific rider (called AFTER confirmation)
  Future<void> _assignSpecificRider(Order order, Rider rider) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;

    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;

    // Optimistic UI Update
    setState(() {
      _orders[orderIndex] = _orders[orderIndex].copyWith(
        orderStatus: Order.STATUS_ASSIGNED,
        assignedRiderId: () => rider.id,
        assignedRiderName: () => rider.name,
      );
      _sortOrders();
    });
    _showLoadingSnackbar("Assigning to ${rider.name}...");

    try {
      bool success = await ProducerApiService.assignOrderToRider(order.orderId, rider.id, Order.STATUS_ASSIGNED);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Order ${order.orderId} assigned to ${rider.name}.');
          _showOrderNextStepDialog(Order.STATUS_ASSIGNED);
        } else {
          _showErrorSnackBar('Failed to assign order ${order.orderId} to ${rider.name}.');
          setState(() { // Revert UI
            _orders[orderIndex] = _orders[orderIndex].copyWith(
              orderStatus: originalStatus,
              assignedRiderId: () => originalRiderId,
              assignedRiderName: () => originalRiderName,
            );
            _sortOrders();
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error assigning specific rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while assigning the rider.');
        setState(() { // Revert UI
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
      // Use the general status update API for this action
      bool success = await ProducerApiService.updateOrderStatus(order.orderId, Order.STATUS_READY_FOR_PICKUP);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Order ${order.orderId} marked as Ready for Pickup.');
          _showOrderNextStepDialog(Order.STATUS_READY_FOR_PICKUP);
        } else {
          _showErrorSnackBar('Failed to mark order ${order.orderId} as Ready for Pickup.');
          setState(() { // Revert UI
             _orders[orderIndex] = _orders[orderIndex].copyWith(
               orderStatus: originalStatus,
               assignedRiderId: () => originalRiderId,
               assignedRiderName: () => originalRiderName,
             );
            _sortOrders();
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("[ProducerDash] Error marking ready for any rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while updating order status.');
        setState(() { // Revert UI
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Confirm Rejection"),
          content: Text("Reject Order #${order.orderId} (${order.mealName})? This cannot be undone."),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text("Reject Order", style: TextStyle(color: errorColor)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog first
                _updateSimpleOrderStatus(order, Order.STATUS_CANCELLED); // Call update with Cancelled status
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
      print("[ProducerDash] Warning: Order $orderId not found in _orders list for update.");
    }
    return index;
  }

  // --- Profile Edit Handlers ---
  void _handleEditProfile() {
    if (_profile == null || !mounted) return;
    debugPrint('Edit Profile Action Triggered');
    setState(() {
      _isEditingProfile = true;
      _profileNameController.text = _profile!.name;
      _profilePhoneController.text = _profile!.phoneNumber ?? '';
      _profileLocationController.text = _profile!.location ?? '';
    });
  }

  Future<void> _saveProfileChanges() async {
    if (_profile == null || !mounted || !_isEditingProfile) return;
    if (_profileFormKey.currentState?.validate() ?? false) {
      debugPrint('Save Profile Changes Action Triggered');
      _showLoadingSnackbar('Saving profile...');
      try {
        final String name = _profileNameController.text.trim();
        final String? phone = _profilePhoneController.text.trim().isEmpty ? null : _profilePhoneController.text.trim();
        final String? location = _profileLocationController.text.trim().isEmpty ? null : _profileLocationController.text.trim();

        bool success = await ProducerApiService.updateProducerProfile(
          _profile!.producerId,
          name: name,
          phoneNumber: phone,
          location: location,
        );
        _dismissLoadingSnackbar();
        if (!mounted) return;

        if (success) {
          // Fetch the updated profile to reflect changes accurately
          await _initializeProducerProfile(forceRefresh: true);
          setState(() {
            _isEditingProfile = false;
          });
          _showSuccessSnackbar('Profile updated successfully.');
        } else {
          _showErrorSnackBar('Failed to save profile changes.');
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
      _isEditingProfile = false;
      // Reset controllers to original values if needed, but typically just exiting edit mode is enough
    });
  }

  Future<void> _handleToggleActiveStatus(bool newStatus) async {
    if (_profile == null || !mounted || _isEditingProfile) return;
    debugPrint('Toggle Active Status Action Triggered: New Status = $newStatus');
    _showLoadingSnackbar('Updating status...');
    try {
      bool success = await ProducerApiService.updateProducerStatus(_profile!.producerId, newStatus);
      _dismissLoadingSnackbar();
      if (!mounted) return;
      if (success) {
        // Update local state immutably
        setState(() => _profile = _profile!.copyWith(isActive: newStatus));
        _showSuccessSnackbar('Profile status updated to ${newStatus ? "Active" : "Offline"}.');
      } else {
        setState(() {}); // Trigger rebuild to revert switch
        _showErrorSnackBar('Failed to update status.');
      }
    } catch (e) {
      debugPrint("Error toggling active status via API: $e");
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {}); // Revert switch on error
        _showErrorSnackBar('An error occurred updating status: $e');
      }
    }
  }

  // --- Stock and Produce Item Management Handlers ---

  // Triggered by FAB or "Add Produce" button
  void _handleAddProduce() {
    if (_editingProduceId != null || !mounted || _isEditingProfile) return;
    debugPrint('Add Produce Action Triggered');
    final newId = 'TEMP_${DateTime.now().millisecondsSinceEpoch}';
    final newProduct = Product(produceId: newId, produceName: ''); // Empty product
    _initializeProduceEditControllers(newProduct);
    setState(() {
      // Temporarily add to list to show the edit form
      _produce.add(newProduct);
      _produce.sort((a, b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
      _editingProduceId = newId;
    });
    _showInfoSnackbar('Fill in details for the new produce item.');
  }

  // Triggered by tapping a produce item card
  void _handleEditProduce(Product product) {
    if (!mounted || _isEditingProfile) return;
    debugPrint('Edit Produce Action Triggered for ID: ${product.produceId}');
    _cancelAllEdits(exceptProduceId: product.produceId);
    _initializeProduceEditControllers(product);
    setState(() => _editingProduceId = product.produceId);
  }

  // Initializes controllers for the produce edit form
  void _initializeProduceEditControllers(Product product) {
    _produceNameController = TextEditingController(text: product.produceName);
    _produceCaloriesController = TextEditingController(text: product.calories?.toString() ?? '');
    _produceProteinsController = TextEditingController(text: product.proteins?.toStringAsFixed(1) ?? '');
    _produceCarbsController = TextEditingController(text: product.carbohydrates?.toStringAsFixed(1) ?? '');
    _produceFatsController = TextEditingController(text: product.fats?.toStringAsFixed(1) ?? '');
    _produceUnitGramsController = TextEditingController(text: product.unitGrams?.toString() ?? '');
    _produceSourceController = TextEditingController(text: product.source ?? '');
  }

  // Saves changes from the produce edit form (calls Add or Update API)
  Future<void> _saveProduceChanges() async {
    if (_editingProduceId == null || !mounted) return;
    if (_produceFormKey.currentState?.validate() ?? false) {
      final String idToSave = _editingProduceId!;
      final int index = _produce.indexWhere((p) => p.produceId == idToSave);
      if (index == -1) {
        _cancelProduceEdit();
        return;
      }
      final bool isNewItem = idToSave.startsWith('TEMP_');
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
                _produce.add(addedProduct); // Add real
                _produce.sort((a, b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null;
                _disposeProduceEditControllers();
              });
              _showSuccessSnackbar('Added "${addedProduct.produceName}".');
            } else {
              _showErrorSnackBar('Failed to add produce.');
              setState(() { // Remove TEMP on failure
                _produce.removeAt(index);
                _editingProduceId = null;
                _disposeProduceEditControllers();
              });
            }
          }
        } else { // Update existing
          bool success = await ProducerApiService.updateProduce(idToSave, payload);
          _dismissLoadingSnackbar();
          if (mounted) {
            if (success) {
              // Update local list immutably
              final updatedProduct = _produce[index].copyWith(
                 produceName: payload['produce_name'],
                 calories: () => _parseIntNullable(payload['calories']),
                 proteins: () => _parseDoubleNullable(payload['proteins']),
                 carbohydrates: () => _parseDoubleNullable(payload['carbohydrates']),
                 fats: () => _parseDoubleNullable(payload['fats']),
                 unitGrams: () => _parseIntNullable(payload['unit_grams']),
                 source: () => payload['source'],
              );
              setState(() {
                _produce[index] = updatedProduct;
                 _produce.sort((a, b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null;
                _disposeProduceEditControllers();
              });
              _showSuccessSnackbar('Updated "${updatedProduct.produceName}".');
            } else {
              _showErrorSnackBar('Failed to update "${payload['produce_name'] ?? 'produce'}".');
            }
          }
        }
      } catch (e) {
        debugPrint("Error saving produce via API: $e");
        _dismissLoadingSnackbar();
        if (mounted) {
          _showErrorSnackBar('An error occurred saving produce: $e');
          if (isNewItem) { // Clean up TEMP item on exception
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

  // Cancels editing a produce item
  void _cancelProduceEdit() {
    if (!mounted) return;
    debugPrint('Cancel Produce Edit Action Triggered');
    final String? idToCancel = _editingProduceId;
    setState(() {
      _editingProduceId = null;
      _disposeProduceEditControllers();
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary new produce item on cancel.");
      }
    });
  }

  // Shows confirmation and handles deleting a produce item from the master list
  void _handleDeleteProduce(Product product) {
    if (!mounted || _isEditingProfile || (_editingProduceId != null && _editingProduceId != product.produceId)) return;
    debugPrint('Delete Produce Action Triggered for ID: ${product.produceId}');
    if (product.produceId.startsWith('TEMP_')) { // Just cancel if it's a TEMP item
      _cancelProduceEdit();
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: whiteColor.withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          title: const Row(children: [Icon(Icons.warning_amber_rounded, color: errorColor), SizedBox(width: 10), Text('Confirm Deletion')]),
          content: Text('Permanently delete "${product.produceName}" from the system?\nThis cannot be undone.', style: const TextStyle(color: subtleText)),
          actions: <Widget>[
            TextButton(style: TextButton.styleFrom(foregroundColor: subtleText), child: const Text('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: 16), label: const Text('Delete'),
              style: ElevatedButton.styleFrom(backgroundColor: destructiveButtonBackground, foregroundColor: destructiveButtonForeground, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                Navigator.of(ctx).pop();
                _performDeleteProduce(product);
              },
            ),
          ],
        );
      },
    );
  }

  // Performs the actual deletion API call and updates state
  Future<void> _performDeleteProduce(Product product) async {
    _showLoadingSnackbar('Deleting "${product.produceName}"...');
    try {
      bool success = await ProducerApiService.deleteProduce(product.produceId);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          final deletedName = product.produceName;
          setState(() {
            _produce.removeWhere((p) => p.produceId == product.produceId);
            // Remove from stock selection as well
            _selectedProduceIds.remove(product.produceId);
            _produceQuantities.remove(product.produceId);
          });
          _showSuccessSnackbar('Deleted "$deletedName".');
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

  // Updates the producer's stock via API call
  Future<void> _updateProducerStock() async {
    if (_profile == null) {
      _showErrorSnackBar('Profile not loaded. Cannot update stock.');
      return;
    }
    // Prepare stock list in the format API expects: [{"produce_id": ..., "quantity": ...}]
    final stockList = _selectedProduceIds.map((id) {
       // Ensure quantity is valid (non-null, non-negative)
       final quantity = _produceQuantities[id];
       if (quantity == null || quantity < 0) {
         print("[ProducerDash] Warning: Invalid quantity ($quantity) for produce ID $id. Skipping.");
         return null; // Skip items with invalid quantity
       }
       return {'produce_id': id, 'quantity': quantity};
    }).whereType<Map<String, dynamic>>().toList(); // Filter out nulls

    if (stockList.isEmpty) {
      _showInfoSnackbar('No items selected or quantities set to update stock.');
      return;
    }

    _showLoadingSnackbar('Updating stock...');
    try {
      bool success = await ProducerApiService.updateProducerStock(_profile!.producerId, stockList);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Stock updated successfully.');
          // Refresh profile to get latest stock state from backend
          await _initializeProducerProfile(forceRefresh: true);
           // Sync UI selection AFTER profile refresh completes
           _syncSelectionFromProfile();
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
      if (_editingProduceId!.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == _editingProduceId);
        debugPrint("Removed temporary produce item due to action/switch.");
      }
      _editingProduceId = null;
      _disposeProduceEditControllers();
      didCancel = true;
    }
    if (didCancel) {
      setState(() {});
      debugPrint("Cancelled active edits due to action/switch.");
    }
  }

  // --- Location Fetching ---
  Future<void> _getCurrentLocation() async {
     // Only allow fetching if editing profile
    if (!_isEditingProfile || !mounted) return;
    setState(() => _isLoadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Location permissions permanently denied.');
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String displayAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      try {
        final apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
           _showInfoSnackbar('Could not fetch address.');
        }
      } catch (e) {
        print("Reverse geocoding failed: $e");
         _showInfoSnackbar('Could not fetch address.');
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
  void _showSnackbar(String message, {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: isError ? whiteColor : textOnTeal), textAlign: TextAlign.center),
        backgroundColor: isError ? errorColor.withOpacity(0.9) : primaryTeal.withOpacity(0.9),
        duration: Duration(seconds: durationSeconds),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        elevation: 2.0,
      ),
    );
  }

  void _showErrorSnackBar(String message) => _showSnackbar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackbar(String message) => _showSnackbar(message, isError: false);
  void _showInfoSnackbar(String message) => _showSnackbar(message, isError: false, durationSeconds: 2); // Use normal style for info

  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..removeCurrentSnackBar()..showSnackBar(
      SnackBar(
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
          const SizedBox(width: 15),
          Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
        backgroundColor: Colors.black.withOpacity(0.8),
        duration: const Duration(minutes: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
      ),
    );
  }

  void _dismissLoadingSnackbar() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  void _showOrderNextStepDialog(String newStatus) {
     if (!mounted) return;
    String message; String title; IconData icon;
    switch (newStatus) {
      case Order.STATUS_ACCEPTED: title = "Order Accepted"; message = "Start preparing the order. Mark 'Ready/Assign' when done."; icon = Icons.check_circle_outline; break;
      case Order.STATUS_PREPARING: title = "Order Preparing"; message = "Mark 'Ready/Assign' once ready."; icon = Icons.kitchen_outlined; break;
      case Order.STATUS_READY_FOR_PICKUP: title = "Ready for Pickup"; message = "Order is now available for any rider to collect."; icon = Icons.inventory_2_outlined; break;
      case Order.STATUS_ASSIGNED: title = "Rider Assigned"; message = "The assigned rider has been notified to pick up the order."; icon = Icons.person_pin_circle_outlined; break;
      case Order.STATUS_DISPATCHED: title = "Order Dispatched"; message = "Order marked as dispatched."; icon = Icons.local_shipping_outlined; break;
      case Order.STATUS_OUT_FOR_DELIVERY: title = "Out for Delivery"; message = "Rider is en route."; icon = Icons.two_wheeler_rounded; break;
      case Order.STATUS_DELIVERED: title = "Order Delivered"; message = "Order completed successfully."; icon = Icons.done_all; break;
      case Order.STATUS_COMPLETED: title = "Order Completed"; message = "Order is marked as completed."; icon = Icons.celebration_outlined; break;
      case Order.STATUS_CANCELLED: title = "Order Cancelled"; message = "Order has been cancelled."; icon = Icons.cancel_outlined; break;
      default: title = "Order Updated"; message = "Order status updated to '$newStatus'."; icon = Icons.info_outline;
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [Icon(icon, color: primaryTeal), const SizedBox(width: 8), Text(title)]),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK"))],
    ));
  }


  // --- Build Method and UI Widgets ---
  @override
  Widget build(BuildContext context) {
    // Determine AppBar Avatar Image
    ImageProvider? appBarAvatarImage;
    if (_isLoadingProfile || _profile == null) {
      appBarAvatarImage = const AssetImage(placeholderImagePath);
    } else if (_profile!.image != null && _profile!.image!.isNotEmpty) {
      try {
        Uri.parse(_profile!.image!); // Validate URL
        appBarAvatarImage = CachedNetworkImageProvider(_profile!.image!); // Use Cached provider
      } catch (e) {
        debugPrint("Invalid URL for AppBar image: ${_profile!.image}");
        appBarAvatarImage = const AssetImage(placeholderImagePath);
      }
    } else {
      appBarAvatarImage = const AssetImage(placeholderImagePath);
    }

    return Scaffold(
      // Use the unified drawer with prefix
      drawer: drawer.AppDrawer(invokedBy: 'producer_dashboard'),
      backgroundColor: Colors.grey[100], // Light grey background for contrast
      appBar: AppBar(
        backgroundColor: primaryTeal,
        elevation: 2.0,
        iconTheme: const IconThemeData(color: textOnTeal),
        title: Text(_getAppBarTitle(), style: const TextStyle(color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: false,
        actions: [
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () => _fetchAllData(forceRefresh: true),
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
                   // No need to setState here, fallback is handled by initial logic
                 },
                child: appBarAvatarImage is AssetImage ? const Icon(Icons.person, color: Colors.grey, size: 24) : null,
              ),
            ),
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: textOnTeal),
            tooltip: 'Logout',
            onPressed: () {
              debugPrint("Logout tapped");
              _showSnackbar('Logout action simulated.', isError: false);
              // TODO: Navigator.pushReplacementNamed(context, '/login');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBodyContent(), // Main content based on state
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index != _currentIndex && mounted) {
            _cancelAllEdits();
            setState(() => _currentIndex = index);
          }
        },
        backgroundColor: whiteColor.withOpacity(0.98),
        selectedItemColor: primaryTeal,
        unselectedItemColor: subtleText.withOpacity(0.9),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 8.0,
        items: [
          _buildBottomNavItem(Icons.account_circle_outlined, Icons.account_circle, 'Profile', 0),
          _buildBottomNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 1),
          _buildBottomNavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Stock', 2), // Stock Management Tab
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  BottomNavigationBarItem _buildBottomNavItem(IconData icon, IconData activeIcon, String label, int index) {
     bool isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavItemIcon(isSelected ? activeIcon : icon, isSelected),
      label: label,
    );
  }

  Widget _buildNavItemIcon(IconData iconData, bool isSelected) {
     final icon = Icon(
      iconData,
      color: isSelected ? primaryTeal : subtleText.withOpacity(0.8),
      size: 24,
    );
    // Removed the background circle for a cleaner look
    return SizedBox(width: 32, height: 32, child: Center(child: icon));
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0: return _isEditingProfile ? 'Edit Profile' : 'Producer Profile';
      case 1: return 'Manage Orders';
      case 2: return _editingProduceId != null ? (_editingProduceId!.startsWith("TEMP_") ? 'Add Produce Item' : 'Edit Produce Item') : 'Manage Stock & Produce';
      default: return 'Producer Dashboard';
    }
  }

  Widget? _buildFloatingActionButton() {
    if (_isEditingProfile || _editingProduceId != null) return null; // No FAB during edits

    switch (_currentIndex) {
      case 0: // Profile Tab
        return FloatingActionButton.small(
          onPressed: (_profile == null || _isLoadingProfile) ? null : _handleEditProfile,
          tooltip: 'Edit Profile',
          backgroundColor: (_profile == null || _isLoadingProfile) ? Colors.grey : primaryTeal,
          foregroundColor: textOnTeal,
          child: const Icon(Icons.edit_outlined, size: 20),
          heroTag: 'fab_profile_edit',
        );
      case 1: // Orders Tab
        return null; // No FAB for orders
      case 2: // Produce/Stock Tab
        if (_selectedProduceIds.isNotEmpty) {
          return FloatingActionButton.extended(
            onPressed: _updateProducerStock,
            tooltip: 'Update Stock Levels',
            icon: const Icon(Icons.update),
            label: const Text("Update Stock"),
            backgroundColor: darkTeal,
            foregroundColor: textOnTeal,
            heroTag: 'fab_stock_update',
          );
        } else {
          return FloatingActionButton(
            onPressed: _handleAddProduce,
            tooltip: 'Add New Produce Item',
            backgroundColor: primaryTeal,
            foregroundColor: textOnTeal,
            child: const Icon(Icons.add),
            heroTag: 'fab_produce_add',
          );
        }
      default: return null;
    }
  }

  Widget _buildBodyContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty) {
      return _buildErrorView();
    }
    // Use IndexedStack to preserve tab state
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildProfileTab(),
        _buildOrdersTab(),
        _buildProduceTab(), // Handles both stock selection and produce editing
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Card(
      color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(25.0), child: Column(
        mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: errorColor, size: 48),
          const SizedBox(height: 16),
          Text(_error, style: const TextStyle(color: textOnWhite, fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18), label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => _fetchAllData(forceRefresh: true), // Force refresh on retry
          ),
        ],
      )),
    )));
  }

  // --- Profile Tab UI ---
  Widget _buildProfileTab() {
     // Show loading specifically for profile if it's still loading
    if (_isLoadingProfile && _profile == null) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
     // Show error specific to profile fetch if it occurred and no cached data
    if (_profileFetchError.isNotEmpty && _profile == null) {
      return _buildProfileErrorView(); // Specific error view for profile
    }
     // If profile is loaded (or cache is available)
    if (_profile != null) {
       // Show editing UI or display UI
      return _isEditingProfile ? _buildProfileEditView(_profile!) : _buildProfileDisplayView(_profile!);
    }
    // Fallback empty state if profile is null and no error (shouldn't happen often)
    return _buildEmptyState(
      'Profile Unavailable',
      'Could not load profile details. Pull down to refresh.',
      icon: Icons.person_off_outlined,
    );
  }

  Widget _buildProfileErrorView() {
     return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Card(
      color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(25.0), child: Column(
        mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.person_off_outlined, color: errorColor, size: 48),
          const SizedBox(height: 16),
          Text("Error Loading Profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textOnWhite)),
          const SizedBox(height: 8),
          Text(_profileFetchError, style: const TextStyle(color: subtleText, fontSize: 14), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => _initializeProducerProfile(forceRefresh: true), // Retry fetching profile
          ),
        ],
      )),
    )));
  }


  Widget _buildProfileDisplayView(ProducerProfile profile) {
    final dateFormat = DateFormat('MMM d, yyyy, hh:mm a');
    // Use CachedNetworkImageProvider for better performance and error handling
    final profileAvatarImage = (profile.image != null && profile.image!.isNotEmpty)
        ? CachedNetworkImageProvider(profile.image!)
        : const AssetImage(placeholderImagePath) as ImageProvider;

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Profile Header Card
          Card(
            elevation: 2.0, color: cardBackground.withOpacity(0.95), margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0), child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, children: [
                CircleAvatar(
                  radius: 45, backgroundColor: lightTeal.withOpacity(0.5),
                  backgroundImage: profileAvatarImage,
                  onBackgroundImageError: (_, __) => debugPrint('Error loading profile network image'),
                   // Show icon if it's the placeholder asset
                  child: profileAvatarImage is AssetImage ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                ),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkTeal)),
                  if (profile.producerType != null && profile.producerType!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2.0), child: Text(profile.producerType!, style: const TextStyle(fontSize: 14, color: subtleText))),
                  if (profile.rating != null && profile.rating! > 0)
                    Padding(padding: const EdgeInsets.only(top: 8.0), child: Row(children: [
                      const Icon(Icons.star_rounded, color: starColor, size: 18), const SizedBox(width: 4),
                      Text(profile.rating!.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textOnWhite)),
                      if (profile.reviews != null && profile.reviews!.isNotEmpty && profile.reviews!.toLowerCase() != 'none') ...[
                        const SizedBox(width: 6), Text('(${profile.reviews} reviews)', style: const TextStyle(fontSize: 12, color: subtleText)),
                      ],
                    ])),
                ])),
              ],
            )),
          ),
          // Active Status Card
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
          // Info Section
          _buildProfileSectionCard(title: 'Contact & Details', icon: Icons.info_outline_rounded, children: [
            _buildDetailItem(Icons.email_outlined, 'Email', profile.email ?? ''),
            _buildDetailItem(Icons.phone_outlined, 'Phone', profile.phoneNumber ?? ''),
            _buildDetailItem(Icons.location_on_outlined, 'Location', profile.location ?? ''),
            _buildDetailItem(Icons.calendar_today_rounded, 'Registered', dateFormat.format(profile.registrationDate)),
             if (profile.lastLogin != null)
                 _buildDetailItem(Icons.access_time_rounded, 'Last Login', dateFormat.format(profile.lastLogin!)),
             if (profile.isEmailVerified != null)
                 _buildDetailItem(Icons.verified_outlined, 'Email Verified', profile.isEmailVerified! ? 'Yes' : 'No'),
            _buildDetailItem(Icons.person_outline_rounded, 'User Type', profile.userType ?? 'N/A'),
            _buildDetailItem(Icons.category_outlined, 'Producer Type', profile.producerType ?? 'N/A'),
          ]),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildProfileEditView(ProducerProfile profile) {
    return Form(
      key: _profileFormKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- Profile Image Handling (Placeholder/Example) ---
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: lightTeal.withOpacity(0.3),
                   backgroundImage: (_uploadedProfileImageUrl != null)
                       ? CachedNetworkImageProvider(_uploadedProfileImageUrl!) // Show uploaded if available
                       : ((profile.image != null && profile.image!.isNotEmpty)
                           ? CachedNetworkImageProvider(profile.image!) // Show current
                           : const AssetImage(placeholderImagePath) as ImageProvider), // Fallback
                   onBackgroundImageError: (_, __) {}, // Handle errors silently in background
                   child: _isUploadingProfileImage
                       ? const CircularProgressIndicator(color: primaryTeal)
                       : null,
                ),
                Material( // Button to pick image
                   color: primaryTeal, shape: const CircleBorder(), elevation: 2,
                   child: InkWell(
                      customBorder: const CircleBorder(), onTap: _pickAndUploadProfileImage, // TODO: Implement image picker
                      child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.camera_alt, color: whiteColor, size: 20)),
                   ),
                 ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // --- Editable Fields ---
          _buildEditableItem(_profileNameController, 'Producer Name *', Icons.person_outline_rounded, validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
          _buildEditableItem(_profilePhoneController, 'Phone Number', Icons.phone_outlined, keyboardType: TextInputType.phone),
          _buildEditableItem(_profileLocationController, 'Location / Service Area', Icons.location_on_outlined, maxLines: 2),
          // Location Fetch Button
          Padding(padding: const EdgeInsets.only(top: 4.0, left: 40), // Align with text field input
            child: TextButton.icon(
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              icon: _isLoadingLocation ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(_isLoadingLocation ? 'Fetching...' : 'Get Current Location'),
              style: TextButton.styleFrom(foregroundColor: primaryTeal, textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: 24),
          // --- Action Buttons ---
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _cancelProfileEdit, child: const Text('Cancel', style: TextStyle(color: subtleText)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: _saveProfileChanges,
            ),
          ]),
          const SizedBox(height: 80), // Space for bottom nav/FAB
        ],
      ),
    );
  }

  // Placeholder for image picking logic
  Future<void> _pickAndUploadProfileImage() async {
    // TODO: Implement image picking using image_picker
    // TODO: Implement image uploading to your backend/storage
    // TODO: Update _uploadedProfileImageUrl state on success
     _showInfoSnackbar("Image editing coming soon!");
    // setState(() => _isUploadingProfileImage = true);
    // await Future.delayed(Duration(seconds: 2)); // Simulate upload
    // setState(() {
    //   _uploadedProfileImageUrl = "https://via.placeholder.com/150/009688/FFFFFF/?text=NewPic"; // Example URL
    //   _isUploadingProfileImage = false;
    // });
  }

  Widget _buildProfileSectionCard({required String title, required IconData icon, required List<Widget> children}) {
     return Card(elevation: 1.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)), color: whiteColor.withOpacity(0.9), margin: const EdgeInsets.only(bottom: 16), child: Padding(
      padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: primaryTeal, size: 18), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal))]),
        const Divider(height: 16, thickness: 0.8, color: dividerColor),
        ...children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 4.0), child: child)),
      ]),
    ));
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)), const SizedBox(width: 10),
      SizedBox(width: 90, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, color: textOnWhite, fontSize: 13))),
      Expanded(child: Text(value.isEmpty ? 'Not provided' : value, style: TextStyle(color: value.isEmpty ? subtleText.withOpacity(0.7) : subtleText, fontSize: 13), softWrap: true)),
    ]));
  }

  Widget _buildEditableItem(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text, String? Function(String?)? validator}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, size: 18, color: primaryTeal.withOpacity(0.9)), prefixIconConstraints: const BoxConstraints(minWidth: 36),
        isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
        labelStyle: const TextStyle(color: subtleText, fontSize: 13), floatingLabelStyle: const TextStyle(color: primaryTeal),
         errorStyle: const TextStyle(fontSize: 11, color: errorColor), // Added error style
      ),
      style: const TextStyle(color: textOnWhite, fontSize: 13),
      maxLines: maxLines, keyboardType: keyboardType,
      validator: validator, // Use the provided validator
      autovalidateMode: AutovalidateMode.onUserInteraction,
    ));
  }


  // --- Orders Tab UI ---
  Widget _buildOrdersTab() {
    // Show loading specific to orders if applicable
    if (_isLoadingOrders && _orders.isEmpty) {
       return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
     // Show general error if orders failed to load (and no profile error shown)
    if (_error.isNotEmpty && _profileFetchError.isEmpty && _orders.isEmpty) {
      return _buildErrorView(); // Use the general error view
    }

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // No summary section shown if no orders
          if (_orders.isNotEmpty) ...[
             _buildOrdersListSection(),
          ] else if (!_isLoading) ...[
             // Show empty state only when not loading and orders list is empty
             _buildEmptyState(
               'No Orders Yet',
               'New customer orders will appear here.',
               icon: Icons.receipt_long_outlined,
             ),
          ] else ...[
             // If still loading but list is empty (initial load scenario)
             const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator(color: primaryTeal))),
          ]
        ],
      ),
    );
  }

  Widget _buildOrdersListSection() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: (index == _orders.length - 1) ? 0 : 12.0),
          child: _buildOrderItem(_orders[index]), // Use the modified card builder
        );
      },
    );
  }

  // Modified Order Item Card with Expansion Tile and Actions
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
          order.mealName, // Product name
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3.0),
          child: Text(
            '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
            style: const TextStyle(fontSize: 12, color: subtleText),
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              NumberFormat.currency(symbol: 'UGX ', decimalDigits: 0).format(order.totalPrice), // Format price
              style: const TextStyle(fontWeight: FontWeight.bold, color: darkTeal, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text('${order.quantity} item${order.quantity > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: subtleText)),
          ],
        ),
        children: [
          Divider(height: 1, color: dividerColor.withOpacity(0.7)),
          Padding(padding: const EdgeInsets.all(12.0), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildOrderDetailItem('Customer', order.customerName ?? 'Unknown'),
              _buildOrderDetailItem('Status', order.orderStatus, color: statusColor),
              _buildOrderDetailItem('Payment', order.paymentStatus ?? 'Unknown'),
              if (order.notes != null && order.notes!.isNotEmpty)
                _buildOrderDetailItem('Notes', order.notes!),
              if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
                _buildOrderDetailItem('Delivery To', order.deliveryAddress!),
               // Show Assigned Rider if available
               if (order.assignedRiderId != null)
                  _buildOrderDetailItem(
                    'Assigned Rider',
                    '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}',
                     color: assignedColor // Use specific color for rider
                  ),
              const SizedBox(height: 12),
              _buildOrderActions(order), // Action buttons
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildOrderDetailItem(String label, String value, {Color? color}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: textOnWhite))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: color ?? subtleText), softWrap: true)),
    ]));
  }

  // Builds action buttons based on status, including Dispatch/Assign
  Widget _buildOrderActions(Order order) {
    List<Widget> buttons = [];
    String status = order.orderStatus;

    // Common Reject/Cancel action (visible in most active states)
     bool canCancel = ![Order.STATUS_DELIVERED, Order.STATUS_COMPLETED, Order.STATUS_CANCELLED, Order.STATUS_OUT_FOR_DELIVERY]
                        .contains(status);
     if (canCancel) {
        buttons.add(_actionButton('Cancel', () => _showRejectConfirmation(order), isDestructive: true));
     }

    switch (status) {
      case Order.STATUS_PENDING:
        buttons.add(_actionButton('Accept', () => _updateSimpleOrderStatus(order, Order.STATUS_ACCEPTED)));
        break;
      case Order.STATUS_ACCEPTED:
      case Order.STATUS_PREPARING: // Allow preparing or directly assigning from Accepted/Preparing state
         buttons.add(_actionButton('Ready / Assign', () => _handleReadyForShipping(order), isPrimary: true));
         // Optional: Add a separate "Start Preparing" button if needed
         // if (status == Order.STATUS_ACCEPTED) {
         //   buttons.add(_actionButton('Start Prep', () => _updateSimpleOrderStatus(order, Order.STATUS_PREPARING)));
         // }
        break;
      case Order.STATUS_READY_FOR_PICKUP:
         // Optionally show info that it's waiting for ANY rider
         buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text("Waiting for rider...", style: TextStyle(fontSize: 12, color: subtleText, fontStyle: FontStyle.italic))));
         // Allow re-assigning a specific rider even if marked as ready for any? (Optional)
         buttons.add(_actionButton('Assign Specific', () => _handleReadyForShipping(order)));
         break;
      case Order.STATUS_ASSIGNED:
         // Optionally show assigned rider info here too or just rely on the details section
         buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text("Rider Assigned", style: TextStyle(fontSize: 12, color: assignedColor, fontWeight: FontWeight.w500))));
         // Allow changing assigned rider? (More complex flow)
         // buttons.add(_actionButton('Re-assign', () => _handleReadyForShipping(order)));
        break;
      // No more actions typically initiated by Producer after Assignment/Ready
      case Order.STATUS_DISPATCHED:
      case Order.STATUS_OUT_FOR_DELIVERY:
      case Order.STATUS_DELIVERED:
      case Order.STATUS_COMPLETED:
      case Order.STATUS_CANCELLED:
      default:
        break; // No actions
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    // Use Wrap for button layout
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.end,
      children: buttons,
    );
  }

   // Helper for creating styled action buttons consistently
  Widget _actionButton(String label, VoidCallback onPressed, {bool isPrimary = false, bool isDestructive = false}) {
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
        elevation: isPrimary ? 1 : 0, // Add slight elevation for primary action
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }


  // --- Produce/Stock Tab UI ---
  Widget _buildProduceTab() {
     // Show loading specific to produce if applicable
    if (_isLoadingProduce && _produce.isEmpty) {
       return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
     // Show general error if produce failed to load
     if (_error.isNotEmpty && _profileFetchError.isEmpty && _produce.isEmpty) {
        return _buildErrorView();
     }

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Conditionally show edit form or stock list
          if (_editingProduceId != null)
            _buildProduceEditSection() // Edit form for ONE produce item
          else
            _buildStockSelectionSection(), // List for selecting MULTIPLE stock items

          if (_editingProduceId != null) const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStockSelectionSection() {
     if (_produce.isEmpty && !_isLoading) {
      return _buildEmptyState(
        'No Produce Items Found',
        'Tap the (+) button below to add the first produce item.',
        icon: Icons.eco_outlined,
      );
    }
    // Use the refined list builder for stock selection
    return _buildProduceListForStock();
  }

  Widget _buildProduceEditSection() {
    if (_editingProduceId == null) return const SizedBox.shrink();
    final productToEdit = _produce.firstWhere((p) => p.produceId == _editingProduceId, orElse: () {
      print("Error: Product with ID $_editingProduceId not found for editing.");
      WidgetsBinding.instance.addPostFrameCallback((_) => _cancelProduceEdit());
      return Product(produceId: 'invalid', produceName: 'Error');
    });
    if (productToEdit.produceId == 'invalid') return const SizedBox.shrink();
    return _buildProduceEditForm(productToEdit); // Show the edit form
  }

   // Builds the list for selecting/managing stock quantities
  Widget _buildProduceListForStock() {
     // Filter out temporary items from stock selection view
     final availableProduce = _produce.where((p) => !p.produceId.startsWith('TEMP_')).toList();

    if (availableProduce.isEmpty && !_isLoadingProduce) {
      return _buildEmptyState("No Produce Items Defined", "Add produce items using the (+) button first.", icon: Icons.inventory_2_outlined);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Select Available Stock", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkTeal)),
              // Optional: Button to clear all selections
              if (_selectedProduceIds.isNotEmpty) TextButton(
                  onPressed: () => setState(() { _selectedProduceIds.clear(); _produceQuantities.clear(); }),
                  child: Text("Clear All", style: TextStyle(fontSize: 12, color: subtleText)),
                )
            ],
          ),
        ),
        Card(
          elevation: 1.5, color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: ListView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: availableProduce.length,
            itemBuilder: (context, index) {
              final product = availableProduce[index];
              final bool isSelected = _selectedProduceIds.contains(product.produceId);
              return Column(children: [
                CheckboxListTile(
                  title: Text(product.produceName, style: TextStyle(fontSize: 14, color: textOnWhite)),
                   subtitle: product.unitGrams != null ? Text("${product.calories ?? '-'} kcal / ${product.unitGrams}g", style: TextStyle(fontSize: 11, color: subtleText)) : null, // Show basic info
                  value: isSelected,
                  onChanged: (bool? selected) => setState(() {
                    if (selected == true) {
                      _selectedProduceIds.add(product.produceId);
                      _produceQuantities.putIfAbsent(product.produceId, () => 1); // Default to 1
                    } else {
                      _selectedProduceIds.remove(product.produceId);
                      _produceQuantities.remove(product.produceId);
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading, dense: true, activeColor: primaryTeal,
                   secondary: IconButton( // Add Edit button here
                     icon: Icon(Icons.edit_note_outlined, size: 20, color: subtleText),
                     tooltip: 'Edit Produce Item Details',
                     onPressed: () => _handleEditProduce(product),
                   ),
                ),
                if (isSelected) Padding(
                  padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 12.0),
                  child: Row(children: [
                    const Text("Quantity:", style: TextStyle(fontSize: 13, color: subtleText)), const SizedBox(width: 12),
                    SizedBox(width: 80, height: 40, child: TextFormField(
                      key: ValueKey(product.produceId), initialValue: _produceQuantities[product.produceId]?.toString() ?? '1',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10), border: OutlineInputBorder(), hintText: "0", hintStyle: TextStyle(fontSize: 13)),
                      style: const TextStyle(fontSize: 14, color: textOnWhite),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (val) => setState(() {
                        final parsed = int.tryParse(val) ?? 0;
                        _produceQuantities[product.produceId] = parsed >= 0 ? parsed : 0;
                      }),
                      validator: (v) => (v == null || v.isEmpty || (int.tryParse(v) ?? -1) < 0) ? 'Invalid' : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    )),
                    const Spacer(),
                    // Optional Delete Button (use with caution on stock screen)
                     IconButton(
                       icon: Icon(Icons.delete_outline_rounded, size: 20, color: errorColor.withOpacity(0.7)),
                       tooltip: 'Delete Produce Item',
                       onPressed: () => _handleDeleteProduce(product),
                     ),
                  ]),
                ),
                if (index < availableProduce.length - 1) Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16, color: dividerColor.withOpacity(0.5)),
              ]);
            },
          )),
        ),
        // Moved Update Stock button to FAB
      ],
    );
  }

  // Builds the form for adding/editing a produce item
  Widget _buildProduceEditForm(Product product) {
    final bool isNewItem = product.produceId.startsWith('TEMP_');
    return Card(
      elevation: 3.0, color: whiteColor.withOpacity(0.98), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0), side: BorderSide(color: primaryTeal, width: 1.5)), margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(padding: const EdgeInsets.all(16.0), child: Form(key: _produceFormKey, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(isNewItem ? 'Add New Produce Item' : 'Edit "${product.produceName}"', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal)), const SizedBox(height: 16),
          TextFormField(controller: _produceNameController, decoration: _inputDecoration('Produce Name *'), style: const TextStyle(fontSize: 14, color: textOnWhite), validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null, autovalidateMode: AutovalidateMode.onUserInteraction), const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _produceCaloriesController, decoration: _inputDecoration('Calories (kcal)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)), const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceUnitGramsController, decoration: _inputDecoration('Unit (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
          ]), const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _produceProteinsController, decoration: _inputDecoration('Proteins (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)), const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceCarbsController, decoration: _inputDecoration('Carbs (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)), const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceFatsController, decoration: _inputDecoration('Fats (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
          ]), const SizedBox(height: 12),
          TextFormField(controller: _produceSourceController, decoration: _inputDecoration('Source URL (optional)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.url, maxLines: 1, validator: (v) => (v != null && v.isNotEmpty && (Uri.tryParse(v) == null || !Uri.tryParse(v)!.isAbsolute)) ? 'Invalid URL' : null, autovalidateMode: AutovalidateMode.onUserInteraction), const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _cancelProduceEdit, child: const Text('Cancel', style: TextStyle(color: subtleText)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))), const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18), label: Text(isNewItem ? 'Add Item' : 'Save Changes'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: _saveProduceChanges,
            ),
          ]),
        ],
      ))),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), isDense: true,
      labelStyle: const TextStyle(color: subtleText, fontSize: 13), floatingLabelStyle: const TextStyle(color: primaryTeal),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: dividerColor.withOpacity(0.8))),
       errorStyle: const TextStyle(fontSize: 11, color: errorColor), // Ensure error style is defined
    );
  }

  String? _validateOptionalNumber(String? value) {
    if (value != null && value.isNotEmpty) {
      if (double.tryParse(value) == null) return 'Invalid #';
      if (double.parse(value) < 0) return '>= 0';
    } return null;
  }

  TextInputFormatter _decimalInputFormatter(int decimalPlaces) {
    String dp = decimalPlaces > 0 ? '{0,$decimalPlaces}' : '';
    return FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d' + dp));
  }

  Widget _buildEmptyState(String title, String subtitle, {required IconData icon}) {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: subtleText.withOpacity(0.5)), const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textOnWhite), textAlign: TextAlign.center), const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: subtleText), textAlign: TextAlign.center),
      ],
    )));
  }

  // --- Status Color and Icon Helpers ---
  Color _getStatusColor(String status) {
    switch (status) {
      case Order.STATUS_PENDING: return pendingColor;
      case Order.STATUS_ACCEPTED: return acceptedColor;
      case Order.STATUS_PREPARING: return preparingColor;
      case Order.STATUS_READY_FOR_PICKUP: return dispatchedColor; // Reuse dispatch color for ready
      case Order.STATUS_ASSIGNED: return assignedColor;
      case Order.STATUS_DISPATCHED: return dispatchedColor;
      case Order.STATUS_OUT_FOR_DELIVERY: return primaryTeal; // Use teal for out for delivery
      case Order.STATUS_DELIVERED: return deliveredColor;
      case Order.STATUS_COMPLETED: return deliveredColor; // Same as delivered
      case Order.STATUS_CANCELLED: return cancelledColor;
      default: return defaultStatusColor;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case Order.STATUS_PENDING: return Icons.pending_actions_outlined;
      case Order.STATUS_ACCEPTED: return Icons.check_circle_outline_rounded;
      case Order.STATUS_PREPARING: return Icons.kitchen_outlined;
      case Order.STATUS_READY_FOR_PICKUP: return Icons.inventory_2_outlined; // Box icon
      case Order.STATUS_ASSIGNED: return Icons.person_pin_circle_outlined; // Assigned person icon
      case Order.STATUS_DISPATCHED: return Icons.local_shipping_outlined;
      case Order.STATUS_OUT_FOR_DELIVERY: return Icons.two_wheeler_rounded; // Rider icon
      case Order.STATUS_DELIVERED: return Icons.done_all_rounded;
      case Order.STATUS_COMPLETED: return Icons.celebration_outlined;
      case Order.STATUS_CANCELLED: return Icons.cancel_outlined;
      default: return Icons.help_outline_rounded;
    }
  }

} // End of _ProducerDash22State


// --- Rider Selection Dialog (Copied from ChefDash, adapted) ---
class _RiderSelectionDialog extends StatefulWidget {
  final int orderId; // Pass order ID for context if needed

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
    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });
    try {
      // Use the static method from ProducerApiService
      final riders = await ProducerApiService.fetchAvailableRiders();
      if (mounted) {
        riders.sort((a, b) { // Sort: Active first, then alphabetically
          if (a.isActive && !b.isActive) return -1;
          if (!a.isActive && b.isActive) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        setState(() { _allRiders = riders; _isLoading = false; });
      }
    } catch (e) {
      print("[ProducerDash] Error fetching riders in dialog: $e");
      if (mounted) {
        setState(() { _errorMessage = "Error fetching riders: ${e.toString()}"; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Assign Rider'),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _fetchRiders, tooltip: 'Refresh Rider List', visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
      ]),
      content: SizedBox(
        width: double.maxFinite, height: MediaQuery.of(context).size.height * 0.5, // Constrain size
        child: _buildContent(),
      ),
      actions: <Widget>[
        TextButton(child: const Text("Mark Ready for Any Rider"), onPressed: () => Navigator.of(context).pop(true)), // Return true
        TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop(null)), // Return null
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_errorMessage != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_errorMessage!, style: TextStyle(color: errorColor), textAlign: TextAlign.center), const SizedBox(height: 10),
        ElevatedButton(onPressed: _fetchRiders, child: const Text("Retry"))
      ])));
    }
    if (_allRiders.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text("No riders found.", textAlign: TextAlign.center)));
    }

    return ListView.builder(
      itemCount: _allRiders.length,
      itemBuilder: (context, index) {
        final rider = _allRiders[index];
        final bool isAvailable = rider.isActive;
        final Color tileColor = isAvailable ? Theme.of(context).dialogBackgroundColor : Colors.grey.shade200;
        final Color textColor = isAvailable ? textOnWhite : Colors.grey.shade600;
        final Color iconColor = isAvailable ? primaryTeal : Colors.grey.shade500;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4), elevation: isAvailable ? 1 : 0.5, color: tileColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0), side: isAvailable ? BorderSide.none : BorderSide(color: Colors.grey.shade300)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(Icons.two_wheeler, color: iconColor, size: 20)),
            title: Text(rider.name, style: TextStyle(color: textColor, fontWeight: isAvailable ? FontWeight.normal : FontWeight.w300)),
            subtitle: Text(isAvailable ? 'Status: Active' : 'Status: Inactive (${rider.status})', style: TextStyle(color: textColor.withOpacity(0.7))), // Show original status too
            trailing: isAvailable ? const Icon(Icons.chevron_right) : const Icon(Icons.block, color: Colors.grey, size: 18),
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