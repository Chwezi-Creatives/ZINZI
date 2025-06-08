
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

// Payment model is used in this file
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter & SystemUiOverlayStyle
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:geolocator/geolocator.dart'; // Moved to producer_profile.dart
import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart'; // Moved to producer_profile.dart
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 
// import 'package:zinzi/cache_config.dart'; // Moved to producer_profile.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/app_drawer_unified.dart' as drawer;
import 'package:zinzi/notifications/notification_provider.dart';
import 'package:zinzi/user_cache.dart'; 
import 'package:zinzi/utils/route_observer.dart';


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
        print("[ProducerDash] Error parsing date: ${json['order_date']} - $e - $e2. Using current time.");
        parsedDate = DateTime.now(); 
      }
    }
    
    List<Map<String, dynamic>>? parseComplementaryMeals(dynamic value) {
      if (value == null || value is! List) return null;
      try {
        return List<Map<String, dynamic>>.from(value);
      } catch (e) {
        print('Error parsing complementary meals: $e');
        return null;
      }
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
      );
      return order;
    } catch (e, stack) {
      print('[ProducerDash] Order parsing error: $e\n$stack');
      rethrow;
    }
  }

  Order copyWith({
    int? orderId, String? mealName, DateTime? orderDate, double? totalPrice, int? quantity,
    String? orderStatus, String? customerName, String? deliveryAddress, String? notes,
    String? ingredients, String? paymentStatus, ValueGetter<int?>? assignedRiderId,
    ValueGetter<String?>? assignedRiderName, List<Map<String, dynamic>>? complementaryMeals,
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
      print('[ProducerDash] Product parsing error: $e\n$stack');
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
              .where((p) => p.status?.toLowerCase() == 'completed')
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
    final status = payment.status?.toLowerCase() ?? 'pending';
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

  Rider({ required this.id, required this.name, required this.status, required this.isActive });

  factory Rider.fromJson(Map<String, dynamic> json) {
    final riderId = _parseIntNullable(json['rider_id'] ?? json['transporter_id'] ?? json['id']);
    final riderName = _getStringSafe(json['name'] ?? json['rider_name'] ?? json['transporter_name']);
    if (riderId == null || riderId == 0) {
      print("[ProducerDash] Warning: Rider ID is missing or invalid in JSON: $json");
    }
    return Rider(
      id: riderId ?? 0, name: riderName ?? 'Unnamed Rider',
      status: _getStringSafe(json['status']) ?? 'unknown',
      isActive: _parseBoolSafe(json['is_active']),
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
    return _parseInt(prefs.getString('producer_id')) ?? prefs.getInt('producer_id');
  }

  static dynamic _handleApiResponse(dynamic responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
      if (decoded is List || decoded is Map) return decoded;
      print("[ProducerDash] API response format warning: Decoded type is ${decoded.runtimeType}");
      return null;
    } catch (e) {
      print("[ProducerDash] API response JSON decoding error: $e");
      return null;
    }
  }

  static Future<Map<String, String>> _getReadHeaders({bool requiresAuth = false}) async {
    Map<String, String> headers = {'Accept': 'application/json'};
    if (requiresAuth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      else print("[ProducerDash] Warning: Auth required for read but no access token found.");
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
      else print("[ProducerDash] Warning: Auth required but no access token found.");
    }
    return headers;
  }

  // Profile methods (fetchProducerProfile, updateProducerStatus, updateProducerProfile, updateProducerProfileImage) removed.

  static Future<List<Order>> fetchProducerOrders() async {
    final producerId = await _getProducerId();
    if (producerId == null) throw Exception('Producer ID not found. Please log in again.');
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders?producer_id=$producerId');
    print("[ProducerDash] Fetching orders: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Order> orders = handledData.map<Order>((orderJson) => Order.fromJson(orderJson)).toList();
          print("[ProducerDash] Fetched ${orders.length} orders");
          return orders;
        } else {
          print('[ProducerDash] Orders response format error: expected List, got ${handledData?.runtimeType}. Body: ${response.body}');
          throw Exception('API response for orders was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception('Failed to load orders (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print('[ProducerDash] Orders fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    print('[ProducerDash][API] Updating order $orderId status to $newStatus');
    print('[ProducerDash][API] Endpoint: $uri');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('user_phone');
      
      final Map<String, dynamic> requestBody = {
        'order_status': newStatus,
        if (userPhone != null) 'restaurant_phone': userPhone,
      };
      
      print('[ProducerDash][API] Request body: $requestBody');
      
      final headers = await _getWriteHeaders();
      print('[ProducerDash][API] Headers: $headers');
      
      final response = await http.patch(
        uri, 
        headers: headers, 
        body: jsonEncode(requestBody)
      ).timeout(const Duration(seconds: 30));
      
      print('[ProducerDash][API] Response status: ${response.statusCode}');
      print('[ProducerDash][API] Response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        print('[ProducerDash][API] Status update successful');
        return true;
      } else {
        print('[ProducerDash][API] Status update failed with status: ${response.statusCode}');
        return false;
      }
    } on TimeoutException catch (e) {
      print('[ProducerDash][API] Request timed out: $e');
      return false;
    } on SocketException catch (e) {
      print('[ProducerDash][API] Network error: $e');
      return false;
    } catch (e, stackTrace) {
      print('[ProducerDash][API] Unexpected error:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<bool> assignOrderToRider(int orderId, int riderId, String newStatus) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/orders/$orderId/status');
    print("[ProducerDash] Assigning order $orderId to rider $riderId, status $newStatus at $uri");
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
      print("[ProducerDash] Exception assigning order: $e");
      return false;
    }
  }

  static Future<List<Rider>> fetchAvailableRiders() async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/transporters');
    print("[ProducerDash] Fetching available riders from: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Rider> riders = handledData.map<Rider?>((jsonItem) {
            try { return Rider.fromJson(jsonItem); }
            catch (e) { print("[ProducerDash] Skipping invalid rider item: $jsonItem - Error: $e"); return null; }
          }).whereType<Rider>().toList();
          print("[ProducerDash] Fetched ${riders.length} riders.");
          return riders;
        } else {
          print("[ProducerDash] Riders API response format unexpected: Expected List, got ${handledData?.runtimeType}. Body: ${response.body}");
          throw Exception('API response for riders was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception('Failed to load riders (Status code: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print("[ProducerDash] Exception fetching riders: $e\n$stack");
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
      print('[ProducerDash] Fetching payments from: $url');
      
      final headers = await _getReadHeaders(requiresAuth: false);
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 30));
      
      print('[ProducerDash] Response status: ${response.statusCode}');
      
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
          
          print('[ProducerDash] Found ${paymentsJson.length} payments');
          
          // Convert each JSON object to ProducerPayment
          final payments = <ProducerPayment>[];
          for (final json in paymentsJson) {
            try {
              if (json is Map<String, dynamic>) {
                payments.add(ProducerPayment.fromJson(json));
              }
            } catch (e) {
              print('[ProducerDash] Error parsing payment: $e');
              continue;
            }
          }
          
          return payments;
        } catch (e) {
          print('[ProducerDash] Error processing payments: $e');
          throw Exception('Failed to process payment data');
        }
      } else {
        throw Exception('Failed to load payments. Status: ${response.statusCode}');
      }
    } on SocketException catch (e) {
      print('[ProducerDash] Network error: $e');
      throw Exception('No internet connection');
    } on TimeoutException {
      print('[ProducerDash] Request timed out');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      print('[ProducerDash] Unexpected error: $e');
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
            print("[ProducerDash] Using cached produce list (${products.length} items)");
            return products;
          } catch (e) {
            print("[ProducerDash] Error parsing cached produce: $e");
          }
        }
      }
    }
    
    final Uri uri = Uri.parse('$_apibaseurl/rr/produce');
    print("[ProducerDash] Fetching fresh master produce list: $uri");
    try {
      final response = await http.get(uri, headers: await _getReadHeaders(requiresAuth: true));
      if (response.statusCode == 200) {
        final dynamic handledData = _handleApiResponse(response.body);
        if (handledData is List) {
          final List<Product> produce = handledData.map<Product>((prodJson) => Product.fromJson(prodJson)).toList();
          print("[ProducerDash] Fetched ${produce.length} produce items from API");
          try {
            final produceJson = produce.map((p) => p.toJson()).toList();
            await UserCache.saveData(_produceCacheKey, produceJson);
            await UserCache.saveData(_produceCacheTimestampKey, DateTime.now().toIso8601String());
            print("[ProducerDash] Cached ${produce.length} produce items");
          } catch (e) {
            print("[ProducerDash] Error caching produce: $e");
          }
          return produce;
        } else {
          print('[ProducerDash] Produce response format error: expected List, got ${handledData?.runtimeType}. Body: ${response.body}');
          throw Exception('API response for produce was not a list. Body: ${response.body}');
        }
      } else {
        throw Exception('Failed to fetch produce (Status: ${response.statusCode}). Body: ${response.body}');
      }
    } catch (e, stack) {
      print('[ProducerDash] Produce fetch error: $e\n$stack');
      rethrow;
    }
  }

  static Future<bool> updateProducerStock(int producerId, List<Map<String, dynamic>> stockList) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/producers/$producerId');
    print("[ProducerDash] Updating stock for producer $producerId at $uri");
    final payload = jsonEncode({"stock": stockList});
    print("[ProducerDash] Stock update payload: $payload");
    try {
      final response = await http.patch(uri, headers: await _getWriteHeaders(), body: payload);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("Exception updating stock: $e");
      return false;
    }
  }

  static Future<Product?> addProduce(Map<String, dynamic> produceData) async {
    final Uri uri = Uri.parse('$_apibaseurl/rr/produce');
    print("[ProducerDash] Adding new produce item at $uri");
    try {
      final payload = {
        'produce_name': _getStringSafe(produceData['produce_name']),
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': _getStringSafe(produceData['source']),
      };
      payload.removeWhere((key, value) => value == null || (value is String && value.isEmpty));
      if (payload['produce_name'] == null || (payload['produce_name'] as String).isEmpty) {
        print("[ProducerDash] Error adding produce: Produce name is required.");
        return null;
      }
      print("[ProducerDash] Add produce payload: ${jsonEncode(payload)}");
      final response = await http.post(uri, headers: await _getWriteHeaders(), body: jsonEncode(payload));
      if (response.statusCode == 201) {
        final dynamic createdProduceData = _handleApiResponse(response.body);
        if (createdProduceData is Map<String, dynamic>) return Product.fromJson(createdProduceData);
        else { print("[ProducerDash] Add produce succeeded but couldn't parse response body: ${response.body}"); return null; }
      } else {
        print("[ProducerDash] Error adding produce: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("[ProducerDash] Exception adding produce: $e");
      return null;
    }
  }

  static Future<bool> updateProduce(String produceId, Map<String, dynamic> produceData) async {
    if (produceId.isEmpty) { print("[ProducerDash] Error updating produce: Invalid Produce ID."); return false; }
    final Uri uri = Uri.parse('$_apibaseurl/rr/uproduce?produce_id=$produceId');
    print("[ProducerDash] Updating produce item $produceId at $uri");
    try {
      final payload = {
        'produce_name': _getStringSafe(produceData['produce_name']),
        'calories': _parseIntNullable(produceData['calories']),
        'proteins': _parseDoubleNullable(produceData['proteins']),
        'carbohydrates': _parseDoubleNullable(produceData['carbohydrates']),
        'fats': _parseDoubleNullable(produceData['fats']),
        'unit_grams': _parseIntNullable(produceData['unit_grams']),
        'source': _getStringSafe(produceData['source']),
      };
      payload.removeWhere((key, value) => value == null || (value is String && value.isEmpty));
      if (payload['produce_name'] == null || (payload['produce_name'] as String).trim().isEmpty) {
        print("[ProducerDash] Error updating produce: Produce name cannot be empty.");
        return false;
      }
      print("[ProducerDash] Update produce payload: ${jsonEncode(payload)}");
      final response = await http.put(uri, headers: await _getWriteHeaders(), body: jsonEncode(payload));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("[ProducerDash] Exception updating produce $produceId: $e");
      return false;
    }
  }

  static Future<bool> deleteProduce(String produceId) async {
    if (produceId.isEmpty) { print("[ProducerDash] Error deleting produce: Invalid Produce ID."); return false; }
    final Uri uri = Uri.parse('$_apibaseurl/rr/uproduce?produce_id=$produceId');
    print("[ProducerDash] Deleting produce item $produceId at $uri");
    try {
      final response = await http.delete(uri, headers: await _getWriteHeaders());
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("[ProducerDash] Exception deleting produce $produceId: $e");
      return false;
    }
  }
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
      };
    }
    print("[ProducerDash] Warning: Could not serialize order of type ${order.runtimeType}");
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
    print("[ProducerDash] Warning: Could not serialize product of type ${product.runtimeType}");
    return {};
  }

  static Future<void> preloadCacheForSplash() async {
    print('[Splash][ProducerDash-Dashboard] Starting cache preload...');
    final stopwatch = Stopwatch()..start();
    try {
      // Profile preload is handled by producer_profile.dart's own static method.
      await ProducerApiService.fetchProducerOrders();
      print('[Splash][ProducerDash-Dashboard] Orders cache preloaded');
      await ProducerApiService.fetchProducerProduce();
      print('[Splash][ProducerDash-Dashboard] Produce cache preloaded');
      print('[Splash][ProducerDash-Dashboard] Cache preload completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('[Splash][ProducerDash-Dashboard] Error during cache preload: $e');
    }
  }

  const ProducerDash22({super.key});

  @override
  State<ProducerDash22> createState() => _ProducerDash22State();
}

