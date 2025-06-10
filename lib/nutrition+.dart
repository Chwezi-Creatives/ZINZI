//cspell:disable
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:zinzi/app_drawer_unified.dart'; // Assuming this exists
import 'package:zinzi/user_cache.dart';       // Assuming this exists
import 'package:zinzi/cache_config.dart';    // Assuming this exists
import 'package:zinzi/utils/image_utils.dart'; // Assuming this exists
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart' as cn;
import 'package:shimmer/shimmer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:convert';

import 'nutri_detail.dart'; // Assuming this exists
// import 'package:zinzi/nutri_detail.dart'; // Duplicate import, removed one

const Color primaryTeal = Color(0xFF00796B);
const Color lightTeal = Color(0xFFB2DFDB);
const Color accentTeal = Color(0xFF009688);
const Color lightBackgroundColor = Color(0xFFF8F8F8);
const Color cardBackgroundColor = Colors.white;
const Color primaryTextColor = Color(0xFF333333);
const Color secondaryTextColor = Color(0xFF666666);
const Color priceColor = primaryTeal;
const Color errorIconColor = Colors.grey;

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
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null
          ? DateTime.tryParse(json['date_added'])
          : null,
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
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null
          ? DateTime.tryParse(json['date_added'])
          : null,
      addedBy: json['added_by'],
      addedByType: json['added_by_type'],
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
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
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? ''),
      imageUrl: json['image_url'],
      dateAdded: json['date_added'] != null
          ? DateTime.tryParse(json['date_added'])
          : null,
      addedBy: json['added_by'],
      addedByType: json['added_by_type'],
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
}

class NutritionItem {
  final String id;
  final String type;
  final String name;
  final String? imagePath;
  final String? description;
  final double? price;
  final String idKey;
  final Map<String, dynamic> rawData;

  NutritionItem({
    required this.id,
    required this.type,
    required this.name,
    this.imagePath,
    this.description,
    this.price,
    required this.idKey,
    required this.rawData,
  });

  factory NutritionItem.fromApi(Map<String, dynamic> json) {
    String detectedIdKey = '';
    String detectedIdValue = '';
    String detectedType = '';

    // Prioritize specific keys for ID and type detection
    if (json.containsKey('spice_id')) {
        detectedIdKey = 'spice_id';
        detectedType = 'spice';
    } else if (json.containsKey('herbal_id')) {
        detectedIdKey = 'herbal_id';
        detectedType = 'herbal';
    } else if (json.containsKey('supplement_id')) {
        detectedIdKey = 'supplement_id';
        detectedType = 'supplement';
    } else if (json.containsKey('gadget_id')) {
        detectedIdKey = 'gadget_id';
        detectedType = 'gadget';
    } else {
        // Fallback to general key detection
        for (final key in json.keys) {
          if (key.endsWith('_id') && json[key] != null) {
            detectedIdKey = key;
            detectedIdValue = json[key].toString();
            detectedType = key.replaceAll('_id', '');
            break;
          }
        }
    }
    
    detectedIdValue = json[detectedIdKey]?.toString() ?? json['id']?.toString() ?? '';


    // Extract name using the correct key for each type
    String extractedName = json['${detectedType}_name'] ?? // e.g., spice_name, herbal_name
                           json['name'] ??
                           'Unknown';

    // Ensure price is parsed correctly
    double? parsedPrice;
    if (json['price'] is num) {
      parsedPrice = (json['price'] as num).toDouble();
    } else if (json['price'] is String) {
      parsedPrice = double.tryParse(json['price']);
    }


    return NutritionItem(
      id: detectedIdValue,
      type: detectedType.isNotEmpty ? detectedType : 'unknown', // Ensure type is set
      name: extractedName,
      imagePath: json['image_url'],
      description: json['description'],
      price: parsedPrice,
      idKey: detectedIdKey.isNotEmpty ? detectedIdKey : 'id',
      rawData: json,
    );
  }

  String get productIdKey => idKey;
  String get productIdValue => id;
  String get orderType => type;
  String get heroTag => imagePath ?? name;
}

