import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:zinzi2/allmeals.dart'; // Assuming this screen exists
import 'package:zinzi2/cart.dart'; // Imports the SHARED cart and favorites are also contined within
import 'package:zinzi2/checkout.dart'; // Assuming this screen exists
import 'package:zinzi2/useranalytics.dart'; // Assuming this screen exists if needed
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart'; // For consistent font
import 'package:zinzi2/widgets/app_drawer.dart'; // Import the AppDrawer
import 'package:zinzi2/user_cache.dart'; // Import UserCache
import 'package:zinzi2/cache_config.dart'; // Import CacheConfig
import 'package:intl/intl.dart';

// Assuming dotenv is initialized elsewhere in your main.dart or similar
final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// --- Static Chef Data (Fallback) ---
class ChefData {
  static List<Map<String, dynamic>> chefs = [
    {
      'image': 'assets/images/kharol.jpg',
      'name': 'Kharol',
      'price': 7.0,
      'rating': 3.0,
      'location': 'KATWE',
    },
    {
      'image': 'assets/images/dani3.jpg',
      'name': 'Edgar',
      'price': 5.0,
      'rating': 3.0,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/abdul.jpg',
      'name': 'Abdul',
      'price': 5.0,
      'rating': 3.0,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/zay.jpg',
      'name': 'Nick',
      'price': 45.0,
      'rating': 5.0,
      'location': 'NEW YORK',
    },
    {
      'image': 'assets/images/victor.jpg',
      'name': 'Victor',
      'price': 5.0,
      'rating': 3.0,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/dante.jpg',
      'name': 'Dante',
      'price': 4.0,
      'rating': 2.0,
      'location': 'MAWANDA Rd',
    },
    // Add placeholder image path for safety if needed
    {
      'image': 'assets/images/placeholderchef.jpeg',
      'name': 'Default Chef',
      'price': 0.0,
      'rating': 0.0,
      'location': 'N/A',
      'chefid': -1 // Default ID
    },
  ];
}

// --- Meal Detail Screen ---
class MealDetailScreen extends StatefulWidget {
  final Map<String, dynamic> meal;

  MealDetailScreen({required this.meal});

  // --- Caching ---
  static List<dynamic> _chefsCache = [];
  static DateTime? _chefsCacheTimestamp;
  static List<dynamic> _producersCache = [];
  static DateTime? _producersCacheTimestamp;

  static const String _chefsCacheKey = 'chefs_list_cache';
  static const String _chefsCacheTimestampKey = 'chefs_list_cache_timestamp';
  static const String _producersCacheKey = 'producers_list_cache';
  static const String _producersCacheTimestampKey =
      'producers_list_cache_timestamp';

  // Load chef cache from UserCache
  static Future<void> loadChefsCacheFromUserCache() async {
    final cachedData = await UserCache.getData(_chefsCacheKey);
    final timestampData = await UserCache.getData(_chefsCacheTimestampKey);

    if (cachedData != null && timestampData != null) {
      try {
        _chefsCache = List<dynamic>.from(cachedData);
        _chefsCacheTimestamp = DateTime.parse(timestampData);
      } catch (_) {
        _chefsCache = [];
        _chefsCacheTimestamp = null;
      }
    } else {
       _chefsCache = [];
       _chefsCacheTimestamp = null;
    }
  }

  // Save chef cache to UserCache
  static Future<void> saveChefsCacheToUserCache(List<dynamic> chefs) async {
    await UserCache.saveData(_chefsCacheKey, chefs);
    await UserCache.saveData(
        _chefsCacheTimestampKey, DateTime.now().toIso8601String());
  }

  // Load producer cache from UserCache
  static Future<void> loadProducersCacheFromUserCache() async {
    final cachedData = await UserCache.getData(_producersCacheKey);
    final timestampData = await UserCache.getData(_producersCacheTimestampKey);

    if (cachedData != null && timestampData != null) {
      try {
        _producersCache = List<dynamic>.from(cachedData);
        _producersCacheTimestamp = DateTime.parse(timestampData);
      } catch (_) {
        _producersCache = [];
        _producersCacheTimestamp = null;
      }
    } else {
       _producersCache = [];
       _producersCacheTimestamp = null;
    }
  }

  // Save producer cache to UserCache
  static Future<void> saveProducersCacheToUserCache(
      List<dynamic> producers) async {
    await UserCache.saveData(_producersCacheKey, producers);
    await UserCache.saveData(
        _producersCacheTimestampKey, DateTime.now().toIso8601String());
  }

  @override
  _MealDetailScreenState createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  bool _ingredientsExpanded = false;
  bool isFavorite = false;
  bool isChefSelected = true; // Default view to 'Cooked' (Chefs)
  bool _isInCart = false;
  bool _isBulkOrder = false;
  DateTime? _planStartDate;
  DateTime? _planEndDate;
  String _selectedFrequency = 'daily';
  int _quantityPerDay = 1;
  Set<String> _selectedDays = {};
  Map<String, dynamic>? selectedChef;
  Map<String, dynamic>? selectedProducer;
  List<dynamic> chefs = [];
  List<dynamic> producers = [];
  bool isLoadingChefs = true;
  bool isLoadingProducers = true;
  bool isInCart = false;
  List<bool> complementaryInCartStatus = [];
  bool _isFetchingChefs = false; // Prevent overlapping chef fetches
  bool _isFetchingProducers = false; // Prevent overlapping producer fetches
  String _chefSearchQuery = '';
  String _producerSearchQuery = '';
  final TextEditingController _chefSearchController = TextEditingController();
  final TextEditingController _producerSearchController =
      TextEditingController();

  // --- UI Constants (Teal Based, Mistkly Look) ---
  static const double _horizontalPadding = 16.0;
  static const double _verticalPadding = 16.0;
  static const double _sectionSpacing = 16.0;
  static const double _cardElevation = 1.0;
  static const double _cardCornerRadius = 12.0;
  static const double _buttonCornerRadius = 8.0;

  static const Color kColorPrimary = Color(0xFF00796B); // Teal Primary
  static const Color kColorPrimaryDark = Color(0xFF004D40); // Darker Teal
  static const Color kColorPrimaryLight = Color(0xFFB2DFDB); // Lighter Teal
  static const Color kColorAccent = Color(0xFFFFAB40); // Orange Accent
  static const Color kColorBackground =
      Color(0xFFF5F5F5); // Light Grey Background
  static const Color kColorSurface = Colors.white;
  static const Color kColorTextPrimary = Color(0xFF212121);
  static const Color kColorTextSecondary = Color(0xFF757575);
  static const Color kColorError = Color(0xFFD32F2F);
  static const Color kColorSuccess = Color(0xFF2E7D32);
  static const Color kColorDivider = Color(0xFFE0E0E0);
  static final Color kBottomSheetBgColor = Colors.teal.shade50;

  @override
  void initState() {
    super.initState();
    // Ensure bestservedwith is populated for cart logic
    if (widget.meal['bestservedwith'] == null && widget.meal['Complementary_dishes'] != null) {
      final dishes = _parseListFromString(widget.meal['Complementary_dishes']);
      final images = _parseListFromString(widget.meal['complementary_images']);
      widget.meal['bestservedwith'] = List.generate(
        dishes.length,
        (i) => {
          'name': dishes[i],
          'price': '0', // Default to 0 if absent
          'image': images.length > i ? images[i] : '',
        },
      );
    }
    _initializeData();
  }

  Future<void> _initializeData() async {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';

    // --- CRITICAL: Use the imported (shared) Favorites and ShoppingCart ---
    isFavorite = Favorites.isFavorite(mealTitle);
    var currentItemInCart = ShoppingCart.items.firstWhere(
      (item) => item['title'] == mealTitle,
      orElse: () => {}, // Return an empty map if not found
    );
    if (currentItemInCart != null) {
      isInCart = true;
      selectedChef = currentItemInCart['selectedchef'];
      selectedProducer = currentItemInCart['selectedproducer'];
      isChefSelected = selectedProducer == null;
    } else {
      isInCart = false;
      selectedChef = null;
      selectedProducer = null;
      isChefSelected = true;
    }
    // --- End Critical Section ---

    // Load data (respecting cache)
    await _loadData();
  }

  // --- Load Data with Cache Logic ---
  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Load caches from persistent storage immediately
    await MealDetailScreen.loadChefsCacheFromUserCache();
    await MealDetailScreen.loadProducersCacheFromUserCache();

    final now = DateTime.now();
    bool chefsCacheValid = MealDetailScreen._chefsCache.isNotEmpty &&
        MealDetailScreen._chefsCacheTimestamp != null &&
        now.difference(MealDetailScreen._chefsCacheTimestamp!) <
            CacheConfig.chefProducerDetailCacheDuration; // Use updated duration
    bool producersCacheValid = MealDetailScreen._producersCache.isNotEmpty &&
        MealDetailScreen._producersCacheTimestamp != null &&
        now.difference(MealDetailScreen._producersCacheTimestamp!) <
            CacheConfig.chefProducerDetailCacheDuration; // Use updated duration

    // Always display cached data immediately if available
    setState(() {
      if (MealDetailScreen._chefsCache.isNotEmpty) {
        chefs = MealDetailScreen._chefsCache;
        isLoadingChefs =
            false; // Assume not loading initially if cache is present
      } else {
        isLoadingChefs = true; // Show loading if no cache
      }

      if (MealDetailScreen._producersCache.isNotEmpty) {
        producers = MealDetailScreen._producersCache;
        isLoadingProducers =
            false; // Assume not loading initially if cache is present
      } else {
        isLoadingProducers = true; // Show loading if no cache
      }
    });

    // Fetch new data in the background if cache is invalid or force refresh
    if (forceRefresh || !chefsCacheValid) {
      print("Fetching chefs (Cache invalid/empty or forced refresh)");
      // Do not await, let it run in the background
      fetchChefsWithRetry();
    } else {
       // If cache is valid and not forcing refresh, ensure loading is off
       if (mounted) setState(() => isLoadingChefs = false);
    }

