
//cspell:disable
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:async'; // Added import for TimeoutException and Timer
import 'dart:convert';
import 'dart:io'; // Required for File and image picking
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For environment variables
import 'package:image_picker/image_picker.dart'; // For image picking
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences for caching and prefs
import 'package:cached_network_image/cached_network_image.dart'; // Image caching

// Add these imports at the top of the file
import 'package:google_maps_flutter/google_maps_flutter.dart';
// --- Assumed Imports (Ensure these files exist) ---
import 'package:zinzi/Transporter_login.dart'; // For logout navigation
import 'package:zinzi/user_cache.dart'; // <<< IMPORT UserCache
import 'package:zinzi/chef_verification_helper.dart'; // For verification dialog
// Removed unused import // <<< IMPORT CacheConfig
// import 'package:zinzi/app_drawer.dart'; // If you reuse the drawer from old code

// --- Environment Variables ---
// Ensure loaded in main.dart: await dotenv.load(fileName: ".env");
final String apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url/api';
final String? imgurClientId = dotenv.env['IMGUR_CLIENT_ID'];

// Path for placeholder image (ensure this exists)
const String placeholderImagePath = 'assets/images/placeholder_avatar.png';

// --- Color Palette (New Dashboard Style) ---
const Color _primaryTeal = Colors.teal;
const Color _accentTeal = Colors.tealAccent;
const Color _lightTeal = Color(0xFFB2DFDB);
const Color _darkTeal = Color(0xFF00695C);
const Color _white = Colors.white;
const Color _grey = Colors.grey;
const Color _lightGrey = Color(0xFFF5F5F5);
const Color _green = Colors.green;
const Color _red = Colors.red;
const Color _errorColor = Color(0xFFD32F2F); // Use a consistent error color
const Color _subtleTextColor = Color(0xFF757575);

// ================================================
// === DATA MODELS (with robust parsing) =========
// ================================================

// --- Reusable JSON parsing helpers (from old code) ---
String? getStringSafe(dynamic value) => value?.toString();

int parseIntSafe(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? defaultValue;
  if (value is double) return value.toInt();
  return defaultValue;
}

int? parseIntNullable(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is double) return value.toInt();
  return null;
}

double? parseDoubleNullable(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double parseDoubleSafe(dynamic value, {double defaultValue = 0.0}) =>
    parseDoubleNullable(value) ?? defaultValue;

bool parseBoolSafe(dynamic value) => value is bool
    ? value
    : (value == 'true' || value == 1 || value == 'True' || value == '1');

DateTime? parseDateSafe(dynamic value) {
  if (value == null) return null;
  try {
    // First try standard ISO format
    return DateTime.tryParse(value.toString())?.toLocal();
  } catch (_) {
    try {
      // Fallback to the specific GMT format if ISO fails
      // Adjust format string if needed based on actual API response
      return DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
          .parseUtc(value.toString())
          .toLocal();
    } catch (e) {
      print("Could not parse date: $value - Error: $e");
      return null; // Return null if both fail
    }
  }
}

DateTime parseRequiredDateSafe(dynamic value) {
  // Use parseDateSafe and provide a default if null
  return parseDateSafe(value) ?? DateTime.now();
}

bool isValidUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  try {
    final uri = Uri.parse(url);
    return uri.isScheme('HTTP') || uri.isScheme('HTTPS');
  } catch (_) {
    return false;
  }
}

