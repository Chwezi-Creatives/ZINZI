//cspell:disable

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

// Payment model is used in this file
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // No longer needed after form removal
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:geolocator/geolocator.dart'; // Moved to producer_profile.dart
import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart'; // Moved to producer_profile.dart
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
// import 'package:zinzi/cache_config.dart'; // Moved to producer_profile.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/app_drawer_unified.dart' as drawer;
import 'package:zinzi/notifications_UIs/notification_provider.dart';
import 'package:zinzi/user_cache.dart'; 
import 'package:zinzi/utils/route_observer.dart';
import 'package:zinzi/utils/location_utils.dart';
import 'package:flutter/foundation.dart';

// --- UI Constants ---
const Color primaryTeal = Color(0xFF00796B); 
const Color lightTeal = Color(0xFFB2DFDB); 
const Color faintLightTeal = Color(0xFFE0F2F1);
const Color darkTeal = Color(0xFF004D40); 
const Color whiteColor = Colors.white;
const Color textOnTeal = Colors.white;
const Color textOnWhite = Color(0xFF212121);
const Color subtleText = Color(0xFF757575);
const Color cardBackground = Color(0xFFF1F8F8); 
const Color errorColor = Color(0xFFD32F2F);
const Color starColor = Color(0xFFFFC107); 
const Color dividerColor = Color(0xFFE0E0E0);
const Color textFieldFillColor = Color(0xFFF5F5F5);

// Status Colors (Centralized Definition)
final Color pendingColor = Colors.orange.shade600;
final Color acceptedColor = Colors.blue.shade600;
final Color preparingColor = Colors.deepPurple.shade400;
final Color readyForPickupColor = Colors.blueAccent;
final Color assignedColor = Colors.blueGrey.shade600;
final Color dispatchedColor = primaryTeal;
final Color outForDeliveryColor = Colors.purple.shade500;
final Color deliveredColor = Colors.green.shade600;
final Color completedColor = Colors.green.shade700;
final Color cancelledColor = Colors.red.shade600;
final Color defaultStatusColor = Colors.grey.shade600;

const Color actionButtonBackground = Color(0xFFE0F2F1); 
const Color actionButtonForeground = darkTeal;
const Color destructiveButtonBackground = Color(0xFFFFEBEE); 
const Color destructiveButtonForeground = Color(0xFFC62828); 
// placeholderImagePath moved to producer_profile.dart

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

// --- NEW: Model for Bulk Order Details ---
class BulkOrderDetails {
  final DateTime? planStartDate;
  final DateTime? planEndDate;
  final String planFrequency;
  final List<DateTime> planSelectedDays;

  BulkOrderDetails({
    this.planStartDate,
    this.planEndDate,
    required this.planFrequency,
    required this.planSelectedDays,
  });

  factory BulkOrderDetails.fromJson(Map<String, dynamic> json) {
    DateTime? _parseDate(String? dateString) {
      if (dateString == null) return null;
      return DateTime.tryParse(dateString);
    }

    List<DateTime> selectedDays = [];
    if (json['plan_selected_days'] is List) {
      for (var dayString in json['plan_selected_days']) {
        if (dayString != null) {
          final parsedDay = _parseDate(dayString.toString());
          if (parsedDay != null) {
            selectedDays.add(parsedDay);
          }
        }
      }
    }
    selectedDays.sort((a, b) => a.compareTo(b));

    return BulkOrderDetails(
      planStartDate: _parseDate(json['plan_start_date'] as String?),
      planEndDate: _parseDate(json['plan_end_date'] as String?),
      planFrequency: json['plan_frequency']?.toString() ?? 'N/A',
      planSelectedDays: selectedDays,
    );
  }
}


// Order Model (Unified)
class Order {
  final int orderId;
  final String mealName; 
  final DateTime orderDate;
  final double totalPrice; 
  final int quantity;
  String orderStatus; 
  final String? customerName; 
  final String? deliveryAddress;
  final String? notes;
  final String? ingredients; 
  final String? paymentStatus;
  int? assignedRiderId;
  String? assignedRiderName;
  final List<Map<String, dynamic>>? complementaryMeals;
  // --- NEW FIELDS for Bulk Orders ---
  final bool isBulkOrder;
  final BulkOrderDetails? bulkOrderDetails;

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
    this.complementaryMeals,
    // --- NEW: Add to constructor with a default value ---
    this.isBulkOrder = false,
    this.bulkOrderDetails,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    // Remove unused orderStatus variable since we're using it directly in the Order constructor
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['order_date'] as String);
    } catch (e) {
      try {
        final apiDateFormat = DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');
        parsedDate = apiDateFormat.parseUtc(json['order_date'] as String).toLocal();
      } catch (e2) {
        debugPrint("[ProducerDash] Error parsing date: ${json['order_date']} - $e - $e2. Using current time.");
        parsedDate = DateTime.now(); 
      }
    }
    
    List<Map<String, dynamic>>? parseComplementaryMeals(dynamic value) {
      if (value == null || value is! List) return null;
      try {
        return List<Map<String, dynamic>>.from(value);
      } catch (e) {
        debugPrint('Error parsing complementary meals: $e');
        return null;
      }
    }
    
    // --- NEW: Helper function to parse bulk order details safely ---
    BulkOrderDetails? _parseBulkOrderDetails(dynamic value) {
      if (value is String && value.isNotEmpty) {
        try {
          final decodedJson = jsonDecode(value) as Map<String, dynamic>;
          return BulkOrderDetails.fromJson(decodedJson);
        } catch (e) {
          debugPrint('[ProducerDash] Error parsing bulk_order_details JSON string: $e');
          return null;
        }
      }
      return null;
    }

    try {
      final order = Order(
        orderId: _parseInt(json['order_id']),
        mealName: _getStringSafe(json['product_name']) ?? 'Unknown Product',
        orderDate: parsedDate,
        totalPrice: _parseDouble(json['total_price']),
        quantity: _parseInt(json['quantity']),
        orderStatus: _getStringSafe(json['order_status']) ?? Order.STATUS_PENDING,
        paymentStatus: _getStringSafe(json['payment_status']),
        notes: _getStringSafe(json['notes']),
        deliveryAddress: _getStringSafe(json['delivery_address']),
        customerName: _getStringSafe(json['customer_name']) ?? _getStringSafe(json['producer_name']),
        ingredients: _getStringSafe(json['ingredients']),
        assignedRiderId: _parseIntNullable(json['assigned_rider_id'] ?? json['transporter_id']), 
        assignedRiderName: _getStringSafe(json['assigned_rider_name']),
        complementaryMeals: parseComplementaryMeals(json['complementary_meals']),
        // --- NEW: Assign parsed bulk order fields ---
        isBulkOrder: _parseBoolSafe(json['is_bulk_order']),
        bulkOrderDetails: _parseBulkOrderDetails(json['bulk_order_details']),
      );
      return order;
    } catch (e, stack) {
      debugPrint('[ProducerDash] Order parsing error: $e\n$stack');
      rethrow;
    }
  }

  Order copyWith({
    int? orderId, String? mealName, DateTime? orderDate, double? totalPrice, int? quantity,
    String? orderStatus, String? customerName, String? deliveryAddress, String? notes,
    String? ingredients, String? paymentStatus, ValueGetter<int?>? assignedRiderId,
    ValueGetter<String?>? assignedRiderName, List<Map<String, dynamic>>? complementaryMeals,
    bool? isBulkOrder, ValueGetter<BulkOrderDetails?>? bulkOrderDetails,
  }) {
    return Order(
      orderId: orderId ?? this.orderId, mealName: mealName ?? this.mealName,
      orderDate: orderDate ?? this.orderDate, totalPrice: totalPrice ?? this.totalPrice,
      quantity: quantity ?? this.quantity, orderStatus: orderStatus ?? this.orderStatus,
      customerName: customerName ?? this.customerName, deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      notes: notes ?? this.notes, ingredients: ingredients ?? this.ingredients,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      assignedRiderId: assignedRiderId != null ? assignedRiderId() : this.assignedRiderId,
      assignedRiderName: assignedRiderName != null ? assignedRiderName() : this.assignedRiderName,
      complementaryMeals: complementaryMeals ?? this.complementaryMeals,
      isBulkOrder: isBulkOrder ?? this.isBulkOrder,
      bulkOrderDetails: bulkOrderDetails != null ? bulkOrderDetails() : this.bulkOrderDetails,
    );
  }

  static const String STATUS_PENDING = 'Pending';
  static const String STATUS_ACCEPTED = 'Accepted';
  static const String STATUS_PREPARING = 'Preparing';
  static const String STATUS_READY_FOR_PICKUP = 'Ready for Pickup';
  static const String STATUS_ASSIGNED = 'Assigned';
  static const String STATUS_DISPATCHED = 'Dispatched'; 
  static const String STATUS_OUT_FOR_DELIVERY = 'Out for Delivery'; 
  static const String STATUS_DELIVERED = 'Delivered'; 
  static const String STATUS_COMPLETED = 'Completed'; 
  static const String STATUS_CANCELLED = 'Cancelled';
}

// ProducerProfile Model moved to producer_profile.dart

