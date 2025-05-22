import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/user_cache.dart';
import 'package:zinzi2/cache_config.dart';
import 'package:zinzi2/utils/image_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart' as cn;
import 'package:shimmer/shimmer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:convert';
import 'nutri_detail.dart';

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

    for (final key in json.keys) {
      if (key.endsWith('_id') && json[key] != null) {
        detectedIdKey = key;
        detectedIdValue = json[key].toString();
        detectedType = key.replaceAll('_id', '');
        break;
      }
    }

    detectedIdKey = detectedIdKey.isNotEmpty ? detectedIdKey : 'id';
    detectedIdValue = detectedIdValue.isNotEmpty
        ? (json[detectedIdKey]?.toString() ?? '')
        : (json['id']?.toString() ?? '');
    detectedType =
        detectedType.isNotEmpty ? detectedType : (json['type'] ?? 'meal');

    // Extract name using the correct key for each type
    String extractedName =
        json['supplement_name'] ??
        json['herbal_name'] ??
        json['gadget_name'] ??
        json['spice_name'] ??
        json['name'] ??
        'Unknown';

    return NutritionItem(
      id: detectedIdValue,
      type: detectedType,
      name: extractedName,
      imagePath: json['image_url'],
      description: json['description'],
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : null,
      idKey: detectedIdKey,
      rawData: json,
    );
  }

  String get productIdKey => idKey;
  String get productIdValue => id;
  String get orderType => type;
  String get heroTag => imagePath ?? name;
}

