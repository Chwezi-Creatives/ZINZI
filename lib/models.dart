
// models.dart
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

// --- Profile Model ---
class ProducerProfile {
  final int producerId;
  final String name;
  final String? email; // Make nullable
  final String? image; // Make nullable
  final String? location; // Make nullable, format might vary
  final String? producerType; // Make nullable
  final double? rating; // Make nullable
  final String? reviews; // Make nullable
  final bool isActive; // Keep required
  final DateTime registrationDate;
  final DateTime? lastLogin; // Make nullable
  final String? phoneNumber; // Added from JSON example
  final String? userType; // Added from JSON example

  ProducerProfile({
    required this.producerId,
    required this.name,
    this.email,
    this.image,
    this.location,
    this.producerType,
    this.rating,
    this.reviews,
    required this.isActive,
    required this.registrationDate,
    this.lastLogin,
    this.phoneNumber,
    this.userType,
  });

  factory ProducerProfile.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? dateString) {
      if (dateString == null) return null;
      try {
        // Handles variations like "Sun, 16 Mar 2025 22:22:27 GMT"
        return DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'").parseUtc(dateString);
      } catch (e) {
        debugPrint("Error parsing date format 'EEE, dd MMM yyyy HH:mm:ss Z': $dateString, Error: $e");
        // Add fallbacks for other potential formats if needed
        try {
          // Example fallback: ISO 8601 format
          return DateTime.parse(dateString).toUtc();
        } catch (e2) {
           debugPrint("Error parsing date with fallback format: $dateString, Error: $e2");
           return null; // Return null if all parsing fails
        }
      }
    }

    String? parseLocation(String? locString) {
       // Simplified location parsing - assumes descriptive part is after coords
      if (locString == null || locString.trim().isEmpty) return null;
      final parts = locString.split(',');
      if (parts.length > 2) {
        // Check if first two parts look like coordinates
        final lat = double.tryParse(parts[0].trim());
        final lon = double.tryParse(parts[1].trim());
        if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
          // Join the remaining parts as the descriptive address
          return parts.sublist(2).join(',').trim();
        }
      }
      // If not parseable as lat,lon,address return the original string trimmed
      return locString.trim();
    }

    double? tryParseRating(dynamic ratingValue) {
      if (ratingValue == null) return null;
      return double.tryParse(ratingValue.toString());
    }

    // Defensive checks for required fields
    final int parsedProducerId = json['producer_id'];
    final String parsedName = json['name'] ?? 'Unnamed Producer'; // Provide default
    final bool parsedIsActive = json['is_active'] ?? false; // Provide default
    final DateTime parsedRegDate = parseDate(json['registration_date']) ?? DateTime.now().toUtc(); // Provide default

    return ProducerProfile(
      producerId: parsedProducerId,
      name: parsedName,
      email: json['email'],
      image: json['image'],
      location: parseLocation(json['location']),
      producerType: json['producer_type'],
      rating: tryParseRating(json['rating']),
      reviews: json['reviews']?.toString(),
      isActive: parsedIsActive,
      registrationDate: parsedRegDate,
      lastLogin: parseDate(json['last_login']),
      phoneNumber: json['phone_number'],
      userType: json['user_type'],
    );
  }

  // --- COPYWITH METHOD ---
  ProducerProfile copyWith({
    int? producerId,
    String? name,
    ValueGetter<String?>? email, // Use ValueGetter for nullable fields if needed
    ValueGetter<String?>? image,
    ValueGetter<String?>? location,
    ValueGetter<String?>? producerType,
    ValueGetter<double?>? rating,
    ValueGetter<String?>? reviews,
    bool? isActive,
    DateTime? registrationDate,
    ValueGetter<DateTime?>? lastLogin,
    ValueGetter<String?>? phoneNumber,
    ValueGetter<String?>? userType,
  }) {
    return ProducerProfile(
      producerId: producerId ?? this.producerId,
      name: name ?? this.name,
      email: email != null ? email() : this.email,
      image: image != null ? image() : this.image,
      location: location != null ? location() : this.location,
      producerType: producerType != null ? producerType() : this.producerType,
      rating: rating != null ? rating() : this.rating,
      reviews: reviews != null ? reviews() : this.reviews,
      isActive: isActive ?? this.isActive,
      registrationDate: registrationDate ?? this.registrationDate,
      lastLogin: lastLogin != null ? lastLogin() : this.lastLogin,
      phoneNumber: phoneNumber != null ? phoneNumber() : this.phoneNumber,
      userType: userType != null ? userType() : this.userType,
    );
  }
}