/// Robustly parses a location string to extract latitude and longitude.
/// Handles formats like:
/// - "lat, lng, address, components..." (e.g., "0.3423356, 32.5629039, 8HR7+W5F, Kawempe...")
/// - "Some address (lat, lng)"
/// - "(lat, lng)"
/// - "lat, lng"
LatLng? _parseLocationToLatLng(String? locationString) {
  if (locationString == null || locationString.trim().isEmpty) {
    return null;
  }

  // First, try to parse as "lat, lng, address, components..." format
  final parts = locationString.split(',').map((s) => s.trim()).toList();
  if (parts.length >= 2) {
    final latStr = parts[0];
    final lngStr = parts[1];
    
    // Check if first two parts are valid numbers
    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
  }

  // Try parenthesized coordinates, e.g., (1.23, 4.56)
  final RegExp parenRegex = RegExp(r'\(\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\)');
  final parenMatch = parenRegex.firstMatch(locationString);

  if (parenMatch != null && parenMatch.groupCount == 2) {
    final latStr = parenMatch.group(1);
    final lngStr = parenMatch.group(2);
    if (latStr != null && lngStr != null) {
      final lat = double.tryParse(latStr);
      final lng = double.tryParse(lngStr);
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
  }

  // Try to parse the whole string as "lat, lng"
  final RegExp directRegex = RegExp(r'^\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*$');
  final directMatch = directRegex.firstMatch(locationString.trim());

  if (directMatch != null && directMatch.groupCount == 2) {
    final latStr = directMatch.group(1);
    final lngStr = directMatch.group(2);
    if (latStr != null && lngStr != null) {
      final lat = double.tryParse(latStr);
      final lng = double.tryParse(lngStr);
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
  }

  // If all parsing fails
  print('Warning: Could not parse LatLng from location string: "$locationString"');
  return null;
}

// --- End Helpers ---

class TransporterProfile {
  final int transporterId;
  final String name;
  final String email;
  final String? phoneNumber; // Keep nullable if API allows
  final String? profileImageUrl;
  final String? vehicleType; // Keep nullable if API allows
  final String? licensePlate; // Keep nullable
  final bool isActive;
  final double? rating; // Keep nullable
  final String? location; // String for now, use getStringSafe
  final DateTime? registrationDate; // Keep nullable
  final DateTime? lastLogin; // From new model
  final String userType; // From new model
  final bool isEmailVerified; // From new model
  final String? address; // From new model

  TransporterProfile({
    required this.transporterId,
    required this.name,
    required this.email,
    this.phoneNumber, // required in new model, but let's keep nullable based on old parsing
    this.profileImageUrl,
    this.vehicleType, // required in new model, keep nullable
    this.licensePlate,
    required this.isActive,
    this.rating, // required in new model, keep nullable
    this.location,
    this.registrationDate, // required in new model, keep nullable
    this.lastLogin,
    required this.userType,
    required this.isEmailVerified,
    this.address,
  });

  factory TransporterProfile.fromJson(Map<String, dynamic> json) {
    return TransporterProfile(
      // Look for various possible keys for ID
      transporterId: parseIntSafe(
          json['transporter_id'] ?? json['rider_id'] ?? json['id']),
      name: getStringSafe(json['name']) ?? 'N/A',
      email: getStringSafe(json['email']) ?? 'N/A',
      phoneNumber: getStringSafe(json['phone_number']), // Use safe getter
      profileImageUrl:
          isValidUrl(getStringSafe(json['image'] ?? json['profile_image_url']))
              ? getStringSafe(json['image'] ?? json['profile_image_url'])
              : null, // Return null if invalid URL
      vehicleType: getStringSafe(json['vehicle_type']),
      licensePlate: getStringSafe(json['license_plate']),
      // Check for 'online_status' as a fallback for 'is_active'
      isActive:
          parseBoolSafe(json['is_active'] ?? json['online_status'] ?? false),
      rating: parseDoubleNullable(json['rating']), // Use nullable parser
      location: getStringSafe(json['location']), // Use safe getter
      registrationDate: parseDateSafe(json['registration_date'] ??
          json['created_at']), // Use nullable parser, check alternate key
      // Fields from new model
      lastLogin: parseDateSafe(json['last_login']),
      userType: getStringSafe(json['user_type']) ?? 'Transporter',
      isEmailVerified: parseBoolSafe(json['is_email_verified'] ?? false),
      address: getStringSafe(json['address']), // Use safe getter
    );
  }

  Map<String, dynamic> toJson() => {
        'transporter_id': transporterId,
        'name': name,
        'email': email,
        'phone_number': phoneNumber,
        'profile_image_url': profileImageUrl,
        'vehicle_type': vehicleType,
        'license_plate': licensePlate,
        'is_active': isActive,
        'rating': rating,
        'location': location,
        'registration_date': registrationDate?.toIso8601String(),
        'last_login': lastLogin?.toIso8601String(),
        'user_type': userType,
        'is_email_verified': isEmailVerified,
        'address': address,
      };

  // copyWith method is useful if you need to update local state optimistically
  // Adapted from old code
  TransporterProfile copyWith({
    int? transporterId,
    String? name,
    String? email,
    ValueGetter<String?>?
        phoneNumber, // Use ValueGetter for nullability control
    ValueGetter<String?>? profileImageUrl,
    ValueGetter<String?>? vehicleType,
    ValueGetter<String?>? licensePlate,
    bool? isActive,
    ValueGetter<double?>? rating,
    ValueGetter<String?>? location,
    ValueGetter<String?>? address,
    ValueGetter<DateTime?>? registrationDate,
    ValueGetter<DateTime?>? lastLogin,
    String? userType,
    bool? isEmailVerified,
  }) {
    return TransporterProfile(
      transporterId: transporterId ?? this.transporterId,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber != null ? phoneNumber() : this.phoneNumber,
      profileImageUrl:
          profileImageUrl != null ? profileImageUrl() : this.profileImageUrl,
      vehicleType: vehicleType != null ? vehicleType() : this.vehicleType,
      licensePlate: licensePlate != null ? licensePlate() : this.licensePlate,
      isActive: isActive ?? this.isActive,
      rating: rating != null ? rating() : this.rating,
      location: location != null ? location() : this.location,
      address: address != null ? address() : this.address,
      registrationDate:
          registrationDate != null ? registrationDate() : this.registrationDate,
      lastLogin: lastLogin != null ? lastLogin() : this.lastLogin,
      userType: userType ?? this.userType,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }
}

class Order {
  // User and restaurant contact information
  final String? userPhone;
  final String? restaurantPhone; // Added restaurant_phone field

  // Helper method to safely get string from dynamic value
  static String? _getStringSafe(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  final int orderId;
  final int? userId;
  final String orderType;
  final String? productId;
  final int? chefId;
  final int? producerId;
  final int? transporterId;
  final DateTime orderDate;
  final String deliveryAddress; // Keep as string, use getStringSafe
  final String? pickupLocation; // <<< NEW: Add pickup_location field
  final String orderStatus;
  final double totalPrice;
  final String? notes; // Use getStringSafe
  final String paymentStatus;
  final String? paymentMode;
  final double? amountPaid;
  final String? transactionId;
  final int quantity;
  final String? mealName;
  final String? ingredients;
  final String? producerName;
  final String? producerAddress; // Use getStringSafe
  final String? chefName;
  final String? transporterName;
  final String? gigDetails;
  final String? productName;

  // Static constants for status strings (good practice, from old code)
  static const STATUS_PENDING = 'Pending'; // Often used for 'available'
  static const STATUS_ASSIGNED = 'assigned'; // Match the example data
  static const STATUS_ACCEPTED = 'Accepted'; // Explicit accept by Rider
  static const STATUS_PICKED_UP = 'Picked Up'; // By Rider
  static const STATUS_ON_THE_WAY =
      'On The Way'; // Common alias for delivering - will be removed from timeline display logic
  static const STATUS_VERIFICATION_NEEDED =
      'verification needed'; // Potential status string
  static const STATUS_DELIVERING = 'Delivering'; // Sometimes used
  static const STATUS_DELIVERED = 'Delivered'; // Rider confirms drop-off
  static const STATUS_COMPLETED =
      'Completed'; // Final state after payment/confirmation
  static const STATUS_CANCELLED = 'Cancelled';

  // Calculated properties for UI display (from new code)
  String get simplifiedDeliveryAddress {
    String rawAddress = deliveryAddress;
    try {
      // Handle potential lat,long,address format
      List<String> parts = rawAddress.split(',');
      if (parts.length > 2 &&
          double.tryParse(parts[0].trim()) != null &&
          double.tryParse(parts[1].trim()) != null) {
        // Combine elements after the coordinates, trimming whitespace
        return parts
            .sublist(2)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(', ');
      }
      // Attempt to decode if it looks like JSON, otherwise use as is
      if (rawAddress.startsWith('{') && rawAddress.endsWith('}')) {
        Map<String, dynamic> addrMap = jsonDecode(rawAddress);
        // Extract descriptive part if available
        return addrMap['desc'] ?? addrMap['display_name'] ?? rawAddress;
      }
    } catch (e) {
      print("Error parsing simplified address: $e");
    }
    // Fallback to the raw string
    return rawAddress;
  }

  // Use the new pickupLocation field for pickup address
  String get pickupAddress {
    // Prioritize the new pickupLocation field if available
    if (pickupLocation != null && pickupLocation!.isNotEmpty) {
      // Similar parsing logic for pickup location if it contains coordinates
      try {
        List<String> parts = pickupLocation!.split(',');
        if (parts.length > 2 &&
            double.tryParse(parts[0].trim()) != null &&
            double.tryParse(parts[1].trim()) != null) {
          return parts
              .sublist(2)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
      } catch (e) {
        print("Error parsing simplified pickup address: $e");
      }
      // Fallback to raw pickup location string if parsing fails or format is different
      return pickupLocation!;
    }
    // Fallback to existing logic if pickupLocation is not available
    if (orderType.toLowerCase() == 'meal' && chefName != null) {
      // Assume chef address isn't directly in order, placeholder
      return "Chef $chefName's Location"; // Simpler placeholder
    } else if (orderType.toLowerCase() == 'produce' &&
        producerAddress != null &&
        producerAddress!.isNotEmpty) {
      return producerAddress!;
    }
    // Add logic for other order types if needed
    return 'Pickup Location Not Specified';
  }

  // Distance in kilometers from the API
  final double? distance;

  // Estimated time based on distance
  String get estimatedTime {
    if (distance == null) return orderType == 'meal' ? '25 min' : '35 min';
    // Rough estimate: 5 minutes per kilometer + 10 minutes buffer
    final estimatedMinutes = (distance! * 5 + 10).round();
    return '$estimatedMinutes min';
  }

  // Format distance with 1 decimal place and 'km' suffix
  String get estimatedDistance => distance != null
      ? '${distance!.toStringAsFixed(1)} km'
      : orderType == 'meal' ? '3.2 km' : '4.5 km';
  // Placeholder for earnings - needs calculation or API field
  double get earnings => orderType == 'meal'
      ? 8.50
      : 10.75; // Example based on total price for now
  //totalPrice * 0.1; // Example: 10% of total price, adjust as needed

  // Placeholder for order items - needs detailed structure if available
  List<String> get orderItems {
    if (productName != null) {
      return ['$productName x$quantity'];
    }
    if (orderType.toLowerCase() == 'meal' && mealName != null) {
      return ['$mealName x$quantity'];
    }
    return ['Item details unavailable'];
  }

  Order({
    required this.orderId,
    required this.userId,
    required this.orderType,
    this.productId,
    this.chefId,
    this.producerId,
    this.transporterId,
    required this.orderDate,
    required this.deliveryAddress,
    this.pickupLocation,
    required this.orderStatus,
    required this.totalPrice,
    this.notes,
    required this.paymentStatus,
    this.paymentMode,
    this.amountPaid,
    this.transactionId,
    required this.quantity,
    this.mealName,
    this.ingredients,
    this.producerName,
    this.producerAddress,
    this.chefName,
    this.transporterName,
    this.gigDetails,
    this.productName,
    this.userPhone,
    this.restaurantPhone, // Add restaurantPhone to constructor
    this.distance, // Add distance field
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String dateString) {
      try {
        // Handle potential "+00:00" suffix
        if (dateString.endsWith('+00:00')) {
          dateString = dateString.substring(0, dateString.length - 6) + 'Z';
        }
        return DateTime.parse(dateString).toLocal();
      } catch (e) {
        print("Warning: Could not parse order date '$dateString': $e");
        return DateTime.now(); // Fallback to current time
      }
    }

    // Helper to safely get a string value
    String? getStringSafe(dynamic value) => value?.toString();

    // Parse user_phone from JSON
    final userPhone = _getStringSafe(json['user_phone']);
    final restaurantPhone = _getStringSafe(json['restaurant_phone']);

    return Order(
      orderId: parseIntSafe(json['order_id']), // Use safe parser
      userId: parseIntNullable(json['user_id']),
      orderType: getStringSafe(json['order_type']) ?? 'unknown',
      productId: getStringSafe(json['product_id']),
      chefId: parseIntNullable(json['chef_id']),
      producerId: parseIntNullable(json['producer_id']),
      transporterId: parseIntNullable(json['transporter_id']),
      orderDate: parseDate(getStringSafe(json['order_date']) ??
          DateTime.now().toIso8601String()),
      deliveryAddress: getStringSafe(json['delivery_address']) ??
          'Address not provided', // Use safe getter
      pickupLocation: getStringSafe(
          json['pickup_location']), // <<< NEW: Parse pickup_location
      orderStatus: getStringSafe(json['order_status']) ?? 'unknown',
      totalPrice: parseDoubleSafe(json['total_price']), // Use safe parser
      notes: getStringSafe(json['notes']), // Use safe getter
      paymentStatus: getStringSafe(json['payment_status']) ?? 'unknown',
      paymentMode: getStringSafe(json['payment_mode']),
      amountPaid: parseDoubleNullable(json['amount_paid']), // Use safe parser
      transactionId: getStringSafe(json['transaction_id']),
      quantity:
          parseIntSafe(json['quantity'], defaultValue: 1), // Use safe parser
      mealName: getStringSafe(json['meal_name']), // Compatibility
      ingredients: getStringSafe(json['ingredients']),
      producerName: getStringSafe(json['producer_name']),
      producerAddress:
          getStringSafe(json['producer_address']), // Use safe getter
      chefName: getStringSafe(json['chef_name']),
      transporterName: getStringSafe(json['transporter_name']),
      gigDetails: getStringSafe(json['gig_details']),
      productName: getStringSafe(json['product_name']), // Use safe getter
      userPhone: userPhone, // Add user_phone from JSON
      restaurantPhone: restaurantPhone, // Add restaurant_phone from JSON
      distance: parseDoubleNullable(json['distance']), // Parse distance from API
    );
  }

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'user_id': userId,
        'order_type': orderType,
        'product_id': productId,
        'chef_id': chefId,
        'producer_id': producerId,
        'transporter_id': transporterId,
        'order_date': orderDate.toIso8601String(),
        'delivery_address': deliveryAddress,
        'pickup_location': pickupLocation, // Include pickup location
        'order_status': orderStatus,
        'total_price': totalPrice,
        'notes': notes,
        'payment_status': paymentStatus,
        'payment_mode': paymentMode,
        'amount_paid': amountPaid,
        'transaction_id': transactionId,
        'quantity': quantity,
        'meal_name': mealName,
        'ingredients': ingredients,
        'producer_name': producerName,
        'producer_address': producerAddress,
        'chef_name': chefName,
        'transporter_name': transporterName,
        'gig_details': gigDetails,
        'product_name': productName,
        'user_phone': userPhone, // Include user_phone
        'restaurant_phone': restaurantPhone, // Include restaurant_phone
      };

  // copyWith method adapted from old code
  Order copyWith({
    int? orderId,
    int? userId,
    String? orderType,
    ValueGetter<String?>? productId,
    ValueGetter<int?>? chefId,
    ValueGetter<int?>? producerId,
    ValueGetter<int?>? transporterId,
    DateTime? orderDate,
    String? deliveryAddress,
    String? pickupLocation,
    String? orderStatus, // Main field to update
    double? totalPrice,
    ValueGetter<String?>? notes,
    String? paymentStatus,
    ValueGetter<String?>? paymentMode,
    ValueGetter<double?>? amountPaid,
    ValueGetter<String?>? transactionId,
    int? quantity,
    ValueGetter<String?>? mealName,
    ValueGetter<String?>? ingredients,
    ValueGetter<String?>? producerName,
    ValueGetter<String?>? producerAddress,
    ValueGetter<String?>? chefName,
    ValueGetter<String?>? transporterName,
    ValueGetter<String?>? gigDetails,
    ValueGetter<String?>? productName,
    ValueGetter<String?>? userPhone,
    ValueGetter<String?>? restaurantPhone,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      orderType: orderType ?? this.orderType,
      productId: productId != null ? productId() : this.productId,
      chefId: chefId != null ? chefId() : this.chefId,
      producerId: producerId != null ? producerId() : this.producerId,
      transporterId:
          transporterId != null ? transporterId() : this.transporterId,
      orderDate: orderDate ?? this.orderDate,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      pickupLocation: pickupLocation ?? this.pickupLocation, // <<< ADD copyWith
      orderStatus: orderStatus ?? this.orderStatus, // Key update
      totalPrice: totalPrice ?? this.totalPrice,
      notes: notes != null ? notes() : this.notes,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMode: paymentMode != null ? paymentMode() : this.paymentMode,
      amountPaid: amountPaid != null ? amountPaid() : this.amountPaid,
      transactionId:
          transactionId != null ? transactionId() : this.transactionId,
      quantity: quantity ?? this.quantity,
      mealName: mealName != null ? mealName() : this.mealName,
      ingredients: ingredients != null ? ingredients() : this.ingredients,
      producerName: producerName != null ? producerName() : this.producerName,
      producerAddress:
          producerAddress != null ? producerAddress() : this.producerAddress,
      chefName: chefName != null ? chefName() : this.chefName,
      transporterName:
          transporterName != null ? transporterName() : this.transporterName,
      gigDetails: gigDetails != null ? gigDetails() : this.gigDetails,
      productName: productName != null ? productName() : this.productName,
      userPhone: userPhone != null ? userPhone() : this.userPhone,
      restaurantPhone:
          restaurantPhone != null ? restaurantPhone() : this.restaurantPhone,
    );
  }
}

class Payment {
  final int id;
  final int transporterId;
  final int orderId;
  final double amount;
  final String transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? status; // Added status field
  final String? orderType; // Made nullable and added as a field

  // Computed properties for backward compatibility
  String get effectiveOrderType => orderType ?? 'delivery';
  String get disbursementTransactionStatus => status ?? 'Successful';
  String get orderTransactionStatus =>
      'Completed'; // Assuming completed since it's a disbursement

  Payment({
    required this.id,
    required this.transporterId,
    required this.orderId,
    required this.amount,
    required this.transactionId,
    required this.createdAt,
    required this.updatedAt,
    this.status,
    this.orderType,
  });

  // Named constructor for API compatibility
  factory Payment.fromApiJson(Map<String, dynamic> json) {
    return Payment(
      id: parseIntSafe(json['id'] ?? json['disbursement_id'] ?? '0'),
      transporterId: parseIntSafe(json['transporter_id'] ?? '0'),
      orderId: parseIntSafe(json['order_id'] ?? '0'),
      amount: parseDoubleSafe(json['amount'] ?? '0'),
      transactionId: getStringSafe(json['transaction_id']) ?? 'N/A',
      status: getStringSafe(json['status']),
      orderType: getStringSafe(json['order_type']),
      createdAt: parseDateSafe(json['created_at']) ?? DateTime.now(),
      updatedAt: parseDateSafe(json['updated_at']) ?? DateTime.now(),
    );
  }

  // Original fromJson for backward compatibility
  factory Payment.fromJson(Map<String, dynamic> json) =>
      Payment.fromApiJson(json);
}

// ================================================
// === API SERVICE (Consolidated & Refined) =======
// ================================================
class TransporterApiService {
  // Helper to handle common API response structure (from new code, refined)
  static dynamic _handleStaticApiResponse(dynamic responseData,
      {String endpointContext = 'unknown'}) {
    print(
        "Handling API response for $endpointContext: Type=${responseData.runtimeType}"); // Log type

    // Case 1: Response is already a List (e.g., direct array of orders)
    if (responseData is List) {
      // print("API Response is List: $responseData"); // Can be verbose
      return responseData;
    }

    // Case 2: Response is a Map
    if (responseData is Map<String, dynamic>) {
      // print("API Response is Map: $responseData"); // Can be verbose
      // Check for common keys containing the list data
      const List<String> dataKeys = [
        'data',
        'orders',
        'payments',
        'profile',
        'items'
      ]; // Add expected keys
      for (String key in dataKeys) {
        if (responseData.containsKey(key) && responseData[key] is List) {
          print("Found data list under key '$key'");
          return responseData[key];
        }
        // Handle case where the key contains the single object (like profile)
        if (responseData.containsKey(key) &&
            responseData[key] is Map<String, dynamic>) {
          print("Found data object under key '$key'");
          return responseData[key];
        }
      }

      // Case 2b: If no list found under known keys, maybe the Map itself is the data (e.g., single profile)
      print(
          "API Warning: Response is a Map but no known list key found. Returning the Map itself for $endpointContext.");
      return responseData; // Return the map itself

      // Original error throwing:
      // print("API Error: Response is a Map but no valid list/object found under known keys (checked: ${dataKeys.join(', ')}). Keys present: ${responseData.keys}");
      // throw Exception('Unexpected API response format for $endpointContext: Expected a List or Map with known data key containing a List/Map, got Map with keys ${responseData.keys}');
    }

    // Case 3: Unexpected type
    print(
        "API Error: Unhandled response format for $endpointContext. Got: ${responseData.runtimeType}");
    throw Exception(
        'Unexpected API response type for $endpointContext: ${responseData.runtimeType}');
  }

  // Helper to get standard headers
  static Map<String, String> _getWriteHeaders({bool requiresAuth = true}) {
    // Placeholder for auth token logic if needed
    // String? authToken = await UserCache.getAuthToken(); // Example
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
      // if (requiresAuth && authToken != null) 'Authorization': 'Bearer $authToken',
    };
    return headers;
  }

  // Fetch transporter profile using the provided ID
  static Future<TransporterProfile> fetchTransporterProfile(
      String transporterId) async {
    if (transporterId.isEmpty) {
      throw Exception('Transporter ID provided is empty.');
    }
    final Uri uri = Uri.parse('$apibaseurl/rr/transporters/$transporterId');
    print("Fetching transporter profile from: $uri");
    try {
      final response =
          await http.get(uri, headers: _getWriteHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        // Use the handler which can return Map or List
        final dynamic handledData = _handleStaticApiResponse(rawData,
            endpointContext: 'fetchTransporterProfile');

        if (handledData is Map<String, dynamic>) {
          return TransporterProfile.fromJson(handledData);
        } else if (handledData is List &&
            handledData.isNotEmpty &&
            handledData[0] is Map<String, dynamic>) {
          print("Warning: Profile API returned a List, using the first item.");
          return TransporterProfile.fromJson(handledData[0]);
        } else {
          // This case might occur if _handleApiResponse returns null or unexpected type
          print(
              "Error: Handled data is not Map or List<Map>: ${handledData?.runtimeType}");
          throw Exception(
              'Failed to parse profile: Expected a Map or List<Map> but received ${handledData?.runtimeType}');
        }
      } else {
        print(
            "Error fetching transporter profile: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load transporter profile (Code: ${response.statusCode}) - ${response.reasonPhrase}');
      }
    } catch (e) {
      print("Exception fetching transporter profile: $e");
      throw Exception('Failed to load transporter profile: ${e.toString()}');
    }
  }

  // Fetch *all* orders for a transporter (dashboard might need filtering later)
  static Future<List<Order>> fetchAllTransporterOrders(
      String transporterId) async {
    if (transporterId.isEmpty) {
      throw Exception('Transporter ID provided is empty.');
    }
    final Uri uri =
        Uri.parse('$apibaseurl/rr/orders?transporter_id=$transporterId');
    print("Fetching all orders for transporter $transporterId from: $uri");
    try {
      final response =
          await http.get(uri, headers: _getWriteHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        final dynamic ordersList = _handleStaticApiResponse(rawData,
            endpointContext: 'fetchAllTransporterOrders');
        if (ordersList is List) {
          return ordersList
              .whereType<Map<String, dynamic>>()
              .map((item) => Order.fromJson(item))
              .toList();
        } else {
          print(
              "All orders API response format unexpected: Expected List, got ${ordersList?.runtimeType}");
          return []; // Return empty list on format error
        }
      } else {
        print(
            "Error fetching all orders: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load orders (Code: ${response.statusCode}) - ${response.reasonPhrase}');
      }
    } catch (e) {
      print("Exception fetching all orders: $e");
      throw Exception('Failed to load orders: ${e.toString()}');
    }
  }

  // Fetch transporter payments/earnings
  static Future<List<Payment>> fetchTransporterPayments(
      String transporterId) async {
    if (transporterId.isEmpty) {
      throw Exception('Transporter ID provided is empty.');
    }
    final Uri uri = Uri.parse(
        '$apibaseurl/rr/disbursements/transporter?transporter_id=$transporterId');
    print("Fetching payments for transporter $transporterId from: $uri");
    try {
      final response =
          await http.get(uri, headers: _getWriteHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic rawData = json.decode(response.body);
        // Use the handler which checks for wrappers
        final dynamic paymentsList = _handleStaticApiResponse(rawData,
            endpointContext: 'fetchTransporterPayments');

        if (paymentsList is List) {
          return paymentsList
              .whereType<Map<String, dynamic>>()
              .map((item) => Payment.fromJson(item))
              .toList();
        } else {
          print(
              "Payments API response format unexpected: Expected List, got ${paymentsList?.runtimeType}");
          return []; // Return empty list on format error
        }
      } else {
        print(
            "Error fetching payments: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to load payments (Code: ${response.statusCode}) - ${response.reasonPhrase}');
      }
    } catch (e) {
      print("Exception fetching payments: $e");
      throw Exception('Failed to load payments: ${e.toString()}');
    }
  }

  // Update order status (called by transporter)
  static Future<bool> updateOrderStatusByTransporter(
      int orderId, String newStatus) async {
    final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/status');
    print(
        "Updating order $orderId status by transporter to $newStatus via $uri");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: true),
        body: jsonEncode({'order_status': newStatus}), // Key from new code
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        print(
            "Order status updated successfully for order $orderId to $newStatus");
        return true;
      } else {
        print(
            "Error updating order status (Transporter): ${response.statusCode} ${response.body}");
        String errorMessage = 'Failed to update status.';
        try {
          final errorBody = json.decode(response.body);
          errorMessage =
              errorBody['message'] ?? errorBody['error'] ?? errorMessage;
        } catch (_) {}
        throw Exception(
            'Failed to update order status (Code: ${response.statusCode}) - $errorMessage');
      }
    } catch (e) {
      print("Exception updating order status (Transporter): $e");
      throw Exception('Failed to update order status: ${e.toString()}');
    }
  }

  // Update transporter's active/online status
  static Future<bool> updateTransporterActiveStatus(
      String transporterId, bool isActive) async {
    if (transporterId.isEmpty)
      throw Exception('Transporter ID provided is empty.');
    final Uri uri = Uri.parse(
        '$apibaseurl/rr/transporters/$transporterId'); // Use general profile endpoint
    print(
        "Updating transporter $transporterId active status to $isActive via $uri (PATCH)");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: true),
        body: jsonEncode({'is_active': isActive}), // Key from models
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        print("Transporter active status updated successfully.");
        return true;
      } else {
        print(
            "Error updating transporter active status: ${response.statusCode} ${response.body}");
        throw Exception(
            'Failed to update active status (Code: ${response.statusCode}) - ${response.reasonPhrase}');
      }
    } catch (e) {
      print("Exception updating transporter active status: $e");
      throw Exception('Failed to update active status: ${e.toString()}');
    }
  }

  // Update transporter's profile details
  static Future<bool> updateTransporterProfile(
      String transporterId, Map<String, dynamic> updateData) async {
    if (transporterId.isEmpty)
      throw Exception('Transporter ID provided is empty.');
    final Uri uri = Uri.parse('$apibaseurl/rr/transporters/$transporterId');

    // Remove null values. Keep empty strings if API needs them to clear fields,
    // otherwise remove them too if they cause issues.
    updateData.removeWhere((key, value) =>
        value == null /* || (value is String && value.isEmpty) */);

    if (updateData.isEmpty) {
      print("Update profile called with no data to update.");
      return true; // Nothing to update
    }
    print(
        "Updating transporter profile $transporterId with data: ${jsonEncode(updateData)}");
    try {
      final response = await http.patch(
        uri,
        headers: _getWriteHeaders(requiresAuth: true),
        body: jsonEncode(updateData),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        print("Transporter profile updated successfully.");
        return true;
      } else {
        print(
            "Error updating transporter profile: ${response.statusCode} ${response.body}");
        String errorMessage = 'Failed to update profile.';
        try {
          final errorBody = json.decode(response.body);
          errorMessage =
              errorBody['message'] ?? errorBody['error'] ?? errorMessage;
        } catch (_) {}
        throw Exception(
            'Failed to update profile (Code: ${response.statusCode}) - $errorMessage');
      }
    } catch (e) {
      print("Exception updating transporter profile: $e");
      throw Exception('Failed to update profile: ${e.toString()}');
    }
  }

  // Upload image to Imgur
  static Future<String?> uploadImageToImgur(File imageFile) async {
    if (imgurClientId == null || imgurClientId!.isEmpty) {
      print("Imgur Client ID missing in .env");
      throw Exception("Image upload configuration missing.");
    }
    final Uri imgurUri = Uri.parse('https://api.imgur.com/3/image');
    print("Uploading image to Imgur...");
    try {
      var request = http.MultipartRequest('POST', imgurUri);
      request.headers['Authorization'] = 'Client-ID $imgurClientId';
      request.files
          .add(await http.MultipartFile.fromPath('image', imageFile.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['data']?['link'] != null) {
          print("Imgur upload successful: ${responseData['data']['link']}");
          return responseData['data']['link'];
        } else {
          String errorMsg = responseData['data']?['error']?.toString() ??
              'Invalid response structure';
          print("Imgur upload failed: $errorMsg");
          throw Exception('Imgur upload failed: $errorMsg');
        }
      } else {
        print("Imgur upload failed: ${response.statusCode} ${response.body}");
        throw Exception(
            'Imgur upload failed with status code ${response.statusCode}');
      }
    } catch (e) {
      print("Imgur upload error: $e");
      throw Exception("Failed to upload image: ${e.toString()}");
    }
  }

  // Accept an available order
  static Future<bool> acceptOrder(int orderId, String transporterId) async {
    final Uri uri = Uri.parse(
        '$apibaseurl/rr/orders/$orderId/status'); // Using the status update endpoint
    print("Accepting order $orderId for transporter $transporterId via $uri");
    try {
      // Parse transporterId to int
      final int? transporterIdInt = int.tryParse(transporterId);
      if (transporterIdInt == null) {
        throw Exception('Invalid transporter ID format');
      }

      print("Sending PATCH request to update order status to 'picked up'...");
      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(requiresAuth: true),
            body: jsonEncode({
              'transporter_id':
                  transporterIdInt, // Send transporter ID as int
              'order_status': Order
                  .STATUS_PICKED_UP // Update status to 'picked up' when order is accepted
            }),
          )
          .timeout(const Duration(seconds: 30)); // Add timeout for the request

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success - check if response contains updated status
        try {
          final responseBody = json.decode(response.body);
          if (responseBody is Map &&
              responseBody.containsKey('order_status')) {
            final updatedStatus =
                responseBody['order_status']?.toString().toLowerCase();
            print(
                "Order $orderId status updated successfully. New status: $updatedStatus");
          } else {
            // No status in response, but still successful
            print(
                "Order $orderId update successful. No status returned in response.");
          }
          return true;
        } catch (e) {
          // If we can't parse the response but got a success status code, still consider it a success
          print(
              "Order $orderId update successful. Could not parse response: $e");
          return true;
        }
      } else {
        print(
            "Error accepting order: ${response.statusCode} ${response.body}");
        String errorMessage = 'Failed to accept order.';
        try {
          final errorBody = json.decode(response.body);
          errorMessage =
              errorBody['message'] ?? errorBody['error'] ?? errorMessage;
        } catch (_) {}
        throw Exception(
            'Failed to accept order (Code: ${response.statusCode}) - $errorMessage');
      }
    } on TimeoutException catch (e) {
      print("Timeout while waiting for order status update: $e");
      throw Exception('Request timed out while updating order status');
    } catch (e) {
      print("Exception accepting order: $e");
      rethrow; // Re-throw to preserve the original stack trace
    }
  }

  // Reject an available order (Optional - depends on API)
  static Future<bool> rejectOrder(int orderId, String transporterId) async {
    print(
        "Rejecting order $orderId (Transporter $transporterId) - Assuming no API call needed, handled locally.");
    // Simulate success as usually this is just ignoring the order in the app
    await Future.delayed(Duration(milliseconds: 50)); // Tiny delay
    return true;
    // If an API call is needed (e.g., /reject endpoint):
    // final Uri uri = Uri.parse('$apibaseurl/rr/orders/$orderId/reject');
    // try { ... http.post/patch ... } catch { ... }
  }
} // End of TransporterApiService

// === MAIN DASHBOARD WIDGET (New UI Structure) ===
// ================================================

class TransporterDashNew extends StatefulWidget {
  final String transporterId;

  /// Preload transporter dashboard cache for splash screen (no UI, no context needed)
  static Future<void> preloadCacheForSplash(String transporterId) async {
    if (transporterId.isEmpty) {
      print('[Splash][TransporterDash] Error: Empty transporter ID provided');
      return;
    }

    // --- Caching Keys ---
    const String profileKey = 'transporter_profile_cache_new_v2';
    const String profileTsKey = 'transporter_profile_cache_timestamp_new_v2';
    const String ordersKey = 'transporter_orders_cache';
    const String ordersTsKey = 'transporter_orders_cache_timestamp';
    final now = DateTime.now();

    // --- Profile ---
    final cachedProfile = await UserCache.getData(profileKey);
    final cachedProfileTs = await UserCache.getData(profileTsKey);
    bool profileCacheValid = false;
    if (cachedProfile != null && cachedProfileTs is String) {
      final cacheTime = DateTime.tryParse(cachedProfileTs);
      if (cacheTime != null && now.difference(cacheTime).inMinutes < 15) {
        profileCacheValid = true;
      }
    }
    if (!profileCacheValid) {
      try {
        final profile =
            await TransporterApiService.fetchTransporterProfile(transporterId);
        await UserCache.saveData(profileKey, profile.toJson());
        await UserCache.saveData(profileTsKey, now.toIso8601String());
        print('[Splash][TransporterDash] Profile cache updated');
      } catch (e) {
        print('[Splash][TransporterDash] Profile preload error: $e');
      }
    } else {
      print(
          '[Splash][TransporterDash] Profile preload skipped: Cache still valid');
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
        // Only fetch transporter orders
        final transporterOrders =
            await TransporterApiService.fetchAllTransporterOrders(
                transporterId);

        // Serialize the orders
        final List<Map<String, dynamic>> serializedOrders =
            transporterOrders.map((order) => order.toJson()).toList();

        await UserCache.saveData(ordersKey, serializedOrders);
        await UserCache.saveData(ordersTsKey, now.toIso8601String());
        print('[Splash][TransporterDash] Orders cache updated');
      } catch (e) {
        print('[Splash][TransporterDash] Orders preload error: $e');
      }
    } else {
      print(
          '[Splash][TransporterDash] Orders preload skipped: Cache still valid');
    }
  }

  const TransporterDashNew({Key? key, required this.transporterId})
      : super(key: key);

  @override
  _TransporterDashNewState createState() => _TransporterDashNewState();
}

