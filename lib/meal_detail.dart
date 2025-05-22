
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:zinzi2/allmeals.dart'; // Assuming this screen exists
import 'package:zinzi2/app_drawer_unified.dart'
    as drawer; // Import unified AppDrawer with prefix
// **** IMPORT THE UPDATED CART ****
import 'package:zinzi2/cart.dart'; // Imports the SHARED cart (with new methods) & favorites
// **** END IMPORT ****
import 'package:zinzi2/checkout.dart'; // Assuming this screen exists
import 'package:zinzi2/useranalytics.dart'; // Assuming this screen exists if needed
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart'; // For consistent font

import 'package:zinzi2/user_cache.dart'; // Import UserCache
import 'package:zinzi2/cache_config.dart'; // Import CacheConfig
import 'package:zinzi2/utils/image_utils.dart'; // Import ImageUtils
import 'package:intl/intl.dart';

// Assuming dotenv is initialized elsewhere in your main.dart or similar
final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// --- Static Chef Data (Fallback) ---
class ChefData {
  static List<Map<String, dynamic>> chefs = [
    {
      'image': 'assets/images/abdul.jpg',
      'name': 'Abdul',
      'price': 5.0, // Assuming this is an add-on price?
      'rating': 3.0,
      'location': 'KAMPALA',
      'chefid': 1, // Example ID
    },
    {
      'image': 'assets/images/dante.jpg',
      'name': 'Dante',
      'price': 4.0, // Assuming this is an add-on price?
      'rating': 2.0,
      'location': 'MAWANDA Rd',
      'chefid': 2, // Example ID
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
        print('[MealDetail] Cache hit: Loaded chefs from cache');
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
        print('[MealDetail] Cache hit: Loaded producers from cache');
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

class _MealDetailScreenState extends State<MealDetailScreen>
    with TickerProviderStateMixin {
  bool _ingredientsExpanded = false;
  bool isFavorite = false;
  bool isChefSelected = true; // Default view to 'Cooked' (Chefs)
  // bool _isInCart = false; // Replaced by isInCart
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
  bool isInCart = false; // Tracks if the *main meal* is in the cart

  // --- NEW: State for complementary item selection ---
  List<bool> _selectedComplementaries = []; // Renamed for clarity

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

  late final AnimationController _refreshIconController;

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // --- Initialize bestservedwith if needed ---
    // Ensure this runs *before* _initializeData
    _ensureBestServedWithStructure();

    // --- Initialize selection state (all false by default) ---
    final bestServedWith = widget.meal['bestservedwith'];
    _selectedComplementaries = bestServedWith != null && bestServedWith is List
        ? List<bool>.filled(bestServedWith.length, false)
        : [];

    _initializeData(); // Initialize cart status, selections, and load data
  }

  // Helper method to ensure the 'bestservedwith' structure is correct
  void _ensureBestServedWithStructure() {
     if (widget.meal['bestservedwith'] == null || widget.meal['bestservedwith'] is! List) {
          // If 'bestservedwith' is missing or not a list, try creating it
          final dishes = _parseListFromString(widget.meal['Complementary_dishes']);
          final images = _parseListFromString(widget.meal['complementary_images']);
          // Assuming prices might be in another field or default to 0
          final prices = _parseListFromString(widget.meal['complementary_prices']); // Example field

          if (dishes.isNotEmpty) {
              widget.meal['bestservedwith'] = List.generate(
              dishes.length,
              (i) => {
                  'name': dishes[i],
                  // Use parsed price if available, otherwise default to '0'
                  'price': prices.length > i && prices[i].isNotEmpty ? prices[i] : '0',
                  'image': images.length > i ? images[i] : '',
              },
              );
              print("Initialized 'bestservedwith' structure.");
          } else {
               widget.meal['bestservedwith'] = []; // Initialize as empty list if no dishes
               print("Initialized 'bestservedwith' as empty list (no dishes).");
          }
     } else {
          // Ensure existing items have the correct keys (name, price, image)
           final currentList = widget.meal['bestservedwith'] as List;
           widget.meal['bestservedwith'] = currentList.map((item) {
               if (item is Map<String, dynamic>) {
                   return {
                       'name': item['name']?.toString() ?? 'Unknown',
                       'price': item['price']?.toString() ?? '0', // Ensure price is string initially
                       'image': item['image']?.toString() ?? '',
                   };
               }
               return {'name': 'Invalid Item', 'price': '0', 'image': ''}; // Fallback for non-map items
           }).toList();
           // print("Validated existing 'bestservedwith' structure.");
     }
  }


  Future<void> _initializeData() async {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';

    // --- CRITICAL: Use the imported (shared) Favorites and ShoppingCart ---
    isFavorite = Favorites.isFavorite(mealTitle);
    // Use the cart helper method to find the item
    final cartItemIndex = ShoppingCart.findItemIndex(mealTitle);
    final currentItemInCart = (cartItemIndex != -1) ? ShoppingCart.items[cartItemIndex] : null;

    // Reset selections initially
    selectedChef = null;
    selectedProducer = null;
    isInCart = false;
    isChefSelected = true; // Default to chef view

    if (currentItemInCart != null) {
      isInCart = true;
      selectedChef = currentItemInCart['selectedchef'];
      selectedProducer = currentItemInCart['selectedproducer'];
      // Determine UI toggle based on which one is NOT null
      isChefSelected = selectedProducer == null;

      // Restore quantity, bulk status, and plan details from cart
      _quantityPerDay = ShoppingCart.getItemQuantity(mealTitle); // Get quantity from cart
      _isBulkOrder = ShoppingCart.isBulkOrder(mealTitle);
      if (_isBulkOrder) {
          _planStartDate = ShoppingCart.getPlanStartDate(mealTitle);
          _planEndDate = ShoppingCart.getPlanEndDate(mealTitle);
          _selectedFrequency = ShoppingCart.getPlanFrequency(mealTitle) ?? 'daily';
          _selectedDays = ShoppingCart.getPlanSelectedDays(mealTitle) ?? {};
      } else {
           // Reset plan details if not a bulk order in cart
           _planStartDate = null;
           _planEndDate = null;
           _selectedFrequency = 'daily';
           _selectedDays.clear();
      }


      // --- IMPORTANT: Restore complementary selection state if item was in cart ---
      List<Map<String, dynamic>> complementariesInCart =
          List<Map<String, dynamic>>.from(
              currentItemInCart['bestservedwith'] ?? []);
      final currentBestServedWith = widget.meal['bestservedwith'];

      if (currentBestServedWith != null && currentBestServedWith is List) {
        // Ensure _selectedComplementaries has the correct length first
        if (_selectedComplementaries.length != currentBestServedWith.length) {
           _selectedComplementaries = List<bool>.filled(currentBestServedWith.length, false);
           print("Warning: Corrected _selectedComplementaries length during init.");
        }
        // Now populate based on cart data
        for (int i = 0; i < currentBestServedWith.length; i++) {
           if (i < _selectedComplementaries.length) { // Double check bounds
               final compName = currentBestServedWith[i]['name'] ?? '';
               _selectedComplementaries[i] = complementariesInCart.any((cartComp) => cartComp['name'] == compName);
           }
        }
      } else {
         // If bestservedwith is null/empty, ensure selection is empty
         _selectedComplementaries = [];
      }
    } else {
      // If not in cart, ensure selections are cleared and complementaries are deselected
      isInCart = false;
      selectedChef = null;
      selectedProducer = null;
      isChefSelected = true; // Default view
      // Ensure complementary selections are reset if item not in cart
      final bestServedWith = widget.meal['bestservedwith'];
      _selectedComplementaries = bestServedWith != null && bestServedWith is List
          ? List<bool>.filled(bestServedWith.length, false)
          : [];
       // Reset quantity and bulk/plan status
       _quantityPerDay = 1;
       _isBulkOrder = false;
       _planStartDate = null;
       _planEndDate = null;
       _selectedFrequency = 'daily';
       _selectedDays.clear();
    }
    // --- End Critical Section ---

    // Load data (respecting cache) - Ensure setState is called safely
    if (mounted) {
       setState(() {}); // Update UI with initial cart/fav/selection status
    }
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
            CacheConfig.chefProducerDetailCacheDuration;
    bool producersCacheValid = MealDetailScreen._producersCache.isNotEmpty &&
        MealDetailScreen._producersCacheTimestamp != null &&
        now.difference(MealDetailScreen._producersCacheTimestamp!) <
            CacheConfig.chefProducerDetailCacheDuration;

    // Always display cached data immediately if available
    if (mounted) {
      setState(() {
        if (MealDetailScreen._chefsCache.isNotEmpty) {
          chefs = MealDetailScreen._chefsCache;
          // Only set loading false if cache is valid or not forcing refresh
          if (chefsCacheValid && !forceRefresh) isLoadingChefs = false;
        } else {
          isLoadingChefs = true; // No cache, definitely loading
        }
        if (MealDetailScreen._producersCache.isNotEmpty) {
          producers = MealDetailScreen._producersCache;
          if (producersCacheValid && !forceRefresh) isLoadingProducers = false;
        } else {
          isLoadingProducers = true; // No cache, definitely loading
        }
      });
    }

    // Fetch new data in the background if cache is invalid or force refresh
    List<Future<void>> fetchFutures = [];
    if (forceRefresh || !chefsCacheValid) {
      print("Fetching chefs (Cache invalid/empty or forced refresh)");
       if(mounted) setState(() => isLoadingChefs = true); // Show loading before fetch starts
      fetchFutures.add(fetchChefsWithRetry());
    }

    if (forceRefresh || !producersCacheValid) {
      print("Fetching producers (Cache invalid/empty or forced refresh)");
       if(mounted) setState(() => isLoadingProducers = true); // Show loading before fetch starts
      fetchFutures.add(fetchProducers());
    }

    // Wait for fetches to complete if any were started
    if (fetchFutures.isNotEmpty) {
      try {
          await Future.wait(fetchFutures);
      } catch (e) {
          print("Error during background data fetch: $e");
          if (mounted) {
               showCustomSnackBar(context, "Error fetching data. Please try refreshing.", isError: true);
          }
      } finally {
           // Ensure loading spinners are off after fetches attempt, even if failed
            if (mounted) {
                setState(() {
                    isLoadingChefs = false;
                    isLoadingProducers = false;
                });
            }
      }
    } else {
       // If no fetches were needed, ensure loading is off
       if (mounted) {
            setState(() {
                isLoadingChefs = false;
                isLoadingProducers = false;
            });
       }
    }
  }

  // --- Manual Refresh Logic ---
  Future<void> _handleRefresh() async {
     _startRefreshAnimation();
    print("Manual refresh triggered.");
    // Set loading states immediately for visual feedback
    if (mounted) {
        setState(() {
            isLoadingChefs = true;
            isLoadingProducers = true;
        });
    }
    try {
        await _loadData(forceRefresh: true);
        showCustomSnackBar(context, 'Data refreshed!');
    } catch (e) {
        print("Error during manual refresh: $e");
        showCustomSnackBar(context, 'Refresh failed. Check connection.', isError: true);
    } finally {
         _stopRefreshAnimation();
         // Ensure loading states are turned off even if fetch failed but component still mounted
         if(mounted) {
             setState(() {
                 isLoadingChefs = false;
                 isLoadingProducers = false;
             });
         }
    }
  }


  // --- Fetch Chefs Logic ---
  Future<void> fetchChefs() async {
    if (_isFetchingChefs || !mounted) return;

    if (mounted) setState(() => _isFetchingChefs = true);
    // Keep isLoadingChefs true if already set by _loadData or _handleRefresh

    final url = '$apibaseurl/rr/rchefs';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 25));
      if (!mounted) return;

      List<dynamic> chefsList = [];
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is List) {
          chefsList = responseData.asMap().entries.map((entry) => _mapChefData(entry.value, entry.key)).toList();
        } else if (responseData is Map<String, dynamic> && responseData['data'] is List) {
          chefsList = (responseData['data'] as List).asMap().entries.map((entry) => _mapChefData(entry.value, entry.key)).toList();
        } else {
          print('Unexpected response format for chefs: $responseData');
        }