// Product Model (Unified)
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
    required this.produceId, required this.produceName, this.calories,
    this.carbohydrates, this.fats, this.proteins, this.unitGrams, this.source,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    try {
      final produceId = _getStringSafe(json['produce_id']);
      if (produceId == null || produceId.isEmpty) {
        throw FormatException("Missing or invalid 'produce_id' in Product JSON: $json");
      }
      final product = Product(
        produceId: produceId, produceName: _getStringSafe(json['produce_name']) ?? '',
        calories: _parseIntNullable(json['calories']), carbohydrates: _parseDoubleNullable(json['carbohydrates']),
        fats: _parseDoubleNullable(json['fats']), proteins: _parseDoubleNullable(json['proteins']),
        unitGrams: _parseIntNullable(json['unit_grams']), source: _getStringSafe(json['source']),
      );
      return product;
    } catch (e, stack) {
      debugPrint('[ProducerDash] Product parsing error: $e\n$stack');
      rethrow; 
    }
  }

  Product copyWith({
    String? produceId, String? produceName, ValueGetter<int?>? calories,
    ValueGetter<double?>? carbohydrates, ValueGetter<double?>? fats,
    ValueGetter<double?>? proteins, ValueGetter<int?>? unitGrams, ValueGetter<String?>? source,
  }) {
    return Product(
      produceId: produceId ?? this.produceId, produceName: produceName ?? this.produceName,
      calories: calories != null ? calories() : this.calories,
      carbohydrates: carbohydrates != null ? carbohydrates() : this.carbohydrates,
      fats: fats != null ? fats() : this.fats, proteins: proteins != null ? proteins() : this.proteins,
      unitGrams: unitGrams != null ? unitGrams() : this.unitGrams, source: source != null ? source() : this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'produce_id': produceId, 'produce_name': produceName,
      if (calories != null) 'calories': calories,
      if (carbohydrates != null) 'carbohydrates': carbohydrates,
      if (fats != null) 'fats': fats, if (proteins != null) 'proteins': proteins,
      if (unitGrams != null) 'unit_grams': unitGrams, if (source != null) 'source': source,
    };
  }
}

// Producer Payment Model
class ProducerPayment {
  final int id;
  final int producerId;
  final int orderId;
  final double amount;
  final String transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Status is always successful for producer payments
  String get status => 'Successful';
  
  // For UI compatibility
  String get disbursementTransactionStatus => status;
  String get orderTransactionStatus => 'Completed';
  String get orderType => 'producer_payment';
  