class _TransporterDashNewState extends State<TransporterDashNew> {
  // --- Caching for Transporter Profile (Integrated from old code) ---
  static TransporterProfile? _profileCache;
  static DateTime? _profileCacheTimestamp;
  // Use distinct keys to avoid conflicts if old/new co-exist during dev
  static const String _profileCacheKey = 'transporter_profile_cache_new_v2';
  static const String _profileCacheTimestampKey =
      'transporter_profile_cache_timestamp_new_v2';

  // --- Caching for Orders ---
  static List<Order>? _ordersCache;
  static DateTime? _ordersCacheTimestamp;
  static const String _ordersCacheKey = 'transporter_orders_cache';
  static const String _ordersCacheTimestampKey =
      'transporter_orders_cache_timestamp';

  int _selectedDrawerIndex = 0; // 0: Dashboard, 1: Deliveries, 2: Profile
  TransporterProfile? _transporterProfile;
  List<Order> _allOrders = []; // Combined list of orders
  List<Payment> _payments = [];

  bool _isLoading = true; // General loading indicator for initial data fetch
  bool _isLoadingProfile = true; // Specific loading for profile section/header
  String? _errorMessage; // General error message for initial data fetch
  String? _profileFetchError; // Specific error for profile fetching

  bool _isOnline =
      false; // Track online/offline status (initialized from profile)

  // Refresh control
  Timer? _refreshTimer;
  DateTime? _lastFullRefresh;
  DateTime? _lastOrdersRefresh;
  DateTime? _lastPaymentsRefresh;
  final Map<int, bool> _updatingOrderStatus = {}; // Track orders being updated
  bool _isRefreshing = false; // Track if a refresh is in progress

  // State for Deliveries Screen tabs
  int _selectedDeliveryTab = 0; // 0: Active, 1: Available, 2: Completed

  // State for Profile Editing
  final _profileEditFormKey = GlobalKey<FormState>(); // Key for profile form
  late TextEditingController _nameController;
  late TextEditingController _emailController; // Display only
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  // Vehicle Controllers - Assuming they are part of profile update
  late TextEditingController _vehicleMakeController;
  late TextEditingController _vehicleModelController;
  late TextEditingController _vehicleYearController;
  late TextEditingController _licensePlateController;
  late TextEditingController _vehicleColorController;

  File? _profileImageFile; // For image picker
  bool _isUploadingProfileImage = false; // Track image upload status
  bool _isSavingProfile = false; // Track profile save status

  // State for Preferences (loaded from prefs or defaults)
  bool _notifyNewOrders = true;
  bool _notifyStatusUpdates = true;
  bool _notifyEarnings = true;
  bool _notifyPromotions = false;
  bool _useDarkMode = false; // Example default
  bool _soundAlerts = true;
  bool _autoNavigate = true;

  // Track when payments were last fetched
  DateTime? _lastPaymentsFetchTime;