class NutritionPage extends StatefulWidget {
  static Future<void> preloadCachesForSplash() async {
    final now = DateTime.now();
    final apiBaseUrl = dotenv.env['API_BASE_URL'];

    if (apiBaseUrl == null) {
      print('[Splash][Nutrition+] API_BASE_URL is null. Cannot preload data.');
      return;
    }

    // Helper function for preloading each category
    Future<void> preloadCategory(String categoryName, String endpoint, String cacheKey, String cacheTsKey) async {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      bool isValid = false;
      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null && now.difference(cacheTime) < CacheConfig.chefProducerDetailCacheDuration) { // Use appropriate duration
          isValid = true;
        }
      }

      if (!isValid) {
        try {
          final response = await http.get(Uri.parse(apiBaseUrl + endpoint));
          if (response.statusCode == 200) {
            final decodedResponse = jsonDecode(response.body);
            if (decodedResponse is Map<String, dynamic> && decodedResponse['data'] is List) {
              final List<dynamic> itemsList = decodedResponse['data'] as List<dynamic>;
              await UserCache.saveData(cacheKey, itemsList); // Store only the list
              await UserCache.saveData(cacheTsKey, now.toIso8601String());
              print('[Splash][Nutrition+] Preloaded and cached $categoryName.');
            } else {
              print('[Splash][Nutrition+] Preload $categoryName error: API response format unexpected. Expected Map with "data" as List. Received: ${decodedResponse.runtimeType}');
            }
          } else {
            print('[Splash][Nutrition+] Preload $categoryName error: API request failed with status ${response.statusCode}.');
          }
        } catch (e, s) {
          print('[Splash][Nutrition+] Preload $categoryName error: $e\n$s');
        }
      } else {
        print('[Splash][Nutrition+] $categoryName data is already cached and valid.');
      }
    }

    // Spices
    await preloadCategory('spices', '/rr/spices', 'nutrition_spices', 'nutrition_spices_ts');
    // Herbals
    await preloadCategory('herbals', '/rr/rherbals', 'nutrition_herbals', 'nutrition_herbals_ts');
    // Supplements
    await preloadCategory('supplements', '/rr/supplements', 'nutrition_supplements', 'nutrition_supplements_ts');
    // Gadgets
    await preloadCategory('gadgets', '/rr/gadgets', 'nutrition_gadgets', 'nutrition_gadgets_ts');
  }


  static final GlobalKey<_NutritionPageState> globalKey =
      GlobalKey<_NutritionPageState>();
  NutritionPage({Key? key}) : super(key: globalKey);

  static Future<void> manualRefreshFromAppBar() async {
    final state = globalKey.currentState;
    if (state != null) {
      await state.manualRefreshFromAppBar();
    }
  }

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final int _preloadThreshold = 15;
  bool _isPreloadingEnabled = true;
  // bool _isLoadingMore = false; // Not currently used, can be removed if not planned

  Future<void> manualRefreshFromAppBar() async {
    if (!mounted) return;
    setState(() {
      spicesLoading = true;
      herbalsLoading = true;
      supplementsLoading = true;
      gadgetsLoading = true;
      spicesError = null;
      herbalsError = null;
      supplementsError = null;
      gadgetsError = null;
    });
    // Clear existing cache before fetching new data to ensure refresh
    await UserCache.removeData('nutrition_spices');
    await UserCache.removeData('nutrition_spices_ts');
    await UserCache.removeData('nutrition_herbals');
    await UserCache.removeData('nutrition_herbals_ts');
    await UserCache.removeData('nutrition_supplements');
    await UserCache.removeData('nutrition_supplements_ts');
    await UserCache.removeData('nutrition_gadgets');
    await UserCache.removeData('nutrition_gadgets_ts');

    await Future.wait([
      _fetchSpices(forceRefresh: true),
      _fetchHerbals(forceRefresh: true),
      _fetchSupplements(forceRefresh: true),
      _fetchGadgets(forceRefresh: true),
    ]);
  }

  late AnimationController _refreshIconController;
  late TabController _tabController;

  List<NutritionItem> fetchedSpices = [];
  bool spicesLoading = false;
  String? spicesError;

  List<Herbal> fetchedHerbals = [];
  bool herbalsLoading = false;
  String? herbalsError;

  List<Supplement> fetchedSupplements = [];
  bool supplementsLoading = false;
  String? supplementsError;

  List<Gadget> fetchedGadgets = [];
  bool gadgetsLoading = false;
  String? gadgetsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _scrollController.addListener(_onScroll);

    _fetchSpices();
    _fetchHerbals();
    _fetchSupplements();
    _fetchGadgets();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _preloadImages();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _refreshIconController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchSpices({bool forceRefresh = false}) async {
    if (!mounted) return;
    print('[Nutrition+] Fetching spices (API fetch started)...');
    setState(() {
      spicesLoading = true;
      spicesError = null;
    });
    _refreshIconController.repeat();

    const String cacheKey = 'nutrition_spices';
    const String cacheTsKey = 'nutrition_spices_ts';

    try {
      if (!forceRefresh) {
        final cachedData = await UserCache.getData(cacheKey);
        final cachedTs = await UserCache.getData(cacheTsKey);
        final now = DateTime.now();

        if (cachedData != null && cachedTs != null) {
          final cacheTime = DateTime.tryParse(cachedTs.toString());
          if (cacheTime != null &&
              now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
            if (cachedData is List) {
              print('[Nutrition+] Loaded spices from cache.');
              if (mounted) {
                setState(() {
                  fetchedSpices = (cachedData as List)
                      .map((jsonItem) => NutritionItem.fromApi(jsonItem as Map<String, dynamic>))
                      .toList();
                  spicesLoading = false;
                });
                _refreshIconController.stop();
              }
              return;
            } else {
              print('[Nutrition+] Cached spices data is not a List (type: ${cachedData.runtimeType}). Fetching from API.');
              await UserCache.removeData(cacheKey); // Clear malformed cache
              await UserCache.removeData(cacheTsKey);
            }
          }
        }
      }

      final String baseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/spices'));

      print('[Nutrition+] Spices API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decodedApiResponse = json.decode(response.body);
        
        if (decodedApiResponse is Map<String, dynamic> && decodedApiResponse['data'] is List) {
          final List<dynamic> itemsList = decodedApiResponse['data'] as List<dynamic>;

          await UserCache.saveData(cacheKey, itemsList);
          await UserCache.saveData(cacheTsKey, DateTime.now().toIso8601String());

          if (mounted) {
            setState(() {
              fetchedSpices = itemsList
                  .map((jsonItem) => NutritionItem.fromApi(jsonItem as Map<String, dynamic>))
                  .toList();
              spicesLoading = false;
            });
          }
        } else {
          print('[Nutrition+] Spices API: Unexpected response format. Expected Map with "data" as List, received ${decodedApiResponse.runtimeType}');
          if (mounted) {
            setState(() {
              spicesError = 'Failed to load spices: Invalid data format.';
              spicesLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            spicesError = 'Failed to load spices. Status: ${response.statusCode}';
            spicesLoading = false;
          });
        }
      }
    } catch (e, s) {
      print('[Nutrition+] Spices API error: $e\n$s');
      if (mounted) {
        setState(() {
          spicesError = 'Error: ' + e.toString();
          spicesLoading = false;
        });
      }
    } finally {
      if (mounted) {
        _refreshIconController.stop();
      }
    }
  }

  Future<void> _fetchHerbals({bool forceRefresh = false}) async {
    if (!mounted) return;
    print('[Nutrition+] Fetching herbals (API fetch started)...');
    setState(() {
      herbalsLoading = true;
      herbalsError = null;
    });

    const String cacheKey = 'nutrition_herbals';
    const String cacheTsKey = 'nutrition_herbals_ts';

    try {
      if (!forceRefresh) {
        final cachedData = await UserCache.getData(cacheKey);
        final cachedTs = await UserCache.getData(cacheTsKey);
        final now = DateTime.now();

        if (cachedData != null && cachedTs != null) {
          final cacheTime = DateTime.tryParse(cachedTs.toString());
          if (cacheTime != null &&
              now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
            if (cachedData is List) {
              print('[Nutrition+] Loaded herbals from cache.');
              if (mounted) {
                setState(() {
                  fetchedHerbals = (cachedData as List)
                      .map((jsonItem) => Herbal.fromJson(jsonItem as Map<String, dynamic>))
                      .toList();
                  herbalsLoading = false;
                });
              }
              return;
            } else {
              print('[Nutrition+] Cached herbals data is not a List (type: ${cachedData.runtimeType}). Fetching from API.');
               await UserCache.removeData(cacheKey);
               await UserCache.removeData(cacheTsKey);
            }
          }
        }
      }

      final String baseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/rherbals'));

      print('[Nutrition+] Herbals API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decodedApiResponse = json.decode(response.body);
        
        if (decodedApiResponse is Map<String, dynamic> && decodedApiResponse['data'] is List) {
          final List<dynamic> itemsList = decodedApiResponse['data'] as List<dynamic>;

          await UserCache.saveData(cacheKey, itemsList);
          await UserCache.saveData(cacheTsKey, DateTime.now().toIso8601String());

          if (mounted) {
            setState(() {
              fetchedHerbals = itemsList
                  .map((jsonItem) => Herbal.fromJson(jsonItem as Map<String, dynamic>))
                  .toList();
              herbalsLoading = false;
            });
          }
        } else {
          print('[Nutrition+] Herbals API: Unexpected response format. Expected Map with "data" as List, received ${decodedApiResponse.runtimeType}');
          if (mounted) {
            setState(() {
              herbalsError = 'Failed to load herbals: Invalid data format.';
              herbalsLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            herbalsError = 'Failed to load herbals. Status: ${response.statusCode}';
            herbalsLoading = false;
          });
        }
      }
    } catch (e, s) {
      print('[Nutrition+] Herbals API error: $e\n$s');
      if (mounted) {
        setState(() {
          herbalsError = 'Error: ' + e.toString();
          herbalsLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSupplements({bool forceRefresh = false}) async {
    if (!mounted) return;
    print('[Nutrition+] Fetching supplements (API fetch started)...');
    setState(() {
      supplementsLoading = true;
      supplementsError = null;
    });

    const String cacheKey = 'nutrition_supplements';
    const String cacheTsKey = 'nutrition_supplements_ts';

    try {
      if (!forceRefresh) {
        final cachedData = await UserCache.getData(cacheKey);
        final cachedTs = await UserCache.getData(cacheTsKey);
        final now = DateTime.now();

        if (cachedData != null && cachedTs != null) {
          final cacheTime = DateTime.tryParse(cachedTs.toString());
          if (cacheTime != null &&
              now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
            if (cachedData is List) {
              print('[Nutrition+] Loaded supplements from cache.');
              if (mounted) {
                setState(() {
                  fetchedSupplements = (cachedData as List)
                      .map((jsonItem) => Supplement.fromJson(jsonItem as Map<String, dynamic>))
                      .toList();
                  supplementsLoading = false;
                });
              }
              return;
            } else {
               print('[Nutrition+] Cached supplements data is not a List (type: ${cachedData.runtimeType}). Fetching from API.');
               await UserCache.removeData(cacheKey);
               await UserCache.removeData(cacheTsKey);
            }
          }
        }
      }

      final String baseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/supplements'));

      print('[Nutrition+] Supplements API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decodedApiResponse = json.decode(response.body);

        if (decodedApiResponse is Map<String, dynamic> && decodedApiResponse['data'] is List) {
          final List<dynamic> itemsList = decodedApiResponse['data'] as List<dynamic>;
          
          await UserCache.saveData(cacheKey, itemsList);
          await UserCache.saveData(cacheTsKey, DateTime.now().toIso8601String());

          if (mounted) {
            setState(() {
              fetchedSupplements = itemsList
                  .map((jsonItem) => Supplement.fromJson(jsonItem as Map<String, dynamic>))
                  .toList();
              supplementsLoading = false;
            });
          }
        } else {
           print('[Nutrition+] Supplements API: Unexpected response format. Expected Map with "data" as List, received ${decodedApiResponse.runtimeType}');
           if (mounted) {
            setState(() {
              supplementsError = 'Failed to load supplements: Invalid data format.';
              supplementsLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            supplementsError = 'Failed to load supplements. Status: ${response.statusCode}';
            supplementsLoading = false;
          });
        }
      }
    } catch (e, s) {
      print('[Nutrition+] Supplements API error: $e\n$s');
      if (mounted) {
        setState(() {
          supplementsError = 'Error: ' + e.toString();
          supplementsLoading = false;
        });
      }
    }
  }

  Future<void> _fetchGadgets({bool forceRefresh = false}) async {
    if (!mounted) return;
    print('[Nutrition+] Fetching gadgets (API fetch started)...');
    setState(() {
      gadgetsLoading = true;
      gadgetsError = null;
    });

    const String cacheKey = 'nutrition_gadgets';
    const String cacheTsKey = 'nutrition_gadgets_ts';

    try {
      if (!forceRefresh) {
        final cachedData = await UserCache.getData(cacheKey);
        final cachedTs = await UserCache.getData(cacheTsKey);
        final now = DateTime.now();

        if (cachedData != null && cachedTs != null) {
          final cacheTime = DateTime.tryParse(cachedTs.toString());
          if (cacheTime != null &&
              now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
            if (cachedData is List) {
              print('[Nutrition+] Loaded gadgets from cache.');
              if (mounted) {
                setState(() {
                  fetchedGadgets = (cachedData as List)
                      .map((jsonItem) => Gadget.fromJson(jsonItem as Map<String, dynamic>))
                      .toList();
                  gadgetsLoading = false;
                });
              }
              return;
            } else {
              print('[Nutrition+] Cached gadgets data is not a List (type: ${cachedData.runtimeType}). Fetching from API.');
              await UserCache.removeData(cacheKey);
              await UserCache.removeData(cacheTsKey);
            }
          }
        }
      }

      final String baseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/gadgets'));

      print('[Nutrition+] Gadgets API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decodedApiResponse = json.decode(response.body);

        if (decodedApiResponse is Map<String, dynamic> && decodedApiResponse['data'] is List) {
          final List<dynamic> itemsList = decodedApiResponse['data'] as List<dynamic>;

          await UserCache.saveData(cacheKey, itemsList);
          await UserCache.saveData(cacheTsKey, DateTime.now().toIso8601String());

          if (mounted) {
            setState(() {
              fetchedGadgets = itemsList
                  .map((jsonItem) => Gadget.fromJson(jsonItem as Map<String, dynamic>))
                  .toList();
              gadgetsLoading = false;
            });
          }
        } else {
          print('[Nutrition+] Gadgets API: Unexpected response format. Expected Map with "data" as List, received ${decodedApiResponse.runtimeType}');
          if (mounted) {
            setState(() {
              gadgetsError = 'Failed to load gadgets: Invalid data format.';
              gadgetsLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            gadgetsError = 'Failed to load gadgets. Status: ${response.statusCode}';
            gadgetsLoading = false;
          });
        }
      }
    } catch (e, s) {
      print('[Nutrition+] Gadgets API error: $e\n$s');
      if (mounted) {
        setState(() {
          gadgetsError = 'Error: ' + e.toString();
          gadgetsLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(),
      // drawer: AppDrawerUnified(), // Uncomment if you have this drawer
      appBar: AppBar(
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Nutrition+',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          AnimatedBuilder(
            animation: _refreshIconController,
            builder: (context, child) {
              bool isLoading = false;
              if (_tabController.indexIsChanging) {
                // If tab is changing, use the previous tab's loading state briefly
                // or handle it based on your preference. For simplicity, just check current tab.
              }
              switch (_tabController.index) {
                case 0:
                  isLoading = spicesLoading;
                  break;
                case 1:
                  isLoading = herbalsLoading;
                  break;
                case 2:
                  isLoading = supplementsLoading;
                  break;
                case 3:
                  isLoading = gadgetsLoading;
                  break;
              }
              return IconButton(
                icon: Transform.rotate(
                  angle: isLoading ? _refreshIconController.value * 2.0 * math.pi : 0, // 2*pi for full rotation
                  child: const Icon(Icons.refresh),
                ),
                tooltip: 'Refresh',
                onPressed: isLoading ? null : () { // Disable button while loading
                  switch (_tabController.index) {
                    case 0:
                      _fetchSpices(forceRefresh: true);
                      break;
                    case 1:
                      _fetchHerbals(forceRefresh: true);
                      break;
                    case 2:
                      _fetchSupplements(forceRefresh: true);
                      break;
                    case 3:
                      _fetchGadgets(forceRefresh: true);
                      break;
                  }
                },
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true, // Good for many tabs
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          indicatorColor: Colors.white,
          indicatorWeight: 2.0,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Spices'),
            Tab(text: 'Herbs'),
            Tab(text: 'Supplements'),
            Tab(text: 'Gadgets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabContent<NutritionItem>(
            loading: spicesLoading,
            error: spicesError,
            items: fetchedSpices,
            onRetry: () => _fetchSpices(forceRefresh: true),
            label: 'spices',
          ),
          _buildTabContent<Herbal>(
            loading: herbalsLoading,
            error: herbalsError,
            items: fetchedHerbals,
            onRetry: () => _fetchHerbals(forceRefresh: true),
            label: 'herbals',
          ),
          _buildTabContent<Supplement>(
            loading: supplementsLoading,
            error: supplementsError,
            items: fetchedSupplements,
            onRetry: () => _fetchSupplements(forceRefresh: true),
            label: 'supplements',
          ),
          _buildTabContent<Gadget>(
            loading: gadgetsLoading,
            error: gadgetsError,
            items: fetchedGadgets,
            onRetry: () => _fetchGadgets(forceRefresh: true),
            label: 'gadgets',
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent<T>({
    required bool loading,
    required String? error,
    required List<T> items,
    required VoidCallback onRetry,
    required String label,
  }) {
    if (loading && items.isEmpty) { // Show loader only if items are empty initially
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(error, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center,),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (items.isEmpty && !loading) { // Show "No items" only if not loading and no error
      return Center(child: Text('No $label found.'));
    }
    return _buildCategoryGrid<T>(items, context, label: label);
  }

  String? getDisplayImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    // Assuming ImageUtils.processImageUrl handles any necessary transformations
    return ImageUtils.processImageUrl(url);
  }

  void _onScroll() {
    if (!mounted || !_isPreloadingEnabled || !_scrollController.hasClients) return;

    try {
      final position = _scrollController.position;
      if (!position.hasContentDimensions || position.maxScrollExtent <= 0) return;

      final threshold = 0.8; // Start preloading when 80% scrolled
      if (position.pixels >= (position.maxScrollExtent * threshold)) {
        _preloadImages();
      }
    } catch (e) {
      debugPrint('Scroll handling error: $e');
    }
  }

  void _preloadImages() {
    if (!mounted || !_isPreloadingEnabled || !_scrollController.hasClients) return;

    List<dynamic> currentItems = [];
    switch (_tabController.index) {
      case 0: currentItems = fetchedSpices; break;
      case 1: currentItems = fetchedHerbals; break;
      case 2: currentItems = fetchedSupplements; break;
      case 3: currentItems = fetchedGadgets; break;
    }

    if (currentItems.isEmpty) return;

    // Estimate item height for rough calculation, adjust as needed
    double estimatedItemHeight = 250; // Adjust based on your _buildItemCard height
    final screenHeight = MediaQuery.of(context).size.height;
    final itemsPerPage = (screenHeight / estimatedItemHeight).ceil();
    
    final firstVisibleIndex = (_scrollController.position.pixels / estimatedItemHeight).floor();
    final lastVisibleIndex = firstVisibleIndex + itemsPerPage;

    final preloadStart = math.max(0, firstVisibleIndex);
    final preloadEnd = math.min(currentItems.length - 1, lastVisibleIndex + _preloadThreshold);

    for (int i = preloadStart; i <= preloadEnd; i++) {
      final item = currentItems[i];
      String? imageUrl;

      if (item is NutritionItem) imageUrl = getDisplayImageUrl(item.imagePath);
      else if (item is Herbal) imageUrl = getDisplayImageUrl(item.imageUrl);
      else if (item is Supplement) imageUrl = getDisplayImageUrl(item.imageUrl);
      else if (item is Gadget) imageUrl = getDisplayImageUrl(item.imageUrl);

      if (imageUrl != null && imageUrl.startsWith('http')) {
        try {
          // cn.CachedNetworkImageProvider(imageUrl).resolve(ImageConfiguration())
          //   .addListener(ImageStreamListener((_, __) {}, onError: (err, stack) {
          //     debugPrint('Error preloading image $imageUrl: $err');
          //   }));
          // Using precacheImage for more direct control if needed, or stick to provider.
          precacheImage(cn.CachedNetworkImageProvider(imageUrl), context, onError: (err, stack) {
             debugPrint('Error preloading image $imageUrl: $err');
          });
        } catch (e) {
          debugPrint('Error setting up image preload for $imageUrl: $e');
        }
      }
    }
  }

  Widget _buildCategoryGrid<T>(List<T> items, BuildContext context,
      {String? defaultItemImagePath, String? label}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
      // Removed NotificationListener, _onScroll is attached directly
      child: GridView.builder(
        controller: _scrollController, // Crucial for _onScroll to work
        physics: const ClampingScrollPhysics(), // Or AlwaysScrollableScrollPhysics if you want pull-to-refresh feel
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12.0,
          mainAxisSpacing: 12.0,
          childAspectRatio: 0.80, // Adjust as needed
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) {
          // Initial preload for first few items can be aggressive
          // if (index < 6) { // Preload first 6 items quickly
          //   WidgetsBinding.instance.addPostFrameCallback((_) {
          //     if (mounted) _preloadImagesForIndex(items, index);
          //   });
          // }
          return AnimatedOpacity( // Consider removing if performance is an issue on older devices
            opacity: 1.0,
            duration: Duration(milliseconds: 300 + (index % 4 * 50)),
            curve: Curves.easeOut,
            child: _buildItemCard<T>(items[index], context,
                label: label, defaultItemImagePath: defaultItemImagePath),
          );
        },
      ),
    );
  }
  // Helper for initial preloading
  // void _preloadImagesForIndex(List<dynamic> items, int index) {
  //   if (index < 0 || index >= items.length) return;
  //   final item = items[index];
  //   String? imageUrl;
  //   if (item is NutritionItem) imageUrl = getDisplayImageUrl(item.imagePath);
  //   // ... add other types
  //   if (imageUrl != null && imageUrl.startsWith('http')) {
  //     precacheImage(cn.CachedNetworkImageProvider(imageUrl), context, onError: (e,s){});
  //   }
  // }


  Widget _buildItemCard<T>(T item, BuildContext context,
      {String? label, String? defaultItemImagePath}) {
    String? imageUrl;
    String name = 'No Name';
    double? price;
    String heroTagSuffix = DateTime.now().millisecondsSinceEpoch.toString(); // Default unique suffix
    String baseHeroTag = 'item';


    if (item is NutritionItem) {
      imageUrl = getDisplayImageUrl(item.imagePath);
      name = item.name;
      price = item.price;
      baseHeroTag = item.id; // Use unique ID for hero tag
      heroTagSuffix = item.type;
    } else if (item is Herbal) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.herbalName;
      price = item.price;
      baseHeroTag = item.herbalId.toString();
      heroTagSuffix = 'herbal';
    } else if (item is Supplement) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.supplementName;
      price = item.price;
      baseHeroTag = item.supplementId.toString();
      heroTagSuffix = 'supplement';
    } else if (item is Gadget) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.gadgetName;
      price = item.price;
      baseHeroTag = item.gadgetId.toString();
      heroTagSuffix = 'gadget';
    }
    final String heroTag = '$baseHeroTag-$heroTagSuffix-${imageUrl ?? name}'; // Make hero tag more unique

    final borderRadius = BorderRadius.circular(15.0);

    return Card(
      elevation: 3.0,
      shadowColor: Colors.grey.withAlpha(50),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: cardBackgroundColor,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: lightTeal.withAlpha(50),
          highlightColor: lightTeal.withAlpha(25),
          onTap: () {
            Widget? decodedImageWidget;
             String? currentItemImagePath;
            if (item is NutritionItem) currentItemImagePath = item.imagePath;
            // Add other types if they can have base64 images
            
            if (currentItemImagePath != null && currentItemImagePath.startsWith('data:image')) {
              try {
                final base64Str = currentItemImagePath.split(',').last;
                final bytes = base64Decode(base64Str);
                decodedImageWidget = Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: 110);
              } catch (e) {
                decodedImageWidget = null;
                 print("Error decoding base64 image: $e");
              }
            }

            NutritionItem detailItem;
            if (item is NutritionItem) {
              detailItem = item;
            } else if (item is Herbal) {
              detailItem = NutritionItem(
                id: item.herbalId.toString(), type: 'herbal', name: item.herbalName,
                imagePath: item.imageUrl, description: item.description, price: item.price,
                idKey: 'herbal_id', rawData: { /* fill from item properties */ }
              );
            } else if (item is Supplement) {
              detailItem = NutritionItem(
                id: item.supplementId.toString(), type: 'supplement', name: item.supplementName,
                imagePath: item.imageUrl, description: item.description, price: item.price,
                idKey: 'supplement_id', rawData: { /* fill from item properties */ }
              );
            } else if (item is Gadget) {
              detailItem = NutritionItem(
                id: item.gadgetId.toString(), type: 'gadget', name: item.gadgetName,
                imagePath: item.imageUrl, description: item.description, price: item.price,
                idKey: 'gadget_id', rawData: { /* fill from item properties */ }
              );
            } else {
              // Should not happen if T is constrained, but as a fallback:
              detailItem = NutritionItem(id: '', type: 'unknown', name: 'Unknown Item', rawData: {}, idKey: '');
            }
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Nutri_DetailPage( // Assuming Nutri_DetailPage exists
                  item: detailItem,
                  decodedImage: decodedImageWidget, // Pass the decoded image if available
                  tag: heroTag, // FIX: Changed 'heroImageTag' to 'tag'
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Hero(
                  tag: heroTag, // Use the unique heroTag
                  flightShuttleBuilder: (
                    BuildContext flightContext,
                    Animation<double> animation,
                    HeroFlightDirection flightDirection,
                    BuildContext fromHeroContext,
                    BuildContext toHeroContext,
                  ) {
                    final Hero toHero = toHeroContext.widget as Hero;
                    return FadeTransition( // Or ScaleTransition, SizeTransition etc.
                      opacity: animation.drive(
                        Tween<double>(begin: 0.85, end: 1.0).chain(
                          CurveTween(curve: Curves.easeInOut),
                        ),
                      ),
                      child: toHero.child,
                    );
                  },
                  child: Material( // Ensures smooth transitions for image properties
                    type: MaterialType.transparency,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
                      child: (imageUrl != null && imageUrl.startsWith('http'))
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              // width: double.infinity, // Let Expanded handle width
                              // height: 110, // Let Expanded handle height
                              placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(color: Colors.white),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined, color: errorIconColor, size: 40.0),
                                ),
                              ),
                            )
                          : (defaultItemImagePath != null // Fallback for local asset
                              ? Image.asset(defaultItemImagePath, fit: BoxFit.cover)
                              : Container( // Default placeholder if no image
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Icon(Icons.image_not_supported_outlined, color: errorIconColor, size: 40.0),
                                  ),
                                )
                             ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Important for Column inside Expanded
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                      maxLines: 2, // Allow for two lines for longer names
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      price != null && price > 0
                          ? 'UGX ${price.toStringAsFixed(0)}' // No decimals if not needed
                          : 'Price: N/A', // Clearer "Not Available"
                      style: const TextStyle(
                        color: priceColor,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}