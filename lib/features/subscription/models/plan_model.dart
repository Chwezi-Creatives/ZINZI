// Manual JSON serialization for Plan models
import 'dart:convert';

enum BillingCycle {
  monthly,
  biWeekly,
  yearly,
}

extension BillingCycleDisplay on BillingCycle {
  String get displayName {
    switch (this) {
      case BillingCycle.monthly:
        return 'Monthly';
      case BillingCycle.biWeekly:
        return 'Bi-weekly';
      case BillingCycle.yearly:
        return 'Yearly';
    }
  }
}

extension BillingCycleExtension on BillingCycle {
  static BillingCycle fromString(String value) {
    switch (value.toLowerCase()) {
      case 'monthly':
        return BillingCycle.monthly;
      case 'bi-weekly':
      case 'bi weekly':
      case 'biweekly':
        return BillingCycle.biWeekly;
      case 'yearly':
        return BillingCycle.yearly;
      default:
        throw ArgumentError('Unknown BillingCycle value: $value');
    }
  }

  String get value {
    switch (this) {
      case BillingCycle.monthly:
        return 'monthly';
      case BillingCycle.biWeekly:
        return 'bi-weekly';
      case BillingCycle.yearly:
        return 'yearly';
    }
  }
}

class Plan {
  final int id;
  final String name;
  final String? description;
  final dynamic price;
  final BillingCycle billingCycle;
  final List<String> features;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get priceAsDouble {
    if (price == null) return 0.0;
    if (price is num) return (price as num).toDouble();
    if (price is String) return double.tryParse(price) ?? 0.0;
    return 0.0;
  }

  String get priceAsString {
    if (price == null) return '0';
    if (price is String) return price as String;
    if (price is int) return price.toString();
    if (price is double) return (price as double).toStringAsFixed(2);
    return price.toString();
  }

  Plan({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.billingCycle,
    required this.features,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    // Handle both string and list types for features
    List<String> parseFeatures(dynamic features) {
      if (features is String) {
        try {
          return List<String>.from(jsonDecode(features) as List);
        } catch (e) {
          return [];
        }
      } else if (features is List) {
        return List<String>.from(features);
      }
      return [];
    }

    // Helper function to parse price while preserving original type
    dynamic parsePrice(dynamic price) {
      if (price == null) return 0.0;
      if (price is num || price is String) return price;
      return 0.0;
    }

    return Plan(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'].toString(),
      description: json['description']?.toString(),
      price: parsePrice(json['price']),
      billingCycle: BillingCycleExtension.fromString(json['billing_cycle'].toString()),
      features: parseFeatures(json['features']),
      isActive: json['is_active'] is bool ? json['is_active'] : json['is_active']?.toString().toLowerCase() == 'true',
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: DateTime.parse(json['updated_at'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'billing_cycle': billingCycle.value,
      'features': features,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Plan copyWith({
    int? id,
    String? name,
    String? description,
    double? price,
    BillingCycle? billingCycle,
    List<String>? features,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Plan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      billingCycle: billingCycle ?? this.billingCycle,
      features: features ?? List.from(this.features),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PlanCreateUpdateRequest {
  final String name;
  final String description;
  final double price;
  final BillingCycle billingCycle;
  final List<String> features;
  final bool isActive;

  PlanCreateUpdateRequest({
    required this.name,
    required this.description,
    required this.price,
    required this.billingCycle,
    required this.features,
    this.isActive = true,
  });

  factory PlanCreateUpdateRequest.fromPlan(Plan plan) {
    return PlanCreateUpdateRequest(
      name: plan.name,
      description: plan.description ?? '',
      price: plan.price,
      billingCycle: plan.billingCycle,
      features: List.from(plan.features),
      isActive: plan.isActive,
    );
  }

  factory PlanCreateUpdateRequest.fromJson(Map<String, dynamic> json) {
    // Helper to parse price from any type
    double parsePrice(dynamic price) {
      if (price == null) return 0.0;
      if (price is num) return price.toDouble();
      if (price is String) {
        return double.tryParse(price) ?? 0.0;
      }
      return 0.0;
    }

    return PlanCreateUpdateRequest(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: parsePrice(json['price']),
      billingCycle: BillingCycleExtension.fromString(json['billing_cycle']?.toString() ?? 'monthly'),
      features: json['features'] is List ? List<String>.from(json['features']) : [],
      isActive: json['is_active'] is bool ? json['is_active'] : json['is_active']?.toString().toLowerCase() == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'price': price,
      'billing_cycle': billingCycle.value,
      'features': features,
      'is_active': isActive,
    };
  }
}