        if (mounted) {
            setState(() {
                chefs = chefsList; // Update with fetched data (could be empty)
                // isLoadingChefs = false; // Handled in finally or _loadData
            });
            // Update cache only if data is not empty? Or update with empty list? Let's update.
             MealDetailScreen._chefsCache = chefsList;
             MealDetailScreen._chefsCacheTimestamp = DateTime.now();
             await MealDetailScreen.saveChefsCacheToUserCache(chefsList);
        }

      } else {
        print('Failed to load chefs. Status code: ${response.statusCode}.');
        if (mounted && chefs.isEmpty) { // Only show error if no cache was displayed
          showCustomSnackBar(context, 'Failed to load chefs. Please try again.', isError: true);
        }
         // isLoadingChefs = false; // Handled in finally
      }
    } on TimeoutException {
      print('Chef fetch timed out.');
      if (mounted && chefs.isEmpty) {
        showCustomSnackBar(context, 'Chef request timed out.', isError: true);
      }
       // isLoadingChefs = false; // Handled in finally
    } on Exception catch (e) {
      print('Error fetching chefs: $e');
      if (mounted && chefs.isEmpty) {
        showCustomSnackBar(context, 'Unable to load chefs. An error occurred.', isError: true);
      }
       // isLoadingChefs = false; // Handled in finally
    } finally {
      if (mounted) {
        setState(() {
            _isFetchingChefs = false;
            // isLoadingChefs = false; // Turn off loading indicator here
        });
      }
    }
  }

  // Helper to map chef data consistently
  Map<String, dynamic> _mapChefData(dynamic chef, int index) {
    // Ensure chef is a Map
    if (chef is! Map<String, dynamic>) {
      print('Warning: Expected chef data to be a Map, but got ${chef.runtimeType}');
      // Use fallback data
      var fallbackChef = ChefData.chefs.firstWhere(
          (c) => c['name'] == 'Default Chef',
          orElse: () => ChefData.chefs.isNotEmpty ? ChefData.chefs[0] : {});
      if (fallbackChef.isEmpty) return {'chefid': index}; // Minimal fallback
      return {
        'image': fallbackChef['image'] ?? 'assets/images/placeholderchef.jpeg',
        'name': fallbackChef['name'] ?? 'Unknown Chef $index',
        'price': fallbackChef['price'] ?? 0.0,
        'rating': fallbackChef['rating'] ?? 0.0,
        'location': fallbackChef['location'] ?? 'Unknown Location',
        'chefid': fallbackChef['chefid'] ?? index,
      };
    }
    return {
      'image': chef['image'] ?? 'assets/images/placeholderchef.jpeg',
      'name': chef['name'] ?? 'Unknown Chef',
      'price': _parsePrice(chef['price']),
      'rating': _parsePrice(chef['rating']),
      'location': chef['location'] ?? 'Unknown Location',
      'chefid': chef['chefid'] ?? index,
    };
  }

  // --- Fetch Chefs with Retry Logic ---
  Future<void> fetchChefsWithRetry({int retryCount = 2}) async {
    for (int i = 0; i < retryCount; i++) {
      await fetchChefs();
      // Check if fetch was successful OR cache is now valid
      final bool cacheValid = MealDetailScreen._chefsCache.isNotEmpty &&
          MealDetailScreen._chefsCacheTimestamp != null &&
          DateTime.now().difference(MealDetailScreen._chefsCacheTimestamp!) < CacheConfig.chefProducerDetailCacheDuration;

      if (mounted && (chefs.isNotEmpty || cacheValid)) {
        // If we have data (from fetch or valid cache), ensure loading is off and exit
         if (isLoadingChefs) setState(() => isLoadingChefs = false);
        return;
      }

      if (mounted) {
        print('Retry ${i + 1} for fetchChefs...');
        if (i < retryCount - 1) await Future.delayed(Duration(seconds: 1 * (i + 1)));
      } else {
        break; // Stop retrying if widget is disposed
      }
    }

    // After all retries
    if (mounted && chefs.isEmpty) {
      print('Final retry failed for fetchChefs. Using default list.');
      setState(() {
        chefs = ChefData.chefs; // Use static fallback
        isLoadingChefs = false; // Ensure loading is off
        _isFetchingChefs = false;
      });
       showCustomSnackBar(context, 'Failed to load chefs. Showing defaults.', isError: true);
    } else if (mounted && isLoadingChefs) {
       // If retries ended but cache might be valid now, still ensure loading is off
        setState(() => isLoadingChefs = false);
    }
  }

  // --- Fetch Producers Logic ---
   Future<void> fetchProducers() async {
    if (_isFetchingProducers || !mounted) return;

    if(mounted) setState(() => _isFetchingProducers = true);
    // Keep isLoadingProducers true if already set

    final url = '$apibaseurl/rr/rproducers';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 25));
      if (!mounted) return;

      List<dynamic> producerRawList = [];
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is List) {
          producerRawList = responseData;
        } else if (responseData is Map<String, dynamic> && responseData['data'] is List) {
          producerRawList = responseData['data'];
        } else {
          print('Unexpected response format for producers: $responseData');
        }

        final mappedProducers = producerRawList.map((producer) {
          if (producer is! Map<String, dynamic>) {
             print('Warning: Expected producer data Map, got ${producer.runtimeType}');
            return {'producer_id': DateTime.now().millisecondsSinceEpoch + producerRawList.indexOf(producer), 'name': 'Invalid Data', 'image': 'assets/images/producerHolder.png', 'Location': 'N/A', 'Rating': 0.0};
          }
          final name = producer['name']?.toString().trim() ?? '';
          final image = producer['image']?.toString().trim() ?? '';
          final location = producer['location']?.toString().trim() ?? '';
          final rating = _parsePrice(producer['rating']);
          final id = producer['producer_id'] ?? DateTime.now().millisecondsSinceEpoch + producerRawList.indexOf(producer);
          return {
            'producer_id': id,
            'name': name.isEmpty ? 'Unknown Producer' : name,
            'image': image.isEmpty ? 'assets/images/producerHolder.png' : image,
            'Location': location.isEmpty ? 'Unknown Location' : location,
            'Rating': rating,
          };
        }).toList();

        if (mounted) {
            setState(() {
                producers = mappedProducers;
                // isLoadingProducers = false; // Handled in finally
            });
             MealDetailScreen._producersCache = mappedProducers;
             MealDetailScreen._producersCacheTimestamp = DateTime.now();
             await MealDetailScreen.saveProducersCacheToUserCache(mappedProducers);
        }

      } else {
        print('Failed to load producers. Status code: ${response.statusCode}.');
         if (mounted && producers.isEmpty) {
            showCustomSnackBar(context, 'Failed to load producers. Please try again.', isError: true);
        }
         // isLoadingProducers = false; // Handled in finally
      }
    } on TimeoutException {
      print('Producer fetch timed out.');
      if (mounted && producers.isEmpty) {
        showCustomSnackBar(context, 'Producer request timed out.', isError: true);
      }
       // isLoadingProducers = false; // Handled in finally
    } catch (e) {
      print('Error fetching producers: $e');
      if (mounted && producers.isEmpty) {
        showCustomSnackBar(context, 'Unable to load producers. An error occurred.', isError: true);
      }
       // isLoadingProducers = false; // Handled in finally
    } finally {
      if (mounted) {
        setState(() {
             _isFetchingProducers = false;
            // isLoadingProducers = false; // Turn off loading indicator here
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
        String image = _formatImageUrl(widget.meal['Image_link'] ?? 'assets/images/cover.png');
        Favorites.addItem(title, price, image);
        showCustomSnackBar(context, '$title added to favorites!');
      }
      isFavorite =
          !isFavorite; // Toggle local state AFTER updating shared state
    });
    // --- End Favorites ---
  }

  // --- UPDATED: _chooseChef ---
  void _chooseChef(Map<String, dynamic> chef) {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    final mainMealPrice = _parsePrice(widget.meal['Price']);

    setState(() {
      Map<String, dynamic> chefWithId = Map<String, dynamic>.from(chef);
      // Ensure 'chefid' exists
       if (!chefWithId.containsKey('chefid') && chefWithId.containsKey('id')) {
           chefWithId['chefid'] = chefWithId['id'];
       } else if (!chefWithId.containsKey('chefid')) {
           chefWithId['chefid'] = DateTime.now().millisecondsSinceEpoch; // Fallback ID
           print("Warning: Chef missing 'chefid', assigned temporary ID.");
       }

      selectedChef = chefWithId;
      selectedProducer = null;
      isChefSelected = true;

      // Gather currently selected complementaries data
      List<Map<String, dynamic>> currentlySelectedComplementaries = _getSelectedComplementariesData();

       // Calculate price PER UNIT (meal + complementaries)
      double complementaryTotalPrice = currentlySelectedComplementaries.fold(0, (sum, item) => sum + (item['price'] as double? ?? 0.0));
      double singleItemPriceWithComplementaries = mainMealPrice + complementaryTotalPrice;

       // Get quantity (use current cart quantity if exists, else use screen's default)
       int quantity = ShoppingCart.getItemQuantity(mealTitle);
       if (quantity == 0) quantity = _quantityPerDay > 0 ? _quantityPerDay : 1; // If not in cart, use local setting

      // Add/Update item in cart using ShoppingCart class
      ShoppingCart.addItem(
        mealTitle,
        singleItemPriceWithComplementaries, // Price PER UNIT
        quantity: quantity,
        selectedchef: selectedChef, // Pass the newly selected chef map
        selectedproducer: null, // Ensure producer is null
        meal: widget.meal, // Pass the full meal data
        bestservedwith: currentlySelectedComplementaries, // Pass selected complementaries list
         // Keep bulk details consistent if updating an existing cart item
         isBulkOrder: ShoppingCart.isBulkOrder(mealTitle),
         planStartDate: ShoppingCart.getPlanStartDate(mealTitle),
         planEndDate: ShoppingCart.getPlanEndDate(mealTitle),
         planFrequency: ShoppingCart.getPlanFrequency(mealTitle),
         planSelectedDays: ShoppingCart.getPlanSelectedDays(mealTitle),
      );
      isInCart = true; // Ensure cart status reflects the addition/update
    });
    showCustomSnackBar(context, '${chef['name']} selected!');
    Navigator.pop(context); // Close the bottom sheet after selection
  }

  // --- UPDATED: _chooseProducer ---
  void _chooseProducer(Map<String, dynamic> producer) {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    final mainMealPrice = _parsePrice(widget.meal['Price']);

    setState(() {
       Map<String, dynamic> producerWithId = Map<String, dynamic>.from(producer);
       // Ensure 'producer_id' exists
       if (!producerWithId.containsKey('producer_id') && producerWithId.containsKey('id')) {
           producerWithId['producer_id'] = producerWithId['id'];
       } else if (!producerWithId.containsKey('producer_id')) {
           producerWithId['producer_id'] = DateTime.now().millisecondsSinceEpoch; // Fallback ID
           print("Warning: Producer missing 'producer_id', assigned temporary ID.");
       }

      selectedProducer = producerWithId;
      selectedChef = null; // Deselect chef
      isChefSelected = false; // Update the selection state for UI

      // Gather currently selected complementaries data
      List<Map<String, dynamic>> currentlySelectedComplementaries = _getSelectedComplementariesData();

       // Calculate price PER UNIT (meal + complementaries)
      double complementaryTotalPrice = currentlySelectedComplementaries.fold(0, (sum, item) => sum + (item['price'] as double? ?? 0.0));
      double singleItemPriceWithComplementaries = mainMealPrice + complementaryTotalPrice;

      // Get quantity (use current cart quantity if exists, else use screen's default)
       int quantity = ShoppingCart.getItemQuantity(mealTitle);
       if (quantity == 0) quantity = _quantityPerDay > 0 ? _quantityPerDay : 1;

      // Add/Update item in cart using ShoppingCart class
      ShoppingCart.addItem(
        mealTitle,
        singleItemPriceWithComplementaries, // Price PER UNIT
        quantity: quantity,
        selectedchef: null, // Ensure chef is null
        selectedproducer: selectedProducer, // Pass the newly selected producer map
        meal: widget.meal,
        bestservedwith: currentlySelectedComplementaries, // Pass selected complementaries list
         // Keep bulk details consistent if updating
         isBulkOrder: ShoppingCart.isBulkOrder(mealTitle),
         planStartDate: ShoppingCart.getPlanStartDate(mealTitle),
         planEndDate: ShoppingCart.getPlanEndDate(mealTitle),
         planFrequency: ShoppingCart.getPlanFrequency(mealTitle),
         planSelectedDays: ShoppingCart.getPlanSelectedDays(mealTitle),
      );
      isInCart = true; // Ensure cart status reflects the addition/update
    });
    showCustomSnackBar(context, '${producer['name']} selected!');
    Navigator.pop(context); // Close the bottom sheet after selection
  }

  // --- UPDATED: _toggleCart --- (Now primarily handles removal)
 void _toggleCart() {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';

    if (isInCart) { // If the UI *thinks* it's in cart
      // --- Remove from Cart ---
      final index = ShoppingCart.findItemIndex(mealTitle); // Use helper
      if (index != -1) {
        ShoppingCart.removeItemByIndex(index); // This notifies listeners
        showCustomSnackBar(context, '$mealTitle removed from cart');
        // Update local state AFTER modifying shared state
         if (mounted) {
            setState(() {
                isInCart = false;
                selectedChef = null;
                selectedProducer = null;
                isChefSelected = true; // Default back to chef view
                _selectedComplementaries = List<bool>.filled(_selectedComplementaries.length, false);
                _isBulkOrder = false;
                _quantityPerDay = 1; // Reset quantity
                // Optionally reset plan details
                 _planStartDate = null;
                 _planEndDate = null;
                 _selectedFrequency = 'daily';
                 _selectedDays.clear();
            });
         }
      } else {
         // State inconsistency: UI thought it was in cart, but it wasn't found. Correct the state.
          if (mounted) {
              setState(() {
                 isInCart = false;
                 // Reset selections as they are likely invalid now
                 selectedChef = null;
                 selectedProducer = null;
                 isChefSelected = true;
                 _selectedComplementaries = List<bool>.filled(_selectedComplementaries.length, false);
                 _isBulkOrder = false;
                 _quantityPerDay = 1;
              });
          }
          print("Warning: _toggleCart called for removal, but item '$mealTitle' not found in cart.");
      }
    } else {
      // --- Add to Cart ---
      // Call the main _addToCart method. It handles checks for chef/producer selection.
       _addToCart();
    }
  }


  // --- NEW: Method to handle complementary item selection ---
  void _toggleComplementary(int index) {
    if (!mounted) return; // Check if widget is still mounted

    final bestServedWithList = widget.meal['bestservedwith'];
    if (bestServedWithList == null || bestServedWithList is! List || index < 0 || index >= bestServedWithList.length) {
       print("Error: Invalid index or 'bestservedwith' data for _toggleComplementary. Index: $index");
       return;
    }

     // Ensure selection list matches data length before modification
     if (_selectedComplementaries.length != bestServedWithList.length) {
          print("Warning: Correcting _selectedComplementaries length in _toggleComplementary.");
          _selectedComplementaries = List<bool>.filled(bestServedWithList.length, false);
          // Re-initialize might be needed here, or just proceed carefully
          // _initializeData(); // Could cause issues if called mid-build cycle
     }

     // Check index bounds again after potential resize
     if (index >= _selectedComplementaries.length) {
         print("Error: Index $index still out of bounds after correction.");
         return;
     }


    setState(() {
      _selectedComplementaries[index] = !_selectedComplementaries[index];
    });

    // If item is already in cart and a provider is selected, update the cart item
    if (isInCart && (selectedChef != null || selectedProducer != null)) {
      _updateCartWithSelections();
    }
    // If not in cart, selections are stored locally. They will be used when
    // _addToCart, _chooseChef, or _chooseProducer eventually calls ShoppingCart.addItem.
  }

  // --- NEW: Helper to update cart with current selections ---
  void _updateCartWithSelections() {
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    if (!isInCart || ShoppingCart.findItemIndex(mealTitle) == -1) {
        print("Warning: _updateCartWithSelections called but item '$mealTitle' is not in cart.");
        // Correct local state if needed
        if (isInCart && mounted) setState(() => isInCart = false);
        return; // Should not be called if main item is not in cart
    }

    final mainMealPrice = _parsePrice(widget.meal['Price']);
    final currentQuantity = ShoppingCart.getItemQuantity(mealTitle); // Get current quantity from cart

    // Get selected complementaries data
    List<Map<String, dynamic>> currentlySelectedComplementaries = _getSelectedComplementariesData();

     // Calculate new price per unit based on current selections
    double complementaryTotalPrice = currentlySelectedComplementaries.fold(0, (sum, item) => sum + (item['price'] as double? ?? 0.0));
    double singleItemPriceWithComplementaries = mainMealPrice + complementaryTotalPrice;


    // Update cart - addItem will replace the existing item
    ShoppingCart.addItem(
      mealTitle,
      singleItemPriceWithComplementaries, // Pass the NEW price PER UNIT
      quantity: currentQuantity, // Keep the existing quantity
      selectedchef: selectedChef, // Keep the currently selected chef
      selectedproducer: selectedProducer, // Keep the currently selected producer
      meal: widget.meal,
      bestservedwith: currentlySelectedComplementaries, // Pass the NEW list of selected items
       // Keep bulk details consistent with the cart item
       isBulkOrder: ShoppingCart.isBulkOrder(mealTitle),
       planStartDate: ShoppingCart.getPlanStartDate(mealTitle),
       planEndDate: ShoppingCart.getPlanEndDate(mealTitle),
       planFrequency: ShoppingCart.getPlanFrequency(mealTitle),
       planSelectedDays: ShoppingCart.getPlanSelectedDays(mealTitle),
    );
     // Optional: Show feedback that cart was updated
     // showCustomSnackBar(context, 'Cart updated with complementary items.');
  }

   // --- NEW: Helper to get data of selected complementary items ---
   List<Map<String, dynamic>> _getSelectedComplementariesData() {
       List<Map<String, dynamic>> selectedData = [];
       final bestServedWithList = widget.meal['bestservedwith'];

       if (bestServedWithList != null && bestServedWithList is List) {
            // Ensure the selection list length matches before iterating
           if (_selectedComplementaries.length == bestServedWithList.length) {
               for (int i = 0; i < bestServedWithList.length; i++) {
                   if (_selectedComplementaries[i]) { // Check selection state
                       final compItem = bestServedWithList[i];
                       if (compItem is Map<String, dynamic>) {
                           selectedData.add({
                               'name': compItem['name'] ?? 'Unknown Complementary',
                               'price': _parsePrice(compItem['price']), // Ensure price is double
                               'image': compItem['image'] ?? '',
                           });
                       }
                   }
               }
           } else {
                print("Warning: _selectedComplementaries length mismatch in _getSelectedComplementariesData. Returning empty.");
           }
       }
       return selectedData;
   }

  // --- Utility Methods ---
  double _parsePrice(dynamic rawPrice) {
    double price = 0.0; // Default to 0.0 if parsing fails
    if (rawPrice == null) return price;
    if (rawPrice is int) {
      price = rawPrice.toDouble();
    } else if (rawPrice is double) {
      price = rawPrice;
    } else if (rawPrice is String) {
       // Handle potential currency symbols or commas if necessary
      String cleanedPrice = rawPrice.replaceAll(RegExp(r'[^\d.]'), '');
      price = double.tryParse(cleanedPrice) ?? 0.0;
    }
    return price;
  }

  String getShortLocation(String? location) {
    location ??= 'N/A';
    if (location.length <= 30) return location;
    return location.substring(0, 30) + '...';
  }

  String _formatImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return 'assets/images/cover.png'; // Default if null or empty
    }
    
    // Handle local assets
    if (imageUrl.startsWith('assets/')) {
      return imageUrl;
    }
    
    // Use the centralized ImageUtils to process the URL
    return ImageUtils.processImageUrl(imageUrl);
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    // Extract meal data safely using PascalCase keys (or fallback)
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    final mealDescription =
        widget.meal['Meal_description'] ?? 'No description available.';
    final List<String> ingredients =
        _parseListFromString(widget.meal['Ingredients']);

    // Use the structured 'bestservedwith' list created/validated in initState
    final List<dynamic> bestServedWithList = widget.meal['bestservedwith'] ?? [];
    // These lists are only needed for the new _buildBestServedWith method signature
    final List<String> complementariesNames = bestServedWithList
        .map((item) => item['name']?.toString() ?? '')
        .toList();
    final List<String> complementaryImages = bestServedWithList
        .map((item) => item['image']?.toString() ?? '')
        .toList();


    final String imageUrl = _formatImageUrl(widget.meal['Image_link']);
    double price = _parsePrice(widget.meal['Price']);

    // Use GoogleFonts theme base
    final textTheme = Theme.of(context).textTheme.apply(
        fontFamily: GoogleFonts.poppins().fontFamily,
        bodyColor: kColorTextPrimary,
        displayColor: kColorTextPrimary);

    return Theme(
      data: Theme.of(context).copyWith(textTheme: textTheme),
      child: Scaffold(
        drawer: const drawer.AppDrawer(), // Add the drawer here
        appBar: AppBar(
          title: Text(mealTitle, style: GoogleFonts.poppins()),
          foregroundColor: Colors.white,
          backgroundColor: kColorPrimaryDark,
          elevation: 2,
          actions: [
            // Refresh Icon with Animation
            AnimatedBuilder(
              animation: _refreshIconController,
              builder: (context, child) {
                final isLoading = _isFetchingChefs || _isFetchingProducers;
                if (isLoading && !_refreshIconController.isAnimating) {
                    _refreshIconController.repeat();
                } else if (!isLoading && _refreshIconController.isAnimating) {
                     _refreshIconController.stop();
                     _refreshIconController.reset();
                }
                return IconButton(
                  icon: Transform.rotate(
                    angle: _refreshIconController.value * 2 * 3.14159,
                    child: const Icon(Icons.sync),
                  ),
                  tooltip: isLoading ? 'Refreshing...' : 'Refresh Data',
                  onPressed: isLoading ? null : _handleRefresh,
                );
              },
            ),
             IconButton(
              tooltip: 'View Favorites',
              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              color: isFavorite ? Colors.red[400] : Colors.white,
              onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => FavoritesScreen()))
                  .then((_) {
                      if (mounted) { // Check if still mounted before setState
                          setState(() => isFavorite = Favorites.isFavorite(mealTitle));
                      }
                  }),
            ),
            // Cart Icon with Badge reacting to ValueNotifier
            ValueListenableBuilder<List<Map<String, dynamic>>>(
                 valueListenable: ShoppingCart.itemsNotifier,
                 builder: (context, cartItems, child) {
                     return Stack(
                       alignment: Alignment.center,
                       children: [
                         IconButton(
                           tooltip: 'View Cart',
                           icon: Icon(Icons.shopping_cart_outlined),
                           onPressed: () => Navigator.push(
                                   context,
                                   MaterialPageRoute(
                                       builder: (context) => ShoppingCartScreen()))
                               .then((_) => _initializeData()), // Refresh screen state on return
                         ),
                         if (cartItems.isNotEmpty)
                           Positioned(
                             right: 8,
                             top: 8,
                             child: Container(
                               padding: EdgeInsets.all(2.0),
                               decoration: BoxDecoration(
                                 color: kColorAccent, shape: BoxShape.circle,
                               ),
                               constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                               child: Text(
                                 '${cartItems.length}',
                                 style: GoogleFonts.poppins(
                                     color: kColorPrimaryDark, fontSize: 10, fontWeight: FontWeight.bold),
                                 textAlign: TextAlign.center,
                               ),
                             ),
                           ),
                       ],
                     );
                 }
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
                           key: ValueKey(imageUrl), // Add key for better updates if URL changes
                          placeholder: (context, url) => Center(
                              child: CircularProgressIndicator(
                                  color: kColorPrimary)),
                          errorWidget: (context, url, error) {
                             print("Error loading image: $url, Error: $error");
                             return Image.asset(
                              'assets/images/cover.png',
                              fit: BoxFit.cover);
                          },
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
                                Text('Price: ugx ${price.toStringAsFixed(0)}', // Format price
                                    style: GoogleFonts.poppins(
                                        fontSize: 16, // Slightly larger price
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
                                    color: isFavorite ? Colors.red[400] : kColorPrimary),
                                iconSize: 30,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                onPressed: () => _toggleFavorite(mealTitle),
                              ),
                            ),
                            SizedBox(height: 12), // Increased spacing
                             // Add/Remove Cart Button reacts to isInCart state
                             ValueListenableBuilder<List<Map<String, dynamic>>>(
                                valueListenable: ShoppingCart.itemsNotifier,
                                builder: (context, cartItems, child) {
                                   // Recalculate isInCart based on actual cart state when notifier updates
                                   final actualIsInCart = ShoppingCart.findItemIndex(mealTitle) != -1;
                                   // If local state differs from actual cart state, trigger a state update after build
                                   if (isInCart != actualIsInCart && mounted) {
                                     WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) { // Check again as callback is async
                                           setState(() {
                                              isInCart = actualIsInCart;
                                              // Optionally re-initialize if needed to sync selections
                                              if (!actualIsInCart) _initializeData();
                                           });
                                        }
                                     });
                                   }

                                   return Tooltip(
                                      message: actualIsInCart ? 'Remove from Cart' : 'Add to Cart',
                                      child: IconButton(
                                         icon: Icon(
                                            actualIsInCart
                                              ? Icons.remove_shopping_cart_outlined // Indicate removal
                                              : Icons.add_shopping_cart,
                                            color: actualIsInCart
                                              ? kColorError // Use error color for removal
                                              : kColorPrimary, // Primary color for add
                                         ),
                                         iconSize: 30,
                                         padding: EdgeInsets.zero,
                                         constraints: BoxConstraints(),
                                         onPressed: _toggleCart, // Call the toggle function
                                      ),
                                   );
                                }
                             ),
                          ]),
                        ]),
                  ),
                  SizedBox(height: _sectionSpacing + 4),

                  // --- Sections ---
                  // Pass the correctly parsed lists/data to _buildBestServedWith
                  _buildBestServedWith(complementariesNames, complementaryImages),
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
                               // Update state first
                               if (mounted) setState(() => isChefSelected = true);
                               // Then show modal
                               showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20))),
                                   backgroundColor: kBottomSheetBgColor, // Set background color
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
                               // Update state first
                               if (mounted) setState(() => isChefSelected = false);
                               // Then show modal
                               showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20))),
                                   backgroundColor: kBottomSheetBgColor, // Set background color
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
      // Ensure all elements are strings and trimmed
      return List<String>.from(data.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
    }
    if (data is String) {
      return data
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    // If it's neither a List nor a String, return empty
     print("Warning: Could not parse data into List<String>: $data");
    return [];
  }


  // --- UPDATED: _buildBestServedWith using _selectedComplementaries ---
  Widget _buildBestServedWith(
      List<String> complementaries, List<String> complementaryImages) { // Note: Signature kept for compatibility, but internal logic uses structured data
    // Use the structured list from widget.meal for prices etc.
    final bestServedWithData = widget.meal['bestservedwith'];

    if (bestServedWithData == null || bestServedWithData is! List || bestServedWithData.isEmpty) {
      return SizedBox.shrink(); // No complementary items to show
    }

    // Ensure selection list matches data length (Crucial check)
    if (_selectedComplementaries.length != bestServedWithData.length) {
         print("Error: Mismatch between _selectedComplementaries (${_selectedComplementaries.length}) and bestServedWithData (${bestServedWithData.length}) in buildBestServedWith. Hiding section.");
         // Log detailed info for debugging
         // print("Widget Meal Data: ${widget.meal}");
         // Return empty box to prevent build errors
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
            height: 150, // Consistent height
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: bestServedWithData.length, // Use data list length
              itemBuilder: (context, index) {
                // Bounds check already implicitly handled by list length check above
                final itemData = bestServedWithData[index];
                 // Defensive check for item data type
                if (itemData is! Map<String, dynamic>) {
                  print("Warning: Item at index $index is not a Map: $itemData");
                  return SizedBox.shrink();
                }

                final itemTitle = itemData['name']?.toString() ?? 'Unknown';
                final itemPrice = _parsePrice(itemData['price']); // Use safe parser
                String rawImageUrl = itemData['image']?.toString() ?? '';
                final String displayImageUrl = _formatImageUrl(rawImageUrl.isNotEmpty ? rawImageUrl : 'assets/images/cover.png');

                // Use the selection state list
                bool isSelected = _selectedComplementaries[index];

                return GestureDetector(
                  onTap: () => _toggleComplementary(index), // Use index
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
                      // --- VISUAL FEEDBACK: Border ---
                      border: Border.all(
                          color: isSelected
                              ? kColorPrimary // Highlight color when selected
                              : kColorPrimaryLight.withOpacity(0.4), // Default border
                          width: isSelected ? 2.0 : 1.0), // Thicker border when selected
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(_buttonCornerRadius)),
                          child: Stack( // Stack to overlay checkmark
                            children: [
                              CachedNetworkImage(
                                imageUrl: displayImageUrl,
                                key: ValueKey(displayImageUrl), // Key for image updates
                                width: 110.0,
                                height: 75.0, // Fixed height for image
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 75.0,
                                  color: kColorPrimaryLight.withOpacity(0.1),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: kColorPrimary)),
                                ),
                                errorWidget: (context, url, error) {
                                   print("Error loading complementary image: $url, Error: $error");
                                   return Image.asset(
                                    'assets/images/cover.png', // Fallback
                                    height: 75.0,
                                    width: 110.0,
                                    fit: BoxFit.cover);
                                }
                              ),
                              // --- VISUAL FEEDBACK: Checkmark Overlay ---
                              if (isSelected)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: kColorPrimary.withOpacity(0.85), // Semi-transparent background
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.check,
                                        color: Colors.white,
                                        size: 16),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded( // Allow text area to expand vertically
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space out text and icon
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(itemTitle,
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: kColorPrimaryDark,
                                        fontSize: 13),
                                    maxLines: 2, // Allow two lines for title
                                    overflow: TextOverflow.ellipsis),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end, // Align price and icon at bottom
                                  children: [
                                    // Display price only if > 0
                                    Text(itemPrice > 0 ? 'ugx ${itemPrice.toStringAsFixed(0)}' : '0.0',
                                        style: GoogleFonts.poppins(
                                            color: itemPrice > 0 ? kColorTextSecondary : kColorSuccess,
                                            fontSize: 12,
                                            fontWeight: itemPrice > 0 ? FontWeight.normal : FontWeight.w500,
                                            )),
                                    // --- VISUAL FEEDBACK: Add/Check Icon ---
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle // Check icon when selected
                                          : Icons.add_circle_outline, // Add icon otherwise
                                      color: isSelected
                                          ? kColorSuccess // Success color for check
                                          : kColorPrimary, // Primary color for add
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
        onTap: () {
           if(mounted) setState(() => _ingredientsExpanded = !_ingredientsExpanded);
        },
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
              AnimatedSize( // Add animation for smooth expansion
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Wrap(
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
              ),
              if (ingredients.length > 6) ...[
                SizedBox(height: 6),
                 // Animated rotation for expand icon
                 AnimatedRotation(
                    turns: _ingredientsExpanded ? 0.5 : 0,
                    duration: Duration(milliseconds: 300),
                    child: Center(
                        child: Icon(
                            Icons.expand_more, // Always use expand_more, rotation handles direction
                            color: kColorPrimary)),
                 )
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
                      Icons.track_changes_outlined, 'Health Goal', healthGoal), // Updated icon
                if (hasAllergens)
                  _buildPropertyChip(Icons.warning_amber_rounded, 'Allergens',
                      allergens.join(', ')),
                if (hasDiseases)
                  _buildPropertyChip(Icons.healing_outlined, 'Helps Manage', // Updated icon
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
          backgroundColor: kBottomSheetBgColor, // Use consistent BG color
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(title,
              style: GoogleFonts.poppins( // Use GoogleFonts
                  color: kColorPrimaryDark, // Use theme color
                  fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: content
                  .split(',')
                   // Filter out empty strings after splitting and trimming
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text('• $item', // Add bullet point
                            style: GoogleFonts.poppins( // Use GoogleFonts
                                color: kColorTextPrimary, // Use theme color
                                fontSize: 15)),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close',
                  style: GoogleFonts.poppins( // Use GoogleFonts
                      color: kColorPrimary, // Use theme color
                      fontWeight: FontWeight.bold)),
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
     if (prepTimeStr == null) return 0.3; // Default if null

    // Extract only digits
    final digitsOnly = prepTimeStr.replaceAll(RegExp(r'[^0-9]'), '');
    int prepMinutes = int.tryParse(digitsOnly) ?? 30; // Default to 30 if parsing fails

    const maxPrepTime = 90.0; // Assuming 90 minutes is the max prep time shown
    return (prepMinutes / maxPrepTime).clamp(0.0, 1.0);
  }

  // --- Skill Level & Prep Time Card ---
 Widget _buildSkillLevelAndPrepTimeCard() {
    // Use PascalCase keys
    final skillLevel = widget.meal['Skill_level']?.toString();
    final prepTime = widget.meal['Prep_time']?.toString();

    // Only show if at least one value is present and not empty
    final bool showSkill = skillLevel != null && skillLevel.isNotEmpty;
    final bool showPrepTime = prepTime != null && prepTime.isNotEmpty;

    if (!showSkill && !showPrepTime) return SizedBox.shrink();


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
            if (showSkill) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Skill Level:',
                      style: GoogleFonts.poppins(
                          color: kColorTextSecondary, fontSize: 14)),
                  Text(skillLevel!, // Can use ! because of showSkill check
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
              if (showPrepTime) SizedBox(height: 12), // Add spacing only if both are shown
            ],
            if (showPrepTime) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Prep Time:',
                      style: GoogleFonts.poppins(
                          color: kColorTextSecondary, fontSize: 14)),
                  Text(prepTime!, // Can use ! because of showPrepTime check
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
            ? chefs // Use the main `chefs` list from the parent state
            : chefs.where((chef) { // Filter the main list
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
            color: kBottomSheetBgColor, // Use consistent theme color
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
                  Row( // Use consistent Search/Refresh/Clear pattern
                    children: [
                      IconButton(
                        icon: Icon(Icons.search, color: kColorPrimary),
                        tooltip: 'Search Chefs',
                        onPressed: () {
                           showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: kBottomSheetBgColor, // Match background
                              title: Text('Search Chefs', style: GoogleFonts.poppins()),
                              content: StatefulBuilder( // Use StatefulBuilder for dialog suffix icon update
                                 builder: (BuildContext context, StateSetter setDialogState) {
                                    return TextField(
                                        controller: _chefSearchController,
                                        autofocus: true,
                                        decoration: InputDecoration(
                                          hintText: 'Search by name or location',
                                          prefixIcon: Icon(Icons.search, color: kColorPrimary),
                                          suffixIcon: _chefSearchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(Icons.clear, color: kColorError),
                                                tooltip: 'Clear search',
                                                onPressed: () {
                                                  _chefSearchController.clear();
                                                  setModalState(() => _chefSearchQuery = ''); // Update modal state
                                                  setDialogState(() {}); // Update dialog state
                                                },
                                              )
                                            : null,
                                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kColorPrimary)),
                                        ),
                                        onChanged: (value) {
                                          setModalState(() => _chefSearchQuery = value.toLowerCase()); // Update modal state
                                          setDialogState(() {}); // Update dialog state
                                        },
                                      );
                                 },
                              ),

                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Close', style: GoogleFonts.poppins(color: kColorPrimary, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_chefSearchQuery.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear, color: kColorError),
                          tooltip: 'Clear Search',
                          onPressed: () {
                            _chefSearchController.clear();
                            setModalState(() => _chefSearchQuery = '');
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: kColorPrimary),
                         tooltip: 'Refresh Chefs',
                        onPressed: () {
                          setModalState(() {
                            isLoadingChefs = true; // Show loading in modal
                            _chefSearchQuery = ''; // Clear search on refresh
                            _chefSearchController.clear();
                          });
                           // Call fetch and let parent state handle rebuild
                          fetchChefsWithRetry();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              if (_chefSearchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: Text(
                    'Results for: "${_chefSearchQuery}"',
                    style: GoogleFonts.poppins(
                        color: kColorTextSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ),
              Divider(color: kColorDivider, height: 1),
              Flexible(
                child: isLoadingChefs // Check parent's loading state
                    ? Center(
                        key: ValueKey('chef_loading'),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(color: kColorPrimary),
                        ))
                    : (filteredChefs.isEmpty
                        ? Center(
                            key: ValueKey('chef_empty'),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                  _chefSearchQuery.isEmpty
                                      ? "No chefs available."
                                      : "No chefs found matching '$_chefSearchQuery'",
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                      color: kColorTextSecondary)),
                            ))
                        : _buildChefListWithData( // Pass filtered data
                            filteredChefs)),
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
      key: ValueKey('chef_list_${chefsToDisplay.length}'), // Add key for better rebuilds
      itemCount: chefsToDisplay.length,
      padding: EdgeInsets.only(top: 8, bottom: 8), // Add padding
      shrinkWrap: true, // Important for Flexible parent
      itemBuilder: (context, index) {
        final chef = chefsToDisplay[index];
         // Defensive check: Ensure chef is a Map
        if (chef is! Map<String, dynamic>) {
            print("Warning: Invalid chef data at index $index: $chef");
            return SizedBox.shrink(); // Skip invalid item
        }

        final chefName = chef['name']?.toString() ?? 'Unknown Chef';
        final chefImage = _formatImageUrl(
            chef['image']?.toString() ?? 'assets/images/placeholderchef.jpeg');
        final chefRating = _parsePrice(chef['rating']); // Use safe parser
        final chefLocation = chef['location']?.toString() ?? 'Unknown Location';
        final chefId = chef['chefid']; // Assuming _mapChefData ensures this exists

         // Defensive check: Ensure chefId is not null
         if (chefId == null) {
            print("Warning: Chef data missing 'chefid': $chef");
            return SizedBox.shrink(); // Skip item without ID
        }

        final bool isSelected =
            selectedChef != null && selectedChef!['chefid'] == chefId;

        return Card(
          elevation: isSelected ? 3.0 : _cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonCornerRadius),
            side: BorderSide(
                color: isSelected ? kColorPrimary : kColorDivider,
                width: isSelected ? 1.5 : 0.8), // Adjusted thickness
          ),
          color: isSelected ? kColorPrimaryLight.withOpacity(0.2) : kColorSurface, // Highlight background slightly
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0), // Adjusted margin
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
                       key: ValueKey(chefImage), // Add key
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                          width: 50,
                          height: 50,
                          color: kColorDivider,
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
                                color: kColorPrimaryDark)), // Darker text
                        SizedBox(height: 3),
                        Row(
                            children: List.generate(
                                5,
                                (i) => Icon(
                                    i < chefRating.round()
                                        ? Icons.star_rounded // Use rounded star
                                        : Icons.star_border_rounded, // Use rounded border star
                                    color: Colors.amber[600], // Use Amber for stars
                                    size: 15))),
                        SizedBox(height: 4), // Increased spacing
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                color: kColorTextSecondary, size: 13), // Secondary color icon
                            SizedBox(width: 4),
                            Expanded(
                                child: Text(getShortLocation(chefLocation),
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: kColorTextSecondary), // Secondary color text
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
                          color: kColorSuccess, size: 28), // Use success color
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
            ? producers // Use the main `producers` list
            : producers.where((producer) { // Filter the main list
                final name = (producer['name']?.toString().toLowerCase() ?? '');
                final location =
                    (producer['Location']?.toString().toLowerCase() ?? ''); // Key is 'Location'
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
            color: kBottomSheetBgColor, // Use consistent theme color
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
                   Row( // Reuse search/refresh/clear pattern
                    children: [
                      IconButton(
                        icon: Icon(Icons.search, color: kColorPrimary),
                        tooltip: 'Search Producers',
                        onPressed: () {
                           showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: kBottomSheetBgColor, // Match background
                              title: Text('Search Producers', style: GoogleFonts.poppins()),
                              content: StatefulBuilder( // Use StatefulBuilder for dialog suffix icon update
                                builder: (BuildContext context, StateSetter setDialogState) {
                                  return TextField(
                                      controller: _producerSearchController, // Use correct controller
                                      autofocus: true,
                                      decoration: InputDecoration(
                                        hintText: 'Search by name or location',
                                        prefixIcon: Icon(Icons.search, color: kColorPrimary),
                                        suffixIcon: _producerSearchController.text.isNotEmpty
                                          ? IconButton(
                                              icon: Icon(Icons.clear, color: kColorError),
                                              tooltip: 'Clear search',
                                              onPressed: () {
                                                _producerSearchController.clear();
                                                setModalState(() => _producerSearchQuery = ''); // Update modal state
                                                setDialogState(() {}); // Update dialog state
                                              },
                                            )
                                          : null,
                                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kColorPrimary)),
                                      ),
                                      onChanged: (value) {
                                        setModalState(() => _producerSearchQuery = value.toLowerCase()); // Update modal state
                                        setDialogState(() {}); // Update dialog state
                                      },
                                    );
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                   child: Text('Close', style: GoogleFonts.poppins(color: kColorPrimary, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_producerSearchQuery.isNotEmpty) // Show clear button only when searching
                        IconButton(
                          icon: Icon(Icons.clear, color: kColorError),
                           tooltip: 'Clear Search',
                          onPressed: () {
                            _producerSearchController.clear();
                            setModalState(() => _producerSearchQuery = '');
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: kColorPrimary),
                         tooltip: 'Refresh Producers',
                        onPressed: () {
                          setModalState(() {
                            isLoadingProducers = true; // Use correct loading var
                            _producerSearchQuery = ''; // Clear search
                            _producerSearchController.clear();
                          });
                          fetchProducers(); // Call correct fetch function
                        },
                      ),
                    ],
                  ),
                ],
              ),
               if (_producerSearchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: Text(
                    'Results for: "${_producerSearchQuery}"',
                     style: GoogleFonts.poppins(
                        color: kColorTextSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ),
              Divider(color: kColorDivider, height: 1),
              Flexible(
                child: isLoadingProducers // Check parent's loading state
                    ? Center(
                        key: ValueKey('producer_loading'),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(color: kColorPrimary),
                        ))
                    : (filteredProducers.isEmpty
                        ? Center(
                            key: ValueKey('producer_empty'),
                             child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                _producerSearchQuery.isEmpty
                                    ? "No producers available."
                                    : "No producers found matching '$_producerSearchQuery'",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    color: kColorTextSecondary)),
                            ))
                        : _buildProducerListWithData( // Pass filtered data
                            filteredProducers)),
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
       key: ValueKey('producer_list_${producersToDisplay.length}'), // Add key
      itemCount: producersToDisplay.length,
      padding: EdgeInsets.only(top: 8, bottom: 8), // Add padding
      shrinkWrap: true, // Important for Flexible parent
      itemBuilder: (context, index) {
        final producer = producersToDisplay[index];
         // Defensive check: Ensure producer is a Map
        if (producer is! Map<String, dynamic>) {
            print("Warning: Invalid producer data at index $index: $producer");
            return SizedBox.shrink(); // Skip invalid item
        }

        final producerName = producer['name']?.toString() ?? 'Unknown Producer';
        final producerImage = _formatImageUrl(
            producer['image']?.toString() ?? 'assets/images/producerHolder.png');
        final producerLocation = producer['Location']?.toString() ?? 'NA'; // Key is 'Location'
        final producerRating = _parsePrice(producer['Rating']); // Key is 'Rating', use parser
        final producerId = producer['producer_id']; // Assuming fetchProducers ensures this

         // Defensive check: Ensure producerId is not null
        if (producerId == null) {
            print("Warning: Producer data missing 'producer_id': $producer");
            return SizedBox.shrink(); // Skip item without ID
        }

        final bool isSelected = selectedProducer != null &&
            selectedProducer!['producer_id'] == producerId;

        return Card(
          elevation: isSelected ? 3.0 : _cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonCornerRadius),
            side: BorderSide(
                color: isSelected ? kColorPrimary : kColorDivider,
                 width: isSelected ? 1.5 : 0.8), // Adjusted thickness
          ),
          color: isSelected ? kColorPrimaryLight.withOpacity(0.2) : kColorSurface, // Highlight background slightly
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0), // Adjusted margin
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
                       key: ValueKey(producerImage), // Add key
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                       placeholder: (context, url) => Container(
                          width: 50,
                          height: 50,
                          color: kColorDivider,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: kColorPrimary))),
                      errorWidget: (context, url, error) => Image.asset(
                          'assets/images/producerHolder.png', // Correct placeholder
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
                                color: kColorPrimaryDark)), // Darker text
                        SizedBox(height: 3),
                        Row(
                            children: List.generate(
                                5,
                                (i) => Icon(
                                    i < producerRating.round()
                                        ? Icons.star_rounded // Use rounded star
                                        : Icons.star_border_rounded, // Use rounded border star
                                    color: Colors.amber[600], // Use Amber for stars
                                    size: 15))),
                        SizedBox(height: 4), // Increased spacing
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                color: kColorTextSecondary, size: 13), // Secondary color icon
                            SizedBox(width: 4),
                            Expanded(
                                child: Text(getShortLocation(producerLocation),
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: kColorTextSecondary), // Secondary color text
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
                          color: kColorSuccess, size: 28), // Use success color
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
    // Only show if *something* is selected
    if (selectedChef == null && selectedProducer == null) {
      // Show a prompt if nothing is selected yet and not already in cart
       if (!isInCart) {
         return Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text("Please select 'Cooked' or 'Fresh' above to choose a provider.", style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 13)),
         );
       }
      return SizedBox.shrink(); // Hide if nothing selected or already in cart
    }

    final bool isChef = selectedChef != null;
    final data = isChef ? selectedChef! : selectedProducer!;

     // --- Safety Checks ---
    if (data == null || data is! Map<String, dynamic>) {
         print("Warning: Invalid selectedChef/selectedProducer data: $data");
         // Clear invalid selection
         if (mounted) {
             setState(() {
                 if (isChef) selectedChef = null; else selectedProducer = null;
             });
         }
         return SizedBox.shrink();
    }
    // --- End Safety Checks ---


    final name = data['name']?.toString() ?? 'Unknown';
    final image = _formatImageUrl(data['image']?.toString() ??
        (isChef
            ? 'assets/images/placeholderchef.jpeg'
            : 'assets/images/producerHolder.png'));
    // Use correct location key based on type
    final location = getShortLocation(data[isChef ? 'location' : 'Location']?.toString() ??
        'Unknown Location');
    // Use correct rating key and parse safely
    final rating = _parsePrice(data[isChef ? 'rating' : 'Rating']);
    final typeLabel = isChef ? 'Selected Chef' : 'Selected Producer';

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 4, vertical: 10), // Adjust margin slightly
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardCornerRadius), // Use consistent radius
        side: BorderSide(color: kColorPrimary.withOpacity(0.5), width: 1), // Use theme color border
      ),
      color: kBottomSheetBgColor, // Use consistent light background
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeLabel,
                style: GoogleFonts.poppins( // Use GoogleFonts
                    fontSize: 14,
                    color: kColorTextSecondary, // Use theme color
                    fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
            Row(
              children: [
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: image,
                    key: ValueKey(image), // Key for image
                    width: 45,
                    height: 45,
                    fit: BoxFit.cover,
                     placeholder: (context, url) => Container(
                        width: 45,
                        height: 45,
                        color: kColorDivider,
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kColorPrimary))),
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
                          style: GoogleFonts.poppins( // Use GoogleFonts
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kColorPrimaryDark)), // Use theme color
                      SizedBox(height: 2),
                      Row(
                          children: List.generate(
                              5,
                              (i) => Icon(
                                  i < rating.round()
                                      ? Icons.star_rounded // Rounded star
                                      : Icons.star_border_rounded, // Rounded border star
                                  color: i < rating.round()
                                      ? Colors.amber[600] // Use theme color (amber)
                                      : Colors.grey[400], // Lighter grey for empty
                                  size: 14))),
                      SizedBox(height: 3), // Adjust spacing
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, // Use outlined icon
                              color: kColorTextSecondary, size: 12), // Use theme color
                          SizedBox(width: 3),
                          Expanded(
                              child: Text(location,
                                  style: GoogleFonts.poppins( // Use GoogleFonts
                                      fontSize: 12, color: kColorTextSecondary), // Use theme color
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                 // Add a 'Change' button to reopen the respective sheet
                 TextButton(
                    onPressed: () {
                         if (isChef) {
                            showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                backgroundColor: kBottomSheetBgColor, // Consistent background
                                builder: (context) => _buildChefSelectionSheet(),
                            );
                         } else {
                            showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                backgroundColor: kBottomSheetBgColor, // Consistent background
                                builder: (context) => _buildProducerSelectionSheet(),
                            );
                         }
                    },
                    child: Text("Change", style: GoogleFonts.poppins(color: kColorPrimary, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size(0, 0), // Compact size
                         tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                 )
              ],
            ),
          ],
        ),
      ),
    );
  }

 // --- Bottom Proceed Button ---
 Widget _buildProceedToCartButton(BuildContext context) {
    // Use ValueListenableBuilder to react to cart changes for the count and enabled state
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ShoppingCart.itemsNotifier,
      builder: (context, cartItems, child) {
        int cartItemCount = cartItems.length;
        bool canProceed = cartItemCount > 0;

        return Container(
          padding: EdgeInsets.fromLTRB(
              _horizontalPadding, 10.0, _horizontalPadding, _verticalPadding + MediaQuery.of(context).padding.bottom * 0.5), // Adjust padding for safe area
          decoration: BoxDecoration(
            color: kColorSurface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  spreadRadius: 0,
                  blurRadius: 4,
                  offset: Offset(0, -1))
            ],
            border: Border(top: BorderSide(color: kColorDivider, width: 0.5)),
          ),
          child: ElevatedButton.icon(
            icon: Badge(
              label: Text('$cartItemCount', style: GoogleFonts.poppins(fontSize: 10, color: kColorPrimaryDark, fontWeight: FontWeight.bold)),
              isLabelVisible: canProceed,
              backgroundColor: kColorAccent,
              alignment: AlignmentDirectional(1.1, -0.9),
              child: Icon(Icons.shopping_cart_checkout_outlined),
            ),
            label: Text('Proceed to Cart', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            onPressed: canProceed
                ? () {
                     // Navigate to Cart Screen
                    Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ShoppingCartScreen()))
                         // Use _initializeData to refresh the state correctly when returning
                        .then((_) => _initializeData());
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canProceed ? kColorPrimaryDark : Colors.grey.shade400,
              foregroundColor: kColorSurface,
              padding: EdgeInsets.symmetric(vertical: 14),
              textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_buttonCornerRadius)),
              minimumSize: Size(double.infinity, 50),
              elevation: canProceed ? 2 : 0,
            ),
          ),
        );
      },
    );
  }

  // Add meal planning section widget
  Widget _buildMealPlanningSection() {
    return ExpansionTile(
      // Initially expanded? Maybe false by default.
       initiallyExpanded: _isBulkOrder, // Expand if bulk order is active from cart
      tilePadding: EdgeInsets.symmetric(horizontal: 8), // Reduce padding
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)), // Rounded shape
       collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)), // Rounded shape when collapsed
       backgroundColor: kColorSurface, // Match card background
       collapsedBackgroundColor: kColorSurface,
       iconColor: kColorPrimary,
       collapsedIconColor: kColorPrimary,
      title: Text(
        'Meal Planning (Optional)', // Clarify it's optional
        style: GoogleFonts.poppins(
          fontSize: 16, // Slightly smaller title
          fontWeight: FontWeight.w600,
           color: kColorPrimaryDark, // Use theme color
        ),
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                  'Schedule regular deliveries for this meal.',
                  style: GoogleFonts.poppins(fontSize: 13, color: kColorTextSecondary),
                ),
                 SizedBox(height: 12),
              // Date Range Selector
              ListTile(
                contentPadding: EdgeInsets.zero, // Remove extra padding
                title: Text(
                  'Plan Duration',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  _planStartDate == null
                      ? 'Tap to select start and end dates' // Clearer prompt
                      : '${DateFormat('EEE, MMM d').format(_planStartDate!)} - ${DateFormat('EEE, MMM d').format(_planEndDate ?? _planStartDate!)}', // More detailed format
                  style: GoogleFonts.poppins(fontSize: 12, color: _planStartDate != null ? kColorPrimary : kColorTextSecondary ), // Highlight selected dates
                ),
                trailing: Icon(Icons.calendar_today_outlined, color: kColorPrimary),
                onTap: () async {
                  final DateTimeRange? dateRange = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(Duration(days: 1)), // Allow today
                    lastDate: DateTime.now().add(Duration(days: 90)), // Extend range
                    initialDateRange: _planStartDate != null && _planEndDate != null
                        ? DateTimeRange(start: _planStartDate!, end: _planEndDate!)
                        : null,
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: kColorPrimary,
                            onPrimary: Colors.white,
                            surface: kColorSurface, // Use theme surface
                            onSurface: kColorTextPrimary, // Use theme text
                          ),
                           dialogBackgroundColor: kBottomSheetBgColor, // Match other backgrounds
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (dateRange != null && mounted) {
                    setState(() {
                      _planStartDate = dateRange.start;
                      // Ensure end date is at least the start date
                      _planEndDate = dateRange.end.isBefore(dateRange.start) ? dateRange.start : dateRange.end;
                       // Set bulk order flag ONLY if dates are selected
                       _isBulkOrder = (_planStartDate != null && _planEndDate != null);
                    });
                  }
                },
              ),
                Divider(height: 1, color: kColorDivider.withOpacity(0.5)),

              // Frequency Selection
              ListTile(
                 contentPadding: EdgeInsets.zero,
                title: Text(
                  'Delivery Frequency',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: DropdownButton<String>(
                  value: _selectedFrequency,
                  isExpanded: true,
                   underline: SizedBox.shrink(), // Remove default underline
                    icon: Icon(Icons.arrow_drop_down, color: kColorPrimary),
                  items: [
                    DropdownMenuItem(value: 'daily', child: Text('Every Day', style: GoogleFonts.poppins())),
                    DropdownMenuItem(
                        value: 'weekdays', child: Text('Weekdays Only (Mon-Fri)', style: GoogleFonts.poppins())),
                    DropdownMenuItem(
                        value: 'custom', child: Text('Select Specific Days...', style: GoogleFonts.poppins())),
                  ],
                  onChanged: (value) {
                    if (value != null && mounted) {
                      setState(() {
                        _selectedFrequency = value;
                        // Clear custom days if switching away from custom
                        if (value != 'custom') {
                          _selectedDays.clear();
                        }
                         // Also activate bulk order flag if frequency is changed and dates are set
                        _isBulkOrder = (_planStartDate != null && _planEndDate != null);
                      });
                    }
                  },
                ),
              ),

              // Custom Days Selection
              if (_selectedFrequency == 'custom')
                 AnimatedContainer( // Animate appearance
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                       // Using standard weekday constants
                      for (var dayEntry in {
                          DateTime.monday: 'Mon',
                          DateTime.tuesday: 'Tue',
                          DateTime.wednesday: 'Wed',
                          DateTime.thursday: 'Thu',
                          DateTime.friday: 'Fri',
                          DateTime.saturday: 'Sat',
                          DateTime.sunday: 'Sun',
                      }.entries)
                        FilterChip(
                          label: Text(
                            dayEntry.value,
                            style: GoogleFonts.poppins(
                              fontSize: 12, // Smaller font
                              color: _selectedDays.contains(dayEntry.value)
                                  ? Colors.white
                                  : kColorTextPrimary,
                            ),
                          ),
                          selected: _selectedDays.contains(dayEntry.value),
                          onSelected: (bool selected) {
                            if (mounted) {
                                setState(() {
                                    if (selected) {
                                        _selectedDays.add(dayEntry.value);
                                    } else {
                                        _selectedDays.remove(dayEntry.value);
                                    }
                                    // Also activate bulk order flag if days are selected and dates are set
                                    _isBulkOrder = (_planStartDate != null && _planEndDate != null);
                                });
                            }
                          },
                           backgroundColor: kColorDivider.withOpacity(0.5), // Lighter background
                          selectedColor: kColorPrimary,
                           checkmarkColor: Colors.white,
                           padding: EdgeInsets.symmetric(horizontal: 8), // Adjust padding
                           materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Tighter tap target
                           shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12), // More rounded
                                side: BorderSide(color: Colors.transparent) // No side border needed
                           ),
                        ),
                    ],
                  ),
                ),
               Divider(height: 1, color: kColorDivider.withOpacity(0.5)),

              // Quantity per day
              ListTile(
                 contentPadding: EdgeInsets.zero,
                title: Text(
                  'Quantity per delivery day',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                       icon: Icon(Icons.remove_circle_outline, color: _quantityPerDay > 1 ? kColorPrimary : Colors.grey), // Grey out if <= 1
                      tooltip: 'Decrease Quantity',
                      padding: EdgeInsets.zero,
                       constraints: BoxConstraints(),
                      onPressed: _quantityPerDay > 1 ? () {
                         if(mounted) setState(() => _quantityPerDay--);
                      } : null, // Disable if quantity is 1
                    ),
                    SizedBox(width: 8),
                    Text('$_quantityPerDay',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
                     SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline, color: kColorPrimary),
                      tooltip: 'Increase Quantity',
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                      onPressed: () {
                        if(mounted) setState(() => _quantityPerDay++);
                      },
                    ),
                  ],
                ),
              ),

              // Order Summary (Show only if dates are selected)
              if (_planStartDate != null && _planEndDate != null)
                Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Card(
                     color: kColorPrimaryLight.withOpacity(0.15), // Subtle background
                     elevation: 0, // No extra shadow
                     shape: RoundedRectangleBorder(
                         borderRadius: BorderRadius.circular(_buttonCornerRadius), // Use button radius
                         side: BorderSide(color: kColorPrimary.withOpacity(0.2)) // Subtle border
                     ),
                    child: Padding(
                      padding: EdgeInsets.all(12), // Reduced padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Plan Summary',
                              style: GoogleFonts.poppins(
                                fontSize: 15, // Slightly smaller
                                fontWeight: FontWeight.w600,
                                color: kColorPrimaryDark
                              )),
                          SizedBox(height: 8),
                          _buildSummaryRow(
                              'Total Delivery Days:', _calculateTotalDays()),
                          _buildSummaryRow(
                              'Total Meals:', _calculateTotalMeals()),
                          _buildSummaryRow('Estimated Total Cost:',
                              'ugx ${(_calculateTotalMeals() * _parsePrice(widget.meal['Price'])).toStringAsFixed(0)}'), // Use parsed price
                            SizedBox(height: 4),
                             Text(
                              '(Note: Complementary item & provider costs are extra)',
                              style: GoogleFonts.poppins(fontSize: 11, color: kColorTextSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Add to Cart for Bulk Order Button (conditional)
              // Show button only if a plan is defined AND chef/producer is selected
               if (_planStartDate != null && _planEndDate != null && _calculateTotalDays() > 0 && (selectedChef != null || selectedProducer != null))
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: ElevatedButton.icon(
                     icon: Icon(Icons.add_shopping_cart_outlined),
                     label: Text('Add Plan to Cart ($_calculateTotalMeals meals)'),
                     onPressed: () {
                        _addToCart(isBulk: true); // Call add to cart with bulk flag
                     },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kColorSuccess, // Use success color
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 45), // Make button full width
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_buttonCornerRadius)),
                      ),
                  ),
                )
               // Show warning if plan is set but provider isn't
               else if (_planStartDate != null && _planEndDate != null && _calculateTotalDays() > 0 && selectedChef == null && selectedProducer == null)
                 Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Text(
                     "Select 'Cooked' or 'Fresh' above to add the plan to cart.",
                     style: GoogleFonts.poppins(color: kColorError, fontSize: 13)
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
      padding: EdgeInsets.symmetric(vertical: 3), // Reduced vertical padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 13, // Slightly smaller
                color: kColorTextSecondary,
              )),
          Text(value.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14, // Slightly larger value
                fontWeight: FontWeight.w600,
                 color: kColorPrimaryDark, // Darker value text
              )),
        ],
      ),
    );
  }

 int _calculateTotalDays() {
    if (_planStartDate == null || _planEndDate == null) return 0;
    if (_planEndDate!.isBefore(_planStartDate!)) return 0; // Invalid range

    int days = 0;
    DateTime current = _planStartDate!;

    // Loop inclusive of the end date
    while (!current.isAfter(_planEndDate!)) {
      bool includeDay = false;
      final currentWeekday = current.weekday; // Get weekday (1=Mon, 7=Sun)
       // Map DateTime weekday to our 'Mon', 'Tue' strings
      final dayStringMap = {
           DateTime.monday: 'Mon',
           DateTime.tuesday: 'Tue',
           DateTime.wednesday: 'Wed',
           DateTime.thursday: 'Thu',
           DateTime.friday: 'Fri',
           DateTime.saturday: 'Sat',
           DateTime.sunday: 'Sun',
      };
      final currentDayString = dayStringMap[currentWeekday];

      switch (_selectedFrequency) {
        case 'daily':
          includeDay = true;
          break;
        case 'weekdays':
          // Weekday is 1 (Monday) to 5 (Friday)
          includeDay = currentWeekday >= DateTime.monday && currentWeekday <= DateTime.friday;
          break;
        case 'custom':
          // Check if the current day string ('Mon', 'Tue' etc.) is in the selected set
          includeDay = currentDayString != null && _selectedDays.contains(currentDayString);
          break;
      }

      if (includeDay) days++;
      current = current.add(Duration(days: 1));
    }

    return days;
  }

  int _calculateTotalMeals() {
     final totalDays = _calculateTotalDays();
     // Ensure quantity is at least 1 if days > 0
     return totalDays > 0 ? totalDays * (_quantityPerDay > 0 ? _quantityPerDay : 1) : 0;
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    _chefSearchController.dispose();
    _producerSearchController.dispose();
    super.dispose();
  }

  void _startRefreshAnimation() {
    if (mounted && !_refreshIconController.isAnimating) {
        _refreshIconController.repeat();
    }
  }

  void _stopRefreshAnimation() {
    if (mounted && _refreshIconController.isAnimating) {
       _refreshIconController.stop();
       _refreshIconController.reset();
    }
  }

  // --- UPDATED: _addToCart using _selectedComplementaries ---
  void _addToCart({bool isBulk = false}) {
    // Check if chef/producer is required and selected for non-bulk adds
     if (!isBulk && selectedChef == null && selectedProducer == null) {
       showCustomSnackBar(
          context, 'Please select a Chef (Cooked) or Producer (Fresh) first', isError: true); // Indicate error
      // Optionally shake the selection buttons or highlight them
      return;
    }
     // Check if bulk order details are valid if adding bulk
     if (isBulk && (_planStartDate == null || _planEndDate == null || _calculateTotalDays() <= 0)) {
        showCustomSnackBar(
          context, 'Please select valid dates and frequency for the meal plan', isError: true);
        return;
     }
      // Also check for provider selection when adding bulk
     if (isBulk && selectedChef == null && selectedProducer == null) {
       showCustomSnackBar(
          context, 'Please select a Chef or Producer before adding the plan', isError: true);
      return;
    }

    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal';
    final mainMealPrice = _parsePrice(widget.meal['Price']);
     // Use plan quantity if bulk, otherwise use current _quantityPerDay setting (ensuring it's at least 1)
    final int quantity = isBulk ? _calculateTotalMeals() : (_quantityPerDay > 0 ? _quantityPerDay : 1);

     // Ensure quantity is valid
     if (quantity <= 0) {
        showCustomSnackBar(context, 'Quantity must be at least 1', isError: true);
        return;
     }

    // Get selected complementaries data
    List<Map<String, dynamic>> currentlySelectedComplementaries = _getSelectedComplementariesData();

     // Calculate price PER UNIT (meal + complementaries)
    double complementaryTotalPrice = currentlySelectedComplementaries.fold(0, (sum, item) => sum + (item['price'] as double? ?? 0.0));
    double singleItemPriceWithComplementaries = mainMealPrice + complementaryTotalPrice;

    // --- Add to Cart using ShoppingCart class ---
    ShoppingCart.addItem(
      mealTitle,
      singleItemPriceWithComplementaries, // Price PER UNIT
      quantity: quantity,
      selectedchef: selectedChef, // Pass current selection
      selectedproducer: selectedProducer, // Pass current selection
      meal: widget.meal, // Pass full meal data
      bestservedwith: currentlySelectedComplementaries, // Pass the selected list
      // Add bulk order details if applicable
      isBulkOrder: isBulk,
      planStartDate: isBulk ? _planStartDate : null,
      planEndDate: isBulk ? _planEndDate : null,
      planFrequency: isBulk ? _selectedFrequency : null,
      planSelectedDays: isBulk ? _selectedDays : null,
    );

    // Update local state AFTER updating shared state
     if (mounted) {
        setState(() {
            isInCart = true;
            _isBulkOrder = isBulk; // Update bulk order status locally if added as bulk
            // Reset single quantity counter if adding as single item (optional)
            if (!isBulk) _quantityPerDay = 1;
        });
     }

    showCustomSnackBar(context, '${isBulk ? 'Meal plan' : mealTitle} added to cart successfully');
     // Optionally navigate to cart or provide stronger feedback
  }


 // These are now only used internally by the bottom sheets or potentially removed if unused elsewhere
 Widget _buildChefSearch() => SizedBox.shrink();
 Widget _buildProducerSearch() => SizedBox.shrink();
 Widget _buildChefList() => SizedBox.shrink(); // Replaced by _buildChefListWithData in modal
 Widget _buildProducerList() => SizedBox.shrink(); // Replaced by _buildProducerListWithData in modal
 // These are likely unused now
 Widget _buildChefProducerSelection() => SizedBox.shrink();
 Widget _buildComplementaryMeals() => SizedBox.shrink(); // Replaced by _buildBestServedWith

} // End _MealDetailScreenState