  ProducerPayment({
    required this.id,
    required this.producerId,
    required this.orderId,
    required this.amount,
    required this.transactionId,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory ProducerPayment.fromJson(Map<String, dynamic> json) {
    return ProducerPayment(
      id: _parseInt(json['id']),
      producerId: _parseInt(json['producer_id']),
      orderId: _parseInt(json['order_id']),
      amount: _parseDouble(json['amount']?.toString() ?? '0'),
      transactionId: _getStringSafe(json['transaction_id']) ?? 'N/A',
      createdAt: parseDateSafe(json['created_at']) ?? DateTime.now(),
      updatedAt: parseDateSafe(json['updated_at']) ?? DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'producer_id': producerId,
    'order_id': orderId,
    'amount': amount,
    'transaction_id': transactionId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// Custom Earnings History Screen for Producer Payments
class ProducerEarningsHistoryScreen extends StatelessWidget {
  final List<ProducerPayment> payments;
  
  const ProducerEarningsHistoryScreen({
    Key? key,
    required this.payments,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Group payments by date
    final Map<DateTime, List<ProducerPayment>> groupedPayments = {};
    for (final payment in payments) {
      final dateKey = DateTime(
        payment.createdAt.year,
        payment.createdAt.month,
        payment.createdAt.day,
      );
      groupedPayments.putIfAbsent(dateKey, () => []).add(payment);
    }

    // Sort dates in descending order (newest first)
    final sortedDates = groupedPayments.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: sortedDates.map<Widget>((date) {
          final dailyPayments = groupedPayments[date]!;
          
          // Calculate daily total for successful payments
          final dailyTotal = dailyPayments
              .where((p) => p.status.toLowerCase() == 'successful')
              .fold(0.0, (sum, p) => sum + p.amount);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primaryTeal.withOpacity(0.3), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date and total row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEEE, MMM d, yyyy').format(date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'UGX ${dailyTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  
                  // List of payments for this date
                  ...dailyPayments.map((payment) => _buildPaymentItem(payment)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaymentItem(ProducerPayment payment) {
    // Determine status color and icon
    final status = payment.status.toLowerCase();
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final statusText = _getStatusText(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryTeal.withOpacity(0.1), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Payment icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.payment,
                color: Colors.teal,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            
            // Payment details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${payment.orderId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Amount and time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'UGX ${payment.amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('h:mm a').format(payment.createdAt),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
        ],
      ),
    ));
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
      case 'success':
      case 'successful':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'failed':
      case 'rejected':
        return Icons.error;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusText(String status) {
    return status[0].toUpperCase() + status.substring(1);
  }
}

// Payment Model is imported from transooter_dash_before_mapbox.dart for backward compatibility

// Helper function to parse dates safely
DateTime? parseDateSafe(dynamic value) {
  if (value == null) return null;
  try {
    return DateTime.tryParse(value.toString())?.toLocal();
  } catch (_) {
    try {
      return DateFormat("E, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
          .parseUtc(value.toString())
          .toLocal();
    } catch (e) {
      return null;
    }
  }
}

// Rider/Transporter Model (Unified)
class Rider {
  final int id;
  final String name;
  final String status; 
  final bool isActive;
  final double? distanceKm; // Distance in kilometers, null if not available

  Rider({ 
    required this.id, 
    required this.name, 
    required this.status, 
    required this.isActive,
    this.distanceKm,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    final riderId = _parseIntNullable(json['rider_id'] ?? json['transporter_id'] ?? json['id']);
    final riderName = _getStringSafe(json['name'] ?? json['rider_name'] ?? json['transporter_name']);
    if (riderId == null || riderId == 0) {
      debugPrint("[ProducerDash] Warning: Rider ID is missing or invalid in JSON: $json");
    }
    
    // Parse distance if available (can be from _distance_km or distance_km)
    final distanceKm = _parseDoubleNullable(json['_distance_km'] ?? json['distance_km']);
    
    return Rider(
      id: riderId ?? 0, 
      name: riderName ?? 'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown',
      isActive: _parseBoolSafe(json['is_active']),
      distanceKm: distanceKm,
    );
  }
}

// --- Unified API Service (for Dashboard parts) ---
class ProducerApiService {
  static final String _apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://your-api.example.com';

  static Future<String?> _getProducerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('producer_id') ?? prefs.getInt('producer_id')?.toString();
  }
  
  static Future<int?> _getProducerIdInt() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseIntNullable(prefs.getString('producer_id')) ?? prefs.getInt('producer_id');
  }

  static dynamic _handleApiResponse(dynamic responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
      if (decoded is List || decoded is Map) return decoded;
      debugPrint("[ProducerDash] API response format warning: Decoded type is ${decoded.runtimeType}");
      return null;
    } catch (e) {
      debugPrint("[ProducerDash] API response JSON decoding error: $e");
      return null;
    }
  }

  static Future<Map<String, String>> _getReadHeaders({bool requiresAuth = false}) async {
    Map<String, String> headers = {'Accept': 'application/json'};
    if (requiresAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      else debugPrint("[ProducerDash] Warning: Auth required for read but no access token found.");
    }
    return headers;
  }

  static Future<Map<String, String>> _getWriteHeaders({bool requiresAuth = true}) async {
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8', 'Accept': 'application/json',
    };
    if (requiresAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      else debugPrint("[ProducerDash] Warning: Auth required but no access token found.");
    }
    return headers;
  }

  // Profile methods (fetchProducerProfile, updateProducerStatus, updateProducerProfile, updateProducerProfileImage) removed.

  static Future<List<Order>> fetchProducerOrders() async {
    final producerId = await _getProducerId();
    if (producerId == null) throw Exception('Producer ID not found. Please log in again.');
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders?producer_id=$producerId');
    debugPrint("[ProducerDash] Fetching orders: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Order> orders = handledData.map<Order>((orderJson) => Order.fromJson(orderJson)).toList();
          debugPrint("[ProducerDash] Fetched ${orders.length} orders");
          return orders;
        } else {
          debugPrint('[ProducerDash] Orders response format error: expected List, got ${handledData?.runtimeType}. Body: ${response.body}');
          throw Exception('API response for orders was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception('Failed to load orders (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('[ProducerDash] Orders fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    debugPrint('[ProducerDash][API] Updating order $orderId status to $newStatus');
    debugPrint('[ProducerDash][API] Endpoint: $uri');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('user_phone');
      
      final Map<String, dynamic> requestBody = {
        'order_status': newStatus,
        if (userPhone != null) 'restaurant_phone': userPhone,
      };
      
      debugPrint('[ProducerDash][API] Request body: $requestBody');
      
      final headers = await _getWriteHeaders();
      debugPrint('[ProducerDash][API] Headers: $headers');
      
      final response = await http.patch(
        uri, 
        headers: headers, 
        body: jsonEncode(requestBody)
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('[ProducerDash][API] Response status: ${response.statusCode}');
      debugPrint('[ProducerDash][API] Response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('[ProducerDash][API] Status update successful');
        return true;
      } else {
        debugPrint('[ProducerDash][API] Status update failed with status: ${response.statusCode}');
        return false;
      }
    } on TimeoutException catch (e) {
      debugPrint('[ProducerDash][API] Request timed out: $e');
      return false;
    } on SocketException catch (e) {
      debugPrint('[ProducerDash][API] Network error: $e');
      return false;
    } catch (e, stackTrace) {
      debugPrint('[ProducerDash][API] Unexpected error:');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<bool> assignOrderToRider(int orderId, int riderId, String newStatus) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    debugPrint("[ProducerDash] Assigning order $orderId to rider $riderId, status $newStatus at $uri");
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('user_phone');
      
      final Map<String, dynamic> requestBody = {
        'order_status': newStatus,
        'transporter_id': riderId,
        if (userPhone != null) 'restaurant_phone': userPhone,
      };
      
      final response = await http.patch(
        uri, 
        headers: await _getWriteHeaders(),
        body: jsonEncode(requestBody),
      );
      
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("[ProducerDash] Exception assigning order: $e");
      return false;
    }
  }

  // In-memory cache for riders with location-based keys
  static final Map<String, List<Rider>> _ridersCache = {};
  static final Map<String, DateTime> _ridersCacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  static String _getRidersCacheKey(String? geoFencedLocation) {
    return 'riders_${geoFencedLocation ?? 'no_location'}';
  }

  static Future<List<Rider>> fetchAvailableRiders() async {
    // Get geo-fenced location if available
    final String? geoFencedLocation = await getGeoFencedLocationParam();
    final String cacheKey = _getRidersCacheKey(geoFencedLocation);
    final now = DateTime.now();
    
    // Check if we have a valid cache entry
    final lastFetched = _ridersCacheTimestamps[cacheKey];
    if (lastFetched != null && now.difference(lastFetched) < _cacheDuration) {
      final cachedRiders = _ridersCache[cacheKey];
      if (cachedRiders != null && cachedRiders.isNotEmpty) {
        debugPrint('🚀 [produ_dash22] Using cached riders for location: ${geoFencedLocation ?? 'no location'}');
        return List.from(cachedRiders);
      }
    }

    // Prepare API request
    final Map<String, String> queryParams = {
      if (geoFencedLocation != null) 'geo_fenced_location': geoFencedLocation
    };

    final uri = Uri.parse('$_apibaseurl/rr/transporters').replace(
      queryParameters: queryParams,
    );
    
    debugPrint('🔴 [produ_dash22] === HTTP REQUEST ===');
    debugPrint('🔴 [produ_dash22] URL: ${uri.toString()}');
    debugPrint('🔴 [produ_dash22] Method: GET');
    debugPrint('🔴 [produ_dash22] Query Parameters: ${uri.queryParameters}');
    
    try {
      final response = await http.get(
        uri, 
        headers: await _getReadHeaders(requiresAuth: true)
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('🟢 [produ_dash22] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Rider> riders = handledData.map<Rider?>((jsonItem) {
            try { 
              return Rider.fromJson(jsonItem); 
            } catch (e) { 
              debugPrint('⚠️ [produ_dash22] Skipping invalid rider item: $e');
              return null; 
            }
          }).whereType<Rider>().toList();
          
          // Update cache
          _ridersCache[cacheKey] = List.from(riders);
          _ridersCacheTimestamps[cacheKey] = now;
          
          debugPrint('✅ [produ_dash22] Fetched ${riders.length} riders for location: ${geoFencedLocation ?? 'no location'}');
          return riders;
        } else {
          debugPrint('❌ [produ_dash22] Unexpected API response format. Expected List, got ${handledData?.runtimeType}');
          throw Exception('API response for riders was not a list');
        }
      } else {
        // On API error, return cached data if available (even if expired)
        final cachedRiders = _ridersCache[cacheKey];
        if (cachedRiders != null && cachedRiders.isNotEmpty) {
          debugPrint('⚠️ [produ_dash22] API error (${response.statusCode}), using cached riders');
          return List.from(cachedRiders);
        }
        throw Exception('Failed to load riders (Status: ${response.statusCode})');
      }
    } on TimeoutException {
      // On timeout, return cached data if available
      final cachedRiders = _ridersCache[cacheKey];
      if (cachedRiders != null && cachedRiders.isNotEmpty) {
        debugPrint('⚠️ [produ_dash22] Request timed out, using cached riders');
        return List.from(cachedRiders);
      }
      rethrow;
    } catch (e, stack) {
      debugPrint('❌ [produ_dash22] Exception fetching riders: $e\n$stack');
      // If we have any cached data, return it as fallback
      final cachedRiders = _ridersCache[cacheKey] ?? [];
      if (cachedRiders.isNotEmpty) {
        debugPrint('⚠️ [produ_dash22] Using cached riders after error');
        return List.from(cachedRiders);
      }
      rethrow;
    }
  }
  
  static const String _produceCacheKey = 'producer_produce_cache';
  static const String _produceCacheTimestampKey = 'producer_produce_cache_timestamp';
  static const int _cacheExpiryDays = 3; 

  // Fetch producer payments/disbursements
  static Future<List<ProducerPayment>> fetchProducerPayments(int producerId) async {
    try {
      // Use the base URL as is (should be HTTPS from .env)
      final baseUrl = _apibaseurl.endsWith('/') 
          ? _apibaseurl.substring(0, _apibaseurl.length - 1) 
          : _apibaseurl;
      final url = '$baseUrl/rr/disbursements/producer?producer_id=$producerId';
      debugPrint('[ProducerDash] Fetching payments from: $url');
      
      final headers = await _getReadHeaders(requiresAuth: true); // Auth is likely needed
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('[ProducerDash] Response status: ${response.statusCode}');
      
      // Check for HTML response (usually means an error page)
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        throw Exception('Server returned an error page. Please try again later.');
      }
      
      if (response.statusCode == 200) {
        try {
          // Parse the response as JSON
          final dynamic data = jsonDecode(response.body);
          
          // Handle both array response and single object
          final List<dynamic> paymentsJson = data is List ? data : [data];
          
          debugPrint('[ProducerDash] Found ${paymentsJson.length} payments');
          
          // Convert each JSON object to ProducerPayment
          final payments = <ProducerPayment>[];
          for (final json in paymentsJson) {
            try {
              if (json is Map<String, dynamic>) {
                payments.add(ProducerPayment.fromJson(json));
              }
            } catch (e) {
              debugPrint('[ProducerDash] Error parsing payment: $e');
              continue;
            }
          }
          
          return payments;
        } catch (e) {
          debugPrint('[ProducerDash] Error processing payments: $e');
          throw Exception('Failed to process payment data');
        }
      } else {
        throw Exception('Failed to load payments. Status: ${response.statusCode}');
      }
    } on SocketException catch (e) {
      debugPrint('[ProducerDash] Network error: $e');
      throw Exception('No internet connection');
    } on TimeoutException {
      debugPrint('[ProducerDash] Request timed out');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      debugPrint('[ProducerDash] Unexpected error: $e');
      throw Exception('An error occurred. Please try again.');
    }
  }

  static Future<List<Product>> fetchProducerProduce({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedProduce = await UserCache.getData(_produceCacheKey);
      final cachedTimestamp = await UserCache.getData(_produceCacheTimestampKey);
      if (cachedProduce is List && cachedTimestamp is String) {
        final cacheTime = DateTime.tryParse(cachedTimestamp);
        if (cacheTime != null && DateTime.now().difference(cacheTime).inDays < _cacheExpiryDays) {
          try {
            final List<Product> products = (cachedProduce as List).map((item) => Product.fromJson(item as Map<String, dynamic>)).toList();
            debugPrint("[ProducerDash] Using cached produce list (${products.length} items)");
            return products;
          } catch (e) {
            debugPrint("[ProducerDash] Error parsing cached produce: $e");
          }
        }
      }
    }
    
    final Uri uri = Uri.parse('$_apibaseurl/rr/produce');
    debugPrint("[ProducerDash] Fetching fresh master produce list: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Product> produce = handledData.map<Product>((prodJson) => Product.fromJson(prodJson)).toList();
          debugPrint("[ProducerDash] Fetched ${produce.length} produce items from API");
          try {
            final produceJson = produce.map((p) => p.toJson()).toList();
            await UserCache.saveData(_produceCacheKey, produceJson);
            await UserCache.saveData(_produceCacheTimestampKey, DateTime.now().toIso8601String());
            debugPrint("[ProducerDash] Cached ${produce.length} produce items");
          } catch (e) {
            debugPrint("[ProducerDash] Error caching produce: $e");
          }
          return produce;
        } else {
          debugPrint('[ProducerDash] Produce response format error: expected List, got ${handledData?.runtimeType}. Body: ${response.body}');
          throw Exception('API response for produce was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception('Failed to fetch produce (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      debugPrint('[ProducerDash] Produce fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateProducerStock(int producerId, List<Map<String, dynamic>> stockList) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId');
    debugPrint("[ProducerDash] Updating stock for producer $producerId at $uri");
    final payload = jsonEncode({"stock": stockList});
    debugPrint("[ProducerDash] Stock update payload: $payload");
    try {
      final response = await http.patch(uri, headers: await _getWriteHeaders(), body: payload);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("Exception updating stock: $e");
      return false;
    }
  }

  // --- REMOVED METHODS because for now we dont need them---
  // addProduce, updateProduce, and deleteProduce have been removed.
  // --- END REMOVED METHODS ---
}

// --- Main Widget State ---
class ProducerDash22 extends StatefulWidget {
  static Map<String, dynamic> _serializeOrder(dynamic order) {
    if (order == null) return {};
    if (order is Map<String, dynamic>) return order;
    if (order is Order) {
      return {
        'order_id': order.orderId, 'product_name': order.mealName,
        'order_date': order.orderDate.toIso8601String(), 'total_price': order.totalPrice,
        'quantity': order.quantity, 'order_status': order.orderStatus,
        'customer_name': order.customerName, 'delivery_address': order.deliveryAddress,
        'notes': order.notes, 'ingredients': order.ingredients,
        'payment_status': order.paymentStatus, 'assigned_rider_id': order.assignedRiderId,
        'assigned_rider_name': order.assignedRiderName,
        'complementary_meals': order.complementaryMeals,
        'is_bulk_order': order.isBulkOrder,
        'bulk_order_details': order.bulkOrderDetails != null ? jsonEncode(order.bulkOrderDetails) : null,
      };
    }
    debugPrint("[ProducerDash] Warning: Could not serialize order of type ${order.runtimeType}");
    return {};
  }

  static Map<String, dynamic> _serializeProduct(dynamic product) {
    if (product == null) return {};
    if (product is Map<String, dynamic>) return product;
    if (product is Product) {
      return {
        'produce_id': product.produceId, 'produce_name': product.produceName,
        'calories': product.calories, 'carbohydrates': product.carbohydrates,
        'fats': product.fats, 'proteins': product.proteins,
        'unit_grams': product.unitGrams, 'source': product.source,
      };
    }
    debugPrint("[ProducerDash] Warning: Could not serialize product of type ${product.runtimeType}");
    return {};
  }

  static Future<void> preloadCacheForSplash() async {
    debugPrint('[Splash][ProducerDash-Dashboard] Starting cache preload...');
    final stopwatch = Stopwatch()..start();
    try {
      // Profile preload is handled by producer_profile.dart's own static method.
      await ProducerApiService.fetchProducerOrders();
      debugPrint('[Splash][ProducerDash-Dashboard] Orders cache preloaded');
      await ProducerApiService.fetchProducerProduce();
      debugPrint('[Splash][ProducerDash-Dashboard] Produce cache preloaded');
      debugPrint('[Splash][ProducerDash-Dashboard] Cache preload completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[Splash][ProducerDash-Dashboard] Error during cache preload: $e');
    }
  }

  const ProducerDash22({super.key});

  @override
  State<ProducerDash22> createState() => _ProducerDash22State();
}

class _ProducerDash22State extends State<ProducerDash22> with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  int _currentIndex = 0; // Default to Orders tab (index 0 after profile removal)
  final List<Order> _orders = [];
  final Map<int, String> _previousOrderStatuses = {}; // Track previous order statuses
  final List<Product> _produce = []; 
  bool _isLoading = true; 
  bool _isLoadingOrders = true;
  bool _isLoadingProduce = true;
  String _error = ''; 
  String _selectedStatusFilter = 'All'; // State for the selected order status filter

  Set<String> _selectedProduceIds = {};
  Map<String, int> _produceQuantities = {};
  final Map<int, bool> _expandedOrders = {}; // Track expanded state for each order
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  Timer? _pollingTimer;
  bool _isRefreshing = false; 
  bool _isRouteActive = false; 

  late final NotificationProvider notificationProvider;

  // Temp variable to store producer ID for stock updates.
  int? _currentProducerId;
  
  // State for earnings tab
  List<ProducerPayment> _payments = [];
  bool _isLoadingPayments = false;
  bool _hasPaymentError = false;
  
  // Fetch payments for the producer
  Future<void> _fetchPayments() async {
    if (_isLoadingPayments) {
      debugPrint('[ProducerDash] Fetch already in progress, skipping');
      return;
    }
    
    debugPrint('[ProducerDash] Starting to fetch payments');
    
    if (!mounted) {
      debugPrint('[ProducerDash] Widget not mounted, aborting');
      return;
    }
    
    setState(() {
      _isLoadingPayments = true;
      _hasPaymentError = false;
      _error = '';
    });
    
    try {
      debugPrint('[ProducerDash] Getting producer ID');
      final producerId = await ProducerApiService._getProducerIdInt();
      if (producerId == null) {
        debugPrint('[ProducerDash] No producer ID found');
        if (!mounted) return;
        setState(() {
          _hasPaymentError = true;
          _error = 'Producer ID not found. Please log in again.';
        });
        return;
      }
      
      debugPrint('[ProducerDash] Fetching payments for producer ID: $producerId');
      final payments = await ProducerApiService.fetchProducerPayments(producerId);
      
      debugPrint('[ProducerDash] Received ${payments.length} payments');
      
      if (!mounted) {
        debugPrint('[ProducerDash] Widget disposed during fetch, ignoring results');
        return;
      }
      
      setState(() {
        _payments = payments;
        _hasPaymentError = false;
        _error = '';
      });
      
      debugPrint('[ProducerDash] Payments updated in state');
      
    } catch (e, stack) {
      debugPrint('[ProducerDash] Error fetching payments: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _hasPaymentError = true;
        _error = 'Failed to load payment history: ${e.toString()}. Please try again later.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPayments = false;
        });
      }
      debugPrint('[ProducerDash] Finished fetch payments operation');
    }
  }


  @override
  void initState() {
    super.initState();
    notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _fetchAllData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final route = ModalRoute.of(context);
        if (route != null) {
          final routeObserver = RouteObserverProvider.of(context);
          routeObserver.subscribe(this, route as PageRoute);
          _isRouteActive = route.isCurrent;
          if (_currentIndex == 0 && _isRouteActive) {
            _startPolling();
          }
        }
      }
    });
    notificationProvider.addListener(_handleNotificationRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Moved subscription to initState with post-frame callback
  }

  @override
  void didPush() { _updateRouteStatus(true); }
  @override
  void didPopNext() { _updateRouteStatus(true); }
  @override
  void didPushNext() { _updateRouteStatus(false); }
  @override
  void didPop() { _updateRouteStatus(false); }
  
  void _updateRouteStatus(bool isActive) {
    if (!mounted) return;
    setState(() => _isRouteActive = isActive);
    if (isActive && _currentIndex == 0) {
      _startPolling();
    } else {
      _pollingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    notificationProvider.removeListener(_handleNotificationRefresh);
    WidgetsBinding.instance.removeObserver(this);
    final routeObserver = RouteObserverProvider.of(context);
    routeObserver.unsubscribe(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isRouteActive && _currentIndex == 0) {
        _startPolling();
        _fetchAllData(forceRefresh: true);
      }
    } else if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
    }
  }

  void _handleNotificationRefresh() {
    debugPrint("[ProducerDash] Received notification refresh trigger.");
    if (!_isRefreshing && mounted) _fetchAllData(forceRefresh: true);
  }

  void _onTabChanged(int newIndex) {
    if (!mounted || _currentIndex == newIndex) return;

    setState(() => _currentIndex = newIndex);
    
    if (!_isRouteActive) {
      _pollingTimer?.cancel();
      return;
    }
    
    if (newIndex == 0) { // Orders tab
      _startPolling();
    } else {
      _pollingTimer?.cancel();
      if (newIndex == 1 && _payments.isEmpty && !_isLoadingPayments && !_hasPaymentError) {
        _fetchPayments();
      }
    }
  }

  // --- FIX: Smarter polling logic for new orders and status updates ---
  Future<void> _pollOrders() async {
    if (_isRefreshing || !mounted || _currentIndex != 0 || !_isRouteActive) return;

    try {
      final fetchedOrders = await ProducerApiService.fetchProducerOrders();
      if (!mounted) return;
      
      final currentOrderIds = _orders.map((o) => o.orderId).toSet();
      final List<Order> newOrders = [];
      bool hasUpdates = false;

      for (final fetchedOrder in fetchedOrders) {
        if (!currentOrderIds.contains(fetchedOrder.orderId)) {
          newOrders.add(fetchedOrder);
          hasUpdates = true;
        } else {
          final existingOrderIndex = _orders.indexWhere((o) => o.orderId == fetchedOrder.orderId);
          if (existingOrderIndex != -1) {
            final existingOrder = _orders[existingOrderIndex];
            if (existingOrder.orderStatus != fetchedOrder.orderStatus ||
                existingOrder.assignedRiderId != fetchedOrder.assignedRiderId) {
              _orders[existingOrderIndex] = fetchedOrder;
              hasUpdates = true;
            }
          }
        }
      }

      if (hasUpdates) {
        setState(() {
          if (newOrders.isNotEmpty) {
             _orders.insertAll(0, newOrders);
          }
          _sortOrders();
        });

        if (newOrders.isNotEmpty) {
          _showInfoSnackbar("${newOrders.length} new order(s) received.");
        }
      }
    } catch (e) {
      debugPrint("[ProducerDash] Silent polling error: $e");
    }
  }


  void _startPolling() {
    if (_currentIndex != 0 || !_isRouteActive) return;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && _currentIndex == 0 && _isRouteActive && !_isRefreshing) {
        debugPrint("[ProducerDash] Polling for new orders...");
        _pollOrders();
      }
    });
    debugPrint("[ProducerDash] Started polling for orders");
  }

  Future<void> _fetchAllData({bool forceRefresh = false}) async {
    if (!mounted || _isRefreshing) return;
    
    _pollingTimer?.cancel(); // Pause polling during manual refresh
    
    setState(() { _isLoading = true; _isRefreshing = true; _error = ''; });

    try {
      _currentProducerId = await ProducerApiService._getProducerIdInt();
      if (_currentProducerId == null) throw Exception('Producer ID not found');

      await Future.wait([
        _fetchOrdersAndProduce(forceRefresh: forceRefresh),
        _syncStockFromProfile(),
      ]);
      
    } catch (e, stackTrace) {
      debugPrint("[ProducerDash] Error fetching all data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _error = 'Failed to load data. Please check connection.';
          _orders.clear(); _produce.clear();
          _selectedProduceIds.clear(); _produceQuantities.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; _isRefreshing = false; });
        _startPolling(); // --- FIX: Restart polling after refresh completes
      }
    }
  }
  