// --- Order Model ---
class Order {
  final int orderId;
  final int producerId;
  final int userId;
  final String mealName;
  final String ingredients;
  final int quantity;
  final double totalPrice;
  final String orderStatus;
  final String paymentStatus;
  final String paymentMode;
  final String deliveryAddress; // Parsed address string
  final DateTime orderDate;
  final String notes;
  final String? productId;
  final String orderType;
  // Added fields from JSON example that were missing
  final double? amountPaid;
  final String? transactionId;
  final int? chefId;
  final String? chefName;
  final String? producerName;


  static const String STATUS_PENDING = 'Pending';
  static const String STATUS_ACCEPTED = 'Accepted';
  static const String STATUS_PREPARING = 'Preparing';
  static const String STATUS_DISPATCHED = 'Dispatched';
  static const String STATUS_DELIVERED = 'Delivered';
  static const String STATUS_CANCELLED = 'Cancelled';

  Order({
    required this.orderId,
    required this.producerId,
    required this.userId,
    required this.mealName,
    required this.ingredients,
    required this.quantity,
    required this.totalPrice,
    required this.orderStatus,
    required this.paymentStatus,
    required this.paymentMode,
    required this.deliveryAddress,
    required this.orderDate,
    required this.notes,
    required this.orderType,
    this.productId,
    // Added fields
    this.amountPaid,
    this.transactionId,
    this.chefId,
    this.chefName,
    this.producerName,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? dateString) {
       if (dateString == null) return null;
       try {
         return DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'").parseUtc(dateString);
       } catch (e) {
         debugPrint("Error parsing date: $dateString, Error: $e");
         return null;
       }
    }

    String parseDeliveryAddress(dynamic addressData) {
      if (addressData is String) {
        final parts = addressData.split(',');
        if (parts.length > 2) {
          final lat = double.tryParse(parts[0].trim());
          final lon = double.tryParse(parts[1].trim());
          if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            return parts.sublist(2).join(',').trim();
          }
        }
        return addressData.trim();
      }
      return 'N/A';
    }

    // Defensive checks for required fields
    final int parsedOrderId = json['order_id'];
    final int parsedProducerId = json['producer_id'];
    final int parsedUserId = json['user_id'];
    final String parsedMealName = json['meal_name'] ?? 'N/A';
    final String parsedIngredients = json['ingredients'] ?? 'N/A';
    final int parsedQuantity = json['quantity'] ?? 0;
    final double parsedTotalPrice = double.tryParse(json['total_price']?.toString() ?? '0.0') ?? 0.0;
    final String parsedOrderStatus = json['order_status'] ?? STATUS_PENDING;
    final String parsedPaymentStatus = json['payment_status'] ?? 'N/A';
    final String parsedPaymentMode = json['payment_mode'] ?? 'N/A';
    final String parsedDeliveryAddress = parseDeliveryAddress(json['delivery_address']);
    final DateTime parsedOrderDate = parseDate(json['order_date']) ?? DateTime.now().toUtc();
    final String parsedNotes = json['notes'] ?? 'No notes';
    final String parsedOrderType = json['order_type'] ?? 'meal';