    if (forceRefresh || !producersCacheValid) {
      print("Fetching producers (Cache invalid/empty or forced refresh)");
      // Do not await, let it run in the background
      fetchProducers();
    } else {
       // If cache is valid and not forcing refresh, ensure loading is off
       if (mounted) setState(() => isLoadingProducers = false);
    }
  }

  // --- Manual Refresh Logic ---
  Future<void> _handleRefresh() async {
    print("Manual refresh triggered.");
    await _loadData(forceRefresh: true);
    showCustomSnackBar(context, 'Data refreshed!');
  }

  // --- Fetch Chefs Logic ---
  Future<void> fetchChefs() async {
    if (_isFetchingChefs || !mounted)
      return; // Prevent overlapping fetches or running if disposed

    // Only show loading indicator if there's no cached data currently displayed
    if (chefs.isEmpty) {
      setState(() {
        isLoadingChefs = true;
      });
    }
    setState(() {
      _isFetchingChefs = true;
    });

    final url = '$apibaseurl/rr/rchefs';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 25)); // Increased timeout
      if (!mounted) return;

      List<dynamic> chefsList = []; // Initialize outside conditional blocks

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Handle both direct list and nested map responses
        if (responseData is List) {
          chefsList = responseData.asMap().entries.map((entry) {
            final index = entry.key;
            final chef = entry.value;
            return _mapChefData(chef, index);
          }).toList();
        } else if (responseData is Map<String, dynamic> &&
            responseData['data'] != null &&
            responseData['data'] is List) {
          chefsList =
              (responseData['data'] as List).asMap().entries.map((entry) {
            final index = entry.key;
            final chef = entry.value;
            return _mapChefData(chef, index);
          }).toList();
        } else {
          print('Unexpected response format for chefs: $responseData');
          // If format is wrong, keep the current list (could be cached or empty)
          // chefsList = chefs; // Keep current list
        }

        // Update state and cache if new data is successfully fetched
        if (chefsList.isNotEmpty) {
           setState(() {
             chefs = chefsList;
             MealDetailScreen._chefsCache = chefsList; // Update static cache
            MealDetailScreen._chefsCacheTimestamp =
                DateTime.now(); // Update static timestamp
           });
           // Save to persistent cache
           await MealDetailScreen.saveChefsCacheToUserCache(chefsList);
        } else {
           // If fetch was successful but returned empty list, and no cache was present,
           // ensure the displayed list is empty and loading is off.
           if (chefs.isEmpty) {
              setState(() {
                 chefs = [];
                 isLoadingChefs = false;
              });
           }
        }
      } else {
        // Handle non-200 status codes
        print('Failed to load chefs. Status code: ${response.statusCode}.');
        // If no cache was present, show error and set chefs to empty
        if (chefs.isEmpty) {
           setState(() {
              chefs = [];
              isLoadingChefs = false;
           });
          showCustomSnackBar(
              context, 'Failed to load chefs. Please try again.');
        }
        // If cache was present, just log the error and keep showing cache.
      }
    } on TimeoutException {
      print('Chef fetch timed out.');
      // If no cache was present, show error and set chefs to empty
      if (chefs.isEmpty) {
         setState(() {
            chefs = [];
            isLoadingChefs = false;
         });
         showCustomSnackBar(context, 'Chef request timed out.');
      }
      // If cache was present, just log the error and keep showing cache.
    } on Exception catch (e) {
      print('Error fetching chefs: $e');
      // If no cache was present, show error and set chefs to empty
      if (chefs.isEmpty) {
         setState(() {
            chefs = [];
            isLoadingChefs = false;
         });
         showCustomSnackBar(context, 'Unable to load chefs. An error occurred.');
      }
      // If cache was present, just log the error and keep showing cache.
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingChefs = false; // Always reset fetching flag
          // isLoadingChefs is managed within the try/catch blocks now
        });
      }
    }
  }

  // Helper to map chef data consistently
  Map<String, dynamic> _mapChefData(dynamic chef, int index) {
    // Ensure chef is a Map
    if (chef is! Map<String, dynamic>) {
      print(
          'Warning: Expected chef data to be a Map, but got ${chef.runtimeType}');
      // Return a default placeholder chef using data from ChefData if possible, or hardcoded defaults
      var fallbackChef = ChefData.chefs.firstWhere(
          (c) => c['name'] == 'Default Chef',
          orElse: () => ChefData.chefs[0]);
      return {
        'image': fallbackChef['image'] ?? 'assets/images/placeholderchef.jpeg',
        'name': fallbackChef['name'] ?? 'Unknown Chef $index',
        'price': fallbackChef['price'] ?? 0.0,
        'rating': fallbackChef['rating'] ?? 0.0,
        'location': fallbackChef['location'] ?? 'Unknown Location',
        'chefid':
            fallbackChef['chefid'] ?? index, // Use default chefid or index
      };
    }
    return {
      'image': chef['image'] ?? 'assets/images/placeholderchef.jpeg',
      'name': chef['name'] ?? 'Unknown Chef',
      'price': double.tryParse(chef['price']?.toString() ?? '0.0') ?? 0.0,
      'rating': double.tryParse(chef['rating']?.toString() ?? '0.0') ?? 0.0,
      'location': chef['location'] ?? 'Unknown Location',
      'chefid': chef['chefid'] ?? index, // Fallback unique ID using index
    };
  }

  // --- Fetch Chefs with Retry Logic ---
  Future<void> fetchChefsWithRetry({int retryCount = 2}) async {
    for (int i = 0; i < retryCount; i++) {
      await fetchChefs();
      // If fetchChefs successfully populated the list (even with fallback), exit retry loop
      if (mounted && chefs.isNotEmpty) {
        return;
      }
      // If still mounted and chefs list is empty after fetch attempt, print retry message
      if (mounted) {
        print('Retry ${i + 1} for fetchChefs...');
        if (i < retryCount - 1) {
          await Future.delayed(Duration(seconds: 1 * (i + 1))); // Backoff delay
        }
      } else {
        // If not mounted anymore, break the loop
        break;
      }
    }
    // After all retries, if still no chefs and mounted, show final message
    if (mounted && chefs.isEmpty) {
      print('Final retry failed for fetchChefs. Using default list.');
      setState(() {
        chefs = ChefData.chefs; // Ensure fallback is set finally
        isLoadingChefs = false;
        _isFetchingChefs = false;
      });
      showCustomSnackBar(
          context, 'Failed to load chefs after multiple attempts.');
    }
  }

  // --- Fetch Producers Logic ---
  Future<void> fetchProducers() async {
    if (_isFetchingProducers || !mounted)
      return; // Prevent overlapping fetches or running if disposed

    // Only show loading indicator if there's no cached data currently displayed
    if (producers.isEmpty) {
      setState(() {
        isLoadingProducers = true;
      });
    }
    setState(() {
      _isFetchingProducers = true;
    });

    final url = '$apibaseurl/rr/rproducers';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 25)); // Increased timeout
      if (!mounted) return;

      List<dynamic> producerRawList = [];

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        List<dynamic> producerRawList = [];

        if (responseData is List) {
          producerRawList = responseData;
        } else if (responseData is Map<String, dynamic> &&
            responseData['data'] is List) {
          producerRawList = responseData['data'];
        } else {
          print('Unexpected response format for producers: $responseData');
          // If format is wrong, keep the current list (could be cached or empty)
          // producerRawList = producers; // Keep current list
        }

        final mappedProducers = producerRawList.map((producer) {
          // Ensure producer is a Map
          if (producer is! Map<String, dynamic>) {
            print(
                'Warning: Expected producer data to be a Map, but got ${producer.runtimeType}');
            // Return a default placeholder producer
            return {
              'producer_id': -1, // Default ID
              'name': 'Unknown Producer',
              'image': 'assets/images/producerHolder.png',
              'Location':
                  'Unknown Location', // Ensure keys match expected usage
              'Rating': 0.0,
            };
          }
          // Proceed with mapping if it's a Map
          final name = (producer['name'] != null &&
                  producer['name'].toString().trim().isNotEmpty)
              ? producer['name'].toString()
              : 'Unknown Producer';
          final image = (producer['image'] != null &&
                  producer['image'].toString().trim().isNotEmpty)
              ? producer['image'].toString()
              : 'assets/images/producerHolder.png'; // Default placeholder
          final location = (producer['location'] != null &&
                  producer['location'].toString().trim().isNotEmpty)
              ? producer['location'].toString()
              : 'Unknown Location'; // Default location text
          final rating = producer['rating'] != null
              ? double.tryParse(producer['rating'].toString()) ?? 0.0
              : 0.0;
          // IMPORTANT: Ensure 'producer_id' exists and provide a fallback
          final id = producer['producer_id'] ??
              DateTime.now()
                  .millisecondsSinceEpoch; // Use timestamp as fallback ID

          return {
            'producer_id': id,
            'name': name,
            'image': image,
            'Location':
                location, // Using CamelCase 'Location' as key (match usage in _buildProducerList)
            'Rating':
                rating, // Using CamelCase 'Rating' as key (match usage in _buildProducerList)
          };
        }).toList();

        // Update state and cache if new data is successfully fetched
        if (mappedProducers.isNotEmpty) {
           setState(() {
             producers = mappedProducers;
            MealDetailScreen._producersCache =
                mappedProducers; // Update static cache
            MealDetailScreen._producersCacheTimestamp =
                DateTime.now(); // Update static timestamp
           });
           // Save to persistent cache
           await MealDetailScreen.saveProducersCacheToUserCache(mappedProducers);
        } else {
           // If fetch was successful but returned empty list, and no cache was present,
           // ensure the displayed list is empty and loading is off.
           if (producers.isEmpty) {
              setState(() {
                 producers = [];
                 isLoadingProducers = false;
              });
           }
        }
      } else {
        // Handle non-200 status codes
        print('Failed to load producers. Status code: ${response.statusCode}.');
        // If no cache was present, show error and set producers to empty
        if (producers.isEmpty) {
           setState(() {
              producers = [];
              isLoadingProducers = false;
           });
          showCustomSnackBar(
              context, 'Failed to load producers. Please try again.');
        }
        // If cache was present, just log the error and keep showing cache.
      }
    } on TimeoutException {
      print('Producer fetch timed out.');
      // If no cache was present, show error and set producers to empty
      if (producers.isEmpty) {
         setState(() {
            producers = [];
            isLoadingProducers = false;
         });
         showCustomSnackBar(context, 'Producer request timed out.');
      }
      // If cache was present, just log the error and keep showing cache.
    } catch (e) {
      print('Error fetching producers: $e');
      // If no cache was present, show error and set producers to empty
      if (producers.isEmpty) {
         setState(() {
            producers = [];
            isLoadingProducers = false;
         });
         showCustomSnackBar(
             context, 'Unable to load producers. An error occurred.');
      }
      // If cache was present, just log the error and keep showing cache.
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingProducers = false; // Always reset fetching flag
          // isLoadingProducers is managed within the try/catch blocks now
        });
      }
    }
  }

  // --- UI Interaction Methods ---

  void _toggleFavorite(String title) {
    // --- Use the imported (shared) Favorites ---
    setState(() {
      if (isFavorite) {
        Favorites.removeItem(title);
        showCustomSnackBar(context, '$title removed from favorites.');
      } else {
        double price = _parsePrice(widget.meal['Price']);
        String image = widget.meal['Image_link'] ?? 'assets/images/cover.png';
        Favorites.addItem(title, price, image);
        showCustomSnackBar(context, '$title added to favorites!');
      }
      isFavorite =
          !isFavorite; // Toggle local state AFTER updating shared state
    });
    // --- End Favorites ---
  }

  void _chooseChef(Map<String, dynamic> chef) {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    double price = _parsePrice(widget.meal['Price']);

    setState(() {
      // Ensure chef object has 'chefid' field
      Map<String, dynamic> chefWithId = Map<String, dynamic>.from(chef);
      if (!chefWithId.containsKey('chefid') && chefWithId.containsKey('id')) {
        chefWithId['chefid'] = chefWithId['id'];
      }
      selectedChef = chefWithId;
      selectedProducer = null; // Deselect producer
      isChefSelected = true; // Update the selection state for UI

      // --- Use the imported (shared) ShoppingCart ---
      // Always add/update the item. The addItem method in cart.dart handles replacement.
      ShoppingCart.addItem(
        mealTitle,
        price,
        selectedchef: selectedChef, // Pass the newly selected chef
        selectedproducer: null, // Ensure producer is null
        meal: widget.meal, bestservedwith: [], // Pass the full meal data
      );
      isInCart = true; // Ensure cart status reflects the addition/update
    });
    showCustomSnackBar(context, '${chef['name']} selected!');
    Navigator.pop(context); // Close the bottom sheet after selection
  }

  void _chooseProducer(Map<String, dynamic> producer) {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    double price = _parsePrice(widget.meal['Price']);

    // --- Use the imported (shared) ShoppingCart ---
    setState(() {
      // Ensure producer object has 'producer_id' field
      Map<String, dynamic> producerWithId = Map<String, dynamic>.from(producer);
      if (!producerWithId.containsKey('producer_id') &&
          producerWithId.containsKey('id')) {
        producerWithId['producer_id'] = producerWithId['id'];
      }
      selectedProducer = producerWithId;
      selectedChef = null; // Deselect chef
      isChefSelected = false; // Update the selection state for UI

      // Collect selected complementaries
      List<Map<String, String>> selectedComplementaries = [];
      if (complementaryInCartStatus.isNotEmpty && widget.meal['bestservedwith'] != null) {
        for (var i = 0; i < complementaryInCartStatus.length; i++) {
          if (complementaryInCartStatus[i]) {
            final complementary = widget.meal['bestservedwith'][i];
            selectedComplementaries.add({
              'name': complementary['name']?.toString() ?? '',
              'price': complementary['price']?.toString() ?? '0',
              'image': complementary['image']?.toString() ?? '',
            });
          }
        }
      }
      // Always add/update the item. The addItem method in cart.dart handles replacement.
      ShoppingCart.addItem(
        mealTitle,
        price,
        selectedchef: null, // Ensure chef is null
        selectedproducer: selectedProducer, // Pass the newly selected producer
        meal: widget.meal,
        bestservedwith: selectedComplementaries, // always pass selected
      );
      isInCart = true; // Ensure cart status reflects the addition/update
    });
    // --- End ShoppingCart ---
    showCustomSnackBar(context, '${producer['name']} selected!');
    Navigator.pop(context); // Close the bottom sheet after selection
  }

  void _toggleCart() {
    if (_isInCart) {
      final index = ShoppingCart.getItems()
          .indexWhere((item) => item['title'] == widget.meal['Meal_name']);
      if (index != -1) {
        ShoppingCart.removeItemByIndex(index);
      }
      showCustomSnackBar(
          context, '${widget.meal['Meal_name']} removed from cart');
      } else {
      if (_isBulkOrder) {
        // Add bulk order to cart
        final totalDays = _calculateTotalDays();
        final totalMeals = _calculateTotalMeals();
        final totalPrice = _parsePrice(widget.meal['Price']) * totalMeals;

        // Collect selected complementaries
      List<Map<String, String>> selectedComplementaries = [];
      if (complementaryInCartStatus.isNotEmpty && widget.meal['bestservedwith'] != null) {
        for (var i = 0; i < complementaryInCartStatus.length; i++) {
          if (complementaryInCartStatus[i]) {
            final complementary = widget.meal['bestservedwith'][i];
            selectedComplementaries.add({
              'name': complementary['name']?.toString() ?? '',
              'price': complementary['price']?.toString() ?? '0',
              'image': complementary['image']?.toString() ?? '',
            });
          }
        }
      }
      ShoppingCart.addItem(
        widget.meal['Meal_name'],
        totalPrice,
        quantity: totalMeals,
        selectedchef: selectedChef,
        meal: widget.meal,
        bestservedwith: selectedComplementaries, // always pass selected
      );

        showCustomSnackBar(context, 'Bulk order added to cart');
      } else {
        // Add single order to cart
        // Collect selected complementaries
      List<Map<String, String>> selectedComplementaries = [];
      if (complementaryInCartStatus.isNotEmpty && widget.meal['bestservedwith'] != null) {
        for (var i = 0; i < complementaryInCartStatus.length; i++) {
          if (complementaryInCartStatus[i]) {
            final complementary = widget.meal['bestservedwith'][i];
            selectedComplementaries.add({
              'name': complementary['name']?.toString() ?? '',
              'price': complementary['price']?.toString() ?? '0',
              'image': complementary['image']?.toString() ?? '',
            });
          }
        }
      }
      ShoppingCart.addItem(
        widget.meal['Meal_name'],
        _parsePrice(widget.meal['Price']),
        quantity: 1,
        selectedchef: selectedChef,
        meal: widget.meal,
        bestservedwith: selectedComplementaries, // always pass selected
      );

        showCustomSnackBar(
            context, '${widget.meal['Meal_name']} added to cart');
      }
    }
    setState(() {
      _isInCart = !_isInCart;
    });
  }

  void showCustomSnackBar(BuildContext context, String message) {
    if (!Navigator.of(context).mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) {
      print("Warning: Could not find ScaffoldMessenger to show SnackBar.");
      return;
    }

    scaffoldMessenger.hideCurrentSnackBar();
    final snackBar = SnackBar(
      content: Text(message, style: TextStyle(color: Color(0xFF212121))),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(15, 60, 15, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: Color(0xFFB2DFDB),
      action: SnackBarAction(
        label: 'OK',
        textColor: Color(0xFF004D40),
        onPressed: () {
          scaffoldMessenger.hideCurrentSnackBar();
        },
      ),
    );
    scaffoldMessenger.showSnackBar(snackBar);
  }

  // Simplified complementary item handling - assumes they are added independently
  void _toggleComplementary(String title, int index, String imageUrl) {
    setState(() {
      complementaryInCartStatus[index] = !complementaryInCartStatus[index];

      // Safely get the bestservedwith list
      final bestServedWithList = widget.meal['bestservedwith'];
      if (bestServedWithList == null || bestServedWithList is! List) {
        print('Error: bestservedwith is null or not a List. Value: '
            '[31m${widget.meal['bestservedwith']}[0m');
        return;
      }
      if (index >= bestServedWithList.length) {
        print('Error: index $index out of range for bestservedwith length ${bestServedWithList.length}');
        return;
      }

      // Create a list of selected complementary items with proper type
      List<Map<String, dynamic>> selectedComplementaries = [];
      for (var i = 0; i < complementaryInCartStatus.length; i++) {
        if (complementaryInCartStatus[i]) {
          if (i >= bestServedWithList.length) {
            print('Warning: complementary index $i out of range for bestservedwith');
            continue;
          }
          final complementary = bestServedWithList[i];
          if (complementary != null) {
            double price = 0.0;
            if (complementary['price'] is double) {
              price = complementary['price'];
            } else if (complementary['price'] is int) {
              price = (complementary['price'] as int).toDouble();
            } else if (complementary['price'] is String) {
              price = double.tryParse(complementary['price']) ?? 0.0;
            }
            selectedComplementaries.add({
              'name': complementary['name']?.toString() ?? '',
              'price': price,
              'image': complementary['image']?.toString() ?? '',
            });
          } else {
            print('Warning: complementary at index $i is null');
          }
        }
      }

      // If item is already in cart, update it with new complementary selections
      if (isInCart) {
        final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
        var currentItemInCart = ShoppingCart.items.firstWhere(
          (item) => item['title'] == mealTitle,
          orElse: () => {},
        );

        if (currentItemInCart != null && currentItemInCart.isNotEmpty) {
           ShoppingCart.addItem(
            mealTitle,
            widget.meal['Price'] is double
              ? widget.meal['Price']
              : double.tryParse(widget.meal['Price'].toString()) ?? 0.0,
            quantity: currentItemInCart['quantity'] ?? 1,
             selectedchef: selectedChef,
             selectedproducer: selectedProducer,
             meal: widget.meal,
            bestservedwith: selectedComplementaries,
          );
        }
      }
    });
  }

  // --- Utility Methods ---
  double _parsePrice(dynamic rawPrice) {
    double price = 5.00; // Default
    if (rawPrice is int) {
      price = rawPrice.toDouble();
    } else if (rawPrice is double) {
      price = rawPrice;
    } else if (rawPrice is String) {
      price = double.tryParse(rawPrice) ?? 5.00;
    }
    return price;
  }

  String getShortLocation(String? location) {
    location ??= 'N/A';
    if (location.length <= 30) return location;
    return location.substring(0, 30) + '...';
  }

  String _formatImageUrl(String? imageUrl) {
    imageUrl ??= 'assets/images/cover.png'; // Default if null
    if (imageUrl.contains('drive.google.com/uc?export=view&id=')) {
      return imageUrl; // Already formatted
    } else if (imageUrl.contains('drive.google.com') &&
        imageUrl.contains('/d/')) {
      final parts = imageUrl.split('/d/');
      if (parts.length > 1) {
        final idPart = parts[1].split('/')[0];
        return 'https://drive.google.com/uc?export=view&id=$idPart';
      }
    }
    // Assume regular URL or asset path otherwise
    return imageUrl;
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    // Extract meal data safely using PascalCase keys
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    final mealDescription =
        widget.meal['Meal_description'] ?? 'No description available.';
    final List<String> ingredients =
        _parseListFromString(widget.meal['Ingredients']);
    final List<String> complementaries =
        _parseListFromString(widget.meal['Complementary_dishes']);
    final List<String> complementaryImages = _parseListFromString(
        widget.meal['complementary_images']); // Keep snake_case (added locally)

    // Initialize complementaryInCartStatus based on actual cart state (more reliable)
    // --- Use imported (shared) ShoppingCart ---
    complementaryInCartStatus = List.generate(complementaries.length, (index) {
      final title = complementaries[index];
      return ShoppingCart.items.any((item) => item['title'] == title);
    });
    // --- End ShoppingCart Check ---

    final String imageUrl = _formatImageUrl(widget.meal['Image_link']);
    double price = _parsePrice(widget.meal['Price']);

    // Determine if the current item (with potential selection) is in the cart
    // This check is more nuanced now because the item might be in cart with a different chef/producer initially
    // We update `isInCart` within `_chooseChef`/`_chooseProducer`/`_toggleCart`
    // Here, we mainly use the state variable `isInCart` which should be kept in sync.

    // Use GoogleFonts theme base
    final textTheme = Theme.of(context).textTheme.apply(
        fontFamily: GoogleFonts.poppins().fontFamily,
        bodyColor: kColorTextPrimary,
        displayColor: kColorTextPrimary);

    return Theme(
      data: Theme.of(context).copyWith(textTheme: textTheme),
      child: Scaffold(
        drawer: const AppDrawer(), // Add the drawer here
        appBar: AppBar(
          title: Text(mealTitle, style: GoogleFonts.poppins()),
          foregroundColor: Colors.white,
          backgroundColor: kColorPrimaryDark,
          elevation: 2,
          actions: [
            IconButton(
              tooltip: 'View Favorites',
              icon: Icon(Icons.favorite),
              onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => FavoritesScreen()))
                  .then((_) => setState(() {
                        isFavorite = Favorites.isFavorite(mealTitle);
                      })),
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'View Cart',
                  icon: Icon(Icons.shopping_cart),
                  onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                               builder: (context) => ShoppingCartScreen()))
                      .then((_) => setState(() {
                            var currentItemInCart =
                                ShoppingCart.items.firstWhere(
                              (item) => item['title'] == mealTitle,
                              orElse: () => {},
                            );
                            if (currentItemInCart != null) {
                              isInCart = true;
                              selectedChef = currentItemInCart['selectedchef'];
                              selectedProducer =
                                  currentItemInCart['selectedproducer'];
                              isChefSelected = selectedProducer == null;
                            } else {
                              isInCart = false;
                              selectedChef = null;
                              selectedProducer = null;
                              isChefSelected = true;
                            }
                            complementaryInCartStatus =
                                List.generate(complementaries.length, (index) {
                              final title = complementaries[index];
                              return ShoppingCart.items
                                  .any((item) => item['title'] == title);
                            });
                          })),
                ),
                if (ShoppingCart.items.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: EdgeInsets.all(2.0),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '${ShoppingCart.items.length}',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        backgroundColor: kColorBackground,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _handleRefresh, // Add refresh handler
            color: kColorPrimary, // Indicator color
            child: SingleChildScrollView(
              physics:
                  const AlwaysScrollableScrollPhysics(), // Ensure scroll even when content fits
              padding: EdgeInsets.all(_horizontalPadding.toDouble()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Meal Image ---
                  Hero(
                    tag: 'meal-${widget.meal['Meal_id'] ?? mealTitle}',
                    flightShuttleBuilder: (flightContext, animation,
                        flightDirection, fromHeroContext, toHeroContext) {
                      // Use a scale+fade transition for both directions
                      final Widget heroWidget =
                          (flightDirection == HeroFlightDirection.push)
                              ? toHeroContext.widget
                              : fromHeroContext.widget;
                      return ScaleTransition(
                        scale: animation.drive(
                            Tween<double>(begin: 0.95, end: 1.0)
                                .chain(CurveTween(curve: Curves.easeInOut))),
                        child: FadeTransition(
                          opacity: animation,
                          child: heroWidget,
                        ),
                      );
                    },
                    child: Container(
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_cardCornerRadius),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              spreadRadius: 1,
                              blurRadius: 5,
                              offset: Offset(0, 2))
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_cardCornerRadius),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          placeholder: (context, url) => Center(
                              child: CircularProgressIndicator(
                                  color: kColorPrimary)),
                          errorWidget: (context, url, error) => Image.asset(
                              'assets/images/cover.png',
                              fit: BoxFit.cover),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: _sectionSpacing),

                  // --- Meal Title, Description, Price, Actions ---
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(mealTitle,
                                    style: GoogleFonts.poppins(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: kColorPrimaryDark)),
                                SizedBox(height: 6),
                                Text(mealDescription,
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        height: 1.4,
                                        color: kColorTextSecondary)),
                                SizedBox(height: 8),
                                Text('Price: \$${price.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: kColorPrimary)),
                              ])),
                          SizedBox(width: 10),
                          Column(children: [
                            Tooltip(
                              message: isFavorite
                                  ? 'Remove from Favorites'
                                  : 'Add to Favorites',
                              child: IconButton(
                                icon: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: kColorPrimary),
                                iconSize: 30,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _toggleFavorite(mealTitle),
                              ),
                            ),
                            SizedBox(height: 8),
                            Tooltip(
                              message: (isInCart &&
                                      (selectedChef != null ||
                                          selectedProducer != null))
                                  ? 'Remove from Cart'
                                  : 'Add to Cart',
                              child: IconButton(
                                icon: Icon(
                                  (isInCart &&
                                          (selectedChef != null ||
                                              selectedProducer != null))
                                      ? Icons.shopping_cart
                                      : Icons.add_shopping_cart,
                                  color: (isInCart &&
                                          (selectedChef != null ||
                                              selectedProducer != null))
                                      ? kColorPrimary
                                      : kColorTextSecondary,
                                ),
                                iconSize: 30,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _toggleCart(),
                              ),
                            ),
                          ]),
                        ]),
                  ),
                  SizedBox(height: _sectionSpacing + 4),

                  // --- Sections ---
                  _buildBestServedWith(complementaries, complementaryImages),
                  SizedBox(height: _sectionSpacing),
                  _buildIngredientsSection(ingredients),
                  SizedBox(height: _sectionSpacing),
                  _buildPropertiesSection(),
                  SizedBox(height: _sectionSpacing),
                  _buildSkillLevelAndPrepTimeCard(),
                  SizedBox(height: _sectionSpacing + 4),

                  // --- Cooked/Fresh Selection ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      "Choose Preparation:",
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: kColorPrimaryDark),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.kitchen_outlined, size: 18),
                            label: Text('Cooked', style: GoogleFonts.poppins()),
                            onPressed: () {
                              setState(() {
                                isChefSelected = true;
                              });
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(20))),
                                builder: (context) =>
                                    _buildChefSelectionSheet(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isChefSelected
                                  ? kColorPrimary
                                  : kColorSurface,
                              foregroundColor: isChefSelected
                                  ? kColorSurface
                                  : kColorTextSecondary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      _buttonCornerRadius)),
                              side: isChefSelected
                                  ? null
                                  : BorderSide(color: kColorDivider),
                              elevation: isChefSelected ? 2 : 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.eco_outlined, size: 18),
                            label: Text('Fresh', style: GoogleFonts.poppins()),
                            onPressed: () {
                              setState(() {
                                isChefSelected = false;
                              });
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(20))),
                                builder: (context) =>
                                    _buildProducerSelectionSheet(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !isChefSelected
                                  ? kColorPrimary
                                  : kColorSurface,
                              foregroundColor: !isChefSelected
                                  ? kColorSurface
                                  : kColorTextSecondary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      _buttonCornerRadius)),
                              side: !isChefSelected
                                  ? null
                                  : BorderSide(color: kColorDivider),
                              elevation: !isChefSelected ? 2 : 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Display Selected Chef/Producer Info ---
                  _buildSelectedOptionCard(),
                  SizedBox(height: _sectionSpacing),

                  // Add meal planning section
                  _buildMealPlanningSection(),
                ],
              ),
            ),
          ),
        ), // End RefreshIndicator
        bottomNavigationBar: _buildProceedToCartButton(context),
      ),
    );
  }

  // --- Section Builder Widgets ---

  List<String> _parseListFromString(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      // Ensure all elements are strings
      return List<String>.from(data.map((e) => e.toString()));
    }
    if (data is String) {
      return data
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // If it's neither a List nor a String, return empty
    return [];
  }

  Widget _buildBestServedWith(
      List<String> complementaries, List<String> complementaryImages) {
    if (complementaries.isEmpty) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Best Served With:',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kColorPrimaryDark)),
          SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: complementaries.length,
              itemBuilder: (context, index) {
                final itemTitle = complementaries[index];
                String rawImageUrl = (index < complementaryImages.length &&
                        complementaryImages[index].isNotEmpty)
                    ? complementaryImages[index]
                    : 'assets/images/cover.png';
                final String displayImageUrl = _formatImageUrl(rawImageUrl);

                bool currentInCartStatus = complementaryInCartStatus[index];

                return GestureDetector(
                  onTap: () {
                    _toggleComplementary(itemTitle, index, displayImageUrl);
                  },
                  child: Container(
                    width: 110.0,
                    margin: EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_buttonCornerRadius),
                      color: kColorSurface,
                      boxShadow: [
                        BoxShadow(
                            color: kColorDivider.withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2))
                      ],
                      border: Border.all(
                          color: kColorPrimaryLight.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(_buttonCornerRadius)),
                          child: CachedNetworkImage(
                            imageUrl: displayImageUrl,
                            width: 110.0,
                            height: 75.0,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              height: 75.0,
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kColorPrimary)),
                            ),
                            errorWidget: (context, url, error) => Image.asset(
                                'assets/images/cover.png',
                                height: 75.0,
                                width: 110.0,
                                fit: BoxFit.cover),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(itemTitle,
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: kColorPrimaryDark,
                                      fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Row(
                                children: [
                                  Expanded(
                                      child: Text('\$2.00',
                                          style: GoogleFonts.poppins(
                                              color: kColorTextSecondary,
                                              fontSize: 12))),
                                  Icon(
                                    currentInCartStatus
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                    color: currentInCartStatus
                                        ? kColorSuccess
                                        : kColorPrimary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsSection(List<String> ingredients) {
    if (ingredients.isEmpty) return SizedBox.shrink();

    return Card(
      elevation: _cardElevation,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardCornerRadius)),
      color: kColorSurface,
      child: InkWell(
        onTap: () => setState(() {
          _ingredientsExpanded = !_ingredientsExpanded;
        }),
        borderRadius: BorderRadius.circular(_cardCornerRadius),
        child: Padding(
          padding: EdgeInsets.all(_verticalPadding * 0.8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ingredients',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kColorPrimaryDark)),
              SizedBox(height: 10),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children:
                    (_ingredientsExpanded ? ingredients : ingredients.take(6))
                         .map((ingredient) {
                   return Chip(
                     label: Text(ingredient,
                         style: GoogleFonts.poppins(
                             color: kColorPrimaryDark,
                             fontWeight: FontWeight.w500)),
                     backgroundColor: kColorPrimaryLight.withOpacity(0.2),
                     padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(8),
                       side: BorderSide(color: kColorPrimary.withOpacity(0.3)),
                     ),
                   );
                 }).toList(),
               ),
               if (ingredients.length > 6) ...[
                 SizedBox(height: 6),
                 Center(
                     child: Icon(
                         _ingredientsExpanded
                             ? Icons.expand_less
                             : Icons.expand_more,
                         color: kColorPrimary)),
               ]
             ],
           ),
         ),
       ),
     );
   }

   Widget _buildPropertiesSection() {
     final healthGoal = widget.meal['Goal']?.toString() ?? 'General Health';
     final List<String> allergens =
         _parseListFromString(widget.meal['Allergies']);
     final List<String> diseasesManaged =
         _parseListFromString(widget.meal['Disease_management']);

     bool hasHealthGoal =
         healthGoal != 'General Health' && healthGoal.isNotEmpty;
     bool hasAllergens = allergens.isNotEmpty;
     bool hasDiseases = diseasesManaged.isNotEmpty;

     if (!hasHealthGoal && !hasAllergens && !hasDiseases)
       return SizedBox.shrink();

     return Card(
       elevation: _cardElevation,
       margin: EdgeInsets.zero,
       shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(_cardCornerRadius)),
       color: kColorSurface,
       child: Padding(
         padding: EdgeInsets.all(_verticalPadding * 0.8),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text('Health Information',
                 style: GoogleFonts.poppins(
                     fontSize: 18,
                     fontWeight: FontWeight.w600,
                     color: kColorPrimaryDark)),
             SizedBox(height: 12),
             Wrap(
               spacing: 8.0,
               runSpacing: 8.0,
               children: [
                 if (hasHealthGoal)
                   _buildPropertyChip(
                       Icons.track_changes, 'Health Goal', healthGoal),
                 if (hasAllergens)
                   _buildPropertyChip(Icons.warning_amber_rounded, 'Allergens',
                       allergens.join(', ')),
                 if (hasDiseases)
                   _buildPropertyChip(Icons.healing, 'Helps Manage',
                       diseasesManaged.join(', ')),
               ],
             ),
           ],
         ),
       ),
     );
   }

   Widget _buildPropertyChip(IconData icon, String label, String data) {
     return ActionChip(
       avatar: CircleAvatar(
         backgroundColor: kColorPrimaryLight.withOpacity(0.5),
         child: Icon(icon, color: kColorPrimaryDark, size: 18),
       ),
       label: Text(label,
           style: GoogleFonts.poppins(
               color: kColorPrimaryDark, fontWeight: FontWeight.w500)),
       backgroundColor: kColorPrimaryLight.withOpacity(0.2),
       onPressed: () {
         _showPopup(context, label, data);
       },
       tooltip: data,
       shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(16),
           side: BorderSide(color: kColorPrimary.withOpacity(0.3))),
       padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
       materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
     );
   }

   // --- Popup Dialog for Properties ---
   void _showPopup(BuildContext context, String title, String content) {
     showDialog(
       context: context,
       builder: (context) {
         return AlertDialog(
           backgroundColor: Colors.teal[50],
           shape:
               RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
           title: Text(title,
               style: TextStyle(
                   color: Colors.teal[900], fontWeight: FontWeight.bold)),
           content: SingleChildScrollView(
             child: ListBody(
               children: content
                   .split(',')
                   .map((item) => Padding(
                         padding: const EdgeInsets.symmetric(vertical: 4.0),
                         child: Text(item.trim(),
                             style: TextStyle(
                                 color: Colors.teal[800], fontSize: 15)),
                       ))
                   .toList(),
             ),
           ),
           actions: [
             TextButton(
               onPressed: () => Navigator.of(context).pop(),
               child: Text('Close',
                   style: TextStyle(
                       color: Colors.teal[700], fontWeight: FontWeight.bold)),
             ),
           ],
         );
       },
     );
   }

   // --- Skill Level & Prep Time Calculation ---
   double _getSkillLevelValue(String? skillLevel) {
     skillLevel ??= 'Intermediate';
     switch (skillLevel.toLowerCase()) {
       case 'beginner':
         return 0.25;
       case 'intermediate':
         return 0.60;
       case 'advanced':
         return 1.0;
       default:
         return 0.60;
     }
   }

   double _getPrepTimeValue(String? prepTimeStr) {
     prepTimeStr ??= '30';
     const maxPrepTime = 90.0;
     int prepMinutes = int.tryParse(prepTimeStr) ?? 30;
     return (prepMinutes / maxPrepTime).clamp(0.0, 1.0);
   }

   // --- Skill Level & Prep Time Card ---
   Widget _buildSkillLevelAndPrepTimeCard() {
     // Use PascalCase keys
     final skillLevel = widget.meal['Skill_level']?.toString();
     final prepTime = widget.meal['Prep_time']?.toString();

     if (skillLevel == null && prepTime == null) return SizedBox.shrink();

     return Card(
       elevation: _cardElevation,
       margin: EdgeInsets.zero,
       shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(_cardCornerRadius)),
       color: kColorSurface,
       child: Padding(
         padding: EdgeInsets.all(_verticalPadding * 0.8),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text('Cooking Info',
                 style: GoogleFonts.poppins(
                     fontSize: 18,
                     fontWeight: FontWeight.w600,
                     color: kColorPrimaryDark)),
             SizedBox(height: 12),
             if (skillLevel != null) ...[
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text('Skill Level:',
                       style: GoogleFonts.poppins(
                           color: kColorTextSecondary, fontSize: 14)),
                   Text(skillLevel,
                       style: GoogleFonts.poppins(
                           color: kColorTextPrimary,
                           fontSize: 14,
                           fontWeight: FontWeight.w500)),
                 ],
               ),
               SizedBox(height: 4),
               LinearProgressIndicator(
                 value: _getSkillLevelValue(skillLevel),
                 color: kColorPrimary,
                 backgroundColor: kColorDivider,
                 minHeight: 6,
                 borderRadius: BorderRadius.circular(3),
               ),
               if (prepTime != null) SizedBox(height: 12),
             ],
             if (prepTime != null) ...[
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text('Prep Time:',
                       style: GoogleFonts.poppins(
                           color: kColorTextSecondary, fontSize: 14)),
                   Text('$prepTime',
                       style: GoogleFonts.poppins(
                           color: kColorTextPrimary,
                           fontSize: 14,
                           fontWeight: FontWeight.w500)),
                 ],
               ),
               SizedBox(height: 4),
               LinearProgressIndicator(
                 value: _getPrepTimeValue(prepTime),
                 color: kColorPrimary,
                 backgroundColor: kColorDivider,
                 minHeight: 6,
                 borderRadius: BorderRadius.circular(3),
               ),
             ],
           ],
         ),
       ),
     );
   }

   // --- Chef Selection Sheet ---
   Widget _buildChefSelectionSheet() {
     return StatefulBuilder(
       builder: (BuildContext context, StateSetter setModalState) {
         // Filter chefs based on search query within the modal's state
         final filteredChefs = _chefSearchQuery.isEmpty
             ? chefs
             : chefs.where((chef) {
                 final name = (chef['name']?.toString().toLowerCase() ?? '');
                final location =
                    (chef['location']?.toString().toLowerCase() ?? '');
                 return name.contains(_chefSearchQuery) ||
                     location.contains(_chefSearchQuery);
               }).toList();

         return Container(
           padding: EdgeInsets.only(
             top: 12,
             left: _horizontalPadding,
             right: _horizontalPadding,
             bottom: MediaQuery.of(context).viewInsets.bottom + _verticalPadding,
           ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
           decoration: BoxDecoration(
             color: kBottomSheetBgColor,
             borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
           ),
           child: Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text("Select a Chef",
                       style: GoogleFonts.poppins(
                           fontSize: 18,
                           fontWeight: FontWeight.bold,
                           color: kColorPrimaryDark)),
                   Row(
                     children: [
                       IconButton(
                         icon: Icon(Icons.search, color: kColorPrimary),
                         onPressed: () {
                           showDialog(
                             context: context,
                             builder: (context) => AlertDialog(
                               title: Text('Search Chefs',
                                   style: GoogleFonts.poppins()),
                               content: TextField(
                                 controller: _chefSearchController,
                                 decoration: InputDecoration(
                                   hintText: 'Search by name or location',
                                   prefixIcon: Icon(Icons.search),
                                 ),
                                 onChanged: (value) {
                                  setModalState(() {
                                    // Use setModalState to update the modal's state
                                     _chefSearchQuery = value.toLowerCase();
                                   });
                                 },
                               ),
                               actions: [
                                 TextButton(
                                   onPressed: () {
                                     Navigator.pop(context);
                                     _chefSearchController.clear();
                                    setModalState(() {
                                      // Use setModalState
                                       _chefSearchQuery = '';
                                     });
                                   },
                                   child: Text('Cancel'),
                                 ),
                                 TextButton(
                                   onPressed: () {
                                     Navigator.pop(context);
                                   },
                                   child: Text('Done'),
                                 ),
                               ],
                             ),
                           );
                         },
                       ),
                       IconButton(
                         icon: Icon(Icons.refresh, color: kColorPrimary),
                         onPressed: () {
                          setModalState(() {
                            // Use setModalState
                             isLoadingChefs = true;
                           });
                           // Call fetchChefsWithRetry, which will call setState in the parent widget
                           // and also potentially setModalState if needed within the fetch logic
                           fetchChefsWithRetry().then((_) {
                            if (mounted) {
                              // Check if the parent widget is still mounted
                              setModalState(() {
                                // Update modal state after fetch
                                 isLoadingChefs = false;
                               });
                             }
                           });
                         },
                       ),
                     ],
                   ),
                 ],
               ),
               if (_chefSearchQuery.isNotEmpty)
                 Padding(
                   padding: const EdgeInsets.symmetric(vertical: 8.0),
                   child: Text(
                     'Searching for: $_chefSearchQuery',
                     style: GoogleFonts.poppins(
                         color: kColorTextSecondary, fontSize: 14),
                   ),
                 ),
               Divider(color: kColorDivider),
               Flexible(
                 child: isLoadingChefs
                     ? Center(
                         key: ValueKey('chef_loading'),
                         child: CircularProgressIndicator(color: kColorPrimary))
                     : (filteredChefs.isEmpty // Use filteredChefs here
                         ? Center(
                             key: ValueKey('chef_empty'),
                             child: Text("No chefs available.",
                                 style: GoogleFonts.poppins(
                                     color: kColorTextSecondary)))
                        : _buildChefListWithData(
                            filteredChefs)), // Pass filtered data
               ),
             ],
           ),
         );
       },
     );
   }

   // Helper method to build the chef list with provided data
   Widget _buildChefListWithData(List<dynamic> chefsToDisplay) {
     return ListView.builder(
       itemCount: chefsToDisplay.length,
       padding: EdgeInsets.zero,
       itemBuilder: (context, index) {
         final chef = chefsToDisplay[index];
         final chefName = chef['name'] ?? 'Unknown Chef';
         final chefImage = _formatImageUrl(
             chef['image'] ?? 'assets/images/placeholderchef.jpeg');
         final chefRating = (chef['rating'] as double?) ?? 0.0;
         final chefLocation = chef['location'] ?? 'Unknown Location';
         final chefId = chef['chefid'];

         final bool isSelected =
             selectedChef != null && selectedChef!['chefid'] == chefId;

         return Card(
           elevation: isSelected ? 3.0 : _cardElevation,
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             side: BorderSide(
                 color: isSelected ? kColorPrimary : kColorDivider,
                 width: isSelected ? 2.0 : 0.8),
           ),
           color: kColorSurface, // No overlay, always white
           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
           child: InkWell(
             onTap: () => _chooseChef(chef),
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             child: Padding(
               padding: const EdgeInsets.all(10.0),
               child: Row(
                 children: [
                   ClipOval(
                     child: CachedNetworkImage(
                       imageUrl: chefImage,
                       width: 50,
                       height: 50,
                       fit: BoxFit.cover,
                       placeholder: (context, url) => Container(
                           width: 50,
                           height: 50,
                           child: Center(
                               child: CircularProgressIndicator(
                                   strokeWidth: 2, color: kColorPrimary))),
                       errorWidget: (context, url, error) => Image.asset(
                           'assets/images/placeholderchef.jpeg',
                           width: 50,
                           height: 50,
                           fit: BoxFit.cover),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(chefName,
                             style: GoogleFonts.poppins(
                                 fontSize: 15,
                                 fontWeight: FontWeight.bold,
                                 color: kColorPrimary)),
                         SizedBox(height: 3),
                         Row(
                             children: List.generate(
                                 5,
                                 (i) => Icon(
                                     i < chefRating.round()
                                         ? Icons.star
                                         : Icons.star_border,
                                     color: kColorPrimary, // Always teal
                                     size: 15))),
                         SizedBox(height: 3),
                         Row(
                           children: [
                             Icon(Icons.location_on_outlined,
                                 color: kColorPrimary, size: 13),
                             SizedBox(width: 4),
                             Expanded(
                                 child: Text(getShortLocation(chefLocation),
                                     style: GoogleFonts.poppins(
                                         fontSize: 12, color: kColorPrimary),
                                     overflow: TextOverflow.ellipsis)),
                           ],
                         ),
                       ],
                     ),
                   ),
                   if (isSelected)
                     Padding(
                       padding: const EdgeInsets.only(left: 8.0),
                       child: Icon(Icons.check_circle,
                           color: Colors.green, size: 28),
                     ),
                 ],
               ),
             ),
           ),
         );
       },
     );
   }

   // --- Producer Selection Sheet ---
   Widget _buildProducerSelectionSheet() {
     return StatefulBuilder(
       builder: (BuildContext context, StateSetter setModalState) {
         // Filter producers based on search query within the modal's state
         final filteredProducers = _producerSearchQuery.isEmpty
             ? producers
             : producers.where((producer) {
                 final name = (producer['name']?.toString().toLowerCase() ?? '');
                 final location =
                     (producer['Location']?.toString().toLowerCase() ?? '');
                 return name.contains(_producerSearchQuery) ||
                     location.contains(_producerSearchQuery);
               }).toList();

         return Container(
           padding: EdgeInsets.only(
             top: 12,
             left: _horizontalPadding,
             right: _horizontalPadding,
             bottom: MediaQuery.of(context).viewInsets.bottom + _verticalPadding,
           ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
           decoration: BoxDecoration(
             color: kBottomSheetBgColor,
             borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
           ),
           child: Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   Text("Select a Producer",
                       style: GoogleFonts.poppins(
                           fontSize: 18,
                           fontWeight: FontWeight.bold,
                           color: kColorPrimaryDark)),
                   Row(
                     children: [
                       IconButton(
                         icon: Icon(Icons.search, color: kColorPrimary),
                         onPressed: () {
                           showDialog(
                             context: context,
                             builder: (context) => AlertDialog(
                               title: Text('Search Producers',
                                   style: GoogleFonts.poppins()),
                               content: TextField(
                                 controller: _producerSearchController,
                                 decoration: InputDecoration(
                                   hintText: 'Search by name or location',
                                   prefixIcon: Icon(Icons.search),
                                 ),
                                 onChanged: (value) {
                                  setModalState(() {
                                    // Use setModalState
                                     _producerSearchQuery = value.toLowerCase();
                                   });
                                 },
                               ),
                               actions: [
                                 TextButton(
                                   onPressed: () {
                                     Navigator.pop(context);
                                     _producerSearchController.clear();
                                    setModalState(() {
                                      // Use setModalState
                                       _producerSearchQuery = '';
                                     });
                                   },
                                   child: Text('Cancel'),
                                 ),
                                 TextButton(
                                   onPressed: () {
                                     Navigator.pop(context);
                                   },
                                   child: Text('Done'),
                                 ),
                               ],
                             ),
                           );
                         },
                       ),
                       IconButton(
                         icon: Icon(Icons.refresh, color: kColorPrimary),
                         onPressed: () {
                          setModalState(() {
                            // Use setModalState
                             isLoadingProducers = true;
                           });
                           // Call fetchProducers, which will call setState in the parent widget
                           // and also potentially setModalState if needed within the fetch logic
                           fetchProducers().then((_) {
                            if (mounted) {
                              // Check if the parent widget is still mounted
                              setModalState(() {
                                // Update modal state after fetch
                                 isLoadingProducers = false;
                               });
                             }
                           });
                         },
                       ),
                     ],
                   ),
                 ],
               ),
               if (_producerSearchQuery.isNotEmpty)
                 Padding(
                   padding: const EdgeInsets.symmetric(vertical: 8.0),
                   child: Text(
                     'Searching for: $_producerSearchQuery',
                     style: GoogleFonts.poppins(
                         color: kColorTextSecondary, fontSize: 14),
                   ),
                 ),
               Divider(color: kColorDivider),
               Flexible(
                 child: isLoadingProducers
                     ? Center(
                         key: ValueKey('producer_loading'),
                         child: CircularProgressIndicator(color: kColorPrimary))
                     : (filteredProducers.isEmpty // Use filteredProducers here
                         ? Center(
                             key: ValueKey('producer_empty'),
                             child: Text("No producers available.",
                                 style: GoogleFonts.poppins(
                                     color: kColorTextSecondary)))
                        : _buildProducerListWithData(
                            filteredProducers)), // Pass filtered data
               ),
             ],
           ),
         );
       },
     );
   }

   // Helper method to build the producer list with provided data
   Widget _buildProducerListWithData(List<dynamic> producersToDisplay) {
     return ListView.builder(
       itemCount: producersToDisplay.length,
       padding: EdgeInsets.zero,
       itemBuilder: (context, index) {
         final producer = producersToDisplay[index];
         final producerName = producer['name'] ?? 'Unknown Producer';
         final producerImage = _formatImageUrl(
             producer['image'] ?? 'assets/images/producerHolder.png');
         final producerLocation = producer['Location'] ?? 'NA';
         final producerRating = (producer['Rating'] as double?) ?? 0.0;
         final producerId = producer['producer_id'];

         final bool isSelected = selectedProducer != null &&
             selectedProducer!['producer_id'] == producerId;

         return Card(
           elevation: isSelected ? 3.0 : _cardElevation,
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             side: BorderSide(
                 color: isSelected ? kColorPrimary : kColorDivider,
                 width: isSelected ? 2.0 : 0.8),
           ),
           color: kColorSurface, // No overlay, always white
           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
           child: InkWell(
             onTap: () => _chooseProducer(producer),
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             child: Padding(
               padding: const EdgeInsets.all(10.0),
               child: Row(
                 children: [
                   ClipOval(
                     child: CachedNetworkImage(
                       imageUrl: producerImage,
                       width: 50,
                       height: 50,
                       fit: BoxFit.cover,
                       placeholder: (context, url) => Container(
                           width: 50,
                           height: 50,
                           child: Center(
                               child: CircularProgressIndicator(
                                   strokeWidth: 2, color: kColorPrimary))),
                       errorWidget: (context, url, error) => Image.asset(
                           'assets/images/producerHolder.png',
                           width: 50,
                           height: 50,
                           fit: BoxFit.cover),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(producerName,
                             style: GoogleFonts.poppins(
                                 fontSize: 15,
                                 fontWeight: FontWeight.bold,
                                 color: kColorPrimary)),
                         SizedBox(height: 3),
                         Row(
                             children: List.generate(
                                 5,
                                 (i) => Icon(
                                     i < producerRating.round()
                                         ? Icons.star
                                         : Icons.star_border,
                                     color: kColorPrimary, // Always teal
                                     size: 15))),
                         SizedBox(height: 3),
                         Row(
                           children: [
                             Icon(Icons.location_on_outlined,
                                 color: kColorPrimary, size: 13),
                             SizedBox(width: 4),
                             Expanded(
                                 child: Text(getShortLocation(producerLocation),
                                     style: GoogleFonts.poppins(
                                         fontSize: 12, color: kColorPrimary),
                                     overflow: TextOverflow.ellipsis)),
                           ],
                         ),
                       ],
                     ),
                   ),
                   if (isSelected)
                     Padding(
                       padding: const EdgeInsets.only(left: 8.0),
                       child: Icon(Icons.check_circle,
                           color: Colors.green, size: 28),
                     ),
                 ],
               ),
             ),
           ),
         );
       },
     );
   }

   // --- Chef List Builder (for Bottom Sheet) ---
   Widget _buildChefList() {
     // Filter chefs based on search query
     final filteredChefs = _chefSearchQuery.isEmpty
         ? chefs
         : chefs.where((chef) {
             final name = (chef['name']?.toString().toLowerCase() ?? '');
             final location = (chef['location']?.toString().toLowerCase() ?? '');
             return name.contains(_chefSearchQuery) ||
                 location.contains(_chefSearchQuery);
           }).toList();

     return ListView.builder(
       itemCount: filteredChefs.length,
       padding: EdgeInsets.zero,
       itemBuilder: (context, index) {
         final chef = filteredChefs[index];
         final chefName = chef['name'] ?? 'Unknown Chef';
         final chefImage = _formatImageUrl(
             chef['image'] ?? 'assets/images/placeholderchef.jpeg');
         final chefRating = (chef['rating'] as double?) ?? 0.0;
         final chefLocation = chef['location'] ?? 'Unknown Location';
         final chefId = chef['chefid'];

         final bool isSelected =
             selectedChef != null && selectedChef!['chefid'] == chefId;

         return Card(
           elevation: isSelected ? 3.0 : _cardElevation,
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             side: BorderSide(
                 color: isSelected ? kColorPrimary : kColorDivider,
                 width: isSelected ? 2.0 : 0.8),
           ),
           color: kColorSurface, // No overlay, always white
           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
           child: InkWell(
             onTap: () => _chooseChef(chef),
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             child: Padding(
               padding: const EdgeInsets.all(10.0),
               child: Row(
                 children: [
                   ClipOval(
                     child: CachedNetworkImage(
                       imageUrl: chefImage,
                       width: 50,
                       height: 50,
                       fit: BoxFit.cover,
                       placeholder: (context, url) => Container(
                           width: 50,
                           height: 50,
                           child: Center(
                               child: CircularProgressIndicator(
                                   strokeWidth: 2, color: kColorPrimary))),
                       errorWidget: (context, url, error) => Image.asset(
                           'assets/images/placeholderchef.jpeg',
                           width: 50,
                           height: 50,
                           fit: BoxFit.cover),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(chefName,
                             style: GoogleFonts.poppins(
                                 fontSize: 15,
                                 fontWeight: FontWeight.bold,
                                 color: kColorPrimary)),
                         SizedBox(height: 3),
                         Row(
                             children: List.generate(
                                 5,
                                 (i) => Icon(
                                     i < chefRating.round()
                                         ? Icons.star
                                         : Icons.star_border,
                                     color: kColorPrimary, // Always teal
                                     size: 15))),
                         SizedBox(height: 3),
                         Row(
                           children: [
                             Icon(Icons.location_on_outlined,
                                 color: kColorPrimary, size: 13),
                             SizedBox(width: 4),
                             Expanded(
                                 child: Text(getShortLocation(chefLocation),
                                     style: GoogleFonts.poppins(
                                         fontSize: 12, color: kColorPrimary),
                                     overflow: TextOverflow.ellipsis)),
                           ],
                         ),
                       ],
                     ),
                   ),
                   if (isSelected)
                     Padding(
                       padding: const EdgeInsets.only(left: 8.0),
                       child: Icon(Icons.check_circle,
                           color: Colors.green, size: 28),
                     ),
                 ],
               ),
             ),
           ),
         );
       },
     );
   }

   // --- Producer List Builder (for Bottom Sheet) ---
   Widget _buildProducerList() {
     // Filter producers based on search query
     final filteredProducers = _producerSearchQuery.isEmpty
         ? producers
         : producers.where((producer) {
             final name = (producer['name']?.toString().toLowerCase() ?? '');
             final location =
                 (producer['Location']?.toString().toLowerCase() ?? '');
             return name.contains(_producerSearchQuery) ||
                 location.contains(_producerSearchQuery);
           }).toList();

     return ListView.builder(
       itemCount: filteredProducers.length,
       padding: EdgeInsets.zero,
       itemBuilder: (context, index) {
         final producer = filteredProducers[index];
         final producerName = producer['name'] ?? 'Unknown Producer';
         final producerImage = _formatImageUrl(
             producer['image'] ?? 'assets/images/producerHolder.png');
         final producerLocation = producer['Location'] ?? 'NA';
         final producerRating = (producer['Rating'] as double?) ?? 0.0;
         final producerId = producer['producer_id'];

         final bool isSelected = selectedProducer != null &&
             selectedProducer!['producer_id'] == producerId;

         return Card(
           elevation: isSelected ? 3.0 : _cardElevation,
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             side: BorderSide(
                 color: isSelected ? kColorPrimary : kColorDivider,
                 width: isSelected ? 2.0 : 0.8),
           ),
           color: kColorSurface, // No overlay, always white
           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
           child: InkWell(
             onTap: () => _chooseProducer(producer),
             borderRadius: BorderRadius.circular(_buttonCornerRadius),
             child: Padding(
               padding: const EdgeInsets.all(10.0),
               child: Row(
                 children: [
                   ClipOval(
                     child: CachedNetworkImage(
                       imageUrl: producerImage,
                       width: 50,
                       height: 50,
                       fit: BoxFit.cover,
                       placeholder: (context, url) => Container(
                           width: 50,
                           height: 50,
                           child: Center(
                               child: CircularProgressIndicator(
                                   strokeWidth: 2, color: kColorPrimary))),
                       errorWidget: (context, url, error) => Image.asset(
                           'assets/images/producerHolder.png',
                           width: 50,
                           height: 50,
                           fit: BoxFit.cover),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text(producerName,
                             style: GoogleFonts.poppins(
                                 fontSize: 15,
                                 fontWeight: FontWeight.bold,
                                 color: kColorPrimary)),
                         SizedBox(height: 3),
                         Row(
                             children: List.generate(
                                 5,
                                 (i) => Icon(
                                     i < producerRating.round()
                                         ? Icons.star
                                         : Icons.star_border,
                                     color: kColorPrimary, // Always teal
                                     size: 15))),
                         SizedBox(height: 3),
                         Row(
                           children: [
                             Icon(Icons.location_on_outlined,
                                 color: kColorPrimary, size: 13),
                             SizedBox(width: 4),
                             Expanded(
                                 child: Text(getShortLocation(producerLocation),
                                     style: GoogleFonts.poppins(
                                         fontSize: 12, color: kColorPrimary),
                                     overflow: TextOverflow.ellipsis)),
                           ],
                         ),
                       ],
                     ),
                   ),
                   if (isSelected)
                     Padding(
                       padding: const EdgeInsets.only(left: 8.0),
                       child: Icon(Icons.check_circle,
                           color: Colors.green, size: 28),
                     ),
                 ],
               ),
             ),
           ),
         );
       },
     );
   }

   // --- Widget to display currently selected Chef/Producer ---
   Widget _buildSelectedOptionCard() {
     if (selectedChef == null && selectedProducer == null) {
       return SizedBox.shrink(); // Don't show anything if nothing is selected
     }

     final bool isChef = selectedChef != null;
     final data = isChef ? selectedChef! : selectedProducer!;
     final name = data['name'] ?? 'Unknown';
     final image = _formatImageUrl(data['image'] ??
         (isChef
             ? 'assets/images/placeholderchef.jpeg'
             : 'assets/images/producerHolder.png'));
     final location = getShortLocation(data[isChef ? 'location' : 'Location'] ??
         'Unknown Location'); // Use correct location key
     final rating = (data[isChef ? 'rating' : 'Rating'] as double?) ??
         0.0; // Use correct rating key
     final typeLabel = isChef ? 'Selected Chef' : 'Selected Producer';

     return Card(
       elevation: 2,
       margin: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(12),
         side: BorderSide(color: Colors.teal.withOpacity(0.5), width: 1),
       ),
       color: Colors.teal[50], // Light teal background
       child: Padding(
         padding: const EdgeInsets.all(12.0),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(typeLabel,
                 style: TextStyle(
                     fontSize: 14,
                     color: Colors.grey[600],
                     fontWeight: FontWeight.w500)),
             SizedBox(height: 8),
             Row(
               children: [
                 ClipOval(
                   child: CachedNetworkImage(
                     imageUrl: image,
                     width: 45,
                     height: 45,
                     fit: BoxFit.cover,
                     placeholder: (context, url) => Container(
                         width: 45,
                         height: 45,
                         child: Center(
                             child: CircularProgressIndicator(
                                 strokeWidth: 2, color: Colors.teal))),
                     errorWidget: (context, url, error) => Image.asset(
                         isChef
                             ? 'assets/images/placeholderchef.jpeg'
                             : 'assets/images/producerHolder.png',
                         width: 45,
                         height: 45,
                         fit: BoxFit.cover),
                   ),
                 ),
                 const SizedBox(width: 10),
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(name,
                           style: TextStyle(
                               fontSize: 16,
                               fontWeight: FontWeight.bold,
                               color: Colors.teal[900])),
                       SizedBox(height: 2),
                       Row(
                           children: List.generate(
                               5,
                               (i) => Icon(
                                   i < rating.round()
                                       ? Icons.star
                                       : Icons.star_border,
                                   color: i < rating.round()
                                       ? Colors.teal
                                       : Colors.grey,
                                   size: 14))),
                       SizedBox(height: 2),
                       Row(
                         children: [
                           Icon(Icons.location_on,
                               color: Colors.grey[600], size: 12),
                           SizedBox(width: 3),
                           Expanded(
                               child: Text(location,
                                   style: TextStyle(
                                       fontSize: 12, color: Colors.grey[700]),
                                   overflow: TextOverflow.ellipsis)),
                         ],
                       ),
                     ],
                   ),
                 ),
                 // Optional: Add a 'Change' button? Or rely on the main buttons.
                 // TextButton(onPressed: () { /* show sheet again */ }, child: Text("Change"))
               ],
             ),
           ],
         ),
       ),
     );
   }

   // --- Bottom Proceed Button ---
   Widget _buildProceedToCartButton(BuildContext context) {
     // --- Use imported (shared) ShoppingCart ---
    int cartItemCount = ShoppingCart.items.length; // Get total items for badge
     // --- End ShoppingCart ---

     return Container(
       padding: EdgeInsets.fromLTRB(
           _horizontalPadding, 10.0, _horizontalPadding, _verticalPadding),
       decoration: BoxDecoration(
         color: kColorSurface,
         boxShadow: [
           BoxShadow(
               color: Colors.black.withOpacity(0.08),
               spreadRadius: 0,
               blurRadius: 4,
               offset: Offset(0, -1))
         ],
       ),
       child: ElevatedButton.icon(
         icon: Badge(
           label: Text('$cartItemCount'),
           isLabelVisible: cartItemCount > 0,
           backgroundColor: Colors.red,
           child: Icon(Icons.shopping_cart_checkout),
         ),
         label: Text('Proceed to Cart', style: GoogleFonts.poppins()),
         onPressed: cartItemCount > 0
             ? () {
                 Navigator.push(
                     context,
                     MaterialPageRoute(
                         builder: (context) =>
                             ShoppingCartScreen())).then((_) => setState(() {
                      var currentItemInCart = ShoppingCart.items.firstWhere(
                         (item) =>
                             item['title'] == widget.meal['Meal_name'],
                         orElse: () => {},
                       );
                       if (currentItemInCart != null) {
                         isInCart = true;
                         selectedChef = currentItemInCart['selectedchef'];
                         selectedProducer =
                             currentItemInCart['selectedproducer'];
                         isChefSelected = selectedProducer == null;
                       } else {
                         isInCart = false;
                         selectedChef = null;
                         selectedProducer = null;
                         isChefSelected = true;
                       }
                       final complementaries = _parseListFromString(
                           widget.meal['Complementary_dishes']);
                       complementaryInCartStatus =
                           List.generate(complementaries.length, (index) {
                         final title = complementaries[index];
                        return ShoppingCart.items
                             .any((item) => item['title'] == title);
                       });
                     }));
               }
             : null,
         style: ElevatedButton.styleFrom(
           backgroundColor:
               cartItemCount > 0 ? kColorPrimaryDark : Colors.grey.shade400,
           foregroundColor: kColorSurface,
           padding: EdgeInsets.symmetric(vertical: 14),
           textStyle:
               GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
           shape: RoundedRectangleBorder(
               borderRadius: BorderRadius.circular(_buttonCornerRadius)),
           minimumSize: Size(double.infinity, 50),
         ),
       ),
     );
   }

  // Add meal planning section widget
  Widget _buildMealPlanningSection() {
    return ExpansionTile(
      title: Text(
        'Meal Planning',
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Range Selector
              ListTile(
                title: Text(
                  'Plan Duration',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                subtitle: Text(
                  _planStartDate == null
                      ? 'Select dates'
                      : '${DateFormat('MMM d').format(_planStartDate!)} - ${DateFormat('MMM d').format(_planEndDate ?? _planStartDate!)}',
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                trailing: Icon(Icons.calendar_today),
                onTap: () async {
                  final DateTimeRange? dateRange = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(Duration(days: 30)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: kColorPrimary,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: kColorTextPrimary,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (dateRange != null) {
                    setState(() {
                      _planStartDate = dateRange.start;
                      _planEndDate = dateRange.end;
                    });
                  }
                },
              ),

              // Frequency Selection
              ListTile(
                title: Text(
                  'Delivery Frequency',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                subtitle: DropdownButton<String>(
                  value: _selectedFrequency,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(
                        value: 'weekdays', child: Text('Weekdays Only')),
                    DropdownMenuItem(
                        value: 'custom', child: Text('Select Days')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedFrequency = value!;
                    });
                  },
                ),
              ),

              // Custom Days Selection
              if (_selectedFrequency == 'custom')
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (var day in [
                        DateTime.monday,
                        DateTime.tuesday,
                        DateTime.wednesday,
                        DateTime.thursday,
                        DateTime.friday,
                        DateTime.saturday,
                        DateTime.sunday,
                      ])
                        FilterChip(
                          label: Text(
                            DateFormat('E').format(DateTime(2024, 1, day)),
                            style: GoogleFonts.poppins(
                              color: _selectedDays.contains(DateFormat('E')
                                      .format(DateTime(2024, 1, day)))
                                  ? Colors.white
                                  : kColorTextPrimary,
                            ),
                          ),
                          selected: _selectedDays.contains(
                              DateFormat('E').format(DateTime(2024, 1, day))),
                          onSelected: (bool selected) {
                            setState(() {
                              if (selected) {
                                _selectedDays.add(DateFormat('E')
                                    .format(DateTime(2024, 1, day)));
                              } else {
                                _selectedDays.remove(DateFormat('E')
                                    .format(DateTime(2024, 1, day)));
                              }
                            });
                          },
                          backgroundColor: Colors.grey[200],
                          selectedColor: kColorPrimary,
                        ),
                    ],
                  ),
                ),

              // Quantity per day
              ListTile(
                title: Text(
                  'Quantity per day',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        if (_quantityPerDay > 1) {
                          setState(() => _quantityPerDay--);
                        }
                      },
                    ),
                    Text('$_quantityPerDay',
                        style: GoogleFonts.poppins(fontSize: 16)),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline),
                      onPressed: () {
                        setState(() => _quantityPerDay++);
                      },
                    ),
                  ],
                ),
              ),

              // Order Summary
              if (_planStartDate != null)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order Summary',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                          SizedBox(height: 8),
                          _buildSummaryRow(
                              'Total Days:', _calculateTotalDays()),
                          _buildSummaryRow(
                              'Total Meals:', _calculateTotalMeals()),
                          _buildSummaryRow('Total Cost:',
                              '\$${(_calculateTotalMeals() * _parsePrice(widget.meal['Price'])).toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, dynamic value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: kColorTextSecondary,
              )),
          Text(value.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  int _calculateTotalDays() {
    if (_planStartDate == null || _planEndDate == null) return 0;

    int days = 0;
    DateTime current = _planStartDate!;

    while (current.isBefore(_planEndDate!.add(Duration(days: 1)))) {
      bool includeDay = false;

      switch (_selectedFrequency) {
        case 'daily':
          includeDay = true;
          break;
        case 'weekdays':
          includeDay = current.weekday <= 5;
          break;
        case 'custom':
          includeDay = _selectedDays.contains(DateFormat('E')
              .format(DateTime(2024, 1, current.weekday)));
          break;
      }

      if (includeDay) days++;
      current = current.add(Duration(days: 1));
    }

    return days;
  }

  int _calculateTotalMeals() {
    return _calculateTotalDays() * _quantityPerDay;
   }

   @override
   void dispose() {
     _chefSearchController.dispose();
     _producerSearchController.dispose();
     super.dispose();
   }

  void _addToCart() {
    if (selectedChef == null && selectedProducer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Please select a chef or producer before adding to cart'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create a list of selected complementary items with proper type
    List<Map<String, dynamic>> selectedComplementaries = [];
    if (complementaryInCartStatus.isNotEmpty && widget.meal['bestservedwith'] != null) {
      for (var i = 0; i < complementaryInCartStatus.length; i++) {
        if (complementaryInCartStatus[i]) {
          final complementary = widget.meal['bestservedwith'][i];
          double price = 0.0;
          if (complementary['price'] is double) {
            price = complementary['price'];
          } else if (complementary['price'] is int) {
            price = (complementary['price'] as int).toDouble();
          } else if (complementary['price'] is String) {
            price = double.tryParse(complementary['price']) ?? 0.0;
          }
          selectedComplementaries.add({
            'name': complementary['name']?.toString() ?? '',
            'price': price,
            'image': complementary['image']?.toString() ?? '',
          });
        }
      }
    }
    // Add main meal to cart with selected complementaries
    double mainMealPrice = 0.0;
    try {
      mainMealPrice = widget.meal['Price'] is double
          ? widget.meal['Price']
          : double.tryParse(widget.meal['Price'].toString()) ?? 0.0;
    } catch (_) {
      mainMealPrice = 0.0;
    }

    // Ensure all complementary prices are double
    for (final comp in selectedComplementaries) {
      if (comp['price'] != null && comp['price'] is! double) {
        if (comp['price'] is int) {
          comp['price'] = (comp['price'] as int).toDouble();
        } else if (comp['price'] is String) {
          comp['price'] = double.tryParse(comp['price'].toString()) ?? 0.0;
        }
      }
    }

    ShoppingCart.addItem(
      widget.meal['Meal_name'],
      mainMealPrice,
      quantity: _quantityPerDay,
      selectedchef: selectedChef,
      selectedproducer: selectedProducer,
      meal: widget.meal,
      bestservedwith: selectedComplementaries.map((e) => e as Map<String, dynamic>).toList(),
    );

    setState(() {
      _isInCart = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to cart successfully'),
        backgroundColor: Colors.teal[800],
      ),
    );
  }

  Widget _buildChefProducerSelection() {
    return Card(
      color: Colors.teal[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardCornerRadius),
      ),
      elevation: _cardElevation,
      child: Padding(
        padding: EdgeInsets.all(_horizontalPadding.toDouble()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Preparation',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.teal[800],
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: Text('Cooked by Chef', style: GoogleFonts.poppins()),
                    value: true,
                    groupValue: isChefSelected,
                    onChanged: (value) {
                      setState(() {
                        isChefSelected = value!;
                        selectedProducer =
                            null; // Clear producer when switching to chef
                      });
                    },
                    activeColor: Colors.teal[800],
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: Text('Prepared by Producer',
                        style: GoogleFonts.poppins()),
                    value: false,
                    groupValue: isChefSelected,
                    onChanged: (value) {
                      setState(() {
                        isChefSelected = value!;
                        selectedChef =
                            null; // Clear chef when switching to producer
                      });
                    },
                    activeColor: Colors.teal[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (isChefSelected) ...[
              _buildChefSearch(),
              _buildChefList(),
            ] else ...[
              _buildProducerSearch(),
              _buildProducerList(),
            ],
            if ((isChefSelected && selectedChef == null) ||
                (!isChefSelected && selectedProducer == null))
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Please select a ${isChefSelected ? 'chef' : 'producer'}',
                  style: GoogleFonts.poppins(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplementaryMeals() {
    if (widget.meal['bestservedwith'] == null ||
        (widget.meal['bestservedwith'] as List).isEmpty) {
      return SizedBox.shrink();
    }

    return Card(
      color: Colors.teal[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardCornerRadius),
      ),
      elevation: _cardElevation,
      child: Padding(
        padding: EdgeInsets.all(_horizontalPadding.toDouble()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Complementary Items',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.teal[800],
              ),
            ),
            SizedBox(height: 8),
            ...List.generate(
              widget.meal['bestservedwith'].length,
              (index) {
                final complementary = widget.meal['bestservedwith'][index];
                if (complementary == null || complementary is! Map) {
                  // Defensive: skip null/malformed items
                  return SizedBox.shrink();
                }
                final name = complementary['name']?.toString() ?? 'Unknown';
                final price = complementary['price']?.toString() ?? '0';
                return CheckboxListTile(
                  title: Text(
                    name,
                    style: GoogleFonts.poppins(),
                  ),
                  subtitle: Text(
                    '\$${price}',
                    style: GoogleFonts.poppins(
                      color: Colors.teal[800],
                    ),
                  ),
                  value: complementaryInCartStatus[index],
                  onChanged: (value) {
                    setState(() {
                      complementaryInCartStatus[index] = value!;
                    });
                  },
                  activeColor: Colors.teal[800],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Add search methods
  Widget _buildChefSearch() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: _chefSearchController,
        decoration: InputDecoration(
          hintText: 'Search chefs...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _chefSearchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildProducerSearch() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: _producerSearchController,
        decoration: InputDecoration(
          hintText: 'Search producers...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _producerSearchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }
}

// --- Custom SnackBar Utility ---
void showCustomSnackBar(BuildContext context, String message) {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
   final snackBar = SnackBar(
    content: Text(message),
     duration: Duration(seconds: 2),
     behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.all(8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    backgroundColor: Colors.teal[700],
     action: SnackBarAction(
       label: 'OK',
      textColor: Colors.white,
       onPressed: () {
         scaffoldMessenger.hideCurrentSnackBar();
       },
     ),
   );
   scaffoldMessenger.showSnackBar(snackBar);
 }