  // --- NEW: Polling State Variables ---
  Timer? _pollingTimer;
  bool _isPolling = false; // To prevent concurrent poll executions

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadPreferences(); // Load saved preferences
    _loadInitialData(); // Start data loading (includes profile cache check)
  }

  void _initializeControllers() {
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _vehicleMakeController = TextEditingController();
    _vehicleModelController = TextEditingController();
    _vehicleYearController = TextEditingController();
    _licensePlateController = TextEditingController();
    _vehicleColorController = TextEditingController();
  }

  @override
  void dispose() {
    // --- NEW: Stop polling timer on dispose to prevent memory leaks ---
    _stopPolling();
    // ---
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleYearController.dispose();
    _licensePlateController.dispose();
    _vehicleColorController.dispose();
    _searchController.dispose(); // Dispose search controller
    super.dispose();
  }

  // Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      setState(() {
        _notifyNewOrders = prefs.getBool('notifyNewOrders') ?? true;
        _notifyStatusUpdates = prefs.getBool('notifyStatusUpdates') ?? true;
        _notifyEarnings = prefs.getBool('notifyEarnings') ?? true;
        _notifyPromotions = prefs.getBool('notifyPromotions') ?? false;
        _useDarkMode = prefs.getBool('useDarkMode') ?? false;
        _soundAlerts = prefs.getBool('soundAlerts') ?? true;
        _autoNavigate = prefs.getBool('autoNavigate') ?? true;
      });
    } catch (e) {
      print("Error loading preferences: $e");
      // Use defaults if loading fails
    }
  }

  // Load profile cache from UserCache
  Future<void> _loadProfileCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_profileCacheKey);
    final timestampData = await UserCache.getData(_profileCacheTimestampKey);

    if (cachedData is Map<String, dynamic> && timestampData is String) {
      try {
        _profileCache = TransporterProfile.fromJson(cachedData);
        _profileCacheTimestamp = DateTime.tryParse(timestampData)?.toLocal();
        print("Loaded profile from cache. Timestamp: $_profileCacheTimestamp");
      } catch (e) {
        print("Error parsing cached transporter profile (new): $e");
        _profileCache = null;
        _profileCacheTimestamp = null;
        await UserCache.removeData(
            _profileCacheKey); // Clear potentially corrupted cache
        await UserCache.removeData(_profileCacheTimestampKey);
      }
    } else {
      print("No valid profile cache found in prefs.");
      _profileCache = null;
      _profileCacheTimestamp = null;
    }
  }

  // Load orders cache from UserCache
  Future<bool> _loadOrdersCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_ordersCacheKey);
    final timestampData = await UserCache.getData(_ordersCacheTimestampKey);

    if (cachedData is List && timestampData is String) {
      try {
        final DateTime? cacheTime = DateTime.tryParse(timestampData)?.toLocal();
        final bool cacheIsValid = cacheTime != null &&
            DateTime.now().difference(cacheTime).inMinutes < 15;

        if (cacheIsValid) {
          final List<Order> orders =
              (cachedData as List).map((json) => Order.fromJson(json)).toList();
          // Sort orders by orderDate descending (latest first)
          orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
          _allOrders = orders;
          _ordersCache = orders;
          _ordersCacheTimestamp = cacheTime;

          // Update UI with cached data
          if (mounted) {
            setStateIfMounted(() {
              _isLoading = false; // Turn off loading indicator
            });
          }

          print(
              "Loaded ${orders.length} orders from cache. Timestamp: $_ordersCacheTimestamp");
          return true;
        } else {
          print("Orders cache expired. Cache time: $cacheTime");
          _ordersCache = null;
          _ordersCacheTimestamp = null;
        }
      } catch (e) {
        print("Error parsing cached orders: $e");
        _ordersCache = null;
        _ordersCacheTimestamp = null;
        await UserCache.removeData(_ordersCacheKey);
        await UserCache.removeData(_ordersCacheTimestampKey);
      }
    } else {
      print("No valid orders cache found in prefs.");
      _ordersCache = null;
      _ordersCacheTimestamp = null;
    }
    return false;
  }

  // Save orders to cache
  Future<void> _saveOrdersCacheToPrefs(List<Order> orders) async {
    try {
      // Sort orders by orderDate descending (latest first) before saving
      orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
      final List<Map<String, dynamic>> serializedOrders =
          orders.map((order) => order.toJson()).toList();

      await UserCache.saveData(_ordersCacheKey, serializedOrders);
      final now = DateTime.now();
      await UserCache.saveData(_ordersCacheTimestampKey, now.toIso8601String());

      _ordersCache = orders;
      _ordersCacheTimestamp = now;
      print(
          "Saved ${orders.length} orders to cache. Timestamp: $_ordersCacheTimestamp");
    } catch (e) {
      print("Error saving orders to cache: $e");
    }
  }

  // Refresh payments data
  Future<void> refreshPayments() async {
    try {
      print('Refreshing payments data...');
      final paymentsResult =
          await TransporterApiService.fetchTransporterPayments(
                  widget.transporterId)
              .timeout(const Duration(seconds: 15));

      if (mounted) {
        setStateIfMounted(() {
          _payments = paymentsResult.cast<Payment>();
          // Update cache timestamp to prevent immediate refetch
          _lastPaymentsFetchTime = DateTime.now();
        });
        print('Successfully refreshed ${paymentsResult.length} payments');
      }
    } on TimeoutException {
      print('Timeout while refreshing payments');
      if (mounted) {
        _showErrorSnackBar('Connection timeout. Earnings may be out of date.');
      }
    } catch (e) {
      print('Error refreshing payments: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to refresh earnings. Pull down to retry.');
      }
      rethrow; // Re-throw to allow callers to handle the error if needed
    }
  }

  // Save cache to UserCache
  Future<void> _saveProfileCacheToPrefs(TransporterProfile profile) async {
    try {
      Map<String, dynamic> cacheableProfile = profile.toJson();
      await UserCache.saveData(_profileCacheKey, cacheableProfile);
      final now = DateTime.now();
      await UserCache.saveData(
          _profileCacheTimestampKey, now.toIso8601String());
      _profileCache = profile; // Update in-memory cache
      _profileCacheTimestamp = now;
      print("Saved profile to cache. Timestamp: $_profileCacheTimestamp");
    } catch (e) {
      print("Error saving profile to cache: $e");
    }
  }

  // Helper to safely call setState only if the widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // Combined cache load and background fetch for Transporter Profile
  Future<void> _initializeTransporterProfile() async {
    if (mounted) {
      // Only set profile loading true if profile is not already loaded
      if (_transporterProfile == null) {
        setState(() {
          _isLoadingProfile = true;
          _profileFetchError = null;
        });
      } else {
        // If profile exists (likely from cache already displayed),
        // still set loading true to indicate background refresh check
        setState(() {
          _isLoadingProfile = true;
          _profileFetchError = null;
        });
      }
    }

    // 1. Load from cache if not already done or if expired
    await _loadProfileCacheFromPrefs();

    // 2. Display cached data immediately if available and not already shown
    if (_profileCache != null && mounted) {
      final now = DateTime.now();
      final bool cacheIsValid = _profileCacheTimestamp != null &&
          now.difference(_profileCacheTimestamp!).inMinutes < 15;

      // Update state only if profile isn't set yet or if cache is valid (to refresh potentially stale UI)
      if (_transporterProfile == null || cacheIsValid) {
        if (cacheIsValid) {
          print("TransporterDashNew: Displaying valid cached profile.");
        } else {
          print(
              "TransporterDashNew: Displaying expired cached profile while fetching.");
        }
        setStateIfMounted(() {
          _transporterProfile = _profileCache;
          _isOnline =
              _transporterProfile!.isActive; // Set online status from cache
          _updateProfileControllers(
              _transporterProfile!); // Populate edit fields
          // Only stop loading indicator if cache is valid, otherwise keep it for background fetch
          _isLoadingProfile = !cacheIsValid;
        });
      } else {
        print(
            "TransporterDashNew: Valid profile already in state, proceeding to fetch.");
        // Ensure loading indicates background activity
        setStateIfMounted(() => _isLoadingProfile = true);
      }
    } else if (mounted) {
      print("TransporterDashNew: No cached profile found, fetching...");
      setStateIfMounted(
          () => _isLoadingProfile = true); // Ensure loading is shown
    }

    // 3. Fetch fresh data in the background
    await _fetchTransporterProfileAndUpdate();
  }

  // Separate function to fetch Transporter Profile and update state/cache
  Future<void> _fetchTransporterProfileAndUpdate() async {
    try {
      final profile = await TransporterApiService.fetchTransporterProfile(
          widget.transporterId);
      // Update state only if the fetched profile is different or if profile was null
      if (mounted &&
          (_transporterProfile == null ||
              profile.toJson().toString() !=
                  _transporterProfile!.toJson().toString())) {
        print("TransporterDashNew: Fetched fresh transporter profile data.");
        await _saveProfileCacheToPrefs(profile); // Save fresh data to cache
        setStateIfMounted(() {
          _transporterProfile = profile;
          _isOnline = profile.isActive; // Update online status from fresh data
          _updateProfileControllers(
              profile); // Populate edit fields from fresh data
          _isLoadingProfile = false; // Done loading/refreshing profile
          _profileFetchError = null; // Clear any previous error
        });
      } else if (mounted) {
        // Data hasn't changed, just ensure loading indicators are off
        print(
            "TransporterDashNew: Fetched profile data is same as current state.");
        setStateIfMounted(() {
          _isLoadingProfile = false;
          _profileFetchError = null;
        });
      }
    } catch (error, stackTrace) {
      print(
          "Error fetching fresh transporter profile (new): $error\n$stackTrace");
      if (mounted) {
        // Only show error prominently if there's no cached data at all
        if (_transporterProfile == null) {
          setStateIfMounted(() {
            _profileFetchError = 'Failed to load profile: $error';
            _isLoadingProfile = false; // Stop profile loading
            _isLoading =
                false; // Stop general loading too if profile fails initially
            _errorMessage = _profileFetchError; // Show error in main body
          });
        } else {
          // Keep showing cached data, log error silently or show subtle indicator
          print(
              "TransporterDashNew: Failed to fetch fresh profile, showing cached version. Error: $error");
          setStateIfMounted(() {
            _isLoadingProfile = false; // Ensure loading indicator stops
            _profileFetchError =
                "Couldn't refresh profile: $error"; // Store less intrusive error
          });
        }
      }
    }
  }

  // Load initial orders and payments, triggers profile loading
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    // Reset states
    setStateIfMounted(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Initialize profile first to get the online status
    await _initializeTransporterProfile();

    // 1. Load orders from cache if available
    bool loadedOrdersFromCache = await _loadOrdersCacheFromPrefs();

    // 2. Always fetch fresh data in background
    try {
      final ordersResult =
          await TransporterApiService.fetchAllTransporterOrders(
              widget.transporterId);
      final paymentsResult =
          await TransporterApiService.fetchTransporterPayments(
              widget.transporterId);

      if (mounted) {
        final List<Order> allOrders = ordersResult.cast<Order>().toList();
        setStateIfMounted(() {
          _allOrders = allOrders;
          _payments = paymentsResult.cast<Payment>();
          _isLoading = false;
          _errorMessage = null;
        });

        await _saveOrdersCacheToPrefs(allOrders);

        // --- NEW: Start polling if user is online after initial data load ---
        if (_isOnline) {
          _startPolling();
        }
      }
    } catch (e, stackTrace) {
      print(
          "Error loading initial data (orders/payments): $e\n$stackTrace");
      if (mounted && !loadedOrdersFromCache) {
        setStateIfMounted(() {
          _errorMessage = "Failed to load data: ${e.toString()}";
          _isLoading = false;
          if (_allOrders.isEmpty) {
            _allOrders = [];
            _payments = [];
          }
        });
      } else if (mounted) {
        setStateIfMounted(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper to update profile editing controllers
  void _updateProfileControllers(TransporterProfile profile) {
    if (_nameController.text != profile.name)
      _nameController.text = profile.name;
    if (_emailController.text != profile.email)
      _emailController.text = profile.email;
    if (_phoneController.text != (profile.phoneNumber ?? ''))
      _phoneController.text = profile.phoneNumber ?? '';
    if (_addressController.text != (profile.address ?? ''))
      _addressController.text = profile.address ?? '';
    if (_licensePlateController.text != (profile.licensePlate ?? ''))
      _licensePlateController.text = profile.licensePlate ?? '';

    _vehicleMakeController.text =
        getStringSafe(profile.toJson()['vehicle_make']) ?? "Honda";
    _vehicleModelController.text =
        getStringSafe(profile.toJson()['vehicle_model']) ?? "CBR300R";
    _vehicleYearController.text =
        getStringSafe(profile.toJson()['vehicle_year']) ?? "2023";
    _vehicleColorController.text =
        getStringSafe(profile.toJson()['vehicle_color']) ?? "Black";
  }

  // --- NEW: Polling Methods for New Orders ---
  void _startPolling() {
    if (_pollingTimer?.isActive ?? false) return; // Already running
    if (!mounted || !_isOnline) return; // Don't start if offline or unmounted

    const pollInterval =
        Duration(seconds: 6); // Check for new orders every 20 seconds
    _pollingTimer = Timer.periodic(pollInterval, (timer) {
      _pollForNewOrders();
    });
    print(
        '[Polling] Started polling for new orders every ${pollInterval.inSeconds} seconds.');
  }

  void _stopPolling() {
    if (_pollingTimer?.isActive ?? false) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      print('[Polling] Stopped.');
    }
  }

  Future<void> _pollForNewOrders() async {
    // Guard against concurrent execution, or if user is offline/disposed
    if (_isPolling || !mounted || !_isOnline) return;

    setStateIfMounted(() => _isPolling = true);

    try {
      final List<Order> fetchedOrders =
          await TransporterApiService.fetchAllTransporterOrders(
              widget.transporterId);

      if (!mounted) return; // Check again after await

      // Get IDs of current "available" orders to detect new ones
      final Set<int> currentAvailableOrderIds =
          _getAvailableOrders().map((o) => o.orderId).toSet();

      // Find new available orders from the fetched list
      final List<Order> newAvailableOrders = fetchedOrders.where((order) {
        final status = _normalizeStatus(order.orderStatus);
        final isAvailable = status == _normalizeStatus(Order.STATUS_ASSIGNED) ||
            status == _normalizeStatus(Order.STATUS_PENDING);
        return isAvailable && !currentAvailableOrderIds.contains(order.orderId);
      }).toList();

      // Merge the full fetched list to keep all statuses up-to-date
      final Map<int, Order> orderMap = {
        for (var o in _allOrders) o.orderId: o
      };
      for (var fetchedOrder in fetchedOrders) {
        orderMap[fetchedOrder.orderId] = fetchedOrder;
      }
      final updatedList = orderMap.values.toList();
      updatedList.sort((a, b) => b.orderDate.compareTo(a.orderDate));

      // Update state with the master list
      setStateIfMounted(() {
        _allOrders = updatedList;
      });

      // If new orders were found, notify the user and update the cache
      if (newAvailableOrders.isNotEmpty) {
        print(
            '[Polling] Found ${newAvailableOrders.length} new available order(s).');
        await _saveOrdersCacheToPrefs(updatedList); // Update cache
        _showNewOrderNotification(newAvailableOrders.length);
      }
    } catch (e) {
      // Fail silently to not bother the user with constant errors during polling
      print('[Polling] Error fetching new orders: $e');
    } finally {
      if (mounted) {
        setStateIfMounted(() => _isPolling = false);
      }
    }
  }

  void _showNewOrderNotification(int newOrderCount) {
    if (!mounted) return;

    final message = newOrderCount == 1
        ? 'A new delivery is available!'
        : '$newOrderCount new deliveries are available!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: _white)),
        backgroundColor: _green, // Use green for positive notification
        duration: Duration(seconds: 5),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: _accentTeal,
          onPressed: () {
            // Navigate to the available orders tab
            setStateIfMounted(() {
              _selectedDrawerIndex = 1;
              _selectedDeliveryTab = 1;
            });
          },
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      ),
    );

    // Optional: Auto-navigate if preference is set
    if (_autoNavigate) {
      setStateIfMounted(() {
        _selectedDrawerIndex = 1;
        _selectedDeliveryTab = 1;
      });
    }

    // Optional: Play sound if preference is set
    if (_soundAlerts) {
      // This is where you would add a sound playing library call
      // e.g., audioPlayer.play(AssetSource('sounds/new_order_alert.mp3'));
      print('[Polling] Sound alert would play here.');
    }
  }
  // --- END: Polling Methods ---

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    // Determine initial loading state based on profile *and* general loading
    bool showInitialLoader =
        (_isLoading || _isLoadingProfile) && _transporterProfile == null;

    return Scaffold(
      backgroundColor: _white,
      appBar: AppBar(
        title: _buildAppBarTitle(),
        backgroundColor: _white,
        foregroundColor: _darkTeal,
        elevation: _selectedDrawerIndex == 2
            ? 0
            : 1, // Add elevation except for profile screen
        iconTheme: IconThemeData(color: _darkTeal),
        actions: [
          // Show refresh indicator only when profile is loading in background
          if ((_isLoadingProfile && _transporterProfile != null) || _isPolling)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _primaryTeal))),
            )
        ],
      ),
      drawer: _buildDrawer(),
      body: showInitialLoader
          ? Center(child: CircularProgressIndicator(color: _primaryTeal))
          : _errorMessage != null &&
                  _transporterProfile ==
                      null // Show fatal error only if profile also failed
              ? _buildFatalErrorBody(_errorMessage!)
              : _buildBody(),
    );
  }

  Widget _buildFatalErrorBody(String message) {
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: _red, size: 50),
          SizedBox(height: 16),
          Text(
            'Failed to Load Dashboard',
            style: TextStyle(
                color: _red, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: _grey),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            icon: Icon(Icons.refresh),
            label: Text('Retry'),
            onPressed: _loadInitialData,
            style: ElevatedButton.styleFrom(
                backgroundColor: _primaryTeal, foregroundColor: _white),
          )
        ],
      ),
    ));
  }

  Widget _buildAppBarTitle() {
    String title;
    Widget? titleWidget;

    switch (_selectedDrawerIndex) {
      case 0: // Dashboard
        title = _transporterProfile?.name ?? 'Transporter Dashboard';
        titleWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: _primaryTeal.withOpacity(0.1),
              backgroundImage: (_transporterProfile?.profileImageUrl != null &&
                      _transporterProfile!.profileImageUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(
                      _transporterProfile!.profileImageUrl!)
                  : const AssetImage('assets/images/proffr.png'),
              onBackgroundImageError:
                  (_transporterProfile?.profileImageUrl != null &&
                          _transporterProfile!.profileImageUrl!.isNotEmpty)
                      ? (_, __) {
                          print(
                              "Error loading profile image: ${_transporterProfile?.profileImageUrl}");
                        }
                      : null,
              child: (_transporterProfile?.profileImageUrl == null ||
                          _transporterProfile!.profileImageUrl!.isEmpty) &&
                      _transporterProfile?.name.isNotEmpty ==
                          true // Added null check for name
                  ? Text(
                      _transporterProfile!.name[0].toUpperCase(),
                      style: TextStyle(
                          color: _primaryTeal, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            SizedBox(width: 10),
            Text(title,
                style: TextStyle(
                    color: _darkTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        );
        break;
      case 1:
        title = 'Deliveries';
        break;
      case 2:
        title = 'Profile';
        break;
      case 3:
        title = 'Earnings History';
        break; // Added for consistency if Earnings is a main view
      default:
        title = 'Dashboard';
    }

    return titleWidget ??
        Text(title,
            style: TextStyle(
                color: _darkTeal, fontWeight: FontWeight.bold, fontSize: 18));
  }

  Widget _buildDrawer() {
    // Use standard Flutter Drawer
    return Drawer(
      backgroundColor: _white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: _primaryTeal),
            accountName: Text(
              _transporterProfile?.name ?? 'Rider Name',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            accountEmail: Text(_transporterProfile?.email ?? 'rider@email.com'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: _lightTeal,
              backgroundImage: (_transporterProfile?.profileImageUrl != null &&
                      _transporterProfile!.profileImageUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(
                      _transporterProfile!.profileImageUrl!)
                  : const AssetImage('assets/images/proffr.png'),
              onBackgroundImageError:
                  (_transporterProfile?.profileImageUrl != null &&
                          _transporterProfile!.profileImageUrl!.isNotEmpty)
                      ? (_, __) {
                          print(
                              "Error loading drawer image: ${_transporterProfile?.profileImageUrl}");
                        }
                      : null,
              child: (_transporterProfile?.profileImageUrl == null ||
                          _transporterProfile!.profileImageUrl!.isEmpty) &&
                      _transporterProfile?.name.isNotEmpty == true
                  ? Text(
                      _transporterProfile!.name[0].toUpperCase(),
                      style: TextStyle(
                          fontSize: 30,
                          color: _darkTeal,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            // Optional: Add other header elements if needed
            // otherAccountsPictures: [ ... ],
          ),
          _buildDrawerItem(Icons.dashboard_customize_outlined, 'Dashboard', 0),
          _buildDrawerItem(Icons.delivery_dining_outlined, 'Deliveries', 1),
          _buildDrawerItem(Icons.person_outline, 'Profile', 2),
          Divider(color: Colors.grey.shade300, indent: 16, endIndent: 16),
          _buildDrawerItem(Icons.account_balance_wallet_outlined,
              'Earnings History', 3), // Index 3 for Earnings
          _buildDrawerItem(Icons.logout, 'Sign Out', 4), // Index 4 for Sign Out
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, int index) {
    bool isSelected = _selectedDrawerIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? _primaryTeal : _grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? _primaryTeal : _darkTeal,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      tileColor: isSelected ? _primaryTeal.withOpacity(0.1) : null,
      onTap: () {
        Navigator.pop(context); // Close the drawer
        if (index == 4) {
          _signOut(); // Handle sign out
        } else if (index == 3) {
          // Navigate to Earnings History Screen directly
          if (_payments.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EarningsHistoryScreen(payments: _payments)));
          } else {
            _showSnackBar("No earnings history available yet.", isError: true);
          }
        } else {
          // Only update state if index actually changed
          if (_selectedDrawerIndex != index) {
            setState(() {
              _selectedDrawerIndex = index;
              // Reset delivery tab when navigating away from deliveries
              if (index != 1) {
                _selectedDeliveryTab = 0;
              }
            });
          }
        }
      },
    );
  }

  // --- Snackbar Helpers (Adapted from old) ---
  void _showSnackBar(String message,
      {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: TextStyle(color: _white), // Consistent white text
            textAlign: TextAlign.center),
        backgroundColor: isError
            ? _errorColor.withOpacity(0.9)
            : _darkTeal.withOpacity(0.9), // Use dark teal for success
        duration: Duration(seconds: durationSeconds),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        elevation: 4.0,
      ),
    );
  }

  void _showErrorSnackBar(String message) =>
      _showSnackBar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackBar(String message) =>
      _showSnackBar(message, isError: false);

  // --- Logout ---
  Future<void> _signOut() async {
    // Optional: Confirmation Dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _grey))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Sign Out', style: TextStyle(color: _red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // --- NEW: Stop polling on sign out ---
        _stopPolling();
        // ---

        // Get user ID before clearing prefs
        final prefs = await SharedPreferences.getInstance();
        final userId =
            prefs.getString('transporter_user_id') ?? prefs.getString('user_id');

        // Clear user-specific caches
        if (userId != null) {
          await UserCache.clearUserData(userId);
        }

        // Dynamically clear all user-related keys from SharedPreferences
        final keys = prefs.getKeys();
        final patterns = [RegExp(r'_id\b'), RegExp(r'_user_type\b')];
        for (final key in keys) {
          if (patterns.any((p) => p.hasMatch(key))) {
            await prefs.remove(key);
          }
        }
        // Clear specific keys
        await prefs.remove('transporter_token');
        await prefs.remove('transporter_user_id');
        await prefs.remove('user_id');
        await prefs.remove('user_type');

        // Clear profile cache
        await UserCache.removeData(_profileCacheKey);
        await UserCache.removeData(_profileCacheTimestampKey);
        _profileCache = null; // Clear in-memory cache
        _profileCacheTimestamp = null;

        if (mounted) {
          // Navigate to login screen and remove all previous routes
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) => const TransporterLoginPage()),
            (Route<dynamic> route) => false,
          );
        }
      } catch (e) {
        print("Error during sign out: $e");
        _showErrorSnackBar("Could not sign out properly: $e");
        // Still attempt navigation
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) => const TransporterLoginPage()),
            (Route<dynamic> route) => false,
          );
        }
      }
    }
  }

  Widget _buildBody() {
    switch (_selectedDrawerIndex) {
      case 0:
        return _buildDashboardBody();
      case 1:
        return _buildDeliveriesBody();
      case 2:
        return _buildProfileBody();
      default:
        return _buildDashboardBody(); // Fallback
    }
  }

  // --- Dashboard Screen ---
  Widget _buildDashboardBody() {
    // Show loader specifically for dashboard content if general loading is still true
    if (_isLoading && _allOrders.isEmpty && _payments.isEmpty) {
      return Center(child: CircularProgressIndicator(color: _primaryTeal));
    }
    // Show general error if occurred during order/payment fetch
    if (_errorMessage != null && _allOrders.isEmpty && _payments.isEmpty) {
      return _buildFatalErrorBody(_errorMessage!); // Reuse fatal error display
    }

    // Filter orders for dashboard view
    List<Order> activeDeliveries = _getActiveOrders();
    List<Order> recentActivity = _getRecentActivityOrders();
    List<Order> scheduledDeliveries = _getScheduledOrders();
    double todaysEarnings = _calculateTodaysEarnings();

    return RefreshIndicator(
      onRefresh: _loadInitialData, // Pull to refresh all data
      color: _primaryTeal,
      child: ListView(
        padding: EdgeInsets.all(16.0),
        children: [
          // Welcome Message (handle null profile briefly during initial load)
          Text(
            _transporterProfile != null
                ? 'Welcome Back, ${_transporterProfile!.name}!'
                : 'Welcome Back!',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: _darkTeal),
          ),
          SizedBox(height: 8),
          Text(
            'Ready to make some deliveries?',
            style: TextStyle(fontSize: 16, color: _grey),
          ),
          SizedBox(height: 20),
          _buildDashboardActionButtons(),
          SizedBox(height: 20),
          _buildActiveDeliveriesCard(activeDeliveries.length),
          SizedBox(height: 16),
          _buildEarningsCard(todaysEarnings),
          SizedBox(height: 16),
          _buildGoOnlineCard(), // Includes online/offline toggle
          SizedBox(height: 20),
          // Only show recent/scheduled if they contain data
          if (recentActivity.isNotEmpty) ...[
            _buildRecentActivityCard(recentActivity),
            SizedBox(height: 20),
          ],
          if (scheduledDeliveries.isNotEmpty) ...[
            _buildScheduledDeliveriesCard(scheduledDeliveries),
            SizedBox(height: 20),
          ]
        ],
      ),
    );
  }

  Widget _buildDashboardActionButtons() {
    // Same as provided
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(Icons.delivery_dining, size: 18),
            label: Text('Active Deliveries'),
            onPressed: () {
              setState(() {
                _selectedDrawerIndex = 1; // Navigate to Deliveries screen
                _selectedDeliveryTab = 0; // Show Active tab
              });
            },
            style: OutlinedButton.styleFrom(
                foregroundColor: _darkTeal,
                side: BorderSide(color: _lightTeal),
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            icon: Icon(Icons.search, size: 18),
            label: Text('Find Orders'),
            onPressed: () {
              setState(() {
                _selectedDrawerIndex = 1; // Navigate to Deliveries screen
                _selectedDeliveryTab = 1; // Show Available tab
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryTeal, // Teal background
              foregroundColor: _white, // White text/icon
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    String? actionText,
    VoidCallback? onActionTap,
    Widget? trailingWidget,
  }) {
    // Same as provided
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: _grey, fontSize: 14)),
                  SizedBox(height: 8),
                  Text(value,
                      style: TextStyle(
                          color: _darkTeal,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                  if (actionText != null) ...[
                    SizedBox(height: 12),
                    InkWell(
                      onTap: onActionTap,
                      child: Text(
                        actionText,
                        style: TextStyle(
                            color: _primaryTeal, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                if (trailingWidget != null) ...[
                  SizedBox(height: 15),
                  trailingWidget,
                ]
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDeliveriesCard(int count) {
    // Same as provided
    return _buildInfoCard(
        title: 'Active Deliveries',
        value: count.toString(),
        icon: Icons.delivery_dining,
        iconBgColor: _primaryTeal.withOpacity(0.1),
        iconColor: _primaryTeal,
        actionText: 'View all deliveries',
        trailingWidget: Icon(Icons.gps_fixed, color: _primaryTeal),
        onActionTap: () {
          setState(() {
            _selectedDrawerIndex = 1;
            _selectedDeliveryTab = 0;
          });
        });
  }

  double _calculateTodaysEarnings() {
    DateTime now = DateTime.now();
    DateTime todayStart = DateTime(now.year, now.month, now.day);
    DateTime todayEnd = todayStart.add(Duration(days: 1));

    // Sum successful payments from today
    double total = _payments
        .where((p) =>
            p.createdAt.isAfter(todayStart) &&
            p.createdAt.isBefore(todayEnd) &&
            p.disbursementTransactionStatus ==
                'Successful') // Using computed property
        .fold(0.0, (sum, p) => sum + p.amount);

    // Add earnings from orders completed today IF no corresponding payment exists
    for (var order in _getCompletedOrders()) {
      if (order.orderDate.isAfter(todayStart) &&
          order.orderDate.isBefore(todayEnd)) {
        bool paymentExistsToday = _payments.any((p) =>
            p.orderId == order.orderId &&
            p.createdAt.isAfter(todayStart) &&
            p.createdAt.isBefore(todayEnd) &&
            p.disbursementTransactionStatus == 'Successful');
        if (!paymentExistsToday) {
          total +=
              order.earnings; // Use calculated earnings with null safety
        }
      }
    }

    return total;
  }

  Widget _buildEarningsCard(double earnings) {
    // Same as provided
    return _buildInfoCard(
        title: 'Today\'s Earnings',
        value:
            'ugx ${earnings.toStringAsFixed(0)}', // No decimals for UGX maybe? Adjust if needed.
        icon: Icons.attach_money,
        iconBgColor: _green.withOpacity(0.1),
        iconColor: _green,
        actionText: 'View earnings history',
        onActionTap: () {
          if (_payments.isNotEmpty) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => EarningsHistoryScreen(payments: _payments)));
          } else {
            _showSnackBar("No earnings history available yet.", isError: true);
          }
        });
  }

  Widget _buildGoOnlineCard() {
    // Same as provided
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isOnline ? 'You are Online' : 'Go Online',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal),
            ),
            SizedBox(height: 8),
            Text(
              _isOnline
                  ? 'You are receiving new order alerts'
                  : 'Start receiving orders',
              style: TextStyle(color: _grey, fontSize: 14),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                    _isOnline
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    size: 20),
                label: Text(_isOnline ? 'Go Offline' : 'Start Riding'),
                onPressed: _isLoadingProfile
                    ? null
                    : _toggleOnlineStatus, // Disable while profile is loading/refreshing
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isOnline ? Colors.red.shade400 : _primaryTeal,
                  foregroundColor: _white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Toggle Online/Offline Status (Adapted from old code's logic)
  Future<void> _toggleOnlineStatus() async {
    if (_transporterProfile == null) {
      _showErrorSnackBar("Profile not loaded yet.");
      return;
    }
    final bool targetStatus = !_isOnline;
    // Show loading indicator (optional, can use snackbar instead)
    _showLoadingSnackbar(targetStatus ? "Going Online..." : "Going Offline...");

    try {
      bool success = await TransporterApiService.updateTransporterActiveStatus(
          widget.transporterId, targetStatus);
      _dismissLoadingSnackbar(); // Dismiss loading snackbar

      if (success && mounted) {
        setState(() {
          _isOnline = targetStatus;
          // Update local profile cache optimistically
          _transporterProfile =
              _transporterProfile?.copyWith(isActive: targetStatus);
          if (_transporterProfile != null) {
            _saveProfileCacheToPrefs(_transporterProfile!); // Update cache
          }
        });

        // --- NEW: Start or stop polling based on status ---
        if (targetStatus) {
          _startPolling();
        } else {
          _stopPolling();
        }
        // ---

        _showSuccessSnackBar(
            targetStatus ? 'You are now Online!' : 'You are now Offline.');
      } else if (mounted) {
        _showErrorSnackBar('Failed to update status. Please try again.');
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("Failed to toggle online status: $e");
      if (mounted) {
        _showErrorSnackBar('Error updating status: ${e.toString()}');
      }
    }
  }

  // --- Loading Snackbar Helpers (Adapted from old) ---
  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: Colors.white))
        ],
      ),
      backgroundColor: Colors.black.withOpacity(0.7),
      duration: const Duration(seconds: 60), // Long duration, dismiss manually
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
    ));
  }

  void _dismissLoadingSnackbar() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }

  // Filter/Sort Functions (same as provided)
  List<Order> _getRecentActivityOrders() {
    List<Order> completedOrCancelled = _allOrders
        .where((o) => [
              Order.STATUS_DELIVERED.toLowerCase(),
              Order.STATUS_COMPLETED.toLowerCase(),
              Order.STATUS_CANCELLED.toLowerCase()
            ].contains(o.orderStatus.toLowerCase()))
        .toList();
    completedOrCancelled.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return completedOrCancelled.take(3).toList();
  }

  List<Order> _getScheduledOrders() {
    // Scheduled could mean assigned/accepted but not yet started
    return _allOrders
        .where((o) => [
              Order.STATUS_ASSIGNED.toLowerCase(),
              Order.STATUS_ACCEPTED.toLowerCase()
            ].contains(o.orderStatus.toLowerCase()))
        .toList()
      ..sort((a, b) => a.orderDate.compareTo(b.orderDate)); // Soonest first
  }

  Widget _buildRecentActivityCard(List<Order> recentOrders) {
    // Same as provided
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Activity',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkTeal)),
            Text('Your latest deliveries',
                style: TextStyle(color: _grey, fontSize: 14)),
            SizedBox(height: 16),
            if (recentOrders.isEmpty)
              Text('No recent activity.', style: TextStyle(color: _grey))
            else
              Column(
                children: [
                  ...recentOrders
                      .map((order) => _buildRecentActivityItem(order)),
                  Padding(
                    // Add "View full history" link at the end
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDrawerIndex = 1;
                            _selectedDeliveryTab = 2; // Completed tab
                          });
                        },
                        child: Text(
                          'View full history',
                          style: TextStyle(
                              color: _primaryTeal, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  )
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityItem(Order order) {
    // Simplified version - adapt icons/colors as needed
    IconData statusIcon;
    Color iconColor;
    String relativeTime = _getRelativeTime(order.orderDate);

    switch (order.orderStatus.toLowerCase()) {
      case "delivered":
      case "completed":
        statusIcon = Icons.check_circle;
        iconColor = _green;
        break;
      case "cancelled":
        statusIcon = Icons.cancel;
        iconColor = _red;
        break;
      default: // In progress states shown here? Unlikely but handle
        statusIcon = Icons.local_shipping;
        iconColor = _primaryTeal;
        relativeTime = "In Progress";
        break;
    }

    IconData leadingIcon = order.orderType.toLowerCase() == 'meal'
        ? Icons.restaurant
        : Icons.inventory_2; // Example icon based on type

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryTeal.withOpacity(0.1), // Consistent bg color
              shape: BoxShape.circle,
            ),
            child: Icon(leadingIcon, color: _primaryTeal, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order.orderId}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: _darkTeal)),
                Text(_getStatusText(order.orderStatus),
                    style: TextStyle(color: _grey, fontSize: 13)),
              ],
            ),
          ),
          SizedBox(width: 8),
          Column(
            // Align time and status icon vertically
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(relativeTime, style: TextStyle(color: _grey, fontSize: 12)),
              SizedBox(height: 2),
              Icon(statusIcon, color: iconColor, size: 16),
            ],
          ),
        ],
      ),
    );
  }

  String _getRelativeTime(DateTime dateTime) {
    // Same as provided
    final Duration difference = DateTime.now().difference(dateTime);
    if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 2) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return DateFormat('MMM d').format(dateTime);
  }

  String _getStatusText(String apiStatus) {
    // Handle empty status
    if (apiStatus.isEmpty) return 'Unknown';

    // Normalize the input status by converting to lowercase and replacing underscores/hyphens with spaces
    String normalizeStatus(String status) {
      return status.toLowerCase().replaceAll(RegExp(r'[_-]'), ' ').trim();
    }

    final normalizedStatus = normalizeStatus(apiStatus);
    final normalizedTargets = {
      normalizeStatus(Order.STATUS_PENDING): 'Pending',
      normalizeStatus(Order.STATUS_ASSIGNED): 'Assigned',
      normalizeStatus(Order.STATUS_ACCEPTED): 'Accepted',
      normalizeStatus(Order.STATUS_PICKED_UP): 'Picked Up',
      'verification needed': 'Verification Needed', // Added mapping
      normalizeStatus(Order.STATUS_DELIVERED): 'Delivered',
      normalizeStatus(Order.STATUS_COMPLETED): 'Completed',
      normalizeStatus(Order.STATUS_CANCELLED): 'Cancelled',
    };

    // Try to find a matching status in our normalized map
    final matchedStatus = normalizedTargets[normalizedStatus];
    if (matchedStatus != null) {
      return matchedStatus;
    }

    // For any other status, capitalize first letter
    return apiStatus[0].toUpperCase() + apiStatus.substring(1);
  }

  Widget _buildScheduledDeliveriesCard(List<Order> scheduledOrders) {
    // Same as provided
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Next Scheduled Deliveries',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkTeal)),
            Text('Upcoming orders assigned to you',
                style: TextStyle(color: _grey, fontSize: 14)),
            SizedBox(height: 16),
            if (scheduledOrders.isEmpty)
              Text('No scheduled deliveries.', style: TextStyle(color: _grey))
            else
              Column(
                // Use Column directly, no need for map()..toList()
                children:
                    scheduledOrders.map(_buildScheduledDeliveryItem).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledDeliveryItem(Order order) {
    // Same as provided
    String formattedTime = DateFormat('h:mm a').format(order.orderDate);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: InkWell(
          onTap: () => _navigateToOrderDetails(order),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      order.productName ??
                          order.mealName ??
                          'Order #${order.orderId}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _darkTeal,
                          fontSize: 15)),
                  Row(children: [
                    Icon(Icons.access_time, size: 14, color: _grey),
                    SizedBox(width: 4),
                    Text(formattedTime,
                        style: TextStyle(color: _grey, fontSize: 13))
                  ]),
                ],
              ),
              SizedBox(height: 6),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 14, color: _grey),
                SizedBox(width: 4),
                Expanded(
                    child: Text(order.simplifiedDeliveryAddress,
                        style: TextStyle(color: _grey, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1))
              ]),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Dist: ${order.estimatedDistance}',
                      style: TextStyle(color: _grey, fontSize: 13)),
                  Text(
                      'ugx ${order.earnings.toStringAsFixed(0)}', // Use calculated earnings, format UGX
                      style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.bold,
                          fontSize: 14))
                ],
              ),
              Divider(color: _lightTeal.withOpacity(0.5), height: 20),
            ],
          ),
        ));
  }

  // --- Deliveries Screen ---
  Widget _buildDeliveriesBody() {
    // This screen might need its own loading state if fetches are tab-specific
    // For now, assumes _allOrders is loaded initially
    List<Order> ordersToShow;
    switch (_selectedDeliveryTab) {
      case 0:
        ordersToShow = _getActiveOrders();
        break;
      case 1:
        ordersToShow = _getAvailableOrders();
        break;
      case 2:
        ordersToShow = _getCompletedOrders();
        break;
      default:
        ordersToShow = [];
    }

    return Column(
      children: [
        Padding(
          // Search Bar
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by order ID, name, address...',
              prefixIcon: Icon(Icons.search, color: _grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: _grey, size: 20),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: _lightGrey,
              contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(color: _primaryTeal, width: 1)),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim().toLowerCase();
              });
            },
          ),
        ),
        Padding(
          // Tabs
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: _buildDeliveryTabs(),
        ),
        Expanded(
          // Order List
          child: RefreshIndicator(
            onRefresh: _loadInitialData, // Refresh all data
            color: _primaryTeal,
            child: ordersToShow.isEmpty
                ? Center(
                    child: Text(
                        'No ${_getTabName(_selectedDeliveryTab).toLowerCase()} deliveries found.',
                        style: TextStyle(color: _grey, fontSize: 16)))
                : ListView.builder(
                    itemCount: ordersToShow.length,
                    padding: EdgeInsets.only(
                        left: 16, right: 16, bottom: 16, top: 8),
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _buildOrderCard(ordersToShow[
                            index]), // Use the existing order card builder
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryTabs() {
    // Same as provided
    return Container(
      decoration: BoxDecoration(
          color: _lightGrey, borderRadius: BorderRadius.circular(30)),
      padding: EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabItem('Active', 0),
          _buildTabItem('Available', 1),
          _buildTabItem('Completed', 2),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, int index) {
    // Same as provided
    bool isSelected = _selectedDeliveryTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedDeliveryTab = index;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _white : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: Offset(0, 1))
                  ]
                : [],
          ),
          child: Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isSelected ? _primaryTeal : _grey,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  // Helper method to normalize status strings for comparison
  String _normalizeStatus(String status) {
    // First normalize the string (lowercase, remove underscores, trim)
    final normalized =
        status.toLowerCase().replaceAll(RegExp(r'[_-]'), ' ').trim();

    // Treat 'complete', 'completed', and 'delivered' as the same status
    if (normalized == 'complete' || normalized == 'delivered') {
      return 'completed';
    }

    return normalized;
  }

  // Search query controller and variable
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter orders based on search query
  bool _matchesSearchQuery(Order order) {
    if (_searchQuery.isEmpty) return true;

    final query = _searchQuery.toLowerCase();

    // Search in order ID
    if (order.orderId.toString().contains(query)) return true;

    // Search in product/meal name
    if ((order.productName?.toLowerCase() ?? '').contains(query) ||
        (order.mealName?.toLowerCase() ?? '').contains(query)) {
      return true;
    }

    // Search in delivery address
    if ((order.deliveryAddress.toLowerCase()).contains(query)) {
      // deliveryAddress is not nullable
      return true;
    }

    // Search in customer phone
    if (order.userPhone?.contains(query) ?? false) {
      return true;
    }

    return false;
  }

  // Filtering logic for different tabs
  List<Order> _getActiveOrders() {
    // Show orders that are either picked up or need verification
    return _allOrders
        .where((o) {
          final status = _normalizeStatus(o.orderStatus);
          final isActive =
              status == _normalizeStatus(Order.STATUS_PICKED_UP) ||
                  status ==
                      _normalizeStatus(
                          Order.STATUS_VERIFICATION_NEEDED) || // Added actual constant
                  status ==
                      _normalizeStatus(
                          'verification needed'); // Keep string for robustness
          return isActive && _matchesSearchQuery(o);
        })
        .toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate)); // Newest first
  }

  List<Order> _getAvailableOrders() {
    // Show 'assigned' or 'pending' orders in the Available tab
    return _allOrders
        .where((o) {
          final status = _normalizeStatus(o.orderStatus);
          final isAvailable =
              status == _normalizeStatus(Order.STATUS_ASSIGNED) ||
                  status == _normalizeStatus(Order.STATUS_PENDING);
          return isAvailable && _matchesSearchQuery(o);
        })
        .toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate)); // Newest first
  }

  List<Order> _getCompletedOrders() {
    // All these statuses will be normalized to 'completed' by _normalizeStatus
    return _allOrders
        .where((o) =>
            (_normalizeStatus(o.orderStatus) == 'completed' ||
                _normalizeStatus(o.orderStatus) ==
                    _normalizeStatus(Order.STATUS_CANCELLED)) &&
            _matchesSearchQuery(o))
        .toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate)); // Most recent first
  }

  String _getTabName(int index) {
    switch (index) {
      case 0:
        return 'Active';
      case 1:
        return 'Available';
      case 2:
        return 'Completed';
      default:
        return '';
    }
  }

  Future<void> _launchGoogleMapsNavigation(LatLng destination, {Order? order}) async {
    try {
      // Build the base URL with required parameters
      final baseUrl = 'https://www.google.com/maps/dir/?api=1';
      
      // Add origin parameter if we have an order with pickup or chef location
      String originParam = '';
      if (order != null) {
        // Try pickup location first, then chef's location
        String? locationString = order.pickupLocation ?? order.producerAddress;
        if (locationString != null && locationString.isNotEmpty) {
          final originLocation = _parseLocationToLatLng(locationString);
          if (originLocation != null) {
            originParam = '&origin=${originLocation.latitude},${originLocation.longitude}';
          }
        }
      }
      
      // Build the complete URL with all parameters
      final url = '$baseUrl$originParam&destination=${destination.latitude},${destination.longitude}&travelmode=driving&dir_action=navigate&hl=en';

      // Check if the URL can be launched
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        // Fallback to basic URL without origin if the full URL fails
        final fallbackUrl = '$baseUrl&destination=${destination.latitude},${destination.longitude}&travelmode=driving';
        if (await canLaunchUrl(Uri.parse(fallbackUrl))) {
          await launchUrl(Uri.parse(fallbackUrl));
        } else {
          _showErrorSnackBar('Could not launch Google Maps. Please install Google Maps app.');
        }
      }
    } catch (e) {
      print('Error launching Google Maps: $e');
      _showErrorSnackBar('Failed to open navigation: ${e.toString()}');
    }
  }

  // Order Card used in Deliveries List
  Widget _buildOrderCard(Order order) {
    String status = order.orderStatus;
    bool isAvailable =
        _getAvailableOrders().any((o) => o.orderId == order.orderId);
    bool isCompleted =
        _getCompletedOrders().any((o) => o.orderId == order.orderId);

    Color statusColor;
    String statusText =
        _getStatusText(order.orderStatus); // User-friendly status
    Widget? actionButton;

    // Determine Button based on Tab/Status
    if (isAvailable) {
      statusColor = _grey;
      statusText = 'Available'; // Override for clarity
      actionButton = Row(children: [
        Expanded(
            child: OutlinedButton(
          onPressed: () => _handleRejectOrder(order),
          child: Text('Ignore'),
          style: OutlinedButton.styleFrom(
              foregroundColor: _grey,
              side: BorderSide(color: Colors.grey.shade300)),
        )),
        SizedBox(width: 8),
        Expanded(
            child: ElevatedButton(
          onPressed: () => _handleAcceptOrder(order),
          child: Text('Accept'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _primaryTeal, foregroundColor: _white),
        )),
      ]);
    } else if (isCompleted) {
      statusColor =
          (status.toLowerCase() == Order.STATUS_CANCELLED.toLowerCase())
              ? _red
              : _green;
      statusText =
          _getStatusText(status); // Show actual completed/cancelled status
      actionButton = SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _navigateToOrderDetails(order),
            child: Text('View Details'),
            style: OutlinedButton.styleFrom(
                foregroundColor: _darkTeal,
                side: BorderSide(color: _lightTeal)),
          ));
    } else {
      // Active Orders
      statusColor = _primaryTeal;
      statusText = _getStatusText(status);
      actionButton = SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _navigateToOrderDetails(order),
            child: Text('View Details / Update'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _primaryTeal, foregroundColor: _white),
          ));
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.grey.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // Header: ID & Status
              Text('Order #${order.orderId}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _darkTeal)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ]),
            Text(
                DateFormat('MMM d, yyyy, h:mm a')
                    .format(order.orderDate), // More specific date format
                style: TextStyle(color: _grey, fontSize: 12)), // Date
            SizedBox(height: 12),
            _buildAddressRow(Icons.storefront, order.pickupAddress), // Pickup
            SizedBox(height: 6),
            _buildAddressRow(Icons.location_on_outlined,
                order.simplifiedDeliveryAddress), // Delivery
            SizedBox(height: 12),
            _buildOrderInfoRow(order), // Dist, Time, Earn
            SizedBox(height: 16),
            if (actionButton != null) actionButton, // Action Button

            // *** START: Navigation Button Added with new parsing logic ***
            // Only show navigation for active orders
            if (!isAvailable && !isCompleted) ...[
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.directions, size: 18),
                  label: Text('Navigate'),
                  onPressed: () {
                    // Use the robust parsing function
                    final LatLng? destination =
                        _parseLocationToLatLng(order.deliveryAddress);

                    if (destination != null) {
                      print(
                          "Attempting to navigate to: Lat=${destination.latitude}, Lng=${destination.longitude}");
                      _launchGoogleMapsNavigation(destination, order: order);
                    } else {
                      _showErrorSnackBar(
                          'Navigation failed: Could not extract coordinates from the delivery address.');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryTeal,
                    side: BorderSide(color: _lightTeal),
                  ),
                ),
              ),
            ],
            // *** END: Navigation Button Added ***
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, String address) {
    // Same as provided
    return Row(children: [
      Icon(icon, size: 16, color: _primaryTeal),
      SizedBox(width: 8),
      Expanded(
          child: Text(address,
              style: TextStyle(fontSize: 14, color: _darkTeal),
              overflow: TextOverflow.ellipsis,
              maxLines: 2)), // Allow 2 lines for address
    ]);
  }

  Widget _buildOrderInfoRow(Order order) {
    // Same as provided
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _buildInfoChip('Dist: ${order.estimatedDistance}'),
      _buildInfoChip('Time: ${order.estimatedTime}'),
      _buildInfoChip(
          'Earn: ugx ${order.earnings.toStringAsFixed(0)}', // Format UGX
          color: _green,
          fontWeight: FontWeight.bold),
    ]);
  }

  Widget _buildInfoChip(String text,
      {Color color = _grey, FontWeight fontWeight = FontWeight.normal}) {
    // Same as provided
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: _lightGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300, width: 0.5)),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: color, fontWeight: fontWeight)),
    );
  }

  void _navigateToOrderDetails(Order order) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => OrderDetailsScreen(
                  order: order,
                  transporterId: widget.transporterId,
                  onStatusUpdate: () async {
                    await _loadInitialData();
                    // If order was just completed or delivered, refresh payments
                    final updatedOrder = await _fetchOrderDetails(order.orderId);
                    if (updatedOrder != null &&
                        _isCompletedOrDelivered(updatedOrder.orderStatus)) {
                      await refreshPayments();
                    }
                  },
                )));
  }

  bool _isCompletedOrDelivered(String status) {
    final normalized = status.toLowerCase();
    return normalized == 'completed' || normalized == 'delivered';
  }

  Future<Order?> _fetchOrderDetails(int orderId) async {
    try {
      final orders = await TransporterApiService.fetchAllTransporterOrders(
          widget.transporterId);
      return orders.cast<Order?>().firstWhere(
            (order) => order?.orderId == orderId,
            orElse: () => null,
          );
    } catch (e) {
      print('Error fetching order details: $e');
      return null;
    }
  }

  // Accept/Reject handlers (using API service)
  Future<void> _handleAcceptOrder(Order order) async {
    // Same as provided
    bool confirm = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Confirmation'),
              content: Text('Are you sure you want to proceed?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Confirm'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (confirm) {
      _showLoadingSnackbar("Accepting Order #${order.orderId}...");
      try {
        bool success = await TransporterApiService.acceptOrder(
            order.orderId, widget.transporterId);
        _dismissLoadingSnackbar();
        if (success && mounted) {
          _showSuccessSnackBar('Order #${order.orderId} accepted.');
          await _loadInitialData(); // Refresh lists
        } else if (mounted) {
          _showErrorSnackBar('Failed to accept order.');
        }
      } catch (e) {
        _dismissLoadingSnackbar();
        print("Failed to accept order: $e");
        if (mounted)
          _showErrorSnackBar('Failed to accept order: ${e.toString()}');
      }
    }
  }

  Future<void> _handleRejectOrder(Order order) async {
    // Same as provided (local removal assumes reject API isn't needed)
    print("Rejecting order ${order.orderId}");
    try {
      // bool success = await TransporterApiService.rejectOrder(order.orderId, widget.transporterId); // Call API if needed
      // if (success) {
      setStateIfMounted(() {
        _allOrders.removeWhere((o) => o.orderId == order.orderId);
      });
      _showSnackBar('Order #${order.orderId} ignored.',
          isError: false); // Use normal snackbar
      // } else { throw Exception("Reject order API failed."); }
    } catch (e) {
      print("Failed to reject order: $e");
      if (mounted)
        _showErrorSnackBar('Failed to reject order: ${e.toString()}');
    }
  }

  // --- Profile Screen ---
  Widget _buildProfileBody() {
    // Show loader while profile is specifically loading/refreshing
    if (_isLoadingProfile || _transporterProfile == null) {
      // If general error happened AND profile is null, show error
      if (_errorMessage != null && _transporterProfile == null) {
        return _buildFatalErrorBody(_errorMessage!);
      }
      // Otherwise, show profile shimmer/loader
      return Center(child: CircularProgressIndicator(color: _primaryTeal));
    }
    // If profile loaded but there was a refresh error, show subtly? (Optional)
    // if (_profileFetchError != null) { ... show subtle error banner ... }

    // Profile loaded, show the tabbed view
    return DefaultTabController(
      length: 3, // Personal Info, Vehicle, Preferences
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
              child: _buildProfileHeader()), // Avatar, Name, Rating, Logout
          SliverToBoxAdapter(child: _buildProfileStats()), // Stats Card
          SliverPersistentHeader(
            // Pinned Tabs
            delegate: _SliverAppBarDelegate(
              TabBar(
                labelColor: _primaryTeal,
                unselectedLabelColor: _grey,
                indicatorColor: _primaryTeal,
                tabs: [
                  Tab(text: 'Personal Info'),
                  Tab(text: 'Vehicle'),
                  Tab(text: 'Preferences')
                ],
              ),
            ),
            pinned: true,
          ),
        ],
        body: TabBarView(
          // Tab Content
          children: [
            _buildPersonalInfoTab(),
            _buildVehicleTab(),
            _buildPreferencesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    // Same as provided, using _transporterProfile safely
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              // Add overlay for edit icon
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: _lightTeal,
                  backgroundImage: _profileImageFile != null
                      ? FileImage(_profileImageFile!) as ImageProvider
                      : (_transporterProfile?.profileImageUrl != null &&
                              _transporterProfile!
                                  .profileImageUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(_transporterProfile!
                              .profileImageUrl!) // Use CachedNetworkImage
                          : null),
                  onBackgroundImageError: (_, __) {
                    // Handle image load errors
                    print(
                        "Error loading profile header image: ${_transporterProfile?.profileImageUrl}");
                    // Optionally display placeholder icon here if needed
                  },
                  child: (_profileImageFile == null &&
                          (_transporterProfile?.profileImageUrl == null ||
                              _transporterProfile!
                                  .profileImageUrl!.isEmpty))
                      ? Icon(Icons.person, size: 60, color: _primaryTeal)
                      : null,
                ),
                Container(
                  // Edit icon circle
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: _primaryTeal,
                      shape: BoxShape.circle,
                      border: Border.all(color: _white, width: 1.5)),
                  child: Icon(Icons.edit, color: _white, size: 16),
                )
              ],
            ),
          ),
          // Text button removed, tap avatar directly
          SizedBox(height: 12),
          Text(_transporterProfile!.name,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: _darkTeal)),
          SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Chips: Vehicle Type & Rating
            if (_transporterProfile?.vehicleType != null &&
                _transporterProfile!.vehicleType!.isNotEmpty)
              Chip(
                  label: Text(_transporterProfile!.vehicleType!,
                      style: TextStyle(fontSize: 12, color: _darkTeal)),
                  backgroundColor: _primaryTeal.withOpacity(0.1),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  visualDensity: VisualDensity(horizontal: 0.0, vertical: -4),
                  side: BorderSide.none),
            if (_transporterProfile?.vehicleType != null &&
                _transporterProfile!.vehicleType!.isNotEmpty &&
                _transporterProfile?.rating != null)
              SizedBox(width: 8),
            if (_transporterProfile?.rating != null)
              Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _lightTeal.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star, color: Colors.amber, size: 16),
                    SizedBox(width: 4),
                    Text(_transporterProfile!.rating!.toStringAsFixed(1),
                        style: TextStyle(
                            color: _darkTeal,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ])),
          ]),
          SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Logout Button
                onPressed: _signOut, child: Text('Log Out'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryTeal,
                    foregroundColor: _white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              )),
        ],
      ),
    );
  }

  Widget _buildProfileStats() {
    // Same as provided, using calculated stats
    int totalDeliveries = _getCompletedOrders().length;
    double completionRate = totalDeliveries > 0 ? 98.0 : 100.0; // Placeholder
    double totalEarnings = _payments
        .where((p) =>
            (p.disbursementTransactionStatus.toLowerCase() == 'successful' ||
                p.disbursementTransactionStatus.toLowerCase() == 'completed'))
        .fold(0.0, (sum, p) => sum + p.amount);

    return Card(
      /* ... Same Card structure ... */
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rider Stats',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
          Text('Your delivery performance',
              style: TextStyle(color: _grey, fontSize: 14)),
          SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildStatItem(
                Icons.motorcycle, totalDeliveries.toString(), 'Deliveries'),
            _buildStatItem(
                Icons.star_border,
                _transporterProfile?.rating?.toStringAsFixed(1) ?? 'N/A',
                'Rating'), // Handle null rating
          ]),
          SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _buildStatItem(Icons.check_circle_outline,
                '${completionRate.toStringAsFixed(0)}%', 'Completion',
                color: _green),
            _buildStatItem(
                Icons.account_balance_wallet_outlined,
                'ugx ${totalEarnings.toStringAsFixed(0)}',
                'Earnings', // Format UGX
                color: _green),
          ]),
        ]),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label,
      {Color color = _primaryTeal}) {
    // Same as provided
    return Column(children: [
      Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24)),
      SizedBox(height: 8),
      Text(value,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
      Text(label, style: TextStyle(fontSize: 12, color: _grey)),
    ]);
  }

  // --- Profile Tabs Content ---

  Widget _buildPersonalInfoTab() {
    // Same as provided, using _profileEditFormKey
    return SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _profileEditFormKey, // Use form key
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Personal Information',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkTeal)),
            Text('Update your personal details',
                style: TextStyle(color: _grey, fontSize: 14)),
            SizedBox(height: 20),
            _buildTextField(_nameController, 'Full Name'), SizedBox(height: 16),
            _buildTextField(_emailController, 'Email', enabled: false),
            SizedBox(height: 16), // Email not editable
            _buildTextField(_phoneController, 'Phone Number',
                enabled: false, keyboardType: TextInputType.phone),
            SizedBox(height: 16),
            _buildTextField(_addressController, 'Address'),
            SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  // Save Button
                  onPressed: _isSavingProfile ? null : _savePersonalChanges,
                  child: _isSavingProfile
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: _white, strokeWidth: 2))
                      : Text('Save Changes'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryTeal,
                      foregroundColor: _white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                )),
            SizedBox(height: 30),
            _buildDocumentsSection(), // Display documents
          ]),
        ));
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {bool enabled = true, TextInputType keyboardType = TextInputType.text}) {
    // Same as provided
    return TextFormField(
      controller: controller, keyboardType: keyboardType, enabled: enabled,
      style: TextStyle(color: enabled ? _darkTeal : _grey),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(color: _grey),
        filled: true,
        fillColor: enabled
            ? _lightGrey
            : Colors.grey.shade200, // Different fill when disabled
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: _primaryTeal)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(
                color: Colors.grey.shade300)), // Style for disabled border
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),
      // validator: (value) { /* Add validation if needed */ return null; },
    );
  }

  // Save Personal Info (Handles Image Upload)
  Future<void> _savePersonalChanges() async {
    if (!(_profileEditFormKey.currentState?.validate() ?? false)) {
      _showErrorSnackBar("Please fix errors in the form.");
      return;
    }
    if (_isUploadingProfileImage) {
      _showErrorSnackBar("Please wait for image upload to complete.");
      return;
    }

    setState(() => _isSavingProfile = true);
    _showLoadingSnackbar("Saving Profile...");

    String? uploadedImageUrl =
        _transporterProfile?.profileImageUrl; // Start with current URL

    try {
      // 1. Upload image if a new one was picked
      if (_profileImageFile != null) {
        setState(() => _isUploadingProfileImage = true);
        _dismissLoadingSnackbar(); // Dismiss general saving snackbar
        _showLoadingSnackbar(
            "Uploading image..."); // Show image upload snackbar
        try {
          uploadedImageUrl =
              await TransporterApiService.uploadImageToImgur(_profileImageFile!);
          if (uploadedImageUrl == null)
            throw Exception("Image upload returned null URL.");
          setState(() => _isUploadingProfileImage = false);
          _dismissLoadingSnackbar(); // Dismiss image upload snackbar
          _showLoadingSnackbar(
              "Saving Profile..."); // Show saving snackbar again
        } catch (imgErr) {
          setState(() => _isUploadingProfileImage = false);
          _dismissLoadingSnackbar();
          throw Exception("Image upload failed: $imgErr"); // Propagate error
        }
      }

      // 2. Build update data, including potentially new image URL
      Map<String, dynamic> updateData = {
        'name': _nameController.text,
        'phone_number': _phoneController.text,
        'address': _addressController.text,
        // Only include image URL if it's different from the original OR if it was just uploaded
        // Make sure the key matches the API expectation, e.g., 'image' or 'profile_image_url'
        if (uploadedImageUrl != _transporterProfile?.profileImageUrl)
          'image': uploadedImageUrl,
      };
      // Clean data (remove unchanged fields - optional but good practice)
      if (_transporterProfile != null) {
        // Added null check
        updateData.removeWhere(
            (key, value) => value == _transporterProfile!.toJson()[key]);
      }
      updateData.removeWhere(
          (key, value) => value == null || (value is String && value.isEmpty));

      // 3. Call API to update profile if data changed
      if (updateData.isNotEmpty) {
        print("Sending profile update data: $updateData");
        bool success = await TransporterApiService.updateTransporterProfile(
            widget.transporterId, updateData);
        if (!success)
          throw Exception("Profile update API call returned false.");

        // 4. Success: Refresh data, clear temp image file
        await _fetchTransporterProfileAndUpdate(); // Fetch fresh profile to confirm changes
        setState(() {
          _profileImageFile = null;
        }); // Clear picked file
        _dismissLoadingSnackbar();
        _showSuccessSnackBar('Profile updated successfully!');
      } else {
        _dismissLoadingSnackbar();
        _showSnackBar("No changes detected to save.",
            isError: false); // Inform user
      }
    } catch (e) {
      print("Failed to save personal changes: $e");
      _dismissLoadingSnackbar(); // Ensure loading indicator dismissed on error
      if (mounted)
        _showErrorSnackBar('Failed to save profile: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Widget _buildDocumentsSection() {
    // Same as provided (uses placeholder data)
    String licenseExpiry = "April 15, 2027";
    String insuranceExpiry = "December 10, 2025";
    String backgroundCheckDate = "January 5, 2025";
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Documents',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
      Text('Your identification and authorization documents',
          style: TextStyle(color: _grey, fontSize: 14)),
      SizedBox(height: 16),
      _buildDocumentItem('Driver\'s License', 'Expires on $licenseExpiry',
          isVerified: true),
      SizedBox(height: 12),
      _buildDocumentItem('Vehicle Insurance', 'Expires on $insuranceExpiry',
          isVerified: true),
      SizedBox(height: 12),
      _buildDocumentItem(
          'Background Check', 'Completed on $backgroundCheckDate',
          isVerified: true),
      SizedBox(height: 24),
      SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            // Upload Button
            icon: Icon(Icons.upload_file_outlined, size: 18),
            label: Text('Upload New Document'),
            onPressed: () {
              _showSnackBar("Document upload not implemented.", isError: true);
            },
            style: OutlinedButton.styleFrom(
                foregroundColor: _primaryTeal,
                side: BorderSide(color: _lightTeal),
                padding: EdgeInsets.symmetric(vertical: 12)),
          )),
    ]);
  }

  Widget _buildDocumentItem(String title, String subtitle,
      {required bool isVerified}) {
    // Same as provided
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _lightGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300, width: 0.5)),
      child: Row(children: [
        Icon(Icons.description_outlined, color: _darkTeal),
        SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(fontWeight: FontWeight.w600, color: _darkTeal)),
          Text(subtitle, style: TextStyle(color: _grey, fontSize: 12)),
        ])),
        SizedBox(width: 8),
        Chip(
            label: Text(isVerified ? 'Verified' : 'Pending',
                style: TextStyle(fontSize: 10, color: _white)),
            backgroundColor: isVerified ? _green : _grey,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            visualDensity: VisualDensity(horizontal: 0.0, vertical: -4),
            side: BorderSide.none),
      ]),
    );
  }

  Widget _buildVehicleTab() {
    // Same as provided, uses vehicle controllers
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vehicle Information',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
        Text(
            'Details about the ${_transporterProfile?.vehicleType ?? 'vehicle'} you use',
            style: TextStyle(color: _grey, fontSize: 14)),
        SizedBox(height: 20),
        _buildTextField(_vehicleMakeController, 'Make'),
        SizedBox(height: 16),
        _buildTextField(_vehicleModelController, 'Model'),
        SizedBox(height: 16),
        _buildTextField(_vehicleYearController, 'Year',
            keyboardType: TextInputType.number),
        SizedBox(height: 16),
        _buildTextField(_licensePlateController, 'License Plate'),
        SizedBox(height: 16),
        _buildTextField(_vehicleColorController, 'Color'),
        SizedBox(height: 24),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // Save Button
              onPressed: _isSavingProfile
                  ? null
                  : _saveVehicleChanges, // Reuse profile saving flag
              child: _isSavingProfile
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: _white, strokeWidth: 2))
                  : Text('Save Vehicle Info'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryTeal,
                  foregroundColor: _white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
            )),
      ]),
    );
  }

  Future<void> _saveVehicleChanges() async {
    // Same logic as provided, uses updateTransporterProfile
    setState(() => _isSavingProfile = true);
    _showLoadingSnackbar("Saving Vehicle Info...");
    Map<String, dynamic> updateData = {
      // Use keys expected by your API - these might need adjustment
      // Ensure these match the keys used in the TransporterProfile.fromJson/toJson if consistent
      // Using keys common in APIs, adjust if your API uses others.
      'vehicle_make': _vehicleMakeController.text,
      'vehicle_model': _vehicleModelController.text,
      'vehicle_year': _vehicleYearController.text,
      'license_plate': _licensePlateController.text,
      'vehicle_color': _vehicleColorController.text,
      // Include vehicle_type if it's part of the update AND editable
      // 'vehicle_type': _transporterProfile?.vehicleType, // Example: Use existing type or make editable
    };
    updateData.removeWhere((key, value) =>
        value == null ||
        (value is String && value.isEmpty)); // Clean empty fields

    // Optional: Remove unchanged values to minimize payload
    if (_transporterProfile != null) {
      final currentProfileMap = _transporterProfile!.toJson();
      updateData.removeWhere((key, value) => currentProfileMap[key] == value);
    }

    try {
      if (updateData.isNotEmpty) {
        print("Sending vehicle update data: $updateData");
        bool success = await TransporterApiService.updateTransporterProfile(
            widget.transporterId, updateData);
        if (!success)
          throw Exception("Vehicle update API call returned false.");
        await _fetchTransporterProfileAndUpdate(); // Refresh profile
        _dismissLoadingSnackbar();
        _showSuccessSnackBar('Vehicle information updated!');
      } else {
        _dismissLoadingSnackbar();
        _showSnackBar("No vehicle changes detected.", isError: false);
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("Failed to save vehicle changes: $e");
      if (mounted)
        _showErrorSnackBar('Failed to save vehicle info: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Widget _buildPreferencesTab() {
    // Same as provided, uses preference state variables
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Notification Prefs
        _buildPreferenceSectionTitle('Notification Preferences',
            'Customize how you receive notifications'),
        _buildSwitchPreference(
            'New Order Alerts',
            'Notify when new orders are available',
            _notifyNewOrders,
            (v) => setState(() => _notifyNewOrders = v)),
        _buildSwitchPreference(
            'Status Updates',
            'Notify about order status changes',
            _notifyStatusUpdates,
            (v) => setState(() => _notifyStatusUpdates = v)),
        _buildSwitchPreference('Earnings Updates', 'Notify about earnings',
            _notifyEarnings, (v) => setState(() => _notifyEarnings = v)),
        _buildSwitchPreference('Promotions', 'Notify about promotions',
            _notifyPromotions, (v) => setState(() => _notifyPromotions = v)),
        SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
                onPressed: _saveNotificationPreferences,
                child: Text('Save Notification Preferences'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryTeal,
                    foregroundColor: _white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))))),
        SizedBox(height: 30),
        // App Prefs
        _buildPreferenceSectionTitle(
            'App Preferences', 'Customize your app experience'),
        _buildSwitchPreference(
            'Dark Mode',
            'Use dark theme (requires app restart)',
            _useDarkMode,
            (v) => setState(() => _useDarkMode = v)),
        _buildSwitchPreference('Sound Alerts', 'Play sounds for notifications',
            _soundAlerts, (v) => setState(() => _soundAlerts = v)),
        _buildSwitchPreference('Auto-Navigate', 'Automatically open navigation',
            _autoNavigate, (v) => setState(() => _autoNavigate = v)),
        SizedBox(height: 16),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
                onPressed: _saveAppPreferences,
                child: Text('Save App Preferences'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryTeal,
                    foregroundColor: _white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))))),
      ]),
    );
  }

  Widget _buildPreferenceSectionTitle(String title, String subtitle) {
    /* Same */
    return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
          Text(subtitle, style: TextStyle(color: _grey, fontSize: 14)),
        ]));
  }

  Widget _buildSwitchPreference(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    /* Same */
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.w600, color: _darkTeal)),
      subtitle: Text(subtitle, style: TextStyle(color: _grey, fontSize: 13)),
      value: value,
      onChanged: onChanged,
      activeColor: _white,
      activeTrackColor: _primaryTeal,
      inactiveThumbColor: _white,
      inactiveTrackColor: Colors.grey.shade300,
    );
  }

  Future<void> _saveNotificationPreferences() async {
    /* Same - uses SharedPreferences or API */
    _showLoadingSnackbar("Saving Notifications...");
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifyNewOrders', _notifyNewOrders);
      await prefs.setBool('notifyStatusUpdates', _notifyStatusUpdates);
      await prefs.setBool('notifyEarnings', _notifyEarnings);
      await prefs.setBool('notifyPromotions', _notifyPromotions);
      _dismissLoadingSnackbar();
      _showSuccessSnackBar('Notification preferences saved!');
    } catch (e) {
      _dismissLoadingSnackbar();
      _showErrorSnackBar("Failed to save notification prefs: $e");
    }
  }

  Future<void> _saveAppPreferences() async {
    /* Same - uses SharedPreferences */
    _showLoadingSnackbar("Saving App Settings...");
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('useDarkMode', _useDarkMode);
      await prefs.setBool('soundAlerts', _soundAlerts);
      await prefs.setBool('autoNavigate', _autoNavigate);
      _dismissLoadingSnackbar();
      _showSuccessSnackBar('App preferences saved!');
      // Note: Dark mode change might require a theme provider update or restart
    } catch (e) {
      _dismissLoadingSnackbar();
      _showErrorSnackBar("Failed to save app prefs: $e");
    }
  }

  // --- Image Picking ---
  Future<void> _pickProfileImage() async {
    // Same as provided
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
      if (image != null && mounted) {
        setState(() {
          _profileImageFile = File(image.path);
        });
        // Optional: Trigger save immediately
        // _savePersonalChanges();
        _showSnackBar("Image selected. Press 'Save Changes' to apply.",
            isError: false);
      }
    } catch (e) {
      print("Image picking error: $e");
      if (mounted) _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    }
  }
} // End of _TransporterDashNewState