  Future<void> _syncStockFromProfile() async {
    if (_currentProducerId == null) {
      debugPrint("[ProducerDash] Cannot sync stock: Producer ID is null.");
      return;
    }
    
    debugPrint("[ProducerDash] Syncing stock state from server for producer $_currentProducerId...");

    try {
      final uri = Uri.parse('${ProducerApiService._apibaseurl}/rr/rproducers/$_currentProducerId');
      final response = await http.get(
        uri,
        headers: await ProducerApiService._getReadHeaders(requiresAuth: true),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = json.decode(response.body);
        final Map<String, dynamic> profileData = responseBody.containsKey('data') 
            ? responseBody['data'] 
            : responseBody;
            
        final List<dynamic>? stockList = profileData['stock'] as List<dynamic>?;

        final Set<String> serverSelectedIds = {};
        final Map<String, int> serverQuantities = {};

        if (stockList != null && stockList.isNotEmpty) {
          debugPrint("[ProducerDash] Found ${stockList.length} stock items in server profile.");
          for (var stockItem in stockList) {
            final String? produceId = stockItem['produce_id']?.toString();
            if (produceId != null && produceId.isNotEmpty) {
              serverSelectedIds.add(produceId);
              serverQuantities[produceId] = _parseIntNullable(stockItem['quantity']) ?? 1;
            }
          }
        } else {
          debugPrint("[ProducerDash] No stock data found in server profile.");
        }

        setState(() {
          _selectedProduceIds = serverSelectedIds;
          _produceQuantities = serverQuantities;
        });
        debugPrint("[ProducerDash] Stock state synchronized. Selected IDs: ${_selectedProduceIds.length}");

      } else {
        debugPrint("[ProducerDash] Failed to fetch profile for stock sync: ${response.statusCode} - ${response.body}");
        _showErrorSnackBar('Could not sync current stock status.');
      }
    } catch (e, stackTrace) {
      debugPrint("[ProducerDash] Error syncing stock from profile: $e\n$stackTrace");
      if (mounted) _showErrorSnackBar('Error syncing stock status.');
    }
  }


