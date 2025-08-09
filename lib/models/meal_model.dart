import 'package:flutter/foundation.dart';

class Meal {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String chefId;
  final String chefName;
  final List<String> dietaryRestrictions;
  final List<String> ingredients;
  final int preparationTime;
  final int cookingTime;
  final int servings;
  final double rating;
  final int reviewCount;
  final bool isPopular;
  final bool isNew;
  final bool isVegetarian;
  final bool isVegan;
  final bool isGlutenFree;
  final bool isDairyFree;
  final bool isNutFree;

  const Meal({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.chefId,
    required this.chefName,
    this.dietaryRestrictions = const [],
    this.ingredients = const [],
    this.preparationTime = 0,
    this.cookingTime = 0,
    this.servings = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.isPopular = false,
    this.isNew = false,
    this.isVegetarian = false,
    this.isVegan = false,
    this.isGlutenFree = false,
    this.isDairyFree = false,
    this.isNutFree = false,
  });

  // Convert a Meal into a Map
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'chefId': chefId,
        'chefName': chefName,
        'dietaryRestrictions': dietaryRestrictions,
        'ingredients': ingredients,
        'preparationTime': preparationTime,
        'cookingTime': cookingTime,
        'servings': servings,
        'rating': rating,
        'reviewCount': reviewCount,
        'isPopular': isPopular,
        'isNew': isNew,
        'isVegetarian': isVegetarian,
        'isVegan': isVegan,
        'isGlutenFree': isGlutenFree,
        'isDairyFree': isDairyFree,
        'isNutFree': isNutFree,
      };

  // Create a Meal from a Map
  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['imageUrl'] as String,
        chefId: json['chefId'] as String,
        chefName: json['chefName'] as String,
        dietaryRestrictions: (json['dietaryRestrictions'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        ingredients: (json['ingredients'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        preparationTime: json['preparationTime'] as int? ?? 0,
        cookingTime: json['cookingTime'] as int? ?? 0,
        servings: json['servings'] as int? ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: json['reviewCount'] as int? ?? 0,
        isPopular: json['isPopular'] as bool? ?? false,
        isNew: json['isNew'] as bool? ?? false,
        isVegetarian: json['isVegetarian'] as bool? ?? false,
        isVegan: json['isVegan'] as bool? ?? false,
        isGlutenFree: json['isGlutenFree'] as bool? ?? false,
        isDairyFree: json['isDairyFree'] as bool? ?? false,
        isNutFree: json['isNutFree'] as bool? ?? false,
      );
}

// Extension methods for Meal model
extension MealX on Meal {
  String get formattedPrice => 'UGX ${price.toStringAsFixed(0)}';
  
  String get preparationTimeFormatted {
    if (preparationTime < 60) return '$preparationTime min';
    final hours = preparationTime ~/ 60;
    final minutes = preparationTime % 60;
    if (minutes == 0) return '$hours h';
    return '${hours}h ${minutes}min';
  }
  
  String get dietaryInfo {
    final List<String> info = [];
    if (isVegetarian) info.add('Vegetarian');
    if (isVegan) info.add('Vegan');
    if (isGlutenFree) info.add('Gluten Free');
    if (isDairyFree) info.add('Dairy Free');
    if (isNutFree) info.add('Nut Free');
    return info.join(' • ');
  }
}