class NutritionPage extends StatefulWidget {
  /// Preload all Nutrition+ tab caches for splash screen (no UI, no context needed)
  static Future<void> preloadCachesForSplash() async {
    // Spices
    const String spicesKey = 'nutrition_spices';
    const String spicesTsKey = 'nutrition_spices_ts';
    final now = DateTime.now();
    final cachedSpices = await UserCache.getData(spicesKey);
    final cachedSpicesTs = await UserCache.getData(spicesTsKey);
    bool spicesValid = false;
    if (cachedSpices != null && cachedSpicesTs != null) {
      final cacheTime = DateTime.tryParse(cachedSpicesTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < CacheConfig.chefProducerDetailCacheDuration) {
        spicesValid = true;
      }
    }
    if (!spicesValid) {
      // Fetch and cache spices (same as _fetchSpices logic, but no UI)
      try {
        // TODO: Replace with your actual API endpoint for spices
        final apiBaseUrl = dotenv.env['API_BASE_URL'];
if (apiBaseUrl != null) {
  final response = await http.get(Uri.parse(apiBaseUrl + '/rr/rspices'));
  if (response.statusCode == 200) {
    final dataList = jsonDecode(response.body);
    await UserCache.saveData(spicesKey, dataList);
    await UserCache.saveData(spicesTsKey, now.toIso8601String());
  }
} else {
  print('[Splash][Nutrition+] API_BASE_URL is null. Cannot fetch spices.');
}

      } catch (e) { print('[Splash][Nutrition+] preload spices error: $e'); }
    }
    // Herbals
    const String herbalsKey = 'nutrition_herbals';
    const String herbalsTsKey = 'nutrition_herbals_ts';
    final cachedHerbals = await UserCache.getData(herbalsKey);
    final cachedHerbalsTs = await UserCache.getData(herbalsTsKey);
    bool herbalsValid = false;
    if (cachedHerbals != null && cachedHerbalsTs != null) {
      final cacheTime = DateTime.tryParse(cachedHerbalsTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < CacheConfig.chefProducerDetailCacheDuration) {
        herbalsValid = true;
      }
    }
    if (!herbalsValid) {
      try {
        final apiBaseUrl = dotenv.env['API_BASE_URL'];
        if (apiBaseUrl != null) {
          final response = await http.get(Uri.parse(apiBaseUrl + '/rr/rherbals'));
          if (response.statusCode == 200) {
            final dataList = jsonDecode(response.body);
            await UserCache.saveData(herbalsKey, dataList);
            await UserCache.saveData(herbalsTsKey, now.toIso8601String());
          }
        } else {
          print('[Splash][Nutrition+] API_BASE_URL is null. Cannot fetch herbals.');
        }

      } catch (e) { print('[Splash][Nutrition+] preload herbals error: $e'); }
    }
    // Supplements
    const String supplementsKey = 'nutrition_supplements';
    const String supplementsTsKey = 'nutrition_supplements_ts';
    final cachedSupplements = await UserCache.getData(supplementsKey);
    final cachedSupplementsTs = await UserCache.getData(supplementsTsKey);
    bool supplementsValid = false;
    if (cachedSupplements != null && cachedSupplementsTs != null) {
      final cacheTime = DateTime.tryParse(cachedSupplementsTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < CacheConfig.chefProducerDetailCacheDuration) {
        supplementsValid = true;
      }
    }
    if (!supplementsValid) {
      try {
        final apiBaseUrl = dotenv.env['API_BASE_URL'];
        if (apiBaseUrl != null) {
          final response = await http.get(Uri.parse(apiBaseUrl + '/rr/rsupplements'));
          if (response.statusCode == 200) {
            final dataList = jsonDecode(response.body);
            await UserCache.saveData(supplementsKey, dataList);
            await UserCache.saveData(supplementsTsKey, now.toIso8601String());
          }
        } else {
          print('[Splash][Nutrition+] API_BASE_URL is null. Cannot fetch supplements.');
        }

      } catch (e) { print('[Splash][Nutrition+] preload supplements error: $e'); }
    }
    // Gadgets
    const String gadgetsKey = 'nutrition_gadgets';
    const String gadgetsTsKey = 'nutrition_gadgets_ts';
    final cachedGadgets = await UserCache.getData(gadgetsKey);
    final cachedGadgetsTs = await UserCache.getData(gadgetsTsKey);
    bool gadgetsValid = false;
    if (cachedGadgets != null && cachedGadgetsTs != null) {
      final cacheTime = DateTime.tryParse(cachedGadgetsTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < CacheConfig.chefProducerDetailCacheDuration) {
        gadgetsValid = true;
      }
    }
    if (!gadgetsValid) {
      try {
        final apiBaseUrl = dotenv.env['API_BASE_URL'];
        if (apiBaseUrl != null) {
          final response = await http.get(Uri.parse(apiBaseUrl + '/rr/rgadgets'));
          if (response.statusCode == 200) {
            final dataList = jsonDecode(response.body);
            await UserCache.saveData(gadgetsKey, dataList);
            await UserCache.saveData(gadgetsTsKey, now.toIso8601String());
          }
        } else {
          print('[Splash][Nutrition+] API_BASE_URL is null. Cannot fetch gadgets.');
        }

      } catch (e) { print('[Splash][Nutrition+] preload gadgets error: $e'); }
    }
  }
  static final GlobalKey<_NutritionPageState> globalKey = GlobalKey<_NutritionPageState>();
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

class _NutritionPageState extends State<NutritionPage> with TickerProviderStateMixin {
  // Scroll controller for preloading
  final ScrollController _scrollController = ScrollController();
  final int _preloadThreshold = 15; // Number of items before the end to start preloading
  bool _isPreloadingEnabled = true; // Always enable preloading
  bool _isLoadingMore = false; // Track if we're currently loading more items
  Future<void> manualRefreshFromAppBar() async {
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
    await Future.wait([
      _fetchSpices(),
      _fetchHerbals(),
      _fetchSupplements(),
      _fetchGadgets(),
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
    
    // Initialize scroll controller
    _scrollController.addListener(_onScroll);
    
    // Initial data fetch
    _fetchSpices();
    _fetchHerbals();
    _fetchSupplements();
    _fetchGadgets();
    
    // Initial preload after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _preloadImages();
      }
    });
  }

  @override
  void dispose() {
    // Remove scroll listener first to prevent callbacks after disposal
    _scrollController.removeListener(_onScroll);
    
    // Dispose controllers
    _refreshIconController.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    
    // Cancel any pending operations
    // Add any other cleanup here
    
    super.dispose();
  }

  Future<void> _fetchSpices() async {
    print('[Nutrition+] Fetching spices (API fetch started)...');
    setState(() {
      spicesLoading = true;
      spicesError = null;
    });
    _refreshIconController.repeat();

    const String cacheKey = 'nutrition_spices';
    const String cacheTsKey = 'nutrition_spices_ts';

    try {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();

      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
          print('[Nutrition+] Loaded spices from cache.');
          setState(() {
            fetchedSpices = (cachedData as List)
                .map((json) => NutritionItem.fromApi(json))
                .toList();
            spicesLoading = false;
          });
          _refreshIconController.stop();
          return;
        }
      }