    return Order(
      orderId: parsedOrderId,
      producerId: parsedProducerId,
      userId: parsedUserId,
      mealName: parsedMealName,
      ingredients: parsedIngredients,
      quantity: parsedQuantity,
      totalPrice: parsedTotalPrice,
      orderStatus: parsedOrderStatus,
      paymentStatus: parsedPaymentStatus,
      paymentMode: parsedPaymentMode,
      deliveryAddress: parsedDeliveryAddress,
      orderDate: parsedOrderDate,
      notes: parsedNotes,
      orderType: parsedOrderType,
      productId: json['product_id'],
       // Added fields
       amountPaid: double.tryParse(json['amount_paid']?.toString() ?? '0.0'),
       transactionId: json['transaction_id'],
       chefId: json['chef_id'],
       chefName: json['chef_name'],
       producerName: json['producer_name'],
    );
  }

   // --- COPYWITH METHOD (Added for consistency and potential future use) ---
   Order copyWith({
    int? orderId,
    int? producerId,
    int? userId,
    String? mealName,
    String? ingredients,
    int? quantity,
    double? totalPrice,
    String? orderStatus,
    String? paymentStatus,
    String? paymentMode,
    String? deliveryAddress,
    DateTime? orderDate,
    String? notes,
    ValueGetter<String?>? productId, // Use ValueGetter for nullables
    String? orderType,
    ValueGetter<double?>? amountPaid,
    ValueGetter<String?>? transactionId,
    ValueGetter<int?>? chefId,
    ValueGetter<String?>? chefName,
    ValueGetter<String?>? producerName,
  }) {
    return Order(
      orderId: orderId ?? this.orderId,
      producerId: producerId ?? this.producerId,
      userId: userId ?? this.userId,
      mealName: mealName ?? this.mealName,
      ingredients: ingredients ?? this.ingredients,
      quantity: quantity ?? this.quantity,
      totalPrice: totalPrice ?? this.totalPrice,
      orderStatus: orderStatus ?? this.orderStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMode: paymentMode ?? this.paymentMode,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      orderDate: orderDate ?? this.orderDate,
      notes: notes ?? this.notes,
      productId: productId != null ? productId() : this.productId,
      orderType: orderType ?? this.orderType,
      amountPaid: amountPaid != null ? amountPaid() : this.amountPaid,
      transactionId: transactionId != null ? transactionId() : this.transactionId,
      chefId: chefId != null ? chefId() : this.chefId,
      chefName: chefName != null ? chefName() : this.chefName,
      producerName: producerName != null ? producerName() : this.producerName,
    );
  }
}


// --- Product Model ---
class Product {
  final String produceId;
  final String produceName;
  final double? calories;
  final double? carbohydrates;
  final double? proteins;
  final double? fats;
  final String? source;
  final double? unitGrams;

  Product({
    required this.produceId,
    required this.produceName,
    this.calories,
    this.carbohydrates,
    this.proteins,
    this.fats,
    this.source,
    this.unitGrams,
  });

  Map<String, dynamic> toJson() {
    return {
      'produce_id': produceId,
      'produce_name': produceName,
      'calories': calories,
      'carbohydrates': carbohydrates,
      'proteins': proteins,
      'fats': fats,
      'source': source,
      'unit_grams': unitGrams,
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    double? tryParseDouble(dynamic value) {
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    // Defensive checks for required fields
    final String parsedProduceId = json['produce_id'] ?? 'N/A_${DateTime.now().millisecondsSinceEpoch}'; // Generate unique-ish ID if missing
    final String parsedProduceName = json['produce_name'] ?? 'Unnamed Produce'; // Default name

    return Product(
      produceId: parsedProduceId,
      produceName: parsedProduceName,
      calories: tryParseDouble(json['calories']),
      carbohydrates: tryParseDouble(json['carbohydrates']),
      proteins: tryParseDouble(json['proteins']),
      fats: tryParseDouble(json['fats']),
      source: json['source'],
      unitGrams: tryParseDouble(json['unit_grams']),
    );
  }

  // --- COPYWITH METHOD ---
  Product copyWith({
    String? produceId,
    String? produceName,
    ValueGetter<double?>? calories,
    ValueGetter<double?>? carbohydrates,
    ValueGetter<double?>? proteins,
    ValueGetter<double?>? fats,
    ValueGetter<String?>? source,
    ValueGetter<double?>? unitGrams,
  }) {
    return Product(
      produceId: produceId ?? this.produceId,
      produceName: produceName ?? this.produceName,
      calories: calories != null ? calories() : this.calories,
      carbohydrates: carbohydrates != null ? carbohydrates() : this.carbohydrates,
      proteins: proteins != null ? proteins() : this.proteins,
      fats: fats != null ? fats() : this.fats,
      source: source != null ? source() : this.source,
      unitGrams: unitGrams != null ? unitGrams() : this.unitGrams,
    );
  }
}