// ================================================
// === HELPER WIDGETS (AppBar Delegate etc.) ======
// ================================================

// Helper for pinned TabBar in NestedScrollView
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  // Same as provided
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: _white, child: _tabBar);
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

// ================================================
// === ORDER DETAILS SCREEN =======================
// ================================================
class OrderDetailsScreen extends StatefulWidget {
  // Same props as provided
  final Order order;
  final String transporterId;
  final Future<void> Function() onStatusUpdate; // Callback

  const OrderDetailsScreen(
      {Key? key,
      required this.order,
      required this.transporterId,
      required this.onStatusUpdate})
      : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  // TODO: Wire this up to the actual orders list from the dashboard state if needed
  List<Order> _allOrders = [];

  bool _navigationTriggered =
      false; // Track if navigation was started for this order
  // State vars same as provided

  // Method to get user-friendly status text
  String _getDetailedStatusText(String apiStatus) {
    String statusLower = apiStatus.toLowerCase().replaceAll('_', ' ').trim();
    if (statusLower == Order.STATUS_PENDING.toLowerCase()) return 'Pending';
    if (statusLower == Order.STATUS_ASSIGNED.toLowerCase()) return 'Assigned';
    if (statusLower == Order.STATUS_ACCEPTED.toLowerCase()) return 'Accepted';
    if (statusLower == Order.STATUS_PICKED_UP.toLowerCase()) return 'Picked Up';
    if (statusLower == Order.STATUS_VERIFICATION_NEEDED.toLowerCase() ||
        statusLower == "verification needed") return 'Verification Needed';
    if (statusLower == Order.STATUS_ON_THE_WAY.toLowerCase() ||
        statusLower == Order.STATUS_DELIVERING.toLowerCase())
      return 'On The Way'; // Kept for completeness, but not in timeline
    if (statusLower == Order.STATUS_DELIVERED.toLowerCase()) return 'Delivered';
    if (statusLower == Order.STATUS_COMPLETED.toLowerCase()) return 'Completed';
    if (statusLower == Order.STATUS_CANCELLED.toLowerCase()) return 'Cancelled';

    return apiStatus.isNotEmpty
        ? apiStatus[0].toUpperCase() + apiStatus.substring(1)
        : 'Unknown';
  }

