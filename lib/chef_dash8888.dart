//cspell:disable
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:zinzi/app_drawer_unified.dart' as drawer;
import 'package:zinzi/notifications/notification_widget.dart';
import 'package:zinzi/transooter_dash_before_mapbox.dart' show Payment;
import 'package:zinzi/chef_verification_helper.dart';
import 'package:zinzi/utils/image_utils.dart';

// --- Consistent Color Palette ---
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

// --- Status Constants for consistent use throughout the app ---
const String statusPending = 'Pending';
const String statusAccepted = 'Accepted';
const String statusPreparing = 'Preparing';
const String statusReadyForPickup = 'Ready for Pickup';
const String statusAssigned = 'Assigned';
const String statusOutForDelivery = 'Out for Delivery';
const String statusDelivered = 'Delivered';
const String statusCancelled = 'Cancelled';
const String statusRejected = 'Rejected';
const String statusShipped = 'Shipped';
const String statusCompleted = 'Completed';
const String statusVerificationNeeded = 'Verification Needed';

String get _apibaseurl {
  try {
    return dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';
  } catch (e) {
    print(
        "Error accessing dotenv for API_BASE_URL-intranet. Ensure dotenv.load() was called. Using fallback. Error: $e");
    return 'https://api.example.com';
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
  final List<Map<String, dynamic>>? complementaryMeals;

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
    this.complementaryMeals,
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

    List<Map<String, dynamic>>? _parseComplementaryMeals(dynamic value) {
      if (value == null || value is! List) return null;
      try {
        return List<Map<String, dynamic>>.from(value);
      } catch (e) {
        print('Error parsing complementary meals: $e');
        return null;
      }
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
      complementaryMeals: _parseComplementaryMeals(json['complementary_meals']),
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
      mealId: _getStringSafe(json['Meal_id'] ?? json['meal_id'] ?? json['id']) ??
          'N/A_ID',
      mealName:
          _getStringSafe(json['Meal_name'] ?? json['meal_name'] ?? json['name']) ??
              'N/A',
      mealDescription: _getStringSafe(json['Meal_description'] ??
          json['meal_description'] ??
          json['description']),
      imageLink:
          _isValidUrl(_getStringSafe(json['Image_link'] ?? json['image_link'] ?? json['image']))
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

  // Fetches chef profile, primarily to get the current 'stock'
  static Future<Map<String, dynamic>> fetchChefProfile() async {
    final chefId = await _getChefId();
    if (chefId == null) {
      throw Exception('Chef ID not found. Please log in again.');
    }
    final uri = Uri.parse('$_staticBaseUrl/rr/rchefs/$chefId');
    print("[API] Fetching chef profile from: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          return data.first as Map<String, dynamic>;
        }
        if (data is Map<String, dynamic>) {
          return data;
        }
        throw Exception('Unexpected profile data format.');
      } else {
        throw Exception(
            'Failed to load chef profile (Status code: ${response.statusCode})');
      }
    } on TimeoutException {
      throw Exception('Request timed out while fetching profile.');
    } catch (e) {
      throw Exception('Failed to load chef profile: $e');
    }
  }

  // Sends a PATCH request to update the chef's stock
  static Future<bool> updateChefStock(Map<String, dynamic> updateData) async {
    final chefId = await _getChefId();
    if (chefId == null) {
      throw Exception("Chef ID not found. Cannot update stock.");
    }
    
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/chefs/$chefId');
    final headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    
    print("[API] Updating chef stock for chef $chefId at $uri");
    print("[API] Payload: ${jsonEncode(updateData)}");

    try {
      final response = await http.patch(
        uri,
        headers: headers,
        body: jsonEncode(updateData),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        print("[API] Stock update successful: ${response.body}");
        return true;
      } else {
        print("[API] Error updating stock: ${response.statusCode} ${response.body}");
        return false;
      }
    } on TimeoutException {
      throw Exception("Request timed out. Please try again.");
    } catch (e) {
      print("[API] Exception updating stock: $e");
      rethrow;
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
      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));
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
    Map<String, String> headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
    };
    return headers;
  }

  static Future<bool> updateOrderStatus(int orderId, String newStatus,
      {int? chefId, String? completionCode}) async {
    final Uri uri = Uri.parse('$_staticBaseUrl/rr/orders/$orderId/status');
    debugPrint('[API] Updating order $orderId status to: $newStatus');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('user_phone');

      final Map<String, dynamic> body = {
        'order_status': newStatus,
        if (userPhone != null) 'restaurant_phone': userPhone,
      };
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
        String apiErrorMsg = "Failed to update order status.";
        try {
          final errorBody = json.decode(response.body);
          if (errorBody is Map && errorBody.containsKey('message')) {
            apiErrorMsg = errorBody['message'];
          }
        } catch (_) {}
        throw Exception(apiErrorMsg);
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
    final Uri uri =
        Uri.parse('$_staticBaseUrl/rr/orders/$orderId/status');
    print(
        "Assigning order $orderId to rider $riderId, setting status to $newStatus");

    try {
      final prefs = await SharedPreferences.getInstance();
      final userPhone = prefs.getString('user_phone');

      final Map<String, dynamic> requestBody = {
        'order_status': newStatus,
        'transporter_id': riderId,
        if (userPhone != null) 'restaurant_phone': userPhone,
      };

      final response = await http
          .patch(
            uri,
            headers: _getWriteHeaders(),
            body: jsonEncode(requestBody),
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

// --- MISSING WIDGET RESTORED HERE ---
class CachedImageWithShimmer extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;
  final double iconSize;
  final String? errorText;

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  Widget _buildErrorWidget(
      BuildContext context, Color baseColor, Color highlightColor) {
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
                errorText!,
                style: textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
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
    const Color primaryTextColorValue = darkTeal;
    const Color secondaryTextColorValue = Color(0xFF455A64);
    const Color iconColorValue = primaryTeal;
    const Color dividerColorValue = lightTeal;
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
            elevation: 0, // Set elevation to 0 for a flat look
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              // Add a thin, teal border
              side: const BorderSide(color: lightTeal, width: 1.0),
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
            bodyLarge:
                TextStyle(color: primaryTextColorValue, fontSize: 16, height: 1.4),
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
            errorStyle:
                TextStyle(color: Colors.redAccent[700]?.withOpacity(0.9), fontSize: 11.5),
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
          dividerTheme:
              const DividerThemeData(color: dividerColorValue, thickness: 0.8, space: 24),
          iconTheme: const IconThemeData(color: iconColorValue, size: 22),
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(color: primaryTeal),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 4,
            contentTextStyle: const TextStyle(color: whiteColor),
          )),
      home: const ChefDashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ... (Rest of the code is unchanged from the version with the stock management UI)
// ... ChefDashboardScreen, OrdersTab, GigsTab, EarningsTab etc. ...

// ... (This code is exactly as provided in the previous "full code" response)
// Make sure to include the modified ProductsTab from that same response.
// --- START of previous full code (from ChefDashboardScreen down) ---
class ChefDashboardScreen extends StatefulWidget {
  const ChefDashboardScreen({super.key});
  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen>
    with TickerProviderStateMixin {
  // Add route observer for tracking page visibility
  final RouteObserver<PageRoute> _routeObserver = RouteObserver<PageRoute>();
  late TabController _tabController;
  late AnimationController _refreshIconController;
  bool _isRefreshing = false;

  final GlobalKey<_OrdersTabState> _ordersTabKey = GlobalKey<_OrdersTabState>();
  final GlobalKey<_GigsTabState> _gigsTabKey = GlobalKey<_GigsTabState>();
  final GlobalKey<_ProductsTabState> _productsTabKey =
      GlobalKey<_ProductsTabState>();
  final GlobalKey<_EarningsTabState> _earningsTabKey =
      GlobalKey<_EarningsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _tabController.addListener(_handleTabChangeForPolling);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleTabChangeForPolling();
    });
  }

  void _handleTabChangeForPolling() {
    final ordersTab = _ordersTabKey.currentState;
    final gigsTab = _gigsTabKey.currentState;

    if (ordersTab != null) {
      ordersTab._ordersPollingTimer?.cancel();
    }
    if (gigsTab != null) {
      gigsTab._gigsPollingTimer?.cancel();
    }

    bool pollingNow = false;
    switch (_tabController.index) {
      case 0:
        if (ordersTab != null) {
          ordersTab._startOrdersPolling();
          pollingNow = true;
        }
        break;
      case 1:
        if (gigsTab != null) {
          gigsTab._startGigsPolling();
          pollingNow = true;
        }
        break;
    }

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
            final state = _ordersTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 1:
            final state = _gigsTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 2:
            final state = _productsTabKey.currentState;
            if (state != null && state.mounted) {
              await state.manualRefreshFromAppBar();
              didRefresh = true;
            }
            break;
          case 3:
            final state = _earningsTabKey.currentState;
            if (state != null && state.mounted) {
              await state.refreshEarningsTab();
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
          NotificationWidget(
            key: ValueKey('chef_dashboard_notifications'),
            iconColor: Colors.white,
            showCounter: true,
            targetUserType: 'chef',
          ),
        ],
        bottom: TabBar(
          isScrollable: false,
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
            Tab(icon: Icon(Icons.work_outline_rounded), text: 'Gigs'),
            Tab(icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu/Stock'),
            Tab(icon: Icon(Icons.attach_money_outlined), text: 'Earnings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OrdersTab(key: _ordersTabKey),
          GigsTab(key: _gigsTabKey),
          ProductsTab(key: _productsTabKey),
          EarningsTab(key: _earningsTabKey),
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
    with AutomaticKeepAliveClientMixin, RouteAware {
  final Set<int> _loadingOrderIds = {};

  Future<List<Order>>? _ordersFuture;
  List<Order> _allFetchedOrders = [];
  List<Order> _mealOrders = [];
  String _selectedFilter = 'All';
  bool _isLoadingOrders = false;
  bool _didLoadOrders = false;

  final List<String> _orderStatusesForFilter = [
    'All',
    statusPending,
    statusAccepted,
    statusAssigned,
    'Picked Up',
    statusVerificationNeeded,
    statusDelivered,
    statusCompleted,
    statusCancelled,
    statusPreparing,
    statusReadyForPickup,
    statusOutForDelivery,
  ];

  Timer? _ordersPollingTimer;

  @override
  bool get wantKeepAlive => true;

  void _startOrdersPolling() {
    if (!_isRouteActive) return;

    _ordersPollingTimer?.cancel();
    _ordersPollingTimer =
        Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || !_isRouteActive) return;
      await _pollOrdersStatus();
    });
  }

  Future<void> _pollOrdersStatus() async {
    try {
      final fetchedOrders = await ApiService().fetchOrders();
      if (!mounted) return;
      for (final fetched in fetchedOrders) {
        final idx =
            _mealOrders.indexWhere((o) => o.orderId == fetched.orderId);
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
    // Cancel any active polling timers
    _ordersPollingTimer?.cancel();
    _ordersPollingTimer = null;
    
    // Unsubscribe from route observer
    final route = ModalRoute.of(context);
    if (route != null && context.mounted) {
      final routeObserver = context.findAncestorStateOfType<_ChefDashboardScreenState>()?._routeObserver;
      if (routeObserver != null) {
        routeObserver.unsubscribe(this);
      }
    }
    
    // Clear any pending operations
    _isRouteActive = false;
    
    super.dispose();
  }

  @override
  void didPush() {
    super.didPush();
    _isRouteActive = true;
    _startOrdersPolling();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _isRouteActive = true;
    _startOrdersPolling();
  }

  @override
  void didPop() {
    _isRouteActive = false;
    _ordersPollingTimer?.cancel();
    super.didPop();
  }

  @override
  void didPushNext() {
    _isRouteActive = false;
    _ordersPollingTimer?.cancel();
    super.didPushNext();
  }

  bool _isRouteActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      RouteObserver<PageRoute>? routeObserver =
          context.findAncestorStateOfType<_ChefDashboardScreenState>()?._routeObserver;
      routeObserver?.subscribe(this, route as PageRoute);
    }

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
      builder: (BuildContext context) =>
          _RiderSelectionDialog(apiService: ApiService(), orderId: order.orderId),
    );
    if (!mounted || result == null) {
      if (result == null) print('Rider assignment cancelled or dialog closed.');
      return;
    }

    if (result is Rider) {
      await _showRiderAssignmentConfirmation(order, result);
    } else if (result == true) {
      await _markReadyForAnyRider(order);
    }
  }

  Future<void> _showRiderAssignmentConfirmation(Order order, Rider rider) async {
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
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary)),
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
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('An error occurred assigning rider.');
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
      if (allIndex != -1) {
        _allFetchedOrders[allIndex].orderStatus = statusReadyForPickup;
        _allFetchedOrders[allIndex].assignedRiderId = null;
        _allFetchedOrders[allIndex].assignedRiderName = null;
      }
    });
    _showLoadingSnackbar("Marking order as ready...");

    try {
      bool success =
          await ApiService.updateOrderStatus(order.orderId, statusReadyForPickup);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar(
              'Order ${order.orderId} marked as Ready for Pickup.');
          _showOrderNextStepDialog(statusReadyForPickup);
        } else {
          _showErrorSnackbar(
              'Failed to mark order ${order.orderId} as Ready for Pickup.');
          setState(() {
            _mealOrders[orderIndex].orderStatus = originalStatus;
            if (allIndex != -1)
              _allFetchedOrders[allIndex].orderStatus = originalStatus;
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('Error updating order status.');
        setState(() {
          _mealOrders[orderIndex].orderStatus = originalStatus;
          if (allIndex != -1)
            _allFetchedOrders[allIndex].orderStatus = originalStatus;
        });
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
          setState(() {
            _mealOrders[orderIndex].orderStatus = originalStatus;
            if (allIndex != -1)
              _allFetchedOrders[allIndex].orderStatus = originalStatus;
            // Potentially revert rider info if applicable
          });
          _showErrorSnackbar(
              'Failed to update order ${order.orderId} status.');
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
        setState(() {
          _mealOrders[orderIndex].orderStatus = originalStatus;
          if (allIndex != -1)
            _allFetchedOrders[allIndex].orderStatus = originalStatus;
        });
        _showErrorSnackbar('Error updating order status: ${e.toString()}');
      }
    }
  }

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
      _showCompletionCodeVerificationDialog(context, order, targetStatus);
    } catch (e) {
      setState(() => _loadingOrderIds.remove(orderId));
      _showErrorSnackbar('Error updating order status: ${e.toString()}');
    }
  }

  void _showCompletionCodeVerificationDialog(
      BuildContext context, Order order, String targetStatus) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _CompletionCodeDialog(
          order: order,
          targetStatus: targetStatus,
          onSuccess: () {},
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
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
    final statuses = _orderStatusesForFilter;
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
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
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
          if (isExpanding &&
              order.orderStatus.toLowerCase() ==
                  statusVerificationNeeded.toLowerCase()) {
            _initiateCompletionFlow(order, statusDelivered);
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
            child: Text('#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
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
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 10),
          _buildDetailRow(context, Icons.person_outline_rounded, 'Customer ID',
              order.userId?.toString() ?? 'N/A'),
          _buildDetailRow(
              context, Icons.storefront_outlined, 'Producer', order.producerName),
          _buildDetailRow(context, Icons.shopping_bag_outlined, 'Quantity',
              order.quantity.toString()),
          _buildDetailRow(context, Icons.payment_rounded, 'Payment',
              '${order.paymentStatus} (${order.totalPrice})'),
          _buildDetailRow(context, Icons.location_on_outlined, 'Delivery To',
              order.deliveryAddress),
          _buildDetailRow(context, Icons.restaurant_outlined,
              'Ingredients Req.', order.ingredients),
          _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
          if (order.complementaryMeals != null &&
              order.complementaryMeals!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7.0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.card_giftcard_rounded,
                    size: 18,
                    color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Complementary Meals',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      ...order.complementaryMeals!.map((meal) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (meal['image'] != null &&
                                    meal['image'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: CachedImageWithShimmer(
                                      imageUrl: meal['image']?.toString(),
                                      width: 28,
                                      height: 28,
                                      borderRadius: 4.0,
                                      errorIcon: Icons.fastfood_outlined,
                                      iconSize: 16,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    '${meal['name'] ?? 'Meal'} (${meal['price'] ?? 'N/A'})',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ]),
            ),
          if (order.assignedRiderId != null)
            _buildDetailRow(context, Icons.two_wheeler_rounded, 'Assigned Rider',
                '${order.assignedRiderName ?? 'Rider ID: ${order.assignedRiderId}'}'),
          const SizedBox(height: 16),
          _buildActionButtons(
              context, order, handleReadyForShipping, updateSimpleStatus),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Order order,
      Function(Order) handleReadyForShipping, Function(Order, String) updateSimpleStatus) {
    final currentStatus = order.orderStatus.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;

    final canAccept = currentStatus == statusPending.toLowerCase();
    final canReadyOrAssign = currentStatus == statusPreparing.toLowerCase() ||
        currentStatus == statusAccepted.toLowerCase();
    final canReject = currentStatus != statusDelivered.toLowerCase() &&
        currentStatus != statusCompleted.toLowerCase() &&
        currentStatus != statusCancelled.toLowerCase() &&
        currentStatus != statusOutForDelivery.toLowerCase() &&
        currentStatus != statusAssigned.toLowerCase() &&
        currentStatus != 'picked up' &&
        order.assignedRiderId == null;
    final canMarkDelivered = (currentStatus == statusOutForDelivery.toLowerCase() ||
            currentStatus == statusAssigned.toLowerCase() ||
            currentStatus == statusReadyForPickup.toLowerCase()) &&
        currentStatus != statusDelivered.toLowerCase() &&
        currentStatus != statusCompleted.toLowerCase() &&
        order.orderStatus.toLowerCase() != statusDelivered.toLowerCase() &&
        order.orderStatus.toLowerCase() != statusCompleted.toLowerCase();
    final canMarkCompleted = (currentStatus == statusDelivered.toLowerCase() ||
            currentStatus == statusOutForDelivery.toLowerCase()) &&
        currentStatus != statusCompleted.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            if (canAccept)
              TextButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Accept'),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.green.shade700),
                  onPressed: () => updateSimpleStatus(order, statusAccepted)),
            if (canReadyOrAssign)
              Tooltip(
                  message: 'Mark Ready for Pickup or Assign Specific Rider',
                  child: TextButton.icon(
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Text('Ready/Assign'),
                      style:
                          TextButton.styleFrom(foregroundColor: readyForPickupColor),
                      onPressed: () => handleReadyForShipping(order))),
            if (canMarkDelivered)
              TextButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Mark Complete / Delivered'),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.green.shade700),
                  onPressed: () =>
                      _initiateCompletionFlow(order, statusDelivered)),
            if (canMarkCompleted)
              TextButton.icon(
                  icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                  label: const Text('Mark Completed / Delivered'),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700),
                  onPressed: () =>
                      _initiateCompletionFlow(order, statusCompleted)),
            if (canReject)
              TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel'),
                  style: TextButton.styleFrom(foregroundColor: colorScheme.error),
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
                    child: Text("Cancel Order",
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error)),
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
            size: 18, color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
        const SizedBox(width: 12),
        Expanded(
            child: RichText(
                text: TextSpan(style: textTheme.bodyMedium, children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
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
        ElevatedButton(child: const Text('Submit Code'), onPressed: _submitCode),
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
            Navigator.of(context).pop();
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
            onPressed: () => Navigator.of(context).pop(true)),
        TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(null)),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null)
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(8.0),
              child:
                  Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: _fetchRiders, child: const Text("Retry"))
              ])));
    if (_allRiders.isEmpty)
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("No riders/staff found.",
                  textAlign: TextAlign.center)));

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
        final Color iconColor = isAvailable ? primaryTeal : Colors.grey.shade500;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0, // Flat style
          color: tileColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              // Apply border consistently
              side: BorderSide(
                  color: isAvailable ? lightTeal : Colors.grey.shade300,
                  width: 1.0)),
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
                : Icon(Icons.block, color: Colors.grey.shade500, size: 18),
            onTap: () => Navigator.of(context).pop(rider),
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