  Future<void> _fetchOrdersAndProduce({bool forceRefresh = false}) async {
    debugPrint('[ProducerDash][DEBUG] Starting _fetchOrdersAndProduce. Force refresh: $forceRefresh');
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

    if (!forceRefresh) {
      debugPrint('[ProducerDash][CACHE] Attempting to load from cache...');
      try {
        final cachedOrdersJson = await UserCache.getData(ordersKey);
        final cachedOrdersTs = await UserCache.getData(ordersTsKey);
        final cachedProduceJson = await UserCache.getData(produceKey);
        final cachedProduceTs = await UserCache.getData(produceTsKey);
        bool ordersCacheValid = false, produceCacheValid = false;

        if (cachedOrdersJson is List && cachedOrdersJson.isNotEmpty && cachedOrdersTs is String) {
          final cacheTime = DateTime.tryParse(cachedOrdersTs);
          if (cacheTime != null) {
            try {
              debugPrint('[ProducerDash][CACHE] Parsing cached orders...');
              cachedOrdersData = (cachedOrdersJson).map<Order>((orderJson) {
                try {
                  return Order.fromJson(orderJson as Map<String, dynamic>);
                } catch (e) {
                  debugPrint('[ProducerDash][CACHE] Error parsing order: $e');
                  rethrow;
                }
              }).toList();
              ordersCacheValid = true;
              debugPrint('[ProducerDash][CACHE] Successfully parsed ${cachedOrdersData.length} orders from cache');
            } catch (e) { 
              debugPrint('[ProducerDash][CACHE] Error parsing cached orders: $e'); 
            }
          }
        }

        if (cachedProduceJson is List && cachedProduceJson.isNotEmpty && cachedProduceTs is String) {
          final cacheTime = DateTime.tryParse(cachedProduceTs);
          if (cacheTime != null) {
            try {
              debugPrint('[ProducerDash][CACHE] Parsing cached produce...');
              cachedProduceData = (cachedProduceJson).map<Product>((prodJson) {
                try {
                  return Product.fromJson(prodJson as Map<String, dynamic>);
                } catch (e) {
                  debugPrint('[ProducerDash][CACHE] Error parsing product: $e');
                  rethrow;
                }
              }).toList();
              produceCacheValid = true;
              debugPrint('[ProducerDash][CACHE] Successfully parsed ${cachedProduceData.length} products from cache');
            } catch (e) { 
              debugPrint('[ProducerDash][CACHE] Error parsing cached produce: $e'); 
            }
          }
        }

        if (mounted && (ordersCacheValid || produceCacheValid)) {
          debugPrint('[ProducerDash][CACHE] Updating UI with cached data');
          setState(() {
            if (ordersCacheValid && cachedOrdersData != null) { 
              _orders.clear();
              _orders.addAll(cachedOrdersData!);
              _sortOrders(); 
              debugPrint('[ProducerDash][CACHE] Updated ${_orders.length} orders in UI');
            }
            if (produceCacheValid && cachedProduceData != null) { 
              _produce.clear();
              _produce.addAll(cachedProduceData!);
              _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
              debugPrint('[ProducerDash][CACHE] Updated ${_produce.length} products in UI');
            }
            _isLoadingOrders = !ordersCacheValid; 
            _isLoadingProduce = !produceCacheValid;
          });
          loadedFromCache = ordersCacheValid && produceCacheValid;
          debugPrint('[ProducerDash][CACHE] Loaded from cache: $loadedFromCache');
        }
      } catch (e) {
        debugPrint('[ProducerDash][CACHE] Error during cache processing: $e');
      }
    } else {
      debugPrint('[ProducerDash][CACHE] Skipping cache - force refresh requested');
    }

    try {
      debugPrint('[ProducerDash][API] Fetching fresh data from server...');
      final results = await Future.wait([
        ProducerApiService.fetchProducerOrders(),
        ProducerApiService.fetchProducerProduce(),
      ], eagerError: true);
      
      if (mounted) {
        final fetchedOrders = results[0] as List<Order>;
        final fetchedProduce = results[1] as List<Product>;
        
        debugPrint('[ProducerDash][API] Fetched ${fetchedOrders.length} orders and ${fetchedProduce.length} products');
        
        setState(() {
          _orders.clear();
          _orders.addAll(fetchedOrders);
          _produce.clear();
          _produce.addAll(fetchedProduce);
          _sortOrders(); 
          _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
          _isLoadingOrders = false; 
          _isLoadingProduce = false;
        });
        
        try {
          debugPrint('[ProducerDash][CACHE] Saving data to cache...');
          await Future.wait([
            UserCache.saveData(ordersKey, fetchedOrders.map((o) => ProducerDash22._serializeOrder(o)).toList()),
            UserCache.saveData(ordersTsKey, now.toIso8601String()),
            UserCache.saveData(produceKey, fetchedProduce.map((p) => ProducerDash22._serializeProduct(p)).toList()),
            UserCache.saveData(produceTsKey, now.toIso8601String()),
          ]);
          debugPrint('[ProducerDash][CACHE] Data saved to cache');
        } catch (e) {
          debugPrint('[ProducerDash][CACHE] Error saving to cache: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[ProducerDash][API] Error fetching data:');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _isLoadingOrders = false; 
          _isLoadingProduce = false;
          if (!loadedFromCache && _error.isEmpty) {
            if (_orders.isEmpty || _produce.isEmpty) {
              _error = 'Failed to load orders/produce. ${e.toString()}';
            }
          }
        });
        
        if (loadedFromCache || _orders.isNotEmpty || _produce.isNotEmpty) {
          _showErrorSnackBar('Showing available data. ${e.toString()}');
        } else {
          _showErrorSnackBar('Failed to load data. Please check your connection.');
        }
      }
    } finally {
      debugPrint('[ProducerDash] Finished _fetchOrdersAndProduce');
    }
  }

  void _sortOrders() {
    for (var order in _orders) {
      _previousOrderStatuses[order.orderId] = order.orderStatus;
    }
    _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
  }
  
  void _checkAndRefreshEarningsOnStatusChange(int orderId, String newStatus) {
    final previousStatus = _previousOrderStatuses[orderId];
    final isNewlyCompleted = (newStatus == Order.STATUS_COMPLETED || newStatus == Order.STATUS_DELIVERED) &&
        previousStatus != newStatus;
    
    if (isNewlyCompleted) {
      debugPrint('[ProducerDash] Order $orderId status changed to $newStatus, refreshing earnings...');
      _fetchPayments();
    }
  }

  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    debugPrint('[ProducerDash][DEBUG] Starting order status update. Order ID: ${order.orderId}, New Status: $newStatus');
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) {
      debugPrint('[ProducerDash][ERROR] Order not found in local list: ${order.orderId}');
      return;
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    }
    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;
    
    debugPrint('[ProducerDash][DEBUG] Current status: $originalStatus, Will update to: $newStatus');
    
    if (!_previousOrderStatuses.containsKey(order.orderId)) {
      _previousOrderStatuses[order.orderId] = order.orderStatus;
    }

    _checkAndRefreshEarningsOnStatusChange(order.orderId, newStatus);

    setState(() {
      _orders[orderIndex].orderStatus = newStatus;
      if ([Order.STATUS_ACCEPTED, Order.STATUS_PREPARING, Order.STATUS_CANCELLED].contains(newStatus)) {
        debugPrint('[ProducerDash][DEBUG] Clearing rider assignment for status: $newStatus');
        _orders[orderIndex] = _orders[orderIndex].copyWith(
          assignedRiderId: () => null, 
          assignedRiderName: () => null
        );
      }
      _sortOrders();
    });
    
    _showLoadingSnackbar("Updating status to $newStatus...");
    
    try {
      debugPrint('[ProducerDash][DEBUG] Calling API to update order status...');
      bool success = await ProducerApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      
      if (!mounted) {
        debugPrint('[ProducerDash][DEBUG] Widget not mounted after API call, aborting');
        return;
      }
      
      if (success) {
        debugPrint('[ProducerDash][SUCCESS] Order ${order.orderId} status updated to $newStatus');
        _showSuccessSnackbar('Order ${order.orderId} status updated to $newStatus.');
        _showOrderNextStepDialog(newStatus);
        
        _fetchOrdersAndProduce(forceRefresh: true);
      } else {
        debugPrint('[ProducerDash][ERROR] API returned failure for order ${order.orderId}');
        _showErrorSnackBar('Failed to update order ${order.orderId} status.');
        
        setState(() {
          _orders[orderIndex].orderStatus = originalStatus;
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            assignedRiderId: () => originalRiderId, 
            assignedRiderName: () => originalRiderName
          );
          _sortOrders();
        });
      }
    } catch (e, stackTrace) {
      _dismissLoadingSnackbar();
      debugPrint('[ProducerDash][EXCEPTION] Error updating order status:');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (mounted) {
        _showErrorSnackBar('An error occurred while updating status.');
        
        setState(() {
          _orders[orderIndex].orderStatus = originalStatus;
          _orders[orderIndex] = _orders[orderIndex].copyWith(
            assignedRiderId: () => originalRiderId, 
            assignedRiderName: () => originalRiderName
          );
          _sortOrders();
        });
      }
    }
  }

  Future<void> _handleReadyForShipping(Order order) async {
    if (!mounted) return;
    final result = await showDialog<dynamic>(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) => _RiderSelectionDialog(orderId: order.orderId),
    );
    if (!mounted) return;
    if (result is Rider) {
      debugPrint("Rider ${result.name} selected for Order ${order.orderId}. Showing confirmation...");
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      debugPrint("Marking Order ${order.orderId} as Ready for Pickup (Any Rider)");
      await _markReadyForAnyRider(order);
    } else {
      debugPrint("Rider assignment cancelled or dialog closed.");
    }
  }

  Future<void> _showRiderAssignmentConfirmation(Order order, Rider rider) async {
    if (!mounted) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Confirm Assignment for Order #${order.orderId}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Assign this order to rider:'), const SizedBox(height: 8),
          Text('  Name: ${rider.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('  Status: ${rider.isActive ? "Active" : "Inactive"} (${rider.status})'), Text('  ID: ${rider.id}'),
          if (!rider.isActive) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('Warning: Rider is currently inactive.', style: TextStyle(color: Colors.orange.shade800))),
        ]),
        actions: <Widget>[
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop(false)),
          TextButton(child: Text(rider.isActive ? 'Confirm Assignment' : 'Assign Anyway', style: TextStyle(color: primaryTeal)), onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      debugPrint("Confirmation received. Assigning Order ${order.orderId} to Rider ${rider.id} (${rider.name})");
      await _assignSpecificRider(order, rider);
    } else {
      debugPrint("Rider assignment cancelled by user.");
      _showInfoSnackbar("Rider assignment cancelled.");
    }
  }

  Future<void> _assignSpecificRider(Order order, Rider rider) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;
    setState(() {
      _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: Order.STATUS_ASSIGNED, assignedRiderId: () => rider.id, assignedRiderName: () => rider.name);
      _sortOrders();
    });
    _showLoadingSnackbar("Assigning to ${rider.name}...");
    try {
      bool success = await ProducerApiService.assignOrderToRider(order.orderId, rider.id, Order.STATUS_ASSIGNED);
      _dismissLoadingSnackbar();
      if (!mounted) return;
      if (success) {
        _showSuccessSnackbar('Order ${order.orderId} assigned to ${rider.name}.');
        _showOrderNextStepDialog(Order.STATUS_ASSIGNED);
      } else {
        _showErrorSnackBar('Failed to assign order ${order.orderId} to ${rider.name}.');
        setState(() {
          _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: originalStatus, assignedRiderId: () => originalRiderId, assignedRiderName: () => originalRiderName);
          _sortOrders();
        });
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      debugPrint("[ProducerDash] Error assigning specific rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while assigning the rider.');
        setState(() {
          _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: originalStatus, assignedRiderId: () => originalRiderId, assignedRiderName: () => originalRiderName);
          _sortOrders();
        });
      }
    }
  }

  Future<void> _markReadyForAnyRider(Order order) async {
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) return;
    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;
    setState(() {
      _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: Order.STATUS_READY_FOR_PICKUP, assignedRiderId: () => null, assignedRiderName: () => null);
      _sortOrders();
    });
    _showLoadingSnackbar("Marking order as ready...");
    try {
      bool success = await ProducerApiService.updateOrderStatus(order.orderId, Order.STATUS_READY_FOR_PICKUP);
      _dismissLoadingSnackbar();
      if (!mounted) return;
      if (success) {
        _showSuccessSnackbar('Order ${order.orderId} marked as Ready for Pickup.');
        _showOrderNextStepDialog(Order.STATUS_READY_FOR_PICKUP);
      } else {
        _showErrorSnackBar('Failed to mark order ${order.orderId} as Ready for Pickup.');
        setState(() {
          _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: originalStatus, assignedRiderId: () => originalRiderId, assignedRiderName: () => originalRiderName);
          _sortOrders();
        });
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      debugPrint("[ProducerDash] Error marking ready for any rider: $e");
      if (mounted) {
        _showErrorSnackBar('An error occurred while updating order status.');
        setState(() {
          _orders[orderIndex] = _orders[orderIndex].copyWith(orderStatus: originalStatus, assignedRiderId: () => originalRiderId, assignedRiderName: () => originalRiderName);
          _sortOrders();
        });
      }
    }
  }

  void _showRejectConfirmation(Order order) {
    if (!mounted) return;
    showDialog(
      context: context, builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Confirm Rejection"), content: Text("Reject Order #${order.orderId} (${order.mealName})? This cannot be undone."),
        actions: <Widget>[
          TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(dialogContext).pop()),
          TextButton(child: Text("Reject Order", style: TextStyle(color: errorColor)), onPressed: () {
            Navigator.of(dialogContext).pop(); _updateSimpleOrderStatus(order, Order.STATUS_CANCELLED);
          }),
        ],
      ),
    );
  }

  int _findOrderIndex(int orderId) {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index == -1) debugPrint("[ProducerDash] Warning: Order $orderId not found in _orders list for update.");
    return index;
  }

  Future<void> _updateProducerStock() async {
    if (!mounted) return;
  
    if (_currentProducerId == null) {
      _showErrorSnackBar('Producer ID not loaded. Cannot update stock.');
      return;
    }
  
    final List<Map<String, dynamic>> stockList = _selectedProduceIds.map<Map<String, dynamic>?>((String id) {
      try {
        final product = _produce.firstWhere((p) => p.produceId == id);
        final quantity = _produceQuantities[id] ?? 1; // Default to 1 if not set
        return <String, dynamic>{
          'Name': product.produceName,
          'produce_id': id,
          'quantity': quantity,
        };
      } catch (e) {
        return null;
      }
    }).where((item) => item != null).map((item) => item!).toList();
  
    if (mounted) _showLoadingSnackbar('Updating stock...');
  
    try {
      bool success = await ProducerApiService.updateProducerStock(_currentProducerId!, stockList);
    
      if (!mounted) return;
      _dismissLoadingSnackbar();
    
      if (success) {
        _showSuccessSnackbar('Stock updated successfully.');
        await _syncStockFromProfile();
      } else {
        _showErrorSnackBar('Failed to update stock. Please try again.');
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _updateProducerStock: $e\n$stackTrace');
      if (!mounted) return;
      _dismissLoadingSnackbar();
      _showErrorSnackBar('Error: ${e.toString()}');
    }  
  }

  void _showSnackbar(String message, {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: isError ? whiteColor : textOnTeal), textAlign: TextAlign.center),
      backgroundColor: isError ? errorColor.withOpacity(0.9) : primaryTeal.withOpacity(0.9),
      duration: Duration(seconds: durationSeconds), behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)), elevation: 2.0,
    ));
  }
  void _showErrorSnackBar(String message) => _showSnackbar(message, isError: true, durationSeconds: 4);
  void _showSuccessSnackbar(String message) => _showSnackbar(message, isError: false);
  void _showInfoSnackbar(String message) => _showSnackbar(message, isError: false, durationSeconds: 2);
  void _showLoadingSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..removeCurrentSnackBar()..showSnackBar(SnackBar(
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
        const SizedBox(width: 15), Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]),
      backgroundColor: Colors.black.withOpacity(0.8), duration: const Duration(minutes: 1),
      behavior: SnackBarBehavior.floating, margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
    ));
  }
  void _dismissLoadingSnackbar() { if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar(); }

  void _showOrderNextStepDialog(String newStatus) {
    if (!mounted) return;
    String message; String title; IconData icon;
    switch (newStatus.toLowerCase()) { // Normalize status
      case 'accepted': title = "Order Accepted"; message = "Start preparing. Mark 'Ready/Assign' when done."; icon = Icons.check_circle_outline; break;
      case 'preparing': title = "Order Preparing"; message = "Mark 'Ready/Assign' once ready."; icon = Icons.kitchen_outlined; break;
      case 'ready for pickup': title = "Ready for Pickup"; message = "Order available for any rider."; icon = Icons.inventory_2_outlined; break;
      case 'assigned': title = "Rider Assigned"; message = "Assigned rider notified."; icon = Icons.person_pin_circle_outlined; break;
      case 'dispatched': title = "Order Dispatched"; message = "Order dispatched."; icon = Icons.local_shipping_outlined; break;
      case 'out for delivery': title = "Out for Delivery"; message = "Rider is en route."; icon = Icons.two_wheeler_rounded; break;
      case 'delivered': title = "Order Delivered"; message = "Order completed."; icon = Icons.done_all; break;
      case 'completed': title = "Order Completed"; message = "Order is completed."; icon = Icons.celebration_outlined; break;
      case 'cancelled': title = "Order Cancelled"; message = "Order has been cancelled."; icon = Icons.cancel_outlined; break;
      default: title = "Order Updated"; message = "Order status updated to '$newStatus'."; icon = Icons.info_outline;
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(children: [Icon(icon, color: primaryTeal), const SizedBox(width: 8), Text(title)]),
      content: Text(message), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: drawer.AppDrawer(invokedBy: 'producer_dashboard'),
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        backgroundColor: primaryTeal, elevation: 2.0, iconTheme: const IconThemeData(color: textOnTeal),
        title: Text(_getAppBarTitle(), style: const TextStyle(color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: false,
        actions: [
          if (_currentIndex == 1) // Earnings tab
            IconButton(
              icon: _isLoadingPayments ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: whiteColor, strokeWidth: 2)) : const Icon(Icons.refresh),
              tooltip: 'Refresh Earnings',
              onPressed: _isLoadingPayments ? null : _fetchPayments,
            )
          else // Other tabs
            IconButton(
              icon: _isRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: whiteColor, strokeWidth: 2)) : const Icon(Icons.refresh),
              tooltip: 'Refresh Data',
              onPressed: _isRefreshing ? null : () => _fetchAllData(forceRefresh: true),
            ),
        ],
      ),
      body: _buildBodyContent(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index != _currentIndex && mounted) {
            _onTabChanged(index); 
          }
        },
        backgroundColor: whiteColor.withOpacity(0.98), selectedItemColor: primaryTeal,
        unselectedItemColor: subtleText.withOpacity(0.9),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10), type: BottomNavigationBarType.fixed, elevation: 8.0,
        items: [
          _buildBottomNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 0),
          _buildBottomNavItem(Icons.attach_money, Icons.attach_money_outlined, 'Earnings', 1),
          _buildBottomNavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Stock', 2),
        ],
      ),
    );
  }

  BottomNavigationBarItem _buildBottomNavItem(IconData icon, IconData activeIcon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavItemIcon(isSelected ? activeIcon : icon, isSelected), label: label,
    );
  }

  Widget _buildNavItemIcon(IconData iconData, bool isSelected) {
    final icon = Icon(iconData, color: isSelected ? primaryTeal : subtleText.withOpacity(0.8), size: 24);
    return SizedBox(width: 32, height: 32, child: Center(child: icon));
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0: return 'Manage Orders';
      case 1: return 'Earnings';
      case 2: return 'Manage Stock';
      default: return 'Producer Dashboard';
    }
  }

  Widget _buildBodyContent() {
    if (_isLoading && _orders.isEmpty && _produce.isEmpty && _error.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty) {
      return _buildErrorView();
    }

    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildOrdersTab(),
        _buildEarningsTab(),
        _buildProduceTab(),
      ],
    );
  }

  Widget _buildEarningsTab() {
    if (_payments.isEmpty && !_isLoadingPayments && !_hasPaymentError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchPayments();
      });
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayPayments = _payments.where((p) {
      final paymentDate = DateTime(p.createdAt.year, p.createdAt.month, p.createdAt.day);
      return paymentDate.isAtSameMomentAs(today);
    }).toList();
    
    final todayTotal = todayPayments.fold(0.0, (sum, p) => sum + p.amount);
    final totalEarnings = _payments.fold(0.0, (sum, p) => sum + p.amount);

    Widget content;
    
    if (_isLoadingPayments && _payments.isEmpty) {
      content = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryTeal),
            SizedBox(height: 16),
            Text('Loading your earnings...', style: TextStyle(color: textOnWhite)),
          ],
        ),
      );
    } else if (_hasPaymentError) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildErrorView(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchPayments,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryTeal,
              foregroundColor: textOnTeal,
            ),
          ),
        ],
      );
    } else if (_payments.isEmpty) {
      content = _buildEmptyState(
        'No Earnings Yet',
        'Your earnings will appear here when you receive payments.',
        icon: Icons.attach_money,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: primaryTeal.withOpacity(0.2), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today\'s Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textOnWhite,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatCard(
                        'Today\'s Earnings',
                        'UGX ${todayTotal.toStringAsFixed(0)}',
                        Icons.attach_money,
                        primaryTeal,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Orders',
                        '${todayPayments.length}',
                        Icons.receipt,
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Total Earnings',
                          'UGX ${totalEarnings.toStringAsFixed(0)}',
                          Icons.account_balance_wallet,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Payment History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textOnWhite,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ProducerEarningsHistoryScreen(payments: _payments),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _fetchPayments,
          color: primaryTeal,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style:
                      TextStyle(fontSize: 12, color: textOnWhite.withOpacity(0.8)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(String title, String message, {IconData? icon}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textOnWhite),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              onPressed: () => _currentIndex == 1 ? _fetchPayments() : _fetchAllData(forceRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryTeal,
                foregroundColor: textOnTeal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Card(
      color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(25.0), child: Column(
        mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: errorColor, size: 48), const SizedBox(height: 16),
          Text(_error.isNotEmpty ? _error : "An unknown error occurred.", style: const TextStyle(color: textOnWhite, fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18), label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => _fetchAllData(forceRefresh: true),
          ),
        ],
      )),
    )));
  }

  Widget _buildFilterChips() {
    const List<String> statusOptions = [
      'All', 'Pending', 'Accepted', 'Assigned', 'Picked Up', 'Verification Needed',
      'Completed', 'Delivered', 'Cancelled', 'Ready for Pickup', 
      'Out for Delivery'
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: statusOptions.map((status) {
          final isSelected = _selectedStatusFilter == status;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(status),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedStatusFilter = status;
                  });
                }
              },
              backgroundColor: Colors.white,
              selectedColor: faintLightTeal,
              labelStyle: TextStyle(
                fontSize: 13,
                color: isSelected ? darkTeal : subtleText,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: BorderSide(
                  color: isSelected ? primaryTeal.withOpacity(0.7) : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrdersTab() {
    if (_isLoadingOrders && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty && _orders.isEmpty) {
      return _buildErrorView();
    }

    final List<Order> filteredOrders;
    if (_selectedStatusFilter == 'All') {
      filteredOrders = _orders;
    } else if (_selectedStatusFilter == 'Delivered' || _selectedStatusFilter == 'Completed') {
      filteredOrders = _orders
          .where((order) =>
              order.orderStatus.toLowerCase() == 'delivered' ||
              order.orderStatus.toLowerCase() == 'completed')
          .toList();
    } else {
      filteredOrders = _orders
          .where((order) =>
              order.orderStatus.toLowerCase() == _selectedStatusFilter.toLowerCase())
          .toList();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true),
      color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildFilterChips(),
          const SizedBox(height: 16.0),
          if (filteredOrders.isNotEmpty)
            _buildOrdersListSection(filteredOrders)
          else if (!_isLoadingOrders && _error.isEmpty)
            _buildEmptyState(
                'No Orders Found', 
                'No orders match the filter "$_selectedStatusFilter".',
                icon: Icons.filter_alt_off_outlined)
          else if (_error.isNotEmpty && filteredOrders.isEmpty)
            _buildErrorView()
        ],
      ),
    );
  }

  Widget _buildOrdersListSection(List<Order> ordersToDisplay) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ordersToDisplay.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: (index == ordersToDisplay.length - 1) ? 0 : 12.0),
        child: _buildOrderItem(ordersToDisplay[index]),
      ),
    );
  }
  
  // --- NEW: Helper widget to display bulk order details ---
  Widget _buildBulkOrderDetailsSection(BuildContext context, BulkOrderDetails details) {
    final textTheme = Theme.of(context).textTheme;
    final shortDateFormat = DateFormat('EEE, MMM d');
    
    final formattedDays = details.planSelectedDays.isNotEmpty
        ? details.planSelectedDays
            .map((d) => shortDateFormat.format(d))
            .join(', ')
        : 'No specific days selected.';

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        decoration: BoxDecoration(
            color: faintLightTeal.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: lightTeal, width: 1),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                    children: [
                        const Icon(Icons.calendar_month_outlined, size: 18, color: darkTeal),
                        const SizedBox(width: 8),
                        Text("Meal Plan Details", style: textTheme.titleSmall?.copyWith(color: darkTeal, fontWeight: FontWeight.bold)),
                    ],
                ),
                const Divider(height: 16, thickness: 0.5, color: lightTeal),
                if (details.planStartDate != null)
                    _buildOrderDetailItem('Starts', DateFormat.yMMMMd().format(details.planStartDate!)),
                if (details.planEndDate != null)
                    _buildOrderDetailItem('Ends', DateFormat.yMMMMd().format(details.planEndDate!)),
                if (details.planSelectedDays.isNotEmpty)
                      _buildOrderDetailItem('Delivery Days', formattedDays),
            ],
        ),
    );
  }

  Widget _buildOrderItem(Order order) {
    final DateFormat dateFormat = DateFormat('MMM d, hh:mm a');
    final statusColor = _getStatusColor(order.orderStatus);
    final statusIcon = _getStatusIcon(order.orderStatus);
    return Card(
      margin: EdgeInsets.zero, elevation: 0, color: whiteColor.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(color: primaryTeal.withOpacity(0.3), width: 1),
      ),
      child: ExpansionTile(
        key: PageStorageKey<int>(order.orderId),
        tilePadding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 8.0),
        childrenPadding: EdgeInsets.zero,
        expandedAlignment: Alignment.topLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        maintainState: true,
        initiallyExpanded: _expandedOrders[order.orderId] ?? false,
        onExpansionChanged: (expanded) {
          if (mounted) {
            setState(() {
              _expandedOrders[order.orderId] = expanded;
            });
          }
        },
        iconColor: subtleText,
        collapsedIconColor: subtleText,
        leading: Tooltip(message: order.orderStatus, child: CircleAvatar(
          radius: 18, backgroundColor: statusColor.withOpacity(0.15),
          child: Icon(statusIcon, color: statusColor, size: 18),
        )),
        title: Row(
          children: [
            Expanded(child: Text(order.mealName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite), maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (order.isBulkOrder)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Chip(
                  label: const Text('Meal Plan'),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  labelStyle: const TextStyle(fontSize: 10, color: darkTeal, fontWeight: FontWeight.w600),
                  backgroundColor: lightTeal.withOpacity(0.7),
                  side: BorderSide.none,
                ),
              ),
          ],
        ),
        subtitle: Padding(padding: const EdgeInsets.only(top: 3.0), child: Text('#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}', style: const TextStyle(fontSize: 12, color: subtleText))),
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(NumberFormat.currency(symbol: 'UGX ', decimalDigits: 0).format(order.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: darkTeal, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${order.quantity} item${order.quantity > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: subtleText)),
        ]),
        children: [
          Divider(height: 1, color: dividerColor.withOpacity(0.7)),
          Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (order.isBulkOrder && order.bulkOrderDetails != null)
              _buildBulkOrderDetailsSection(context, order.bulkOrderDetails!),

            _buildOrderDetailItem('Customer', order.customerName ?? 'Unknown'),
            _buildOrderDetailItem('Status', order.orderStatus, color: statusColor),
            _buildOrderDetailItem('Payment', order.paymentStatus ?? 'Unknown'),
            if (order.notes != null && order.notes!.isNotEmpty) _buildOrderDetailItem('Notes', order.notes!),
            if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) _buildOrderDetailItem('Delivery To', order.deliveryAddress!),
            if (order.assignedRiderId != null) 
              _buildOrderDetailItem('Assigned Rider', '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}', color: assignedColor),
            
            if (order.complementaryMeals != null && order.complementaryMeals!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1.0),
                      child: Icon(Icons.cases_outlined, size: 18, color: subtleText),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complementary Meals',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: textOnWhite,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...order.complementaryMeals!.map((meal) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (_getStringSafe(meal['image']) != null && _getStringSafe(meal['image'])!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4.0),
                                      child: Image.network(
                                        _getStringSafe(meal['image'])!,
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          width: 28, height: 28, color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image, size: 16, color: subtleText),
                                        ),
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return SizedBox(
                                            width: 28, height: 28,
                                            child: Center(child: CircularProgressIndicator(
                                              strokeWidth: 2, 
                                              color: primaryTeal,
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                  : null,
                                            )),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    '${_getStringSafe(meal['name']) ?? 'Unnamed Meal'} (${_getStringSafe(meal['price']) ?? '0'})',
                                    style: const TextStyle(fontSize: 12, color: subtleText),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 12),
            _buildOrderActions(order),
          ])),
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

  Widget _buildOrderActions(Order order) {
    List<Widget> buttons = [];
    String status = order.orderStatus;
    bool canCancel = ![
      Order.STATUS_DELIVERED.toLowerCase(), 
      Order.STATUS_COMPLETED.toLowerCase(), 
      Order.STATUS_CANCELLED.toLowerCase(), 
      Order.STATUS_OUT_FOR_DELIVERY.toLowerCase(), 
      Order.STATUS_DISPATCHED.toLowerCase(),
      'picked up',
      'verification needed'
    ].contains(status.toLowerCase());
    
    if (canCancel) {
      buttons.add(_actionButton('Cancel', () => _showRejectConfirmation(order), isDestructive: true));
    } else if (status.toLowerCase() == 'verification needed') {
      buttons.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0), 
        child: Text("Needs verification from rider or user", style: TextStyle(fontSize: 12, color: Colors.teal[700], fontWeight: FontWeight.w500))
      ));
    }

    switch (status.toLowerCase()) {
      case 'pending': 
        buttons.add(_actionButton('Accept', () => _updateSimpleOrderStatus(order, 'accepted'))); 
        break;
      case 'accepted': 
      case 'preparing': 
        buttons.add(_actionButton('Ready / Assign', () => _handleReadyForShipping(order), isPrimary: true)); 
        break;
      case 'ready for pickup': 
        buttons.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0), 
          child: Text("Waiting for rider...", style: TextStyle(fontSize: 12, color: subtleText, fontStyle: FontStyle.italic))
        ));
        buttons.add(_actionButton('Assign Specific', () => _handleReadyForShipping(order))); 
        break;
      case 'assigned': 
        buttons.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0), 
          child: Text("Rider Assigned", style: TextStyle(fontSize: 12, color: assignedColor, fontWeight: FontWeight.w500))
        )); 
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8.0, runSpacing: 8.0, alignment: WrapAlignment.end, children: buttons);
  }

  Widget _actionButton(String label, VoidCallback onPressed, {bool isPrimary = false, bool isDestructive = false}) {
    Color bgColor = actionButtonBackground; Color fgColor = actionButtonForeground;
    if (isPrimary) { bgColor = primaryTeal; fgColor = textOnTeal; }
    else if (isDestructive) { bgColor = destructiveButtonBackground; fgColor = destructiveButtonForeground; }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: bgColor, foregroundColor: fgColor, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), elevation: isPrimary ? 1 : 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      child: Text(label),
    );
  }

  Widget _buildProduceTab() {
    if (_isLoadingProduce && _produce.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty && _produce.isEmpty) {
      return _buildErrorView();
    }
    
    return Stack(
      children: [
        RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: () => _fetchAllData(forceRefresh: true),
          color: primaryTeal,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _buildStockSelectionSection(),
            ],
          ),
        ),
        
        if (_selectedProduceIds.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _updateProducerStock,
                icon: const Icon(Icons.update, size: 20),
                label: const Text('UPDATE STOCK', style: TextStyle(letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryTeal,
                  foregroundColor: textOnTeal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStockSelectionSection() {
    if (_produce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      return _buildEmptyState('No Produce Items Found', 'No produce items available to manage stock.', icon: Icons.eco_outlined);
    }
    if (_error.isNotEmpty && _produce.isEmpty) return _buildErrorView();
    return _buildProduceListForStock();
  }

  Widget _buildProduceListForStock() {
    final availableProduce = _produce.where((p) => !p.produceId.startsWith('TEMP_')).toList();
    if (availableProduce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      return _buildEmptyState("No Produce Items", "No produce items available to manage stock.", icon: Icons.inventory_2_outlined);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12.0, left: 8.0, right: 8.0),
          child: Text("Toggle Items in Stock", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal)),
        ),
        Card(
          elevation: 1.5,
          color: whiteColor.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: availableProduce.length,
            itemBuilder: (context, index) {
              final product = availableProduce[index];
              final bool isInStock = _selectedProduceIds.contains(product.produceId);
              
              return Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      product.produceName,
                      style: const TextStyle(fontSize: 14, color: textOnWhite, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      isInStock ? 'In Stock (Qty: ${_produceQuantities[product.produceId] ?? 1})' : 'Out of Stock',
                      style: TextStyle(
                        fontSize: 12,
                        color: isInStock ? Colors.green.shade700 : subtleText,
                      ),
                    ),
                    value: isInStock,
                    onChanged: (bool value) {
                      setState(() {
                        if (value) {
                          _selectedProduceIds.add(product.produceId);
                          _produceQuantities[product.produceId] = 1;
                        } else {
                          _selectedProduceIds.remove(product.produceId);
                          _produceQuantities.remove(product.produceId);
                        }
                      });
                    },
                    activeColor: primaryTeal,
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                  if (index < availableProduce.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 16,
                      endIndent: 16,
                      color: dividerColor.withOpacity(0.5),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case Order.STATUS_PENDING: return pendingColor;
      case 'accepted': return acceptedColor;
      case 'preparing': return preparingColor;
      case 'ready for pickup': return readyForPickupColor;
      case 'assigned': return assignedColor;
      case 'dispatched': return dispatchedColor;
      case 'out for delivery': return outForDeliveryColor;
      case 'delivered': return deliveredColor;
      case 'completed': return completedColor;
      case 'cancelled': return cancelledColor;
      default: return defaultStatusColor;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case Order.STATUS_PENDING: return Icons.pending_actions_outlined;
      case 'accepted': return Icons.check_circle_outline_rounded;
      case 'preparing': return Icons.kitchen_outlined;
      case 'ready for pickup': return Icons.inventory_2_outlined;
      case 'assigned': return Icons.person_pin_circle_outlined;
      case 'dispatched': return Icons.local_shipping_outlined;
      case 'out for delivery': return Icons.two_wheeler_rounded;
      case 'delivered': return Icons.done_all_rounded;
      case 'completed': return Icons.celebration_outlined;
      case 'cancelled': return Icons.cancel_outlined;
      default: return Icons.help_outline_rounded;
    }
  }
} 

class _RiderSelectionDialog extends StatefulWidget {
  final int orderId;
  const _RiderSelectionDialog({required this.orderId});
  @override
  _RiderSelectionDialogState createState() => _RiderSelectionDialogState();
}

class _RiderSelectionDialogState extends State<_RiderSelectionDialog> {
  List<Rider> _allRiders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() { super.initState(); _fetchRiders(); }

  Future<void> _fetchRiders() async {
    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final riders = await ProducerApiService.fetchAvailableRiders();
      if (mounted) {
        riders.sort((a, b) {
          if (a.isActive && !b.isActive) return -1; if (!a.isActive && b.isActive) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        setState(() { _allRiders = riders; _isLoading = false; });
      }
    } catch (e) {
      debugPrint("[ProducerDash] Error fetching riders in dialog: $e");
      if (mounted) setState(() { _errorMessage = "Error fetching riders: ${e.toString().split('Body:')[0]}"; _isLoading = false; });
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
      content: SizedBox(width: double.maxFinite, height: MediaQuery.of(context).size.height * 0.5, child: _buildContent()),
      actions: <Widget>[
        TextButton(child: const Text("Mark Ready for Any Rider"), onPressed: () => Navigator.of(context).pop(true)),
        TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop(null)),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: primaryTeal));
    if (_errorMessage != null) return Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_errorMessage!, style: const TextStyle(color: errorColor), textAlign: TextAlign.center),
      const SizedBox(height: 10), ElevatedButton(onPressed: _fetchRiders, child: const Text("Retry"))
    ])));
    if (_allRiders.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text("No riders found.", textAlign: TextAlign.center)));
    return ListView.builder(
      itemCount: _allRiders.length,
      itemBuilder: (context, index) {
        final rider = _allRiders[index]; final bool isAvailable = rider.isActive;
        final Color tileColor = isAvailable ? Theme.of(context).dialogBackgroundColor : Colors.grey.shade200;
        final Color textColor = isAvailable ? textOnWhite : Colors.grey.shade600;
        final Color iconColor = isAvailable ? primaryTeal : Colors.grey.shade500;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4), elevation: isAvailable ? 1 : 0.5, color: tileColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0), side: isAvailable ? BorderSide.none : BorderSide(color: Colors.grey.shade300)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(Icons.two_wheeler, color: iconColor, size: 20)),
            title: Row(
              children: [
                Text(rider.name, style: TextStyle(color: textColor, fontWeight: isAvailable ? FontWeight.normal : FontWeight.w300)),
                if (rider.distanceKm != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${rider.distanceKm!.toStringAsFixed(1)} km)',
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              isAvailable ? 'Status: Active (${rider.status})' : 'Status: Inactive (${rider.status})',
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11),
            ),
            trailing: isAvailable ? const Icon(Icons.chevron_right) : const Icon(Icons.block, color: Colors.grey, size: 18),
            onTap: () => Navigator.of(context).pop(rider), dense: true,
          ),
        );
      },
    );
  }
}