  late Order _currentOrder;
  final TextEditingController _verificationCodeController =
      TextEditingController();
  bool _isUpdatingStatus =
      false; // Combined flag for status updates/verification
  bool _isVerificationVisible =
      false; // Control visibility of verification card

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    // Show verification immediately if status is 'picked up' and verification is conceptually next,
    // or if status is 'verification needed'.
    // The _isVerificationVisible flag controls the visibility of the code input card.
    // This should be true if the current status implies verification is the active step.
    String normalizedCurrentStatus =
        _currentOrder.orderStatus.toLowerCase().replaceAll('_', ' ').trim();
    _isVerificationVisible = (normalizedCurrentStatus ==
                Order.STATUS_PICKED_UP.toLowerCase() &&
            _nextStepIsVerification()) ||
        normalizedCurrentStatus == Order.STATUS_VERIFICATION_NEEDED.toLowerCase();
  }

  @override
  void didUpdateWidget(OrderDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update local state when the widget is updated with new order data
    if (widget.order.orderId != oldWidget.order.orderId ||
        widget.order.orderStatus != oldWidget.order.orderStatus) {
      setState(() {
        _currentOrder = widget.order;
        String normalizedCurrentStatus =
            _currentOrder.orderStatus.toLowerCase().replaceAll('_', ' ').trim();
        _isVerificationVisible = (normalizedCurrentStatus ==
                    Order.STATUS_PICKED_UP.toLowerCase() &&
                _nextStepIsVerification()) ||
            normalizedCurrentStatus ==
                Order.STATUS_VERIFICATION_NEEDED.toLowerCase();
      });
    }
  }

  @override
  void dispose() {
    _verificationCodeController.dispose();
    super.dispose();
  }

  // --- Snackbar Helpers (Copied for standalone screen use) ---
  void _showSnackBar(String message,
      {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: TextStyle(color: _white), textAlign: TextAlign.center),
      backgroundColor:
          isError ? _errorColor.withOpacity(0.9) : _darkTeal.withOpacity(0.9),
      duration: Duration(seconds: durationSeconds),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      elevation: 4.0,
    ));
  }

  void _showErrorSnackBar(String message) =>
      _showSnackBar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackBar(String message) =>
      _showSnackBar(message, isError: false);
  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 12),
        Text(message, style: const TextStyle(color: Colors.white))
      ]),
      backgroundColor: Colors.black.withOpacity(0.7),
      duration: const Duration(seconds: 60),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
    ));
  }

  void _dismissLoadingSnackbar() {
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
  }
  // --- End Snackbar Helpers ---

  Future<void> _launchGoogleMapsNavigation(LatLng destination) async {
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      _showErrorSnackBar('Could not launch Google Maps');
    }
  }

  // --- Status Logic (Adapting old constants) ---
  String _normalizeStatus(String status) {
    return status.toLowerCase().replaceAll('_', ' ').trim();
  }

  String? _getNextStatus() {
    String currentStatusNormalized =
        _normalizeStatus(_currentOrder.orderStatus);

    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_ASSIGNED) ||
        currentStatusNormalized == _normalizeStatus(Order.STATUS_ACCEPTED)) {
      return Order.STATUS_PICKED_UP;
    }
    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_PICKED_UP)) {
      // If picked up, next is verification needed (conceptually, or actual status update)
      return Order.STATUS_VERIFICATION_NEEDED;
    }
    if (currentStatusNormalized ==
        _normalizeStatus(Order.STATUS_VERIFICATION_NEEDED)) {
      return Order.STATUS_DELIVERED;
    }
    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_DELIVERED)) {
      return Order.STATUS_COMPLETED;
    }
    return null; // No action from completed, cancelled etc.
  }

  // This method determines if verification is the *immediate next conceptual step*
  // given the current state, for UI hints (like button text).
  bool _nextStepIsVerification() {
    // Simplified: If current status is picked up, verification is next.
    // Add more complex logic here if some order types don't need verification.
    return _normalizeStatus(_currentOrder.orderStatus) ==
        _normalizeStatus(Order.STATUS_PICKED_UP);
  }

  String _getCompleteButtonText() {
    String currentStatusNormalized =
        _normalizeStatus(_currentOrder.orderStatus);

    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_ASSIGNED) ||
        currentStatusNormalized == _normalizeStatus(Order.STATUS_ACCEPTED)) {
      return 'Mark as Picked Up';
    }
    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_PICKED_UP)) {
      return 'Proceed to Verification'; // Next step is verification
    }
    if (currentStatusNormalized ==
        _normalizeStatus(Order.STATUS_VERIFICATION_NEEDED)) {
      return 'Mark as Delivered'; // After verification, mark delivered
    }
    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_DELIVERED)) {
      return 'Mark as Completed';
    }
    return 'Update Status'; // Generic fallback
  }

  bool _canCompleteDelivery() {
    // Can take action if there's a next status or if current status is verification needed (implying 'Verify' button)
    return _getNextStatus() != null ||
        _normalizeStatus(_currentOrder.orderStatus) ==
            _normalizeStatus(Order.STATUS_VERIFICATION_NEEDED);
  }

  // --- Actions ---
  Future<void> _handleStatusUpdate() async {
    String currentStatusNormalized =
        _normalizeStatus(_currentOrder.orderStatus);

    if (currentStatusNormalized == _normalizeStatus(Order.STATUS_PICKED_UP)) {
      // If current is Picked Up, the action is to show/focus on verification
      setState(() {
        _isVerificationVisible = true;
      });
      _performStatusUpdate(Order
          .STATUS_VERIFICATION_NEEDED); // Update status to 'verification needed'
      // _showSnackBar("Please enter verification code.", isError: false); // Or rely on verification card becoming visible
      return;
    }

    String? nextStatus = _getNextStatus();
    if (nextStatus == null) {
      print(
          "No further status update available for ${_currentOrder.orderStatus}");
      _showSnackBar(
          "Order is already ${_getDetailedStatusText(_currentOrder.orderStatus)}.",
          isError: false);
      return;
    }
    _performStatusUpdate(nextStatus);
  }

  Future<void> _handleVerifyCode() async {
    String code = _verificationCodeController.text.trim();
    if (code.length != 6) {
      _showErrorSnackBar('Please enter a 6-digit verification code.');
      return;
    }
    FocusScope.of(context).unfocus();

    _showLoadingSnackbar("Verifying Code...");
    setState(() => _isUpdatingStatus = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userType = prefs.getString('user_type')?.toLowerCase() ?? '';
      final userId = prefs.getString('user_id');

      if (userId == null) throw Exception('Transporter ID not found');

      final apiBaseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';

      // API expects 'completed' status when verifying with code
      final response = await http
          .patch(
            Uri.parse('$apiBaseUrl/rr/orders/${_currentOrder.orderId}/status'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transporter_id':
                  userId, // Ensure this is the correct key for your API
              'completion_code': code,
              'order_status': Order
                  .STATUS_COMPLETED // API might expect 'completed' upon successful verification
            }),
          )
          .timeout(Duration(seconds: 15));

      _dismissLoadingSnackbar(); // Dismiss loading after API call

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Assuming success means the status is now 'completed' or 'delivered' via backend logic
        // For UI, we'll transition to 'delivered' if verification was the step, then to 'completed'

        // Fetch the latest order details to get the true new status from backend
        final updatedOrderFromServer =
            await _fetchLatestOrderDetails(_currentOrder.orderId);

        if (mounted) {
          setState(() {
            if (updatedOrderFromServer != null) {
              _currentOrder = updatedOrderFromServer;
            } else {
              // Fallback: if verification was successful, assume next logical step is delivered or completed
              _currentOrder =
                  _currentOrder.copyWith(orderStatus: Order.STATUS_DELIVERED);
            }
            _isVerificationVisible = false; // Hide verification card
          });
          _showSuccessSnackBar(
              'Verification successful! Order delivered/completed.');
          _verificationCodeController.clear();
          await widget.onStatusUpdate(); // Refresh parent
        }
      } else {
        // If verification fails, fetch the latest order status to update UI correctly
        final updatedOrder =
            await _fetchLatestOrderDetails(_currentOrder.orderId);
        if (updatedOrder != null && mounted) {
          setState(() {
            _currentOrder = updatedOrder;
            // Re-evaluate if verification card should be visible based on potentially unchanged status
            String normalizedCurrentStatus = _currentOrder.orderStatus
                .toLowerCase()
                .replaceAll('_', ' ')
                .trim();
            _isVerificationVisible = (normalizedCurrentStatus ==
                        Order.STATUS_PICKED_UP.toLowerCase() &&
                    _nextStepIsVerification()) ||
                normalizedCurrentStatus ==
                    Order.STATUS_VERIFICATION_NEEDED.toLowerCase();
          });
        }

        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ??
              'Verification failed. API Code: ${response.statusCode}');
        } catch (_) {
          throw Exception(
              'API Error: ${response.statusCode}. ${response.body}');
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("Verification failed: $e");
      if (mounted) {
        _showErrorSnackBar(
            'Verification failed: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  // Fetches the latest order details from the server
  Future<Order?> _fetchLatestOrderDetails(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiBaseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';

      print('Fetching latest order details for order $orderId...');
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/rr/orders?order_id=$orderId'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json', // Added Accept header
              'Cache-Control':
                  'no-cache, no-store, must-revalidate', // Aggressive caching prevention
              'Pragma': 'no-cache',
              'Expires': '0',
            },
          )
          .timeout(Duration(seconds: 10));

      print('Order details response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Adjust based on your API response structure for a single order
        // Assuming the order data is directly in the response or under a 'data' key
        Map<String, dynamic>? orderData;
        if (data is Map<String, dynamic> &&
            data.containsKey('data') &&
            data['data'] is Map<String, dynamic>) {
          orderData = data['data'] as Map<String, dynamic>;
        } else if (data is Map<String, dynamic> &&
            data.containsKey('order_id')) {
          // If the root is the order object
          orderData = data;
        }

        if (orderData != null) {
          final updatedOrder = Order.fromJson(orderData);
          print('Fetched updated order status: ${updatedOrder.orderStatus}');
          return updatedOrder;
        } else {
          print('Invalid response format for single order: ${response.body}');
        }
      } else {
        print(
            'Failed to fetch order details: ${response.statusCode} ${response.body}');
      }
      return null;
    } catch (e) {
      print('Error fetching order details: $e');
      return null;
    }
  }

  // Helper to check if status is completed or delivered
  bool _isCompletedOrDelivered(String status) {
    if (status.isEmpty) return false;
    final normalizedStatus = _normalizeStatus(status);
    final normalizedCompleted = _normalizeStatus(Order.STATUS_COMPLETED);
    final normalizedDelivered = _normalizeStatus(Order.STATUS_DELIVERED);

    return normalizedStatus == normalizedCompleted ||
        normalizedStatus == normalizedDelivered;
  }

  // Method to trigger earnings refresh with a delay to account for backend processing
  void _triggerEarningsRefresh() async {
    try {
      // Add a delay to allow backend to process the order status update
      // This helps ensure the payment data is ready when we fetch it
      const delayDuration = Duration(seconds: 10);
      print(
          'Waiting $delayDuration before refreshing earnings to allow backend processing...');
      await Future.delayed(delayDuration);

      if (!mounted) return;

      // Show a loading indicator that we're about to refresh
      _showLoadingSnackbar('Updating earnings data...');

      // First try to use the callback from the parent
      if (widget.onStatusUpdate != null) {
        await widget.onStatusUpdate();
      }

      // Also try to find parent state as a fallback
      final parentState =
          context.findAncestorStateOfType<_TransporterDashNewState>();
      if (parentState != null && parentState.mounted) {
        await parentState.refreshPayments();
        if (mounted) {
          _dismissLoadingSnackbar();
          _showSnackBar('Earnings updated', isError: false);
        }
        print('Earnings refresh completed after order status change');
      } else {
        _dismissLoadingSnackbar();
        print('Parent state not found or not mounted, using callback only');
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print('Error triggering earnings refresh: $e');
      if (mounted) {
        _showErrorSnackBar(
            'Earnings will update shortly. Pull down to refresh if needed.');
      }
    }
  }

  // Helper to perform the actual API call and state update
  Future<void> _performStatusUpdate(String newStatus,
      {bool isVerification = false}) async {
    if (!isVerification) {
      // Show loading snackbar only for non-verification updates
      _showLoadingSnackbar(
          "Updating status to ${_getDetailedStatusText(newStatus)}...");
    }

    // Store the previous status before updating
    final previousStatus = _currentOrder.orderStatus;
    setState(() => _isUpdatingStatus = true);

    try {
      bool success = await TransporterApiService.updateOrderStatusByTransporter(
          _currentOrder.orderId, newStatus);
      _dismissLoadingSnackbar();

      if (success && mounted) {
        // First, fetch the latest order details from the server
        final updatedOrder =
            await _fetchLatestOrderDetails(_currentOrder.orderId);

        // Show success message
        _showSuccessSnackBar(isVerification
            ? 'Delivery verified and completed!'
            : 'Order status updated to ${_getDetailedStatusText(newStatus)}!');

        // Check if this was a transition to completed/delivered
        final wasJustCompletedOrDelivered =
            !_isCompletedOrDelivered(previousStatus) &&
                _isCompletedOrDelivered(newStatus);

        // Update local state with the latest order data
        setState(() {
          if (updatedOrder != null) {
            // Use the fully updated order from the server
            _currentOrder = updatedOrder;
          } else {
            // Fallback to local update if fetch fails
            _currentOrder = _currentOrder.copyWith(orderStatus: newStatus);
          }
          // Re-evaluate verification card visibility based on the new status
          String normalizedCurrentStatus = _currentOrder.orderStatus
              .toLowerCase()
              .replaceAll('_', ' ')
              .trim();
          _isVerificationVisible = (normalizedCurrentStatus ==
                      Order.STATUS_PICKED_UP.toLowerCase() &&
                  _nextStepIsVerification()) ||
              normalizedCurrentStatus ==
                  Order.STATUS_VERIFICATION_NEEDED.toLowerCase();
        });

        // Refresh the order list in the parent widget
        await widget.onStatusUpdate();

        // If this was a transition to completed/delivered, trigger earnings refresh
        if (wasJustCompletedOrDelivered && mounted) {
          _triggerEarningsRefresh();
        }
      } else if (mounted) {
        throw Exception(
            "Update status API failed silently or component unmounted.");
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      print("Failed to update order status to $newStatus: $e");
      if (mounted)
        _showErrorSnackBar('Failed to update status: ${e.toString()}');
    } finally {
      // Ensure flag is always reset
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    String status = _currentOrder.orderStatus;
    String statusNormalized = _normalizeStatus(status);
    Color statusColor;
    String statusTextDisplay = _getDetailedStatusText(status); // User-friendly

    if (statusNormalized == _normalizeStatus(Order.STATUS_DELIVERED) ||
        statusNormalized == _normalizeStatus(Order.STATUS_COMPLETED)) {
      statusColor = _green;
    } else if (statusNormalized == _normalizeStatus(Order.STATUS_CANCELLED)) {
      statusColor = _red;
    } else if (statusNormalized ==
        _normalizeStatus(Order.STATUS_VERIFICATION_NEEDED)) {
      statusColor =
          Colors.orange.shade700; // Distinct color for verification needed
    } else {
      statusColor = _primaryTeal;
    }

    return Scaffold(
      backgroundColor: _white,
      appBar: AppBar(
        /* ... Same AppBar as provided ... */
        backgroundColor: _white,
        foregroundColor: _darkTeal,
        elevation: 1,
        title:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Order #${_currentOrder.orderId}',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _darkTeal)),
          Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(statusTextDisplay,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12))),
        ]),
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: _darkTeal),
            onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        // Use ListView for scrollable content
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildMapPlaceholder(), SizedBox(height: 16),
          _buildOrderDetailsCard(), SizedBox(height: 16),
          _buildStatusTimelineCard(),
          SizedBox(height: 16),

          // Duplicate Directions to Delivery button - shown only for 'picked up' orders
          if (statusNormalized == _normalizeStatus(Order.STATUS_PICKED_UP)) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(Icons.directions, size: 18),
                label: Text('Directions to Delivery Location'),
                onPressed: () {
                  final LatLng? destination =
                      _parseLocationToLatLng(_currentOrder.deliveryAddress);
                  if (destination != null) {
                    print(
                        "Attempting to navigate to: Lat=${destination.latitude}, Lng=${destination.longitude}");
                    setState(() {
                      _navigationTriggered = true;
                    });
                    _launchGoogleMapsNavigation(destination);
                  } else {
                    _showErrorSnackBar(
                        'Navigation failed: Could not extract coordinates from the delivery address.');
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryTeal,
                  side: BorderSide(color: _lightTeal),
                ),
              ),
            ),
            SizedBox(height: 16),
          ],

          // Show verification card conditionally
          if (_isVerificationVisible &&
              statusNormalized != _normalizeStatus(Order.STATUS_DELIVERED) &&
              statusNormalized != _normalizeStatus(Order.STATUS_COMPLETED)) ...[
            _buildDeliveryVerificationCard(),
            SizedBox(height: 16),
          ],
          // Show main action button if applicable
          if (_navigationTriggered &&
              statusNormalized != _normalizeStatus(Order.STATUS_DELIVERED) &&
              statusNormalized != _normalizeStatus(Order.STATUS_COMPLETED) &&
              statusNormalized != _normalizeStatus(Order.STATUS_CANCELLED)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUpdatingStatus
                      ? null
                      : () async {
                          setState(() => _isUpdatingStatus = true);
                          try {
                            // Prepare ID logic (copied from verification helper)
                            final prefs = await SharedPreferences.getInstance();
                            final userType = prefs.getString('user_type');
                            final userId = prefs.getString('user_id');
                            final chefId = prefs.getString('chef_user_id');
                            String? idToSend;
                            String idKey;
                            if (userType != null &&
                                userType.toLowerCase() == 'transporter') {
                              idToSend = userId;
                              idKey = 'transporter_id';
                            } else {
                              idToSend = chefId;
                              idKey = 'chef_id';
                            }
                            if (idToSend == null)
                              throw Exception(
                                  'User ID not found. Please log in again.');
                            final apiBaseUrl =
                                dotenv.env['API_BASE_URL-intranet'] ??
                                    'https://api.example.com';
                            final uri = Uri.parse(
                                '${apiBaseUrl}/rr/orders/${_currentOrder.orderId}/status');
                            final response = await http
                                .patch(
                                  uri,
                                  headers: {
                                    'Content-Type': 'application/json',
                                    'Accept': 'application/json',
                                  },
                                  body: jsonEncode({
                                    idKey: idToSend,
                                    'order_status':
                                        'completed', // Or 'verification_needed_arrived'
                                  }),
                                )
                                .timeout(const Duration(seconds: 15));
                            if (response.statusCode == 200) {
                              // Now show verification dialog
                              final verified = await ChefVerificationHelper
                                  .showVerificationDialog(
                                      context, _currentOrder);
                              if (verified) {
                                // After verification, update status to completed
                                await _performStatusUpdate(
                                    Order.STATUS_COMPLETED,
                                    isVerification: true);
                              } else {
                                _showErrorSnackBar(
                                    'Verification failed or cancelled.');
                              }
                            } else {
                              final detail = jsonDecode(response.body);
                              _showErrorSnackBar(
                                  'Failed to trigger code: ${detail['message'] ?? detail['detail'] ?? response.statusCode}');
                            }
                          } catch (e) {
                            _showErrorSnackBar('Failed to trigger code: $e');
                          } finally {
                            setState(() => _isUpdatingStatus = false);
                          }
                        },
                  child: Text('I have arrived'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: _white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.phone, color: _primaryTeal),
                  label: Text('Contact Customer'),
                  onPressed: () async {
                    final customerPhone =
                        _currentOrder.userPhone ?? "(256) 7YY-YYY-YYY";
                    if (customerPhone.isNotEmpty && customerPhone != "null") {
                      final Uri telUri =
                          Uri(scheme: 'tel', path: customerPhone);
                      if (await canLaunchUrl(telUri)) {
                        await launchUrl(telUri);
                      } else {
                        _showErrorSnackBar('Could not launch phone dialer');
                      }
                    } else {
                      _showErrorSnackBar('Customer phone number not available');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryTeal,
                    side: BorderSide(color: _lightTeal),
                  ),
                ),
              ),
            ),
          ],
          if (_canCompleteDelivery() &&
              statusNormalized != _normalizeStatus(Order.STATUS_DELIVERED) &&
              statusNormalized != _normalizeStatus(Order.STATUS_COMPLETED) &&
              statusNormalized != _normalizeStatus(Order.STATUS_CANCELLED))
            Padding(
              padding: const EdgeInsets.only(
                  top: 8.0), // Add some space above button
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUpdatingStatus
                      ? null
                      : (statusNormalized ==
                                  _normalizeStatus(
                                      Order.STATUS_VERIFICATION_NEEDED) ||
                              (_isVerificationVisible &&
                                  statusNormalized ==
                                      _normalizeStatus(Order.STATUS_PICKED_UP))
                          ? _handleVerifyCode // If verification card is visible and status is picked_up OR status is verification_needed
                          : _handleStatusUpdate),
                  child: _isUpdatingStatus
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _white))
                      : Text(_getCompleteButtonText()),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryTeal,
                      foregroundColor: _white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapPlaceholder() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: GestureDetector(
          onTap: () {
            // Replicate the navigation logic from the Navigate button
            final LatLng? destination =
                _parseLocationToLatLng(_currentOrder.deliveryAddress);
            if (destination != null) {
              setState(() {
                _navigationTriggered = true;
              });
              _launchGoogleMapsNavigation(destination);
            } else {
              _showErrorSnackBar(
                  'Navigation failed: Could not extract coordinates from the delivery address.');
            }
          },
          child: Image.asset(
            'assets/images/go.png',
            fit: BoxFit.contain,
            height: 120, // adjust as needed
          ),
        ),
      ),
    );
  }

  Widget _buildOrderDetailsCard() {
    // Get restaurant phone number or show placeholder if not available
    final restaurantPhone = _currentOrder.restaurantPhone;
    final hasValidRestaurantPhone =
        restaurantPhone != null && restaurantPhone.isNotEmpty && restaurantPhone != 'null';
    final displayRestaurantPhone = hasValidRestaurantPhone
        ? restaurantPhone
        : 'Phone number not available';

    // Get customer phone number or show 'Not available' if not found
    final customerPhone = _currentOrder.userPhone;
    final hasValidCustomerPhone =
        customerPhone != null && customerPhone.isNotEmpty && customerPhone != 'null';
    final displayCustomerPhone =
        hasValidCustomerPhone ? customerPhone : 'Phone number not available';
    return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order Details',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _darkTeal)),
                  SizedBox(height: 16),
                  _buildDetailRow(
                      Icons.storefront,
                      _currentOrder.chefName ??
                          _currentOrder.producerName ??
                          'Pickup Location',
                      isTitle: true),
                  _buildDetailRow(null, _currentOrder.pickupAddress,
                      isAddress: true),
                  hasValidRestaurantPhone
                      ? _buildDetailRow(
                          Icons.phone_outlined,
                          restaurantPhone,
                          isPhone: true,
                        )
                      : _buildDetailRow(
                          Icons.phone_disabled_outlined,
                          displayRestaurantPhone,
                        ),
                  Divider(height: 24, color: _lightTeal),
                  _buildDetailRow(Icons.person_outline, 'Customer',
                      isTitle: true), // Added Customer Title
                  _buildDetailRow(Icons.location_on_outlined, 'Delivery Address',
                      isTitle: false), // Changed to non-title
                  _buildDetailRow(null, _currentOrder.simplifiedDeliveryAddress,
                      isAddress: true),
                  hasValidCustomerPhone
                      ? _buildDetailRow(
                          Icons.phone_outlined,
                          customerPhone!, // Known to be non-null here
                          isPhone: true,
                        )
                      : _buildDetailRow(
                          Icons.phone_disabled_outlined,
                          displayCustomerPhone,
                        ),
                  Divider(height: 24, color: _lightTeal),
                  Text('Order Items:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: _darkTeal)),
                  SizedBox(height: 8),
                  ..._currentOrder.orderItems
                      .map((item) => Padding(
                          padding:
                              const EdgeInsets.only(left: 8.0, bottom: 4.0),
                          child: Text('• $item',
                              style: TextStyle(color: _darkTeal))))
                      .toList(),
                  if (_currentOrder.notes != null &&
                      _currentOrder.notes!.isNotEmpty &&
                      _currentOrder.notes!.toLowerCase() !=
                          'no special instructions') ...[
                    SizedBox(height: 16),
                    _buildDetailRow(Icons.notes_outlined, 'Notes:',
                        isTitle: true),
                    _buildDetailRow(null, _currentOrder.notes!,
                        isAddress: true), // Display notes
                  ],
                  SizedBox(height: 16),
                  _buildOrderInfoRow(_currentOrder), // Reuses helper

                  // *** START: Navigation Button Added with new parsing logic ***
                  if (!['completed', 'delivered', 'cancelled', 'rejected']
                      .contains(_currentOrder.orderStatus.toLowerCase())) ...[
                    SizedBox(height: 16), // Space before button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.directions, size: 18),
                        label: Text('Directions to Delivery Location'),
                        onPressed: () {
                          // Use the robust parsing function
                          final LatLng? destination = _parseLocationToLatLng(
                              _currentOrder.deliveryAddress);

                          if (destination != null) {
                            print(
                                "Attempting to navigate to: Lat=${destination.latitude}, Lng=${destination.longitude}");
                            setState(() {
                              _navigationTriggered = true;
                            });
                            _launchGoogleMapsNavigation(destination);
                          } else {
                            _showErrorSnackBar(
                                'Navigation failed: Could not extract coordinates from the delivery address.');
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryTeal,
                          side: BorderSide(color: _lightTeal),
                        ),
                      ),
                    ),
                  ],
                  // *** END: Navigation Button ***
                ])));
  }

  Widget _buildDetailRow(IconData? icon, String text,
      {bool isTitle = false, bool isAddress = false, bool isPhone = false}) {
    return Padding(
        padding: EdgeInsets.only(
            bottom: isAddress ? 8 : 4.0,
            left: isTitle ? 0 : (icon != null ? 0 : 28)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: _primaryTeal),
            SizedBox(width: 12)
          ],
          Expanded(
            child: isPhone
                ? GestureDetector(
                    onTap: () async {
                      final Uri telUri = Uri(scheme: 'tel', path: text);
                      if (await canLaunchUrl(telUri)) {
                        await launchUrl(telUri);
                      } else {
                        _showErrorSnackBar('Could not launch phone dialer');
                      }
                    },
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: isTitle ? 15 : 14,
                        fontWeight:
                            isTitle ? FontWeight.w600 : FontWeight.normal,
                        color: _primaryTeal, // Make phone numbers stand out
                        decoration: TextDecoration.underline,
                        height: 1.3,
                      ),
                    ),
                  )
                : Text(
                    text,
                    style: TextStyle(
                      fontSize: isTitle ? 15 : 14,
                      fontWeight:
                          isTitle ? FontWeight.w600 : FontWeight.normal,
                      color: isTitle
                          ? _darkTeal
                          : (isAddress ? _darkTeal : _grey),
                      height: 1.3,
                    ),
                  ),
          )
        ]));
  }

  Widget _buildOrderInfoRow(Order order) {
    /* ... Same as provided ... */
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _buildInfoChip('Dist: ${order.estimatedDistance}'),
      _buildInfoChip('Time: ${order.estimatedTime}'),
      _buildInfoChip(
          'Earn: ugx ${order.earnings.toStringAsFixed(0)}', // Format UGX
          color: _green,
          fontWeight: FontWeight.bold)
    ]);
  }

  Widget _buildInfoChip(String text,
      {Color color = _grey, FontWeight fontWeight = FontWeight.normal}) {
    /* ... Same as provided ... */
    return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: _lightGrey,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 0.5)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: fontWeight)));
  }

  // MODIFIED Status Timeline Card
  Widget _buildStatusTimelineCard() {
    const String verificationNeededStatusNormalized = "verification needed";

    String currentNormalizedStatus =
        _normalizeStatus(_currentOrder.orderStatus);

    // Determine if each step in the timeline is met or passed
    bool isAcceptedMet = [
      _normalizeStatus(Order.STATUS_ACCEPTED),
      _normalizeStatus(Order.STATUS_ASSIGNED),
      _normalizeStatus(Order.STATUS_PICKED_UP),
      verificationNeededStatusNormalized,
      _normalizeStatus(Order.STATUS_DELIVERED),
      _normalizeStatus(Order.STATUS_COMPLETED)
    ].contains(currentNormalizedStatus);

    bool isPickedUpMet = [
      _normalizeStatus(Order.STATUS_PICKED_UP),
      verificationNeededStatusNormalized,
      _normalizeStatus(Order.STATUS_DELIVERED),
      _normalizeStatus(Order.STATUS_COMPLETED)
    ].contains(currentNormalizedStatus);

    bool isVerificationStepMet = [
      verificationNeededStatusNormalized,
      _normalizeStatus(Order.STATUS_DELIVERED),
      _normalizeStatus(Order.STATUS_COMPLETED)
    ].contains(currentNormalizedStatus);

    bool isDeliveredMet = [
      _normalizeStatus(Order.STATUS_DELIVERED),
      _normalizeStatus(Order.STATUS_COMPLETED)
    ].contains(currentNormalizedStatus);

    // Subtitles for each step
    String acceptedSubtitle =
        isAcceptedMet ? "You accepted this order" : "Pending acceptance";
    String pickedUpSubtitle =
        isPickedUpMet ? "You picked up the order" : "Pending pickup";

    String verificationSubtitle;
    if (isVerificationStepMet) {
      verificationSubtitle = "Verification successful";
    } else if (currentNormalizedStatus ==
        _normalizeStatus(Order.STATUS_PICKED_UP)) {
      verificationSubtitle = "Awaiting verification code";
    } else {
      verificationSubtitle = "Pending verification";
    }

    String deliveredSubtitle;
    if (isDeliveredMet) {
      deliveredSubtitle = "Order successfully delivered";
    } else if (currentNormalizedStatus == verificationNeededStatusNormalized) {
      deliveredSubtitle = "Ready for delivery"; // After verification
    } else {
      deliveredSubtitle = "Pending delivery completion";
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status Timeline',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkTeal)),
            SizedBox(height: 16),
            _buildStatusItem(
              'Order Accepted/Assigned',
              acceptedSubtitle,
              isAcceptedMet,
            ),
            _buildStatusItem(
              'Order Picked Up',
              pickedUpSubtitle,
              isPickedUpMet,
            ),
            _buildStatusItem(
              'Verification Needed',
              verificationSubtitle,
              isVerificationStepMet,
              // 'needsVerification' (orange clock icon) is shown if this step is PENDING
              // AND current status is 'picked_up' (meaning verification is the next logical action).
              needsVerification: currentNormalizedStatus ==
                      _normalizeStatus(Order.STATUS_PICKED_UP) &&
                  !isVerificationStepMet,
            ),
            _buildStatusItem(
              'Delivered',
              deliveredSubtitle,
              isDeliveredMet,
              isLast: true,
              // 'needsVerification' (orange clock icon) for Delivered step is if current status IS 'verification_needed'
              // (meaning delivery is the next logical action after code verification).
              needsVerification:
                  currentNormalizedStatus == verificationNeededStatusNormalized &&
                      !isDeliveredMet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, String subtitle, bool isCompleted,
      {bool isLast = false, bool needsVerification = false}) {
    // Same as provided, but logic for icon/color is self-contained here.
    IconData iconData;
    Color iconColor;

    if (isCompleted) {
      iconData = Icons.check_circle;
      iconColor = _green;
    } else if (needsVerification) {
      // This step is pending AND needs verification action
      iconData = Icons.access_time;
      iconColor = Colors.orange.shade700;
    } else {
      // This step is pending and does not currently require verification action
      iconData = Icons.radio_button_unchecked;
      iconColor = _grey;
    }

    Color textColor = isCompleted ? _darkTeal : _grey;
    Color subtitleColor = isCompleted
        ? _grey
        : (needsVerification ? Colors.orange.shade700 : _grey);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Icon(iconData, color: iconColor, size: 24),
        if (!isLast)
          Container(
              width: 1,
              height: 30,
              color: isCompleted
                  ? _green
                  : Colors.grey.shade300, // Line color reflects completion of current step
              margin: EdgeInsets.symmetric(vertical: 4))
      ]),
      SizedBox(width: 12),
      Expanded(
          child: Padding(
              padding: const EdgeInsets.only(top: 2.0, bottom: 16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor)),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: subtitleColor))
                  ]))),
    ]);
  }

  // Builds the verification input card
  Widget _buildDeliveryVerificationCard() {
    // Same as provided
    return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery Verification',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _darkTeal)),
                  SizedBox(height: 8),
                  Text(
                      'After delivering the order, Ask the customer for their 6-digit verification code.',
                      style: TextStyle(color: _grey, fontSize: 14)),
                  SizedBox(height: 16),
                  TextField(
                    // Verification Code Input
                    controller: _verificationCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: _darkTeal), // Increase size/spacing
                    decoration: InputDecoration(
                        hintText: '______',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 24,
                            letterSpacing: 8),
                        counterText: "",
                        filled: true,
                        fillColor: _lightGrey,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: BorderSide(color: _primaryTeal)),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 14)),
                  ),
                  SizedBox(height: 8),
                  Text('Customer received code via SMS/Email.',
                      style: TextStyle(color: _grey, fontSize: 11)),
                  // Verify button moved outside this card
                ])));
  }
} // End OrderDetailsScreen