      final String baseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/spices'));

      print('[Nutrition+] Spices API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> dataList;

        if (decoded is List) {
          dataList = decoded;
          print('[Nutrition+] Spices API: decoded is List');
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          dataList = decoded['data'];
          print('[Nutrition+] Spices API: decoded is Map with data field');
        } else {
          dataList = [];
          print('[Nutrition+] Spices API: Unexpected response format');
        }

        await UserCache.saveData(cacheKey, dataList);
        await UserCache.saveData(cacheTsKey, now.toIso8601String());

        setState(() {
          fetchedSpices =
              dataList.map((json) => NutritionItem.fromApi(json)).toList();
          spicesLoading = false;
        });
        _refreshIconController.stop();
      } else {
        setState(() {
          spicesError = 'Failed to load spices.';
          spicesLoading = false;
        });
        _refreshIconController.stop();
      }
    } catch (e) {
      print('[Nutrition+] Spices API error: $e');
      setState(() {
        spicesError = 'Error: ' + e.toString();
        spicesLoading = false;
      });
      _refreshIconController.stop();
    }
  }

  Future<void> _fetchHerbals() async {
    print('[Nutrition+] Fetching herbals (API fetch started)...');
    setState(() {
      herbalsLoading = true;
      herbalsError = null;
    });

    const String cacheKey = 'nutrition_herbals';
    const String cacheTsKey = 'nutrition_herbals_ts';

    try {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();

      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
          print('[Nutrition+] Loaded herbals from cache.');
          setState(() {
            fetchedHerbals = (cachedData as List)
                .map((json) => Herbal.fromJson(json as Map<String, dynamic>))
                .toList();
            herbalsLoading = false;
          });
          return;
        }
      }

      final String baseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/rherbals'));

      print('[Nutrition+] Herbals API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> dataList;

        if (decoded is List) {
          dataList = decoded;
          print('[Nutrition+] Herbals API: decoded is List');
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          dataList = decoded['data'];
          print('[Nutrition+] Herbals API: decoded is Map with data field');
        } else {
          dataList = [];
          print('[Nutrition+] Herbals API: Unexpected response format');
        }

        await UserCache.saveData(cacheKey, dataList);
        await UserCache.saveData(cacheTsKey, now.toIso8601String());

        setState(() {
          fetchedHerbals =
              dataList.map((json) => Herbal.fromJson(json as Map<String, dynamic>)).toList();
          herbalsLoading = false;
        });
      } else {
        setState(() {
          herbalsError = 'Failed to load herbals.';
          herbalsLoading = false;
        });
      }
    } catch (e) {
      print('[Nutrition+] Herbals API error: $e');
      setState(() {
        herbalsError = 'Error: ' + e.toString();
        herbalsLoading = false;
      });
    }
  }

  Future<void> _fetchSupplements() async {
    print('[Nutrition+] Fetching supplements (API fetch started)...');
    setState(() {
      supplementsLoading = true;
      supplementsError = null;
    });

    const String cacheKey = 'nutrition_supplements';
    const String cacheTsKey = 'nutrition_supplements_ts';

    try {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();

      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
          print('[Nutrition+] Loaded supplements from cache.');
          setState(() {
            fetchedSupplements = (cachedData as List)
                .map((json) => Supplement.fromJson(json as Map<String, dynamic>))
                .toList();
            supplementsLoading = false;
          });
          return;
        }
      }

      final String baseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/supplements'));

      print(
          '[Nutrition+] Supplements API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> dataList;

        if (decoded is List) {
          dataList = decoded;
          print('[Nutrition+] Supplements API: decoded is List');
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          dataList = decoded['data'];
          print('[Nutrition+] Supplements API: decoded is Map with data field');
        } else {
          dataList = [];
          print('[Nutrition+] Supplements API: Unexpected response format');
        }

        await UserCache.saveData(cacheKey, dataList);
        await UserCache.saveData(cacheTsKey, now.toIso8601String());

        setState(() {
          fetchedSupplements =
              dataList.map((json) => Supplement.fromJson(json as Map<String, dynamic>)).toList();
          supplementsLoading = false;
        });
      } else {
        setState(() {
          supplementsError = 'Failed to load supplements.';
          supplementsLoading = false;
        });
      }
    } catch (e) {
      print('[Nutrition+] Supplements API error: $e');
      setState(() {
        supplementsError = 'Error: ' + e.toString();
        supplementsLoading = false;
      });
    }
  }

  Future<void> _fetchGadgets() async {
    print('[Nutrition+] Fetching gadgets (API fetch started)...');
    setState(() {
      gadgetsLoading = true;
      gadgetsError = null;
    });

    const String cacheKey = 'nutrition_gadgets';
    const String cacheTsKey = 'nutrition_gadgets_ts';

    try {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();

      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) < CacheConfig.allMealsCacheDuration) {
          print('[Nutrition+] Loaded gadgets from cache.');
          setState(() {
            fetchedGadgets = (cachedData as List)
                .map((json) => Gadget.fromJson(json as Map<String, dynamic>))
                .toList();
            gadgetsLoading = false;
          });
          return;
        }
      }

      final String baseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/gadgets'));

      print('[Nutrition+] Gadgets API response: status=${response.statusCode}');
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        List<dynamic> dataList;

        if (decoded is List) {
          dataList = decoded;
          print('[Nutrition+] Gadgets API: decoded is List');
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          dataList = decoded['data'];
          print('[Nutrition+] Gadgets API: decoded is Map with data field');
        } else {
          dataList = [];
          print('[Nutrition+] Gadgets API: Unexpected response format');
        }

        await UserCache.saveData(cacheKey, dataList);
        await UserCache.saveData(cacheTsKey, now.toIso8601String());

        setState(() {
          fetchedGadgets =
              dataList.map((json) => Gadget.fromJson(json as Map<String, dynamic>)).toList();
          gadgetsLoading = false;
        });
      } else {
        setState(() {
          gadgetsError = 'Failed to load gadgets.';
          gadgetsLoading = false;
        });
      }
    } catch (e) {
      print('[Nutrition+] Gadgets API error: $e');
      setState(() {
        gadgetsError = 'Error: ' + e.toString();
        gadgetsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition+'),
        actions: [
          AnimatedBuilder(
            animation: _refreshIconController,
            builder: (context, child) {
              bool isLoading = false;
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
                  angle: isLoading ? _refreshIconController.value * 6.3 : 0,
                  child: const Icon(Icons.refresh),
                ),
                tooltip: 'Refresh',
                onPressed: () {
                  switch (_tabController.index) {
                    case 0:
                      _fetchSpices();
                      break;
                    case 1:
                      _fetchHerbals();
                      break;
                    case 2:
                      _fetchSupplements();
                      break;
                    case 3:
                      _fetchGadgets();
                      break;
                  }
                },
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
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
          _buildTabContent(
            loading: spicesLoading,
            error: spicesError,
            items: fetchedSpices,
            onRetry: _fetchSpices,
            label: 'spices',
          ),
          _buildTabContent<Herbal>(
            loading: herbalsLoading,
            error: herbalsError,
            items: fetchedHerbals,
            onRetry: _fetchHerbals,
            label: 'herbals',
          ),
          _buildTabContent<Supplement>(
            loading: supplementsLoading,
            error: supplementsError,
            items: fetchedSupplements,
            onRetry: _fetchSupplements,
            label: 'supplements',
          ),
          _buildTabContent<Gadget>(
            loading: gadgetsLoading,
            error: gadgetsError,
            items: fetchedGadgets,
            onRetry: _fetchGadgets,
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
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Center(child: Text('No $label found.'));
    }
    return _buildCategoryGrid<T>(items, context, label: label);
  }

  String? getDisplayImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return ImageUtils.processImageUrl(url);
  }

  // Handle scroll events for preloading
  void _onScroll() {
    // Check if widget is still mounted and preloading is enabled
    if (!mounted || !_isPreloadingEnabled) return;
    
    // Check if scroll controller is still attached
    if (!_scrollController.hasClients) return;
    
    try {
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      
      final threshold = 0.7; // Start preloading when 70% scrolled
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      
      if (maxScroll <= 0) return; // List not yet laid out or has no scroll
      
      if (currentScroll >= (maxScroll * threshold)) {
        _preloadImages();
      }
    } catch (e) {
      // Ignore any errors during scroll handling
      debugPrint('Scroll handling error: $e');
    }
  }

  // Preload images that are about to be visible
  void _preloadImages() {
    // Check if widget is still mounted and preloading is enabled
    if (!mounted || !_isPreloadingEnabled) return;
    
    // Check if scroll controller is still attached
    if (!_scrollController.hasClients) return;
    
    // Get current tab items
    List<dynamic> currentItems = [];
    switch (_tabController.index) {
      case 0:
        currentItems = fetchedSpices;
        break;
      case 1:
        currentItems = fetchedHerbals;
        break;
      case 2:
        currentItems = fetchedSupplements;
        break;
      case 3:
        currentItems = fetchedGadgets;
        break;
    }
    
    if (currentItems.isEmpty) return;
    
    // Calculate visible items
    final firstVisibleIndex = (_scrollController.position.pixels / 200).floor();
    final lastVisibleIndex = ((_scrollController.position.pixels + 
        MediaQuery.of(context).size.height) / 200).ceil();
    
    // Preload images for items slightly beyond the visible area
    final preloadStart = firstVisibleIndex.clamp(0, currentItems.length - 1);
    final preloadEnd = (lastVisibleIndex + _preloadThreshold)
        .clamp(0, currentItems.length - 1);
    
    for (int i = preloadStart; i <= preloadEnd; i++) {
      if (i >= 0 && i < currentItems.length) {
        final item = currentItems[i];
        String? imageUrl;
        
        if (item is NutritionItem) {
          imageUrl = getDisplayImageUrl(item.imagePath);
        } else if (item is Herbal) {
          imageUrl = getDisplayImageUrl(item.imageUrl);
        } else if (item is Supplement) {
          imageUrl = getDisplayImageUrl(item.imageUrl);
        } else if (item is Gadget) {
          imageUrl = getDisplayImageUrl(item.imageUrl);
        }
        
        if (imageUrl != null && imageUrl.startsWith('http')) {
          try {
            // Preload the image into cache silently
            cn.CachedNetworkImageProvider(imageUrl)
              .resolve(ImageConfiguration())
              .addListener(
                ImageStreamListener(
                  (_, __) {},
                  onError: (dynamic error, StackTrace? stackTrace) {
                    // Silently handle errors during preloading
                    debugPrint('Error preloading image: $error');
                  },
                ),
              );
          } catch (e) {
            debugPrint('Error setting up image preload: $e');
          }
        }
      }
    }
  }

  Widget _buildCategoryGrid<T>(List<T> items, BuildContext context, {String? defaultItemImagePath, String? label}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo is ScrollEndNotification) {
            _scrollController.removeListener(_onScroll);
            _scrollController.addListener(_onScroll);
            _preloadImages();
          }
          return false;
        },
        child: GridView.builder(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            childAspectRatio: 0.80,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) {
            // Preload images for the first few items
            if (index < 10) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _preloadImages();
              });
            }
            
            return AnimatedOpacity(
              opacity: 1.0,
              duration: Duration(milliseconds: 400 + (index % 5 * 100)),
              curve: Curves.easeOut,
              child: _buildItemCard<T>(items[index], context, label: label, defaultItemImagePath: defaultItemImagePath),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemCard<T>(T item, BuildContext context, {String? label, String? defaultItemImagePath}) {
    String? imageUrl;
    String name = '';
    double? price;
    String heroTag = '';

    if (item is NutritionItem) {
      imageUrl = getDisplayImageUrl(item.imagePath);
      name = item.name;
      price = item.price;
      heroTag = item.heroTag;
    } else if (item is Herbal) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.herbalName;
      price = item.price;
      heroTag = item.herbalName;
    } else if (item is Supplement) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.supplementName;
      price = item.price;
      heroTag = item.supplementName;
    } else if (item is Gadget) {
      imageUrl = getDisplayImageUrl(item.imageUrl);
      name = item.gadgetName;
      price = item.price;
      heroTag = item.gadgetName;
    }

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
            // Only NutritionItem supports inline base64 images
            Widget? decodedImageWidget;
            if (item is NutritionItem && item.imagePath != null && item.imagePath!.startsWith('data:image')) {
              try {
                final base64Str = item.imagePath!.split(',').last;
                final bytes = base64Decode(base64Str);
                decodedImageWidget = Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: 110);
              } catch (e) {
                decodedImageWidget = null;
              }
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  NutritionItem detailItem;
                  if (item is NutritionItem) {
                    detailItem = item;
                  } else if (item is Herbal) {
                    detailItem = NutritionItem(
                      id: item.herbalId.toString(),
                      type: 'herbal',
                      name: item.herbalName,
                      imagePath: item.imageUrl,
                      description: item.description,
                      price: item.price,
                      idKey: 'herbal_id',
                      rawData: {
                        'herbal_id': item.herbalId,
                        'herbal_name': item.herbalName,
                        'description': item.description,
                        'unit': item.unit,
                        'price': item.price,
                        'image_url': item.imageUrl,
                        'date_added': item.dateAdded?.toIso8601String(),
                        'added_by': item.addedBy,
                        'added_by_type': item.addedByType,
                        'updated_at': item.updatedAt?.toIso8601String(),
                      },
                    );
                  } else if (item is Supplement) {
                    detailItem = NutritionItem(
                      id: item.supplementId.toString(),
                      type: 'supplement',
                      name: item.supplementName,
                      imagePath: item.imageUrl,
                      description: item.description,
                      price: item.price,
                      idKey: 'supplement_id',
                      rawData: {
                        'supplement_id': item.supplementId,
                        'supplement_name': item.supplementName,
                        'description': item.description,
                        'unit': item.unit,
                        'price': item.price,
                        'image_url': item.imageUrl,
                        'date_added': item.dateAdded?.toIso8601String(),
                        'added_by': item.addedBy,
                        'added_by_type': item.addedByType,
                      },
                    );
                  } else if (item is Gadget) {
                    detailItem = NutritionItem(
                      id: item.gadgetId.toString(),
                      type: 'gadget',
                      name: item.gadgetName,
                      imagePath: item.imageUrl,
                      description: item.description,
                      price: item.price,
                      idKey: 'gadget_id',
                      rawData: {
                        'gadget_id': item.gadgetId,
                        'gadget_name': item.gadgetName,
                        'description': item.description,
                        'brand': item.brand,
                        'model': item.model,
                        'price': item.price,
                        'image_url': item.imageUrl,
                        'date_added': item.dateAdded?.toIso8601String(),
                        'added_by': item.addedBy,
                        'added_by_type': item.addedByType,
                        'updated_at': item.updatedAt?.toIso8601String(),
                      },
                    );
                  } else {
                    detailItem = NutritionItem(
                      id: '',
                      type: 'unknown',
                      name: '',
                      imagePath: null,
                      description: null,
                      price: null,
                      idKey: '',
                      rawData: {},
                    );
                  }
                  return Nutri_DetailPage(
                    item: detailItem,
                    decodedImage: decodedImageWidget,
                  );
                },
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Hero(
                  tag: heroTag,
                  flightShuttleBuilder: (
                    BuildContext flightContext,
                    Animation<double> animation,
                    HeroFlightDirection flightDirection,
                    BuildContext fromHeroContext,
                    BuildContext toHeroContext,
                  ) {
                    final Hero toHero = toHeroContext.widget as Hero;
                    return FadeTransition(
                      opacity: animation.drive(
                        Tween<double>(begin: 0.85, end: 1.0).chain(
                          CurveTween(curve: Curves.easeInOut),
                        ),
                      ),
                      child: toHero.child,
                    );
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(15.0)),
                      child: imageUrl != null && imageUrl.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 110,
                              placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  width: double.infinity,
                                  height: 110,
                                  color: Colors.white,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: errorIconColor,
                                    size: 40.0,
                                  ),
                                ),
                              ),
                            )
                          : (defaultItemImagePath != null
                              ? Image.asset(
                                  defaultItemImagePath,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: 110,
                                )
                              : Container(
                                  color: Colors.grey[200],
                                  width: double.infinity,
                                  height: 110,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: errorIconColor,
                                      size: 40.0,
                                    ),
                                  ),
                                )),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      price != null
                          ? 'ugx ${price!.toStringAsFixed(2)}'
                          : 'Price: not available',
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