class _ProducerDash22State extends State<ProducerDash22> with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  int _currentIndex = 0; // Default to Orders tab (index 0 after profile removal)
  // Profile related state variables removed
  List<Order> _orders = [];
  List<Product> _produce = []; 
  bool _isLoading = true; 
  // _isLoadingProfile, _profileFetchError removed
  bool _isLoadingOrders = false;
  bool _isLoadingProduce = false;
  String _error = ''; 

  Set<String> _selectedProduceIds = {};
  Map<String, int> _produceQuantities = {};
  final Map<int, bool> _expandedOrders = {}; // Track expanded state for each order

  // Profile Editing State variables removed

  String? _editingProduceId;
  TextEditingController? _produceNameController;
  TextEditingController? _produceCaloriesController;
  TextEditingController? _produceProteinsController;
  TextEditingController? _produceCarbsController;
  TextEditingController? _produceFatsController;
  TextEditingController? _produceUnitGramsController;
  TextEditingController? _produceSourceController;

  // _profileCache, _profileCacheTimestamp removed

  final GlobalKey<FormState> _produceFormKey = GlobalKey<FormState>();
  // _profileFormKey removed

  Timer? _pollingTimer;
  bool _isRefreshing = false; 
  bool _isRouteActive = false; 

  late final NotificationProvider notificationProvider;

  // Temp variable to store producer ID for stock updates, as _profile is removed.
  int? _currentProducerId;
  
  // State for earnings tab
  List<ProducerPayment> _payments = [];
  bool _isLoadingPayments = false;
  bool _hasPaymentError = false;
  // _error variable is already declared above
  
  // Fetch payments for the producer
  Future<void> _fetchPayments() async {
    if (_isLoadingPayments) {
      print('[ProducerDash] Fetch already in progress, skipping');
      return;
    }
    
    print('[ProducerDash] Starting to fetch payments');
    
    if (!mounted) {
      print('[ProducerDash] Widget not mounted, aborting');
      return;
    }
    
    setState(() {
      _isLoadingPayments = true;
      _hasPaymentError = false;
      _error = '';
    });
    
    try {
      print('[ProducerDash] Getting producer ID');
      final producerId = await ProducerApiService._getProducerIdInt();
      if (producerId == null) {
        print('[ProducerDash] No producer ID found');
        if (!mounted) return;
        setState(() {
          _hasPaymentError = true;
          _error = 'Producer ID not found. Please log in again.';
        });
        return;
      }
      
      print('[ProducerDash] Fetching payments for producer ID: $producerId');
      final payments = await ProducerApiService.fetchProducerPayments(producerId);
      
      print('[ProducerDash] Received ${payments.length} payments');
      
      if (!mounted) {
        print('[ProducerDash] Widget disposed during fetch, ignoring results');
        return;
      }
      
      setState(() {
        _payments = payments;
        _hasPaymentError = false;
        _error = '';
      });
      
      print('[ProducerDash] Payments updated in state');
      
    } catch (e, stack) {
      print('[ProducerDash] Error fetching payments: $e\n$stack');
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
      print('[ProducerDash] Finished fetch payments operation');
    }
  }


  @override
  void initState() {
    super.initState();
    // Profile text controllers removed
    notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _fetchAllData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isRouteActive = ModalRoute.of(context)?.isCurrent ?? false;
        if (_currentIndex == 0 && _isRouteActive) { // Orders tab is now index 0
          _startPolling();
        }
      }
    });
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
    if (isActive && _currentIndex == 0) { // Orders tab is now index 0
      _startPolling();
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    // Profile controllers removed
    _disposeProduceEditControllers();
    notificationProvider.removeListener(_handleNotificationRefresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isRouteActive && _currentIndex == 0) { // Orders tab is now index 0
        _startPolling();
        _fetchOrdersAndProduce();
      }
    } else if (state == AppLifecycleState.paused) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  void _handleNotificationRefresh() {
    print("[ProducerDash] Received notification refresh trigger.");
    if (!_isRefreshing && mounted) _fetchAllData(forceRefresh: true);
  }

  void _onTabChanged(int newIndex) {
    setState(() => _currentIndex = newIndex);
    
    if (!_isRouteActive) return;
    
    // Handle tab-specific logic
    if (newIndex == 0) { // Orders tab
      _startPolling();
    } else if (newIndex == 1) { // Earnings tab
      _pollingTimer?.cancel();
      _pollingTimer = null;
      if (_payments.isEmpty && !_isLoadingPayments && !_hasPaymentError) {
        _fetchPayments();
      }
    } else { // Other tabs (Produce)
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  void _startPolling() {
    if (_currentIndex != 0 || !_isRouteActive) return; // Orders tab is now index 0
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (mounted && _currentIndex == 0 && _isRouteActive && !_isRefreshing && _editingProduceId == null) {
        print("[ProducerDash] Polling for new orders...");
        _fetchOrdersAndProduce(forceRefresh: false);
      } else if (!_isRouteActive || _currentIndex != 0) {
        timer.cancel();
      }
    });
    print("[ProducerDash] Started polling for orders");
  }

  void _disposeProduceEditControllers() {
    _produceNameController?.dispose(); _produceCaloriesController?.dispose();
    _produceProteinsController?.dispose(); _produceCarbsController?.dispose();
    _produceFatsController?.dispose(); _produceUnitGramsController?.dispose();
    _produceSourceController?.dispose();
    _produceNameController = null; _produceCaloriesController = null;
    _produceProteinsController = null; _produceCarbsController = null;
    _produceFatsController = null; _produceUnitGramsController = null;
    _produceSourceController = null;
  }

  Future<void> _fetchAllData({bool forceRefresh = false}) async {
    if (!mounted || _isRefreshing) return;
    setState(() { _isLoading = true; _isRefreshing = true; _error = ''; });
    if (forceRefresh) _cancelAllEdits();

    try {
      // Fetch producer ID for stock updates
      _currentProducerId = await ProducerApiService._getProducerIdInt(); 
      // _initializeProducerProfile removed

      await _fetchOrdersAndProduce(forceRefresh: forceRefresh);
      if (mounted) {
        // Sync stock selection after data is loaded
        // This requires _profile to be loaded. Since profile is separate,
        // stock syncing logic might need adjustment or be tied to when stock tab is active
        // For now, it might not work as expected without profile directly available.
        // Decision: Stock syncing will be implicitly handled by fetching profile in its own tab.
        // This dashboard will manage its own produce list and selections,
        // but the actual "current stock" on the profile object is managed in producer_profile.dart.
        // If a producer updates stock here, it should still reflect on the profile, which means API should handle merging.
      }
    } catch (e, stackTrace) {
      debugPrint("[ProducerDash] Error fetching all data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _error = 'Failed to load data. Please check connection.';
          _orders = []; _produce = []; _selectedProduceIds.clear(); _produceQuantities.clear();
        });
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; _isRefreshing = false; });
    }
  }

  Future<void> _fetchOrdersAndProduce({bool forceRefresh = false}) async {
    print('[ProducerDash][DEBUG] Starting _fetchOrdersAndProduce. Force refresh: $forceRefresh');
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

    // Try to load from cache if not forcing refresh
    if (!forceRefresh) {
      print('[ProducerDash][CACHE] Attempting to load from cache...');
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
              print('[ProducerDash][CACHE] Parsing cached orders...');
              cachedOrdersData = (cachedOrdersJson).map<Order>((orderJson) {
                try {
                  return Order.fromJson(orderJson as Map<String, dynamic>);
                } catch (e) {
                  print('[ProducerDash][CACHE] Error parsing order: $e');
                  rethrow;
                }
              }).toList();
              ordersCacheValid = true;
              print('[ProducerDash][CACHE] Successfully parsed ${cachedOrdersData.length} orders from cache');
            } catch (e) { 
              print('[ProducerDash][CACHE] Error parsing cached orders: $e'); 
            }
          }
        }

        if (cachedProduceJson is List && cachedProduceJson.isNotEmpty && cachedProduceTs is String) {
          final cacheTime = DateTime.tryParse(cachedProduceTs);
          if (cacheTime != null) {
            try {
              print('[ProducerDash][CACHE] Parsing cached produce...');
              cachedProduceData = (cachedProduceJson).map<Product>((prodJson) {
                try {
                  return Product.fromJson(prodJson as Map<String, dynamic>);
                } catch (e) {
                  print('[ProducerDash][CACHE] Error parsing product: $e');
                  rethrow;
                }
              }).toList();
              produceCacheValid = true;
              print('[ProducerDash][CACHE] Successfully parsed ${cachedProduceData.length} products from cache');
            } catch (e) { 
              print('[ProducerDash][CACHE] Error parsing cached produce: $e'); 
            }
          }
        }

        if (mounted && (ordersCacheValid || produceCacheValid)) {
          print('[ProducerDash][CACHE] Updating UI with cached data');
          setState(() {
            if (ordersCacheValid && cachedOrdersData != null) { 
              _orders = cachedOrdersData!; 
              _sortOrders(); 
              print('[ProducerDash][CACHE] Updated ${_orders.length} orders in UI');
            }
            if (produceCacheValid && cachedProduceData != null) { 
              _produce = cachedProduceData!; 
              _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
              print('[ProducerDash][CACHE] Updated ${_produce.length} products in UI');
            }
            _isLoadingOrders = !ordersCacheValid; 
            _isLoadingProduce = !produceCacheValid;
          });
          loadedFromCache = ordersCacheValid && produceCacheValid;
          print('[ProducerDash][CACHE] Loaded from cache: $loadedFromCache');
        }
      } catch (e) {
        print('[ProducerDash][CACHE] Error during cache processing: $e');
      }
    } else {
      print('[ProducerDash][CACHE] Skipping cache - force refresh requested');
    }

    // Fetch fresh data from the server
    try {
      print('[ProducerDash][API] Fetching fresh data from server...');
      final results = await Future.wait([
        ProducerApiService.fetchProducerOrders(),
        ProducerApiService.fetchProducerProduce(),
      ], eagerError: true);
      
      if (mounted) {
        final fetchedOrders = results[0] as List<Order>;
        final fetchedProduce = results[1] as List<Product>;
        
        print('[ProducerDash][API] Fetched ${fetchedOrders.length} orders and ${fetchedProduce.length} products');
        
        setState(() {
          _orders = fetchedOrders; 
          _produce = fetchedProduce;
          _sortOrders(); 
          _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
          _isLoadingOrders = false; 
          _isLoadingProduce = false;
        });
        
        try {
          print('[ProducerDash][CACHE] Saving data to cache...');
          await Future.wait([
            UserCache.saveData(ordersKey, fetchedOrders.map((o) => ProducerDash22._serializeOrder(o)).toList()),
            UserCache.saveData(ordersTsKey, now.toIso8601String()),
            UserCache.saveData(produceKey, fetchedProduce.map((p) => ProducerDash22._serializeProduct(p)).toList()),
            UserCache.saveData(produceTsKey, now.toIso8601String()),
          ]);
          print('[ProducerDash][CACHE] Data saved to cache');
        } catch (e) {
          print('[ProducerDash][CACHE] Error saving to cache: $e');
        }
      }
    } catch (e, stackTrace) {
      print('[ProducerDash][API] Error fetching data:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
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
      print('[ProducerDash] Finished _fetchOrdersAndProduce');
    }
  }

  // _initializeProducerProfile, _fetchProducerProfileAndUpdate, _loadProfileCacheFromPrefs, _saveProfileCacheToPrefs, _updateControllersFromProfile removed

  void _sortOrders() {
    _orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
  }

  void _syncSelectionFromProfile() {
    // This method relied on _profile. Since _profile is gone from this file,
    // this specific sync logic needs to be re-evaluated.
    // For now, the selected IDs and quantities will be managed locally based on user interaction in the stock tab.
    // The actual "truth" of the stock is on the server and reflected in the producer_profile.dart.
    // When this dashboard updates stock, it calls the API.
    // When producer_profile.dart loads, it fetches the latest stock from the API.
    print("[ProducerDash] Stock sync from profile is now managed within producer_profile.dart.");
    // If we still need to initialize _selectedProduceIds and _produceQuantities from *some* source on init,
    // it would need to be from a dedicated API call or local cache if profile data isn't directly here.
    // OR, if we want to retain the old stock values from a previous session on this dashboard itself:
    // _loadStockSelectionFromCache(); // A new method to load _selectedProduceIds and _produceQuantities from UserCache.
    // This is outside the scope of "just removing profile", so I'll leave it as is for now.
  }


  Future<void> _updateSimpleOrderStatus(Order order, String newStatus) async {
    print('[ProducerDash][DEBUG] Starting order status update. Order ID: ${order.orderId}, New Status: $newStatus');
    final orderIndex = _findOrderIndex(order.orderId);
    if (orderIndex == -1) {
      print('[ProducerDash][ERROR] Order not found in local list: ${order.orderId}');
      return;
    }
    
    if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final originalStatus = _orders[orderIndex].orderStatus;
    final originalRiderId = _orders[orderIndex].assignedRiderId;
    final originalRiderName = _orders[orderIndex].assignedRiderName;
    
    print('[ProducerDash][DEBUG] Current status: $originalStatus, Will update to: $newStatus');
    
    // Update UI optimistically
    setState(() {
      _orders[orderIndex].orderStatus = newStatus;
      if ([Order.STATUS_ACCEPTED, Order.STATUS_PREPARING, Order.STATUS_CANCELLED].contains(newStatus)) {
        print('[ProducerDash][DEBUG] Clearing rider assignment for status: $newStatus');
        _orders[orderIndex] = _orders[orderIndex].copyWith(
          assignedRiderId: () => null, 
          assignedRiderName: () => null
        );
      }
      _sortOrders();
    });
    
    _showLoadingSnackbar("Updating status to $newStatus...");
    
    try {
      print('[ProducerDash][DEBUG] Calling API to update order status...');
      bool success = await ProducerApiService.updateOrderStatus(order.orderId, newStatus);
      _dismissLoadingSnackbar();
      
      if (!mounted) {
        print('[ProducerDash][DEBUG] Widget not mounted after API call, aborting');
        return;
      }
      
      if (success) {
        print('[ProducerDash][SUCCESS] Order ${order.orderId} status updated to $newStatus');
        _showSuccessSnackbar('Order ${order.orderId} status updated to $newStatus.');
        _showOrderNextStepDialog(newStatus);
        
        // Force refresh orders to ensure consistency
        _fetchOrdersAndProduce(forceRefresh: true);
      } else {
        print('[ProducerDash][ERROR] API returned failure for order ${order.orderId}');
        _showErrorSnackBar('Failed to update order ${order.orderId} status.');
        
        // Revert UI changes
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
      print('[ProducerDash][EXCEPTION] Error updating order status:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        _showErrorSnackBar('An error occurred while updating status.');
        
        // Revert UI changes
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
      print("Rider ${result.name} selected for Order ${order.orderId}. Showing confirmation...");
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      print("Marking Order ${order.orderId} as Ready for Pickup (Any Rider)");
      await _markReadyForAnyRider(order);
    } else {
      print("Rider assignment cancelled or dialog closed.");
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
      print("Confirmation received. Assigning Order ${order.orderId} to Rider ${rider.id} (${rider.name})");
      await _assignSpecificRider(order, rider);
    } else {
      print("Rider assignment cancelled by user.");
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
      print("[ProducerDash] Error assigning specific rider: $e");
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
      print("[ProducerDash] Error marking ready for any rider: $e");
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
    if (index == -1) print("[ProducerDash] Warning: Order $orderId not found in _orders list for update.");
    return index;
  }

  // Profile edit handlers removed.

  void _handleAddProduce() {
    if (_editingProduceId != null || !mounted /*|| _isEditingProfile*/) return; // _isEditingProfile check removed
    debugPrint('Add Produce Action Triggered');
    final newId = 'TEMP_${DateTime.now().millisecondsSinceEpoch}';
    final newProduct = Product(produceId: newId, produceName: '');
    _initializeProduceEditControllers(newProduct); 
    setState(() {
      _produce.add(newProduct); 
      _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
      _editingProduceId = newId; 
    });
    _showInfoSnackbar('Fill in details for the new produce item.');
  }

  void _handleEditProduce(Product product) {
    if (!mounted /*|| _isEditingProfile*/) return; // _isEditingProfile check removed
    debugPrint('Edit Produce Action Triggered for ID: ${product.produceId}');
    _cancelAllEdits(exceptProduceId: product.produceId); 
    _initializeProduceEditControllers(product); 
    setState(() => _editingProduceId = product.produceId); 
  }

  void _initializeProduceEditControllers(Product product) {
    _produceNameController = TextEditingController(text: product.produceName);
    _produceCaloriesController = TextEditingController(text: product.calories?.toString() ?? '');
    _produceProteinsController = TextEditingController(text: product.proteins?.toStringAsFixed(1) ?? '');
    _produceCarbsController = TextEditingController(text: product.carbohydrates?.toStringAsFixed(1) ?? '');
    _produceFatsController = TextEditingController(text: product.fats?.toStringAsFixed(1) ?? '');
    _produceUnitGramsController = TextEditingController(text: product.unitGrams?.toString() ?? '');
    _produceSourceController = TextEditingController(text: product.source ?? '');
  }

  Future<void> _saveProduceChanges() async {
    if (_editingProduceId == null || !mounted) return;
    if (_produceFormKey.currentState?.validate() ?? false) {
      final String idToSave = _editingProduceId!;
      final int index = _produce.indexWhere((p) => p.produceId == idToSave);
      if (index == -1) { _cancelProduceEdit(); return; }
      final bool isNewItem = idToSave.startsWith('TEMP_');
      Map<String, dynamic> payload = {
        'produce_name': _produceNameController?.text.trim(), 'calories': _produceCaloriesController?.text.trim(),
        'proteins': _produceProteinsController?.text.trim(), 'carbohydrates': _produceCarbsController?.text.trim(),
        'fats': _produceFatsController?.text.trim(), 'unit_grams': _produceUnitGramsController?.text.trim(),
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
                _produce.removeAt(index); _produce.add(addedProduct);
                _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null; _disposeProduceEditControllers();
              });
              _showSuccessSnackbar('Added "${addedProduct.produceName}".');
            } else {
              _showErrorSnackBar('Failed to add produce.');
              setState(() { _produce.removeAt(index); _editingProduceId = null; _disposeProduceEditControllers(); });
            }
          }
        } else {
          bool success = await ProducerApiService.updateProduce(idToSave, payload);
          _dismissLoadingSnackbar();
          if (mounted) {
            if (success) {
              final updatedProduct = _produce[index].copyWith(
                produceName: payload['produce_name'], calories: () => _parseIntNullable(payload['calories']),
                proteins: () => _parseDoubleNullable(payload['proteins']), carbohydrates: () => _parseDoubleNullable(payload['carbohydrates']),
                fats: () => _parseDoubleNullable(payload['fats']), unitGrams: () => _parseIntNullable(payload['unit_grams']),
                source: () => payload['source'],
              );
              setState(() {
                _produce[index] = updatedProduct;
                _produce.sort((a,b) => a.produceName.toLowerCase().compareTo(b.produceName.toLowerCase()));
                _editingProduceId = null; _disposeProduceEditControllers();
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
          if (isNewItem) {
            setState(() { _produce.removeAt(index); _editingProduceId = null; _disposeProduceEditControllers(); });
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
      _editingProduceId = null; _disposeProduceEditControllers(); 
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary new produce item on cancel.");
      }
    });
  }

  // Fix method name typo and ensure it's used
  void _handleProductDelete(Product product) async { 
    if (!mounted || (_editingProduceId != null && _editingProduceId != product.produceId)) return;
    debugPrint('Delete Produce Action Triggered for ID: ${product.produceId}');
    if (product.produceId.startsWith('TEMP_')) { _cancelProduceEdit(); return; }
    showDialog(context: context, builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: whiteColor.withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      title: const Row(children: [Icon(Icons.warning_amber_rounded, color: errorColor), SizedBox(width: 10), Text('Confirm Deletion')]),
      content: Text('Permanently delete "${product.produceName}" from the system?\nThis also removes it from your stock. This cannot be undone.', style: const TextStyle(color: subtleText)),
      actions: <Widget>[
        TextButton(style: TextButton.styleFrom(foregroundColor: subtleText), child: const Text('Cancel'), onPressed: () => Navigator.of(ctx).pop()),
        ElevatedButton.icon(
          icon: const Icon(Icons.delete_forever_outlined, size: 16), label: const Text('Delete'),
          style: ElevatedButton.styleFrom(backgroundColor: destructiveButtonBackground, foregroundColor: destructiveButtonForeground, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () { Navigator.of(ctx).pop(); _performDeleteProduce(product); },
        ),
      ],
    ));
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
            _produce.removeWhere((p) => p.produceId == product.produceId);
            _selectedProduceIds.remove(product.produceId); _produceQuantities.remove(product.produceId);
            if (_editingProduceId == product.produceId) { _editingProduceId = null; _disposeProduceEditControllers(); }
          });
          _showSuccessSnackbar('Deleted "$deletedName".');
        } else {
          _showErrorSnackBar('Failed to delete "${product.produceName}".');
        }
      }
    } catch (e) {
      debugPrint("Error deleting produce via API: $e");
      _dismissLoadingSnackbar();
      if (mounted) _showErrorSnackBar('An error occurred deleting: $e');
    }
  }

  Future<void> _updateProducerStock() async {
    if (_currentProducerId == null) { // Check _currentProducerId instead of _profile
      _showErrorSnackBar('Producer ID not loaded. Cannot update stock.');
      return;
    }
    final stockList = _selectedProduceIds.map((id) {
      final quantity = _produceQuantities[id];
      if (quantity != null && quantity >= 0) return {'produce_id': id, 'quantity': quantity};
      return null;
    }).whereType<Map<String, dynamic>>().toList();
    _showLoadingSnackbar('Updating stock...');
    try {
      bool success = await ProducerApiService.updateProducerStock(_currentProducerId!, stockList); // Use _currentProducerId
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar('Stock updated successfully.');
          // Refreshing the local produce/orders list. Profile refresh is handled by its own tab.
          await _fetchOrdersAndProduce(forceRefresh: true); 
        } else {
          _showErrorSnackBar('Failed to update stock. Please try again.');
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) _showErrorSnackBar('Error connecting to server: $e');
      print("Exception updating stock: $e");
    }
  }

  void _cancelAllEdits({String? exceptProduceId}) {
    if (!mounted) return;
    bool didCancel = false;
    // _isEditingProfile check removed
    if (_editingProduceId != null && _editingProduceId != exceptProduceId) {
      final idToCancel = _editingProduceId;
      _editingProduceId = null; _disposeProduceEditControllers();
      if (idToCancel != null && idToCancel.startsWith('TEMP_')) {
        _produce.removeWhere((p) => p.produceId == idToCancel);
        debugPrint("Removed temporary produce item due to action/switch.");
      }
      didCancel = true;
    }
    if (didCancel) { setState(() {}); debugPrint("Cancelled active edits due to action/switch."); }
  }

  // _getCurrentLocation moved to producer_profile.dart

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
    // AppBar avatar logic removed as _profile is no longer here.
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
            _cancelAllEdits(); 
            setState(() => _currentIndex = index);
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
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  BottomNavigationBarItem _buildBottomNavItem(IconData icon, IconData activeIcon, String label, int index) {
    // Adjust index mapping if necessary due to profile tab removal. 
    // The `index` parameter here refers to the new, 0-based index of the remaining tabs.
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
      // Case 0 for Profile removed
      case 0: return 'Manage Orders'; // Was index 1
      case 1: return 'Earnings';
      case 2: // Was index 2
        return _editingProduceId != null
            ? (_editingProduceId!.startsWith("TEMP_") ? 'Add Produce Item' : 'Edit Produce Item')
            : 'Manage Stock & Produce';
      default: return 'Producer Dashboard';
    }
  }

  Widget? _buildFloatingActionButton() {
    if (/*_isEditingProfile ||*/ _editingProduceId != null) return null; // _isEditingProfile check removed

    switch (_currentIndex) {
      // Case 0 for Profile FAB removed
      case 0: return null; // Orders Tab (was index 1)
      case 1: return null; // Earnings Tab
      case 2: // Produce/Stock Tab (was index 2)
        if (_selectedProduceIds.isNotEmpty) {
          return FloatingActionButton.extended(
            onPressed: _updateProducerStock, tooltip: 'Update Stock Levels',
            icon: const Icon(Icons.update), label: const Text("Update Stock"),
            backgroundColor: darkTeal, foregroundColor: textOnTeal, heroTag: 'fab_stock_update',
          );
        } else {
          return FloatingActionButton(
            onPressed: _handleAddProduce, tooltip: 'Add New Produce Item',
            backgroundColor: primaryTeal, foregroundColor: textOnTeal,
            child: const Icon(Icons.add), heroTag: 'fab_produce_add',
          );
        }
      default: return null;
    }
  }

  Widget _buildBodyContent() {
    if (_isLoading && /*_profile == null &&*/ _orders.isEmpty && _produce.isEmpty && _error.isEmpty /*&& _profileFetchError.isEmpty*/) {
      // _profile and _profileFetchError checks removed
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty /*&& _profile == null*/) { // _profile check removed
      return _buildErrorView();
    }
    // _profileFetchError check removed

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
    // Fetch payments when the tab is first built
    if (_payments.isEmpty && !_isLoadingPayments && !_hasPaymentError) {
      print('[EarningsTab] Triggering initial payments fetch');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('[EarningsTab] Post-frame callback: fetching payments');
        _fetchPayments();
      });
    } else {
      print('[EarningsTab] Not fetching payments - ' 
          'isLoading: $_isLoadingPayments, '
          'hasError: $_hasPaymentError, '
          'paymentCount: ${_payments.length}');
    }

    // Prepare today's data
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
      print('[EarningsTab] Showing loading indicator');
      content = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryTeal),
            SizedBox(height: 16),
            Text('Loading your earnings...', 
                 style: TextStyle(color: textOnWhite)),
          ],
        ),
      );
    } else if (_hasPaymentError) {
      print('[EarningsTab] Showing error view: $_error');
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
      print('[EarningsTab] Showing empty state');
      content = _buildEmptyState(
        'No Earnings Yet',
        'Your earnings will appear here when you receive payments.',
        icon: Icons.attach_money,
      );
    } else {
      print('[EarningsTab] Showing ${_payments.length} payments');
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Today's Earnings Card
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
          // All Earnings History
          Text(
            'Payment History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textOnWhite,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: textOnWhite.withOpacity(0.8),
                  ),
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
              onPressed: () => _fetchPayments(),
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

  // _buildProfileTab, _buildProfileErrorView, _buildProfileDisplayView, _buildProfileEditView, 
  // _buildProfileSectionCard, _buildDetailItem (profile version), _buildEditableItem (profile version) removed.

  Widget _buildOrdersTab() {
    if (_isLoadingOrders && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }
    if (_error.isNotEmpty /*&& _profileFetchError.isEmpty*/ && _orders.isEmpty) { // _profileFetchError check removed
      return _buildErrorView();
    }
    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true), color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0), physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_orders.isNotEmpty) _buildOrdersListSection()
          else if (!_isLoadingOrders && _error.isEmpty) 
            _buildEmptyState('No Orders Yet', 'New customer orders will appear here.', icon: Icons.receipt_long_outlined)
          else if (_error.isNotEmpty && _orders.isEmpty) _buildErrorView()
        ],
      ),
    );
  }

  Widget _buildOrdersListSection() {
    return ListView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _orders.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: (index == _orders.length - 1) ? 0 : 12.0),
        child: _buildOrderItem(_orders[index]),
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
        title: Text(order.mealName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(padding: const EdgeInsets.only(top: 3.0), child: Text('#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}', style: const TextStyle(fontSize: 12, color: subtleText))),
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(NumberFormat.currency(symbol: 'UGX ', decimalDigits: 0).format(order.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: darkTeal, fontSize: 13)),
          const SizedBox(height: 2),
          Text('${order.quantity} item${order.quantity > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: subtleText)),
        ]),
        children: [
          Divider(height: 1, color: dividerColor.withOpacity(0.7)),
          Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildOrderDetailItem('Customer', order.customerName ?? 'Unknown'),
            _buildOrderDetailItem('Status', order.orderStatus, color: statusColor),
            _buildOrderDetailItem('Payment', order.paymentStatus ?? 'Unknown'),
            if (order.notes != null && order.notes!.isNotEmpty) _buildOrderDetailItem('Notes', order.notes!),
            if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) _buildOrderDetailItem('Delivery To', order.deliveryAddress!),
            if (order.assignedRiderId != null) 
              _buildOrderDetailItem('Assigned Rider', '${order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'}', color: assignedColor),
            
            // --- MODIFIED SECTION START ---
            // Display complementary meals if any, with improved styling and robustness
            if (order.complementaryMeals != null && order.complementaryMeals!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon on the left
                    Padding(
                      padding: const EdgeInsets.only(top: 1.0), // Align icon with text
                      child: Icon(Icons.cases_outlined, size: 18, color: subtleText),
                    ),
                    const SizedBox(width: 12),
                    // Title and list of meals on the right
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Complementary Meals',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: textOnWhite,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // List of meals
                          ...order.complementaryMeals!.map((meal) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Image
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
                                // Meal Name and Price
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
            // --- MODIFIED SECTION END ---

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
    bool canCancel = ![Order.STATUS_DELIVERED.toLowerCase(), Order.STATUS_COMPLETED.toLowerCase(), Order.STATUS_CANCELLED.toLowerCase(), Order.STATUS_OUT_FOR_DELIVERY.toLowerCase(), Order.STATUS_DISPATCHED.toLowerCase()].contains(status.toLowerCase());
    if (canCancel) buttons.add(_actionButton('Cancel', () => _showRejectConfirmation(order), isDestructive: true));

    switch (status.toLowerCase()) {
      case 'pending': buttons.add(_actionButton('Accept', () => _updateSimpleOrderStatus(order, 'accepted'))); break;
      case 'accepted': case 'preparing': buttons.add(_actionButton('Ready / Assign', () => _handleReadyForShipping(order), isPrimary: true)); break;
      case 'ready for pickup': 
        buttons.add(const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text("Waiting for rider...", style: TextStyle(fontSize: 12, color: subtleText, fontStyle: FontStyle.italic))));
        buttons.add(_actionButton('Assign Specific', () => _handleReadyForShipping(order))); break;
      case 'assigned': buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Text("Rider Assigned", style: TextStyle(fontSize: 12, color: assignedColor, fontWeight: FontWeight.w500)))); break;
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
    if (_error.isNotEmpty /*&& _profileFetchError.isEmpty*/ && _produce.isEmpty) { // _profileFetchError check removed
      return _buildErrorView();
    }
    return RefreshIndicator(
      onRefresh: () => _fetchAllData(forceRefresh: true), color: primaryTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0), physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_editingProduceId != null) _buildProduceEditSection() else _buildStockSelectionSection(),
          if (_editingProduceId != null) const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStockSelectionSection() {
    if (_produce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      return _buildEmptyState('No Produce Items Found', 'Tap the (+) button below to add the first produce item.', icon: Icons.eco_outlined);
    }
    if (_error.isNotEmpty && _produce.isEmpty) return _buildErrorView();
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
    return _buildProduceEditForm(productToEdit);
  }

  Widget _buildProduceListForStock() {
    final availableProduce = _produce.where((p) => !p.produceId.startsWith('TEMP_')).toList();
    if (availableProduce.isEmpty && !_isLoadingProduce && _error.isEmpty) {
      return _buildEmptyState("No Produce Items Defined", "Add produce items using the (+) button first.", icon: Icons.inventory_2_outlined);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 12.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Select Available Stock", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkTeal)),
        if (_selectedProduceIds.isNotEmpty) TextButton(onPressed: () => setState(() { _selectedProduceIds.clear(); _produceQuantities.clear(); }), child: const Text("Clear All", style: TextStyle(fontSize: 12, color: subtleText))),
      ])),
      Card(
        elevation: 1.5, color: whiteColor.withOpacity(0.9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: ListView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: availableProduce.length,
          itemBuilder: (context, index) {
            final product = availableProduce[index]; final bool isSelected = _selectedProduceIds.contains(product.produceId);
            return Column(children: [
              CheckboxListTile(
                title: Text(product.produceName, style: const TextStyle(fontSize: 14, color: textOnWhite)),
                subtitle: product.unitGrams != null ? Text("${product.calories ?? '-'} kcal / ${product.unitGrams}g", style: const TextStyle(fontSize: 11, color: subtleText)) : null,
                value: isSelected,
                onChanged: (bool? selected) => setState(() {
                  if (selected == true) { _selectedProduceIds.add(product.produceId); _produceQuantities.putIfAbsent(product.produceId, () => 1); }
                  else { _selectedProduceIds.remove(product.produceId); _produceQuantities.remove(product.produceId); }
                }),
                controlAffinity: ListTileControlAffinity.leading, dense: true, activeColor: primaryTeal,
                secondary: IconButton(icon: Icon(Icons.edit_note_outlined, size: 20, color: subtleText), tooltip: 'Edit Produce Item Details', onPressed: () => _handleEditProduce(product)),
              ),
              if (isSelected) Padding(padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 12.0), child: Row(children: [
                const Text("Quantity:", style: TextStyle(fontSize: 13, color: subtleText)), const SizedBox(width: 12),
                SizedBox(width: 80, height: 40, child: TextFormField(
                  key: ValueKey(product.produceId), initialValue: _produceQuantities[product.produceId]?.toString() ?? '1',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10), border: OutlineInputBorder(), hintText: "0", hintStyle: TextStyle(fontSize: 13)),
                  style: const TextStyle(fontSize: 14, color: textOnWhite), inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (val) => setState(() { final parsed = int.tryParse(val) ?? 0; _produceQuantities[product.produceId] = parsed >= 0 ? parsed : 0; }),
                  validator: (v) => (v == null || v.isEmpty || (int.tryParse(v) ?? -1) < 0) ? 'Invalid' : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                )),
                const Spacer(),
              ])),
              if (index < availableProduce.length - 1) Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16, color: dividerColor.withOpacity(0.5)),
            ]);
          },
        )),
      ),
    ]);
  }

  Widget _buildProduceEditForm(Product product) {
    final bool isNewItem = product.produceId.startsWith('TEMP_');
    return Card(
      elevation: 3.0, color: whiteColor.withOpacity(0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0), side: const BorderSide(color: primaryTeal, width: 1.5)),
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(padding: const EdgeInsets.all(16.0), child: Form(key: _produceFormKey, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text(isNewItem ? 'Add New Produce Item' : 'Edit "${product.produceName}"', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkTeal)),
          const SizedBox(height: 16),
          TextFormField(controller: _produceNameController, decoration: _inputDecoration('Produce Name *'), style: const TextStyle(fontSize: 14, color: textOnWhite), validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null, autovalidateMode: AutovalidateMode.onUserInteraction),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _produceCaloriesController, decoration: _inputDecoration('Calories (kcal)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceUnitGramsController, decoration: _inputDecoration('Unit (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _produceProteinsController, decoration: _inputDecoration('Proteins (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceCarbsController, decoration: _inputDecoration('Carbs (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(controller: _produceFatsController, decoration: _inputDecoration('Fats (g)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [_decimalInputFormatter(1)], validator: _validateOptionalNumber, autovalidateMode: AutovalidateMode.onUserInteraction)),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _produceSourceController, decoration: _inputDecoration('Source URL (optional)'), style: const TextStyle(fontSize: 14, color: textOnWhite), keyboardType: TextInputType.url, maxLines: 1, validator: (v) => (v != null && v.isNotEmpty && (Uri.tryParse(v) == null || !Uri.tryParse(v)!.isAbsolute)) ? 'Invalid URL' : null, autovalidateMode: AutovalidateMode.onUserInteraction),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            const Spacer(),
            TextButton(onPressed: _cancelProduceEdit, child: const Text('Cancel', style: TextStyle(color: subtleText)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8))),
            const SizedBox(width: 12),
            ElevatedButton.icon(icon: const Icon(Icons.save_outlined, size: 18), label: Text(isNewItem ? 'Add Item' : 'Save Changes'), style: ElevatedButton.styleFrom(backgroundColor: primaryTeal, foregroundColor: textOnTeal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: _saveProduceChanges),
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
      errorStyle: const TextStyle(fontSize: 11, color: errorColor),
    );
  }

  String? _validateOptionalNumber(String? value) {
    if (value != null && value.isNotEmpty) {
      if (double.tryParse(value) == null) return 'Invalid #';
      if (double.parse(value) < 0) return '>= 0';
    }
    return null;
  }

  TextInputFormatter _decimalInputFormatter(int decimalPlaces) {
    String dp = decimalPlaces > 0 ? '{0,$decimalPlaces}' : '';
    return FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d' + dp));
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
      print("[ProducerDash] Error fetching riders in dialog: $e");
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
            title: Text(rider.name, style: TextStyle(color: textColor, fontWeight: isAvailable ? FontWeight.normal : FontWeight.w300)),
            subtitle: Text(isAvailable ? 'Status: Active (${rider.status})' : 'Status: Inactive (${rider.status})', style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11)),
            trailing: isAvailable ? const Icon(Icons.chevron_right) : const Icon(Icons.block, color: Colors.grey, size: 18),
            onTap: () => Navigator.of(context).pop(rider), dense: true,
          ),
        );
      },
    );
  }
}