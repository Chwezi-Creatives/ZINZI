//cspell:disable
// Supplement Model
class Supplement {
  final int supplementId;
  final String supplementName;
  final String? description;
  final String? unit;
  final double? price;
  final String? imageUrl;
  final DateTime? dateAdded;
  final String? addedBy;
  final String? addedByType;

  Supplement({
    required this.supplementId,
    required this.supplementName,
    this.description,
    this.unit,
    this.price,
    this.imageUrl,
    this.dateAdded,
    this.addedBy,
    this.addedByType,
  });

  factory Supplement.fromJson(Map<String, dynamic> json) {
    return Supplement(
      supplementId: json['supplement_id'],
      supplementName: json['supplement_name'] ?? 'Unknown',
      description: json['description'],
      unit: json['unit'],
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null ? DateTime.tryParse(json['date_added']) : null,
      addedBy: json['added_by'],
      addedByType: json['added_by_type'],
    );
  }
}

// Herbal Model
class Herbal {
  final int herbalId;
  final String herbalName;
  final String? description;
  final String? unit;
  final double? price;
  final String? imageUrl;
  final DateTime? dateAdded;
  final String? addedBy;
  final String? addedByType;
  final DateTime? updatedAt;

  Herbal({
    required this.herbalId,
    required this.herbalName,
    this.description,
    this.unit,
    this.price,
    this.imageUrl,
    this.dateAdded,
    this.addedBy,
    this.addedByType,
    this.updatedAt,
  });

  factory Herbal.fromJson(Map<String, dynamic> json) {
    return Herbal(
      herbalId: json['herbal_id'],
      herbalName: json['herbal_name'] ?? 'Unknown',
      description: json['description'],
      unit: json['unit'],
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null ? DateTime.tryParse(json['date_added']) : null,
      addedBy: json['added_by'],
      addedByType: json['added_by_type'],
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }
}

// Gadget Model
class Gadget {
  final int gadgetId;
  final String gadgetName;
  final String? description;
  final String? brand;
  final String? model;
  final double? price;
  final String? imageUrl;
  final DateTime? dateAdded;
  final String? addedBy;
  final String? addedByType;
  final DateTime? updatedAt;

  Gadget({
    required this.gadgetId,
    required this.gadgetName,
    this.description,
    this.brand,
    this.model,
    this.price,
    this.imageUrl,
    this.dateAdded,
    this.addedBy,
    this.addedByType,
    this.updatedAt,
  });

  factory Gadget.fromJson(Map<String, dynamic> json) {
    return Gadget(
      gadgetId: json['gadget_id'],
      gadgetName: json['gadget_name'] ?? 'Unknown',
      description: json['description'],
      brand: json['brand'],
      model: json['model'],
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null ? DateTime.tryParse(json['date_added']) : null,
      addedBy: json['added_by'],
      addedByType: json['added_by_type'],
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }
}
