// lib/data_models.dart
import 'package:flutter/foundation.dart';

// An abstract class to represent any item that has a name, id, and price.
abstract class Product {
  final dynamic id;
  final String name;
  final double? price;

  Product({required this.id, required this.name, required this.price});
}

class Meal extends Product {
  final String imageUrl;

  Meal({
    required String id,
    required String name,
    required double? price,
    required this.imageUrl,
  }) : super(id: id, name: name, price: price);

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['Meal_id'],
      name: json['Meal_name'],
      // API returns integer, converting to double. Handle nulls.
      price: (json['Price'] as num?)?.toDouble(),
      imageUrl: json['Image_link'],
    );
  }
}

class Spice extends Product {
  final String? imageUrl;

  Spice({
    required int id,
    required String name,
    required double? price,
    this.imageUrl,
  }) : super(id: id, name: name, price: price);

  factory Spice.fromJson(Map<String, dynamic> json) {
    return Spice(
      id: json['spice_id'],
      name: json['spice_name'],
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'],
    );
  }
}

class Herbal extends Product {
   final String? imageUrl;

  Herbal({
    required int id,
    required String name,
    required double? price,
    this.imageUrl,
  }) : super(id: id, name: name, price: price);

  factory Herbal.fromJson(Map<String, dynamic> json) {
    return Herbal(
      id: json['herbal_id'],
      name: json['herbal_name'],
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'],
    );
  }
}

class Gadget extends Product {
   final String? imageUrl;

  Gadget({
    required int id,
    required String name,
    required double? price,
    this.imageUrl,
  }) : super(id: id, name: name, price: price);

  factory Gadget.fromJson(Map<String, dynamic> json) {
    return Gadget(
      id: json['gadget_id'],
      name: json['gadget_name'],
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'],
    );
  }
}

class Supplement extends Product {
   final String? imageUrl;

  Supplement({
    required int id,
    required String name,
    required double? price,
    this.imageUrl,
  }) : super(id: id, name: name, price: price);

  factory Supplement.fromJson(Map<String, dynamic> json) {
    return Supplement(
      id: json['supplement_id'],
      name: json['supplement_name'],
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'],
    );
  }
}