// ================================================
// === EARNINGS HISTORY SCREEN ====================
// ================================================
class EarningsHistoryScreen extends StatelessWidget {
  // Same as provided
  final List<Payment> payments;
  const EarningsHistoryScreen({Key? key, required this.payments})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    Map<DateTime, List<Payment>> groupedPayments = {};
    for (var payment in payments) {
      DateTime dateKey = DateTime(payment.createdAt.year,
          payment.createdAt.month, payment.createdAt.day);
      groupedPayments.putIfAbsent(dateKey, () => []).add(payment);
    }
    List<DateTime> sortedDates = groupedPayments.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Sort newest date first

    return Scaffold(
      backgroundColor: _white,
      appBar: AppBar(
        /* ... Same AppBar ... */
        title: Text('Earnings History',
            style: TextStyle(color: _darkTeal, fontWeight: FontWeight.bold)),
        backgroundColor: _white,
        foregroundColor: _darkTeal,
        elevation: 1,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: _darkTeal),
            onPressed: () => Navigator.of(context).pop()),
      ),
      body: payments.isEmpty
          ? Center(
              child: Text('No payment history found.',
                  style: TextStyle(color: _grey)))
          : ListView.builder(
              itemCount: sortedDates.length,
              padding: EdgeInsets.all(16),
              itemBuilder: (context, index) {
                DateTime date = sortedDates[index];
                List<Payment> dailyPayments = groupedPayments[date]!;
                // Calculate daily total for successful payments using the computed property
                double dailyTotal = dailyPayments
                    .where(
                        (p) => p.disbursementTransactionStatus == 'Successful')
                    .fold(0.0, (sum, p) => sum + p.amount);
                String formattedDate =
                    DateFormat('EEEE, MMM d, yyyy').format(date);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(formattedDate,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: _darkTeal)),
                                      Text(
                                          'ugx ${dailyTotal.toStringAsFixed(0)}',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: _green)),
                                    ]),
                                Divider(height: 20, color: _lightTeal),
                                ...dailyPayments
                                    .map((payment) =>
                                        _buildPaymentItem(payment))
                                    .toList(),
                              ]))),
                );
              }),
    );
  }

  Widget _buildPaymentItem(Payment payment) {
    Color statusColor;
    IconData statusIcon;
    String statusText = payment.disbursementTransactionStatus;

    // Handle null or empty status
    if (statusText.isEmpty) {
      statusText = 'Pending';
    }

    // Determine status color and icon
    switch (statusText.toLowerCase()) {
      case 'successful':
      case 'completed':
        statusColor = _green;
        statusIcon = Icons.check_circle;
        statusText = 'Successful';
        break;
      case 'pending':
        statusColor = _grey;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending';
        break;
      case 'in progress':
      case 'processing':
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusText = 'In Progress';
        break;
      case 'failed':
      case 'rejected':
      case 'declined':
        statusColor = _red;
        statusIcon = Icons.error;
        statusText = 'Failed';
        break;
      default:
        statusColor = _grey;
        statusIcon = Icons.help_outline;
        statusText =
            statusText[0].toUpperCase() + statusText.substring(1).toLowerCase();
    }
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(children: [
          Icon(Icons.receipt_long_outlined, color: _primaryTeal, size: 20),
          SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Order #${payment.orderId}',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'Status: ${payment.disbursementTransactionStatus}',
                  style: TextStyle(color: _grey, fontSize: 12),
                ),
              ])),
          SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('ugx ${payment.amount.toStringAsFixed(0)}', // Format UGX
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: _darkTeal)),
            Row(children: [
              Icon(statusIcon, size: 12, color: statusColor),
              SizedBox(width: 4),
              Text(statusText, // Use normalized status text
                  style: TextStyle(color: statusColor, fontSize: 11)),
            ]),
          ]),
        ]));
  }
}