class _GigsTabState extends State<GigsTab>
    with AutomaticKeepAliveClientMixin, RouteAware {
  final Set<int> _loadingOrderIds = {};

  @override
  bool get wantKeepAlive => true;

  Future<List<Order>>? _ordersFuture;
  List<Order> _allFetchedOrders = [];
  List<Order> _gigOrders = [];
  bool _isLoadingGigs = false;
  String? _errorMessage;
  bool _didLoadGigs = false;
  final Map<int, String> _previousGigStatuses = {};

  Timer? _gigsPollingTimer;
  bool _isVerificationProcessActive = false;

  @override
  void initState() {
    super.initState();
    _startGigsPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route != null) {
      RouteObserver<PageRoute>? routeObserver =
          context.findAncestorStateOfType<_ChefDashboardScreenState>()?._routeObserver;
      routeObserver?.subscribe(this, route as PageRoute);
    }

    // Load orders if not already loaded
    if (!_didLoadGigs) {
      _didLoadGigs = true;
      _loadOrders();
    }
  }

  @override
  void dispose() {
    // Cancel any active polling timers
    _gigsPollingTimer?.cancel();
    _gigsPollingTimer = null;
    
    // Unsubscribe from route observer
    final route = ModalRoute.of(context);
    if (route != null && context.mounted) {
      final routeObserver = context.findAncestorStateOfType<_ChefDashboardScreenState>()?._routeObserver;
      if (routeObserver != null) {
        routeObserver.unsubscribe(this);
      }
    }
    
    // Clear any pending operations
    _isRouteActive = false;
    
    super.dispose();
  }

  bool _isRouteActive = false;

  @override
  void didPush() {
    super.didPush();
    _isRouteActive = true;
    _startGigsPolling();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _isRouteActive = true;
    _startGigsPolling();
  }

  @override
  void didPop() {
    _isRouteActive = false;
    _gigsPollingTimer?.cancel();
    super.didPop();
  }

  @override
  void didPushNext() {
    _isRouteActive = false;
    _gigsPollingTimer?.cancel();
    super.didPushNext();
  }

  void _startGigsPolling() {
    if (!_isRouteActive) return;

    _gigsPollingTimer?.cancel();
    _gigsPollingTimer =
        Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || !_isRouteActive || _isVerificationProcessActive) return;
      await _pollGigsStatus();
    });
  }

  Future<void> _pollGigsStatus() async {
    try {
      final fetchedOrders = await ApiService().fetchOrders();
      if (!mounted) return;
      final newGigOrders = fetchedOrders
          .where((o) => o.orderType?.toLowerCase() == 'gig')
          .toList()
        ..sort((a, b) => b.orderDate.compareTo(a.orderDate));
      final Map<int, String> newStatusMap = {
        for (final o in newGigOrders) o.orderId: o.orderStatus
      };
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
          _previousGigStatuses..clear()..addAll(newStatusMap);
        });
      }
    } catch (_) {}
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
      builder: (BuildContext context) =>
          _RiderSelectionDialog(apiService: ApiService(), orderId: order.orderId),
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

  Future<void> _showRiderAssignmentConfirmation(Order order, Rider rider) async {
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
                              style:
                                  TextStyle(color: Colors.orange.shade800))),
                  ]),
              actions: <Widget>[
                TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(dialogContext).pop(false)),
                TextButton(
                    child: Text(
                        rider.isActive ? 'Confirm Assignment' : 'Assign Anyway'),
                    style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.primary),
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
    final originalStatus = _gigOrders[orderIndex].orderStatus;
    final originalRiderId = _gigOrders[orderIndex].assignedRiderId;
    final originalRiderName = _gigOrders[orderIndex].assignedRiderName;
    final allIndex =
        _allFetchedOrders.indexWhere((o) => o.orderId == order.orderId);
    setState(() {
      _gigOrders[orderIndex].orderStatus = statusAssigned;
      _gigOrders[orderIndex].assignedRiderId = rider.id;
      _gigOrders[orderIndex].assignedRiderName = rider.name;
      if (allIndex != -1) {
        _allFetchedOrders[allIndex].orderStatus = statusAssigned;
        _allFetchedOrders[allIndex].assignedRiderId = rider.id;
        _allFetchedOrders[allIndex].assignedRiderName = rider.name;
      }
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
          setState(() {
            _gigOrders[orderIndex].orderStatus = originalStatus;
            _gigOrders[orderIndex].assignedRiderId = originalRiderId;
            _gigOrders[orderIndex].assignedRiderName = originalRiderName;
            if (allIndex != -1) {
              /* revert _allFetchedOrders too */
            }
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {
          /* Revert */
        });
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
      _gigOrders[orderIndex].orderStatus = statusReadyForPickup;
      _gigOrders[orderIndex].assignedRiderId = null;
      _gigOrders[orderIndex].assignedRiderName = null;
      if (allIndex != -1) {
        /* update _allFetchedOrders */
      }
    });
    _showLoadingSnackbar("Marking Gig as Ready...");
    try {
      bool success =
          await ApiService.updateOrderStatus(order.orderId, statusReadyForPickup);
      _dismissLoadingSnackbar();
      if (mounted) {
        if (success) {
          _showSuccessSnackbar("Gig ${order.orderId} marked as Ready.");
          _showOrderNextStepDialog(statusReadyForPickup);
        } else {
          _showErrorSnackbar('Failed to mark Gig Ready.');
          setState(() {
            /* Revert */
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        _showErrorSnackbar('Error marking Gig Ready.');
        setState(() {
          /* Revert */
        });
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
          setState(() {
            /* Revert */
          });
        }
      }
    } catch (e) {
      _dismissLoadingSnackbar();
      if (mounted) {
        setState(() {
          /* Revert */
        });
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
      bool success =
          await ApiService.updateOrderStatus(orderId, targetStatus, chefId: chefId);
      if (!mounted) return;
      setState(() => _loadingOrderIds.remove(orderId));
      if (success) {
        if (!mounted) return;
        _showSuccessSnackbar('Gig #$orderId marked as $targetStatus.');
        // Refresh to reflect changes
        _loadOrders();
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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _CompletionCodeDialog(
          order: order,
          targetStatus: targetStatus,
          onSuccess: () {
            // Refresh gigs list to show updated status
            _loadOrders();
          },
          onError: (String errorMessage) {
            // Error is shown inline in dialog
          },
          showLoadingCallback: (String message) {
            if (mounted) _showLoadingSnackbar(message);
          },
          dismissLoadingCallback: () {
            if (mounted) _dismissLoadingSnackbar();
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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green.shade600));
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
    /* ... Same as OrdersTab, but messages adjusted for Gigs ... */
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
        break;
      case statusAssigned:
        title = "Staff Assigned!";
        message = "Assigned person notified for this gig.";
        break;
      case statusOutForDelivery:
        title = "Gig In Progress";
        message = "Service is underway.";
        break;
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                margin:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
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
                                width:
                                    MediaQuery.of(context).size.width * 0.4,
                                height: 14,
                                color: whiteColor)
                          ])),
                      const SizedBox(width: 16),
                      Container(
                          width: 80,
                          height: 25,
                          decoration: BoxDecoration(
                              color: whiteColor,
                              borderRadius: BorderRadius.circular(15)))
                    ])))));
  }

  Widget _buildErrorState(String errorMsg) {
    /* ... Same as OrdersTab ... */
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Theme.of(context).colorScheme.error, size: 50),
                  const SizedBox(height: 16),
                  Text('Error Loading Gigs',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.error),
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
                ])));
  }

  Widget _buildEmptyState(String message) {
    /* ... Same as OrdersTab, maybe different icon ... */
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_off_outlined,
                      size: 60, color: Colors.grey[400]),
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
                ])));
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
        if (snapshot.hasError &&
            _gigOrders.isEmpty &&
            _errorMessage == null)
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

  Widget _buildOrderCard(BuildContext context, Order order,
      {required Function(Order) handleReadyForShipping,
      required Function(Order, String) updateSimpleStatus}) {
    final textTheme = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a',
        Localizations.localeOf(context).toString());
    final statusColor = _getStatusColor(order.orderStatus);
    final statusIcon = _getStatusIcon(order.orderStatus);

    bool isVerificationPending =
        order.orderStatus.toLowerCase() == statusVerificationNeeded.toLowerCase();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<int>(order.orderId),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        leading: CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.15),
            child: Icon(statusIcon, color: statusColor, size: 22)),
        title: Text(order.mealName,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: Text('#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
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
                          Theme.of(context).colorScheme.primary))),
            ),
          _buildStatusChip(order.orderStatus),
        ]),
        onExpansionChanged: (isExpanding) async {
          if (isExpanding && isVerificationPending) {
            try {
              setState(() => _isVerificationProcessActive = true);
              final bool verified =
                  await ChefVerificationHelper.showVerificationDialog(
                      context, order);
              if (verified && mounted) {
                await ChefVerificationHelper.updateOrderStatusAfterVerification(
                    order.orderId, statusCompleted);
                _showSuccessSnackbar(
                    'Gig #${order.orderId} verified and marked as completed!');
                _loadOrders();
              }
            } catch (e) {
              if (mounted)
                _showErrorSnackbar('Verification failed: ${e.toString()}');
            } finally {
              if (mounted) setState(() => _isVerificationProcessActive = false);
            }
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildDetailRow(
                  context, Icons.person_outline, 'Customer', order.customerName),
              _buildDetailRow(context, Icons.location_on_outlined, 'Location',
                  order.deliveryAddress),
              _buildDetailRow(context, Icons.list_alt_rounded, 'Requirements',
                  order.ingredients),
              _buildDetailRow(context, Icons.notes_rounded, 'Notes', order.notes),
              if (order.assignedRiderId != null)
                _buildDetailRow(
                    context,
                    Icons.badge_outlined,
                    'Assigned Staff',
                    order.assignedRiderName ?? 'ID: ${order.assignedRiderId}'),
              const SizedBox(height: 16),
              _buildActionButtons(
                  context, order, handleReadyForShipping, updateSimpleStatus),
              const SizedBox(height: 8),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Order order,
      Function(Order) handleReadyForShipping, Function(Order, String) updateSimpleStatus) {
    final currentStatus = order.orderStatus.toLowerCase();
    final colorScheme = Theme.of(context).colorScheme;
    final isPending = currentStatus == statusPending.toLowerCase();
    final isAccepted = currentStatus == statusAccepted.toLowerCase();
    final isInProgress = currentStatus == statusPreparing.toLowerCase() ||
        currentStatus ==
            statusOutForDelivery.toLowerCase(); // 'Shipped' could also be here
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
                style:
                    TextButton.styleFrom(foregroundColor: Colors.green.shade700),
                onPressed: () => _updateGigStatus(order, statusAccepted),
              ),
            if (isAccepted)
              TextButton.icon(
                // Change to 'Start Gig' or 'Prepare'
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label:
                    const Text('Start Prep'), // Or "Start Gig" if applicable
                style: TextButton.styleFrom(
                    foregroundColor: Colors.orange.shade700),
                onPressed: () => _updateGigStatus(order,
                    statusPreparing), // Or statusShipped/OutForDelivery
              ),
            if (needsVerification)
              TextButton.icon(
                icon: const Icon(Icons.password_rounded, size: 18),
                label: const Text('Verify Completion'),
                style: TextButton.styleFrom(foregroundColor: kColorWarning),
                onPressed: () async {
                  try {
                    setState(() => _isVerificationProcessActive = true);
                    final bool verified =
                        await ChefVerificationHelper.showVerificationDialog(
                            context, order);
                    if (verified && mounted) {
                      await ChefVerificationHelper
                          .updateOrderStatusAfterVerification(
                              order.orderId, statusCompleted);
                      _showSuccessSnackbar(
                          'Gig #${order.orderId} verified and marked as completed!');
                      _loadOrders();
                    }
                  } catch (e) {
                    if (mounted)
                      _showErrorSnackbar('Verification failed: ${e.toString()}');
                  } finally {
                    if (mounted)
                      setState(() => _isVerificationProcessActive = false);
                  }
                },
              ),
            if ((isInProgress || currentStatus == statusShipped.toLowerCase()) &&
                !isCompleted &&
                !needsVerification) // If gig is in progress/shipped
              TextButton.icon(
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: const Text('Mark Completed'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade700),
                onPressed: () => _initiateCompletionFlow(order, statusCompleted),
              ),
            // Consider adding reject/cancel if business logic allows
          ]),
    );
  }

  Widget _buildDetailRow(
      BuildContext context, IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon,
            size: 18, color: Theme.of(context).iconTheme.color?.withOpacity(0.8)),
        const SizedBox(width: 12),
        Expanded(
            child: RichText(
                text: TextSpan(style: textTheme.bodyMedium, children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
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
        return Icons.construction_outlined;
      case 'ready for pickup':
        return Icons.flag_circle_outlined;
      case 'assigned':
        return Icons.badge_outlined;
      case 'shipped':
      case 'out for delivery':
        return Icons.directions_run_outlined;
      case 'delivered':
      case 'completed':
        return Icons.celebration_outlined;
      case 'verification needed':
        return Icons.password_rounded;
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

class EarningsTab extends StatefulWidget {
  const EarningsTab({Key? key}) : super(key: key);

  @override
  _EarningsTabState createState() => _EarningsTabState();
}

class ChefEarningsHistoryScreen extends StatelessWidget {
  final List<Payment> payments;

  const ChefEarningsHistoryScreen({Key? key, required this.payments})
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

    return ListView.builder(
      itemCount: sortedDates.length,
      padding: const EdgeInsets.all(8.0),
      itemBuilder: (context, index) {
        DateTime date = sortedDates[index];
        List<Payment> dailyPayments = groupedPayments[date]!;
        double dailyTotal = dailyPayments
            .where((p) => p.disbursementTransactionStatus == 'Successful')
            .fold(0.0, (sum, p) => sum + p.amount);
        String formattedDate = DateFormat('EEEE, MMM d, yyyy').format(date);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'UGX ${dailyTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                  height: 1, thickness: 0.5, color: Color(0xFFF0F0F0)),
              ...dailyPayments
                  .map((payment) => _buildPaymentItem(payment))
                  .toList(),
            ],
          ),
        );
      },
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
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Successful';
        break;
      case 'pending':
        statusColor = Colors.grey;
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
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Failed';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText =
            statusText[0].toUpperCase() + statusText.substring(1).toLowerCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                color: Colors.teal, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${payment.orderId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Status: ${payment.disbursementTransactionStatus}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'UGX ${payment.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningsTabState extends State<EarningsTab>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String _error = '';
  List<Payment> _payments = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  // Make this method public to allow refresh from parent
  Future<void> refreshEarningsTab() async {
    await _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) {
        throw Exception('User ID not found in SharedPreferences');
      }
      final response = await http.get(
        Uri.parse('$_apibaseurl/rr/disbursements/chef').replace(
          queryParameters: {'chef_id': userId},
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is List) {
          setState(() {
            _payments = data.map((p) => Payment.fromJson(p)).toList();
          });
        } else {
          setState(() {
            _error = 'Invalid payment data format';
          });
        }
      } else {
        setState(() {
          _error =
              'Failed to load payments. Status code: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double _calculateTotalEarnings() {
    return _payments
        .where((p) =>
            p.disbursementTransactionStatus.toLowerCase() == 'successful')
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  double _calculateTodaysEarnings() {
    final now = DateTime.now();
    return _payments
        .where((p) =>
            p.createdAt.year == now.year &&
            p.createdAt.month == now.month &&
            p.createdAt.day == now.day &&
            p.disbursementTransactionStatus.toLowerCase() == 'successful')
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _payments.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryTeal));
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchPayments,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final totalEarnings = _calculateTotalEarnings();
    final todayEarnings = _calculateTodaysEarnings();

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: _fetchPayments,
          color: primaryTeal,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Summary Cards
                  Row(
                    children: [
                      _buildStatCard(
                        'Today\'s Earnings',
                        'UGX ${todayEarnings.toStringAsFixed(0)}',
                        Icons.attach_money,
                        primaryTeal,
                      ),
                      const SizedBox(width: 12),
                      _buildStatCard(
                        'Total Earnings',
                        'UGX ${totalEarnings.toStringAsFixed(0)}',
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Main Card for Earnings History
                  Card(
                    elevation: 0, // Flat style
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      // Use consistent thin teal border
                      side: const BorderSide(color: lightTeal, width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Earnings History Header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(
                                0xFFE0F2F1), // Light teal background
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            border: Border.all(
                              color: const Color(
                                  0xFFB2DFDB), // Slightly darker teal border
                              width: 1.0,
                            ),
                          ),
                          child: const Text(
                            'Earnings History',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Color(0xFFF0F0F0)),
                        // Earnings Content
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: 200,
                            maxHeight: constraints.maxHeight * 0.7,
                          ),
                          child: _payments.isNotEmpty
                              ? ChefEarningsHistoryScreen(payments: _payments)
                              : _buildEmptyState(
                                  'No Payment History',
                                  'Your earnings will appear here once you start receiving payments.',
                                  icon: Icons.payment_outlined,
                                ),
                        ),
                      ],
                    ),
                  ),
                  // Add some bottom padding to ensure content isn't cut off
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
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
                      TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsTab extends StatefulWidget {
  const ProductsTab({Key? key}) : super(key: key);

  @override
  _ProductsTabState createState() => _ProductsTabState();
}

extension ProductsTabRefreshExtension on _ProductsTabState {
  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    print("ProductsTab: manualRefreshFromAppBar triggered.");
    _loadData();
    while (mounted && (_isLoadingProducts || _isUpdatingStock)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print("ProductsTab: manualRefreshFromAppBar completed.");
  }
}

class _ProductsTabState extends State<ProductsTab>
    with AutomaticKeepAliveClientMixin {
  List<MealProduct> _products = [];
  final Set<String> _inStockMealIds = {};

  bool _isLoadingProducts = true;
  bool _isUpdatingStock = false;
  bool _didLoad = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProducts = true;
      _error = null;
    });

    try {
      print('=== Starting _loadData ===');
      
      // Fetch master list of all meals and chef's current stock in parallel
      print('Fetching products and chef profile...');
      final results = await Future.wait([
        ApiService.fetchProducts(),
        ApiService.fetchChefProfile(),
      ]);

      if (!mounted) return;

      final allProducts = results[0] as List<MealProduct>;
      final chefProfileResponse = results[1] as Map<String, dynamic>;
      
      print('=== Received Chef Profile Response ===');
      print('Response keys: ${chefProfileResponse.keys.toList()}');
      
      // Check if we have a data field in the response
      final chefData = chefProfileResponse['data'];
      print('Chef data type: ${chefData?.runtimeType}');
      
      List<dynamic>? currentStock;
      
      if (chefData is Map) {
        print('Chef data keys: ${chefData.keys.toList()}');
        currentStock = chefData['stock'] as List<dynamic>?;
        print('Stock data from response: $currentStock');
      }
      
      print('=== Products Data ===');
      print('Total products: ${allProducts.length}');
      print('Current stock type: ${currentStock?.runtimeType}');
      
      if (currentStock != null) {
        print('Current stock items count: ${currentStock.length}');
        if (currentStock.isNotEmpty) {
          print('First stock item: ${currentStock.first}');
          print('First stock item type: ${currentStock.first.runtimeType}');
        }
      }

      // Clear previous selections
      _inStockMealIds.clear();
      print('\n=== Processing Stock Items ===');

      // Populate current "in stock" list from chef profile
      if (currentStock != null && currentStock is List) {
        for (var i = 0; i < currentStock.length; i++) {
          final item = currentStock[i];
          print('\nProcessing stock item $i: $item');
          
          if (item is Map) {
            print('Item $i is a Map with keys: ${item.keys.toList()}');
            
            // Case-insensitive lookup for meal_id
            final mealIdKey = item.keys.firstWhere(
              (key) => key.toString().toLowerCase() == 'meal_id',
              orElse: () => 'meal_id',
            );
            
            print('Found meal_id key: "$mealIdKey" (type: ${mealIdKey.runtimeType})');
            print('Value for $mealIdKey: ${item[mealIdKey]} (type: ${item[mealIdKey]?.runtimeType})');
            
            if (item[mealIdKey] != null) {
              final mealId = item[mealIdKey].toString();
              print('Adding to _inStockMealIds: $mealId');
              _inStockMealIds.add(mealId);
            } else {
              print('Skipping item $i: meal_id is null');
            }
          } else {
            print('Skipping item $i: Not a Map (${item.runtimeType})');
          }
        }
      } else {
        print('No stock items found or invalid format');
      }
      
      print('\n=== Current _inStockMealIds ===');
      print(_inStockMealIds);

      _products = allProducts;
      _products.sort((a, b) => a.mealName.compareTo(b.mealName));

      setState(() {
        _isLoadingProducts = false;
      });
    } catch (e, stackTrace) {
      print("Error loading products/stock: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
          _error = 'Failed to load menu. Please try again.';
        });
      }
    }
  }

  Future<void> _handleUpdateStock() async {
    if (_isUpdatingStock) return;

    setState(() => _isUpdatingStock = true);
    
    // Show loading indicator
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.removeCurrentSnackBar();
    scaffoldMessenger.showSnackBar(const SnackBar(
      content: Text('Updating stock...'),
      backgroundColor: Colors.blueGrey,
      duration: Duration(seconds: 5),
    ));

    try {
      // Create the stock update payload in the expected format
      final List<Map<String, dynamic>> stockItems = [];
      
      // Add all selected meals to stock
      for (String mealId in _inStockMealIds) {
        final meal = _products.firstWhere((p) => p.mealId == mealId);
        // Create a new map with explicit types to ensure proper JSON serialization
        final Map<String, dynamic> stockItem = {
          'Name': meal.mealName.toString(),  // Ensure it's a string
          'meal_id': meal.mealId.toString(),  // Ensure it's a string
          'price': meal.price is int ? meal.price.toDouble() : meal.price,  // Ensure it's a double
          'image': meal.imageLink.toString(),  // Ensure it's a string
          'quantity': 1.0,  // Explicitly use double
        };
        print('Adding stock item: ${jsonEncode(stockItem)}');
        stockItems.add(stockItem);
      }
      
      // Log the stock items for debugging
      print('Stock items to update: ${stockItems.map((item) => '${item['Name']} (${item['meal_id']})').join(', ')}');

      // Create the update payload with stock items
      final Map<String, dynamic> updateData = {'stock': stockItems};

      // Log the payload for debugging
      final encodedPayload = jsonEncode(updateData);
      print('Sending stock update: $encodedPayload');

      final success = await ApiService.updateChefStock(updateData);

      if (mounted) {
        scaffoldMessenger.removeCurrentSnackBar();
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text(
            success 
                ? 'Stock updated successfully!'
                : 'Failed to update stock. Please try again.',
          ),
          backgroundColor: success ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.removeCurrentSnackBar();
        _showErrorSnackbar('Error updating stock: ${e.toString()}');
        print('Error updating stock: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStock = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      // We remove the FloatingActionButton
      body: Column(
        children: [
          Expanded(
            child: _buildBody(),
          ),
          // Add a persistent "Update Stock" button at the bottom
          _buildUpdateStockButton(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingProducts) {
      return _buildProductsShimmer();
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_products.isEmpty) {
      return _buildEmptyState('No meals found in the system.');
    }
    return _buildProductList(_products);
  }

  Widget _buildProductList(List<MealProduct> productsToShow) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: Theme.of(context).colorScheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: productsToShow.length,
        itemBuilder: (context, index) =>
            _buildProductCard(context, productsToShow[index]),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, MealProduct product) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final formatCurrency =
        NumberFormat.currency(locale: 'en_UG', symbol: 'UGX ', decimalDigits: 0);
    final bool isSelected = _inStockMealIds.contains(product.mealId);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: CachedImageWithShimmer(
                imageUrl: product.imageLink,
                width: 80,
                height: 80,
                borderRadius: 8.0,
                fit: BoxFit.cover,
                errorIcon: Icons.restaurant_menu_outlined,
                iconSize: 35,
                errorText: "No Image",
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.mealName.isEmpty ? '(No Name)' : product.mealName,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
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
            // The main interactive element is now the Switch
            Switch(
              value: isSelected,
              onChanged: (bool value) {
                setState(() {
                  if (value) {
                    _inStockMealIds.add(product.mealId);
                  } else {
                    _inStockMealIds.remove(product.mealId);
                  }
                });
              },
              activeColor: primaryTeal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateStockButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        icon: _isUpdatingStock
            ? Container(
                width: 20,
                height: 20,
                padding: const EdgeInsets.all(2.0),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.check_circle_outline_rounded),
        label: Text(_isUpdatingStock ? 'UPDATING...' : 'Update Stock'),
        onPressed: _isUpdatingStock ? null : _handleUpdateStock,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4)));
  }

  Widget _buildProductsShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
        itemCount: 6,
        itemBuilder: (_, __) => Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                    width: 80,
                    height: 80,
                    color: Colors.white,
                    child: const SizedBox()),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 18, width: 200, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 14, width: 250, color: Colors.white),
                    const SizedBox(height: 4),
                    Container(height: 14, width: 150, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 16, width: 80, color: Colors.white),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
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
                onPressed: _loadData)
          ],
        ),
      ),
    );
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
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.grey[700]))
          ],
        ),
      ),
    );
  }
}