// --- Custom SnackBar Utility ---
// Updated to include an optional error style
void showCustomSnackBar(BuildContext context, String message, {bool isError = false}) {
  // Ensure context is still valid
   final navigator = Navigator.maybeOf(context);
   if (navigator == null || !navigator.mounted) return;


  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  if (scaffoldMessenger == null) {
    print("Warning: Could not find ScaffoldMessenger to show SnackBar.");
    return;
  }

  scaffoldMessenger.hideCurrentSnackBar(); // Hide previous snackbar immediately
  final snackBar = SnackBar(
    content: Text(message, style: GoogleFonts.poppins(color: isError ? Colors.white : _MealDetailScreenState.kColorPrimaryDark)),
    duration: Duration(seconds: isError ? 3 : 2), // Longer duration for errors
    behavior: SnackBarBehavior.floating,
     margin: EdgeInsets.fromLTRB(15, 5, 15, 10), // Adjust margins
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_MealDetailScreenState._buttonCornerRadius)), // Use theme radius
    backgroundColor: isError ? _MealDetailScreenState.kColorError : _MealDetailScreenState.kColorPrimaryLight, // Error or Light Teal
    action: SnackBarAction(
      label: 'OK',
      textColor: isError ? Colors.white : _MealDetailScreenState.kColorPrimaryDark, // Adjust text color
      onPressed: () {
        // Simply dismiss
         scaffoldMessenger.hideCurrentSnackBar();
      },
    ),
  );
  scaffoldMessenger.showSnackBar(snackBar);
}
