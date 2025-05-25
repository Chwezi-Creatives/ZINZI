// cspell:disable
import 'dart:convert';
import 'dart:async'; // For Timer
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/meal_detail.dart' as meal_detail;
import 'package:zinzi2/cart.dart' as cart;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts
import 'package:flutter/material.dart' show precacheImage, ScrollController, NetworkImage;
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/user_cache.dart'; // Import UserCache
import 'package:zinzi2/utils/image_utils.dart'; // Import ImageUtils
// Import CacheConfig

// --- Re-add Color Constants (or import from a shared file) ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Use this background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
// Add more if needed (e.g., shimmer colors)
final Color kShimmerBaseColor = Colors.grey.shade300;
final Color kShimmerHighlightColor = Colors.grey.shade100;
// --- End Color Constants ---

// Use environment variable for API base URL
final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url';

class OnlymealsScreen extends StatefulWidget {
  const OnlymealsScreen({super.key}); // Use super parameters

  // Public static cache loader for splash screen
  static Future<void> loadMealsCacheFromPrefs() =>
      _OnlymealsScreenState.loadMealsCacheFromPrefs();

  @override
  _OnlymealsScreenState createState() => _OnlymealsScreenState();
}

class _OnlymealsScreenState extends State<OnlymealsScreen>
    with SingleTickerProviderStateMixin {
  // --- Caching ---
  List<Map<String, dynamic>> _meals = [];
  static List<Map<String, dynamic>> _mealsCache = [];
  static DateTime? _mealsCacheTimestamp;

  static const String _mealsCacheKey = 'only_meals_cache';
  static const String _mealsCacheTimestampKey = 'only_meals_cache_timestamp';

  // Load cache from SharedPreferences (persistent storage)
  static Future<void> loadMealsCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_mealsCacheKey);
    final timestampData = await UserCache.getData(_mealsCacheTimestampKey);

    if (cachedData != null && timestampData != null) {
      try {
        print('[Onlymeals] Cache hit: Loaded meals from cache');
        _mealsCache = List<Map<String, dynamic>>.from(cachedData);
        _mealsCacheTimestamp = DateTime.parse(timestampData);
      } catch (_) {
        _mealsCache = [];
        _mealsCacheTimestamp = null;
      }
    } else {
      _mealsCache = [];
      _mealsCacheTimestamp = null;
    }
  }

  // Save cache to SharedPreferences
  static Future<void> saveMealsCacheToPrefs(
      List<Map<String, dynamic>> meals) async {
    await UserCache.saveData(_mealsCacheKey, meals);
    await UserCache.saveData(
        _mealsCacheTimestampKey, DateTime.now().toIso8601String());
  }

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  // Use ValueNotifier for reactive state management of meals list
  final ValueNotifier<List<Map<String, dynamic>>> _filteredMealsNotifier =
      ValueNotifier([]);
  // Store all meals and lookup map internally
  List<Map<String, dynamic>> _Onlymeals = [];
  Map<String, Map<String, dynamic>> _mealMapByName = {};
  // Separate future for initial fetch state
  Future<void>? _initialFetchFuture; // Changed to Future<void>

  Map<String, dynamic> _userDetails = {};
  bool _isLoadingUserDetails = true;
  bool _isLoadingMeals = true; // Track meal loading state separately
  String _fetchError = ''; // Store fetch error message

  late final AnimationController _refreshIconController;

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Set loading state immediately
    if (mounted) {
      setState(() {
        _isLoadingMeals = true;
      });
    }
    
    // Add scroll listener for image preloading
    _scrollController.addListener(_onScroll);

    // Start fresh data fetch
    _initialFetchFuture = (() async {
      // Start loading fresh data immediately
      await _fetchMealsAndPreprocess();
      
      // Set up search listener
      _searchController.addListener(_onSearchChanged);
      
      // Fetch user details in parallel
      _fetchUserDetails();
    })();
  }

  Future<void> _fetchMealsAndPreprocess() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.get('user_id'); // Get user_id, can be int or String

    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoadingMeals = false;
          _fetchError = "User not logged in. Cannot fetch personalized meals.";
          _filteredMealsNotifier.value = [];
        });
      }
      print("User ID not found in SharedPreferences.");
      return; // Exit if no user ID
    }

    int userIdInt;
    if (userId is int) {
      userIdInt = userId;
    } else if (userId is String) {
      userIdInt = int.tryParse(userId) ??
          -1; // Attempt to parse, use -1 or handle error
      if (userIdInt == -1) {
        if (mounted) {
          setState(() {
            _isLoadingMeals = false;
            _fetchError =
                "Invalid user ID format. Cannot fetch personalized meals.";
            _filteredMealsNotifier.value = [];
          });
        }
        print("Invalid user ID format in SharedPreferences: $userId");
        return; // Exit if user ID is invalid string
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingMeals = false;
          _fetchError =
              "Unexpected user ID type. Cannot fetch personalized meals.";
          _filteredMealsNotifier.value = [];
        });
      }
      print(
          "Unexpected user ID type in SharedPreferences: ${userId.runtimeType}");
      return; // Exit if user ID is unexpected type
    }

    try {
      final meals = await _fetchMeals(userIdInt);
      if (!mounted) return;
      
      // Update the local state with fresh data
      _Onlymeals = meals;
      
      // Update cache in background
      _updateCache(meals);
      
      // Update UI
      _buildMealLookupMap();
      _filterMeals('');
      
      setState(() {
        _isLoadingMeals = false;
      });
      
    } catch (e) {
      print('Error fetching meals: $e');
      if (!mounted) return;
      
      // Try to load from cache if available
      await _loadFromCacheIfAvailable();
      
      setState(() {
        _isLoadingMeals = false;
        if (_Onlymeals.isEmpty) {
          _fetchError = "Failed to load meals. Please check your connection and try again.";
        }
      });
    }
  }

  void _buildMealLookupMap() {
    _mealMapByName = Map.fromEntries(
      _Onlymeals.where((m) => m['meal_name'] != null) // Use lowercase key
          .map((m) => MapEntry(m['meal_name'].toString().toLowerCase(),
              m)), // Use lowercase key
    );
  }

  // Helper method to update cache
  Future<void> _updateCache(List<Map<String, dynamic>> meals) async {
    _OnlymealsScreenState._mealsCache = List<Map<String, dynamic>>.from(meals);
    _OnlymealsScreenState._mealsCacheTimestamp = DateTime.now();
    
    // Persist to UserCache
    await UserCache.saveData(_mealsCacheKey, _OnlymealsScreenState._mealsCache);
    await UserCache.saveData(
      _mealsCacheTimestampKey,
      _OnlymealsScreenState._mealsCacheTimestamp!.toIso8601String(),
    );
  }
  
  // Helper method to load from cache if available
  Future<void> _loadFromCacheIfAvailable() async {
    await OnlymealsScreen.loadMealsCacheFromPrefs();
    
    if (_OnlymealsScreenState._mealsCache.isNotEmpty) {
      _Onlymeals = List<Map<String, dynamic>>.from(_OnlymealsScreenState._mealsCache);
      _buildMealLookupMap();
      _filterMeals('');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMeals(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/rr/meals2/$userId'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        // Expect structure like {"recommended_meals": [...]}
        if (decoded is Map<String, dynamic> && decoded.containsKey('recommended_meals')) {
          final dataList = decoded['recommended_meals']; // Get the array directly
          if (dataList is List) {
            // Convert each meal item to Map<String, dynamic> and ensure price field
            return List<Map<String, dynamic>>.from(dataList.map((item) {
              final mapItem = Map<String, dynamic>.from(item);
              
              // Handle price field - check both 'price' and 'Price' for compatibility
              dynamic priceValue;
              if (mapItem.containsKey('price')) {
                priceValue = mapItem['price'];
              } else if (mapItem.containsKey('Price')) {
                priceValue = mapItem['Price'];
              }
              
              // Ensure price is properly formatted as a number
              if (priceValue is num) {
                // Keep as num (int or double)
                mapItem['price'] = priceValue;
              } else if (priceValue != null) {
                // Try to parse string to number
                mapItem['price'] = double.tryParse(priceValue.toString()) ?? 0.0;
              } else {
                // Default to 0.0 if price is missing or null
                mapItem['price'] = 0.0;
              }
              
              // For backward compatibility, also keep the capitalized version
              mapItem['Price'] = mapItem['price'];
              
              return mapItem;
            }));
          }
        }
        print('Unexpected JSON format for meals: $decoded');
        throw Exception(
            'Unexpected response format from server.'); // Throw specific error
      } else {
        print('Error fetching meals: ${response.statusCode}');
        throw Exception(
            'Failed to load meals (Status Code: ${response.statusCode})'); // Throw specific error
      }
    } on TimeoutException {
      print('Error fetching meals: Request timed out.');
      throw Exception(
          'Could not connect to server. Please check your connection.');
    } catch (e) {
      print('Error fetching meals: $e');
      // Re-throw the caught exception or a generic one
      throw Exception('An error occurred while fetching meals: $e');
    }
  }

  Future<void> _fetchUserDetails() async {
    // Keep implementation as before, ensure setState is used correctly
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) {
      setState(() => _isLoadingUserDetails = false);
      print("No user ID found in SharedPreferences.");
      return;
    }
    final url =
        '$apiBaseUrl/rr/rusers/$userId'; // Use path parameter if API supports it
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Content-Type': 'application/json'
      }).timeout(const Duration(seconds: 10));

      if (mounted) {
        // Check mounted before setState
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          // Assuming the API for single user returns a map under 'data' or directly a map
          Map<String, dynamic>? userDetailsMap;
          if (responseData is Map<String, dynamic>) {
            if (responseData.containsKey('data') &&
                responseData['data'] is Map) {
              userDetailsMap = Map<String, dynamic>.from(responseData['data']);
            } else if (!responseData.containsKey('message')) {
              // If it's the user map directly
              userDetailsMap = Map<String, dynamic>.from(responseData);
            }
          }

          if (userDetailsMap != null) {
            setState(() {
              _userDetails = userDetailsMap!;
              _isLoadingUserDetails = false;
            });
          } else {
            print("User details format unexpected or empty: $responseData");
            setState(() => _isLoadingUserDetails = false);
          }
        } else {
          print(
              "Error fetching user details: ${response.statusCode} - ${response.reasonPhrase}");
          setState(() => _isLoadingUserDetails = false);
        }
      }
    } on TimeoutException {
      print("Timeout fetching user details for ID: $userId");
      if (mounted) setState(() => _isLoadingUserDetails = false);
    } catch (error) {
      print("Error fetching user details for ID $userId: $error");
      if (mounted) setState(() => _isLoadingUserDetails = false);
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // Shorter debounce
      _filterMeals(_searchController.text);
    });
  }

  void _filterMeals(String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) {
      _filteredMealsNotifier.value = List.from(_Onlymeals);
    } else {
      _filteredMealsNotifier.value = _Onlymeals.where((meal) {
        // Use PascalCase keys for filtering
        final mealName = meal['Meal_name']?.toString().toLowerCase() ?? '';
        final cuisine =
            meal['Cuisine_preferences']?.toString().toLowerCase() ?? '';
        final dietPreference =
            meal['Dietary_preference']?.toString().toLowerCase() ?? '';
        // Add ingredients search if available and desired
        // final ingredients = meal['ingredients']?.toString().toLowerCase() ?? '';
        return mealName.contains(cleanQuery) ||
            cuisine.contains(cleanQuery) ||
            dietPreference
                .contains(cleanQuery); // || ingredients.contains(cleanQuery);
      }).toList();
    }
    // No need for setState here as ValueNotifier handles rebuilds via ValueListenableBuilder
  }

  void _clearSearch() {
    _searchController.clear();
    // Filtering is handled by the listener reacting to the empty text
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _filteredMealsNotifier.dispose(); // Dispose the notifier
    _scrollController.dispose(); // Dispose the scroll controller
    super.dispose();
  }

  void _startRefreshAnimation() {
    _refreshIconController.repeat();
  }

  void _stopRefreshAnimation() {
    _refreshIconController.stop();
    _refreshIconController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground, // Use clean background color
      appBar: AppBar(
        title: _buildSearchField(), // Use helper for search field
        backgroundColor: kColorPrimaryDark, // Consistent dark teal
        foregroundColor: kColorTextOnPrimary, // White icons/text
        elevation: 1.0, // Subtle elevation
        iconTheme: const IconThemeData(
            color: kColorTextOnPrimary), // Explicit drawer icon color
        actions: [
          AnimatedBuilder(
            animation: _refreshIconController,
            builder: (context, child) {
              return IconButton(
                icon: Transform.rotate(
                  angle: _isLoadingMeals
                      ? _refreshIconController.value * 6.3
                      : 0, // 2pi radians
                  child: const Icon(Icons.refresh),
                ),
                tooltip: _isLoadingMeals ? 'Refreshing...' : 'Refresh',
                onPressed: _isLoadingMeals
                    ? null
                    : () {
                        _startRefreshAnimation();
                        _fetchMealsAndPreprocess()
                            .whenComplete(_stopRefreshAnimation);
                      },
              );
            },
          ),
          IconButton(
            tooltip: "Shopping Cart",
            icon: const Icon(Icons.shopping_cart_outlined), // Outlined icon
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => cart.ShoppingCartScreen()),
              );
            },
          ),
        ],
      ),
      // Replace with the standardized AppDrawer
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        // Add pull-to-refresh
        onRefresh: _fetchMealsAndPreprocess,
        color: kColorPrimary, // Indicator color
        child: FutureBuilder<void>(
          future: _initialFetchFuture,
          builder: (context, snapshot) {
            if (_isLoadingMeals && _Onlymeals.isEmpty) {
              // Show shimmer only on initial load
              return _buildLoadingShimmerGrid();
            }
            if (snapshot.connectionState == ConnectionState.done &&
                _fetchError.isNotEmpty) {
              // Show error state if fetch completed with an error
              return _buildErrorState(_fetchError);
            }
            // Use ValueListenableBuilder to reactively build the grid
            return ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _filteredMealsNotifier,
              builder: (context, filteredMeals, _) {
                if (!_isLoadingMeals && filteredMeals.isEmpty) {
                  // Show empty state if not loading and filtered list is empty
                  return _buildEmptyState(
                      isSearching: _searchController.text.isNotEmpty);
                }
                // Build the grid with current filtered meals
                return _buildMealGrid(context, filteredMeals);
              },
            );
          },
        ),
      ),
    );
  }

  // Helper for AppBar Search Field
  Widget _buildSearchField() {
    return SizedBox(
      height: 40, // Maintain height
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
            color: kColorTextOnPrimary, fontSize: 15), // White text
        cursorColor: kColorPrimaryLight, // Teal cursor
        decoration: InputDecoration(
          hintText: 'Recommended meals..',
          hintStyle: TextStyle(color: kColorTextOnPrimary.withOpacity(0.7)),
          prefixIcon:
              const Icon(Icons.search, color: kColorTextOnPrimary, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: kColorTextOnPrimary, size: 20),
                  onPressed: _clearSearch,
                  tooltip: "Clear search",
                )
              : null,
          filled: true,
          fillColor: kColorTextOnPrimary.withOpacity(0.15), // Subtle background
          contentPadding: const EdgeInsets.symmetric(
              vertical: 0, horizontal: 15), // Adjust padding
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none, // No border
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(
                color: kColorPrimaryLight,
                width: 1.5), // Highlight border on focus
          ),
        ),
      ),
    );
  }

  // Loading Shimmer Grid
  Widget _buildLoadingShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: kShimmerBaseColor,
      highlightColor: kShimmerHighlightColor,
      child: GridView.builder(
        padding: const EdgeInsets.all(8.0), // Consistent padding
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10.0, // Slightly more spacing
          mainAxisSpacing: 10.0,
          childAspectRatio: 0.85, // Adjust ratio for shimmer card
        ),
        itemCount: 8, // Show a fixed number of shimmer placeholders
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white, // Placeholder background
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  // Empty State Widget
  Widget _buildEmptyState({required bool isSearching}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.no_food_outlined,
            size: 60,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            isSearching
                ? "No meals found matching your search."
                : "No recommendations available right now.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          if (!isSearching) // Add refresh suggestion if not searching
            Text(
              "Pull down to refresh.",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  // Error State Widget
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.red.shade700),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
              onPressed: _fetchMealsAndPreprocess,
              style: ElevatedButton.styleFrom(
                foregroundColor: kColorTextOnPrimary,
                backgroundColor: kColorPrimary, // Text color
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Handle scroll events for image preloading
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final threshold = 0.7; // Start preloading when 70% scrolled
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    if (maxScroll == 0.0) return; // List not yet laid out
    
    if (currentScroll >= (maxScroll * threshold)) {
      _preloadImages();
    }
  }

  // Preload images that are about to be visible
  void _preloadImages() {
    if (!_scrollController.hasClients || _filteredMealsNotifier.value.isEmpty) return;
    
    // Calculate visible items based on scroll position
    final firstVisibleIndex = (_scrollController.position.pixels / 200).floor();
    final lastVisibleIndex = ((_scrollController.position.pixels + 
        _scrollController.position.viewportDimension) / 200).ceil();
    
    // Preload images for items that are about to be visible (current + next 5)
    for (int i = firstVisibleIndex; i <= lastVisibleIndex + 5; i++) {
      if (i >= 0 && i < _filteredMealsNotifier.value.length) {
        final meal = _filteredMealsNotifier.value[i];
        String imagePath = meal['image_link'] ?? '';
        if (imagePath.isNotEmpty && imagePath.startsWith('http')) {
          // Trigger image pre-caching
          precacheImage(NetworkImage(imagePath), context);
        }
      }
    }
  }

  // Preload initial set of images
  void _preloadInitialImages() {
    if (_filteredMealsNotifier.value.isEmpty) return;
    
    // Preload first 10 images or all if less than 10
    final count = _filteredMealsNotifier.value.length > 10 ? 10 : _filteredMealsNotifier.value.length;
    
    for (int i = 0; i < count; i++) {
      final meal = _filteredMealsNotifier.value[i];
      String imagePath = meal['image_link'] ?? '';
      if (imagePath.isNotEmpty && imagePath.startsWith('http')) {
        precacheImage(NetworkImage(imagePath), context);
      }
    }
  }

  // Actual Meal Grid
  Widget _buildMealGrid(
      BuildContext context, List<Map<String, dynamic>> meals) {
    // Initial preload of first few images
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadInitialImages();
    });
    
    return GridView.builder(
      controller: _scrollController, // Add scroll controller
      padding: const EdgeInsets.all(8.0), // Adjusted padding
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // Keep 2 columns for mobile
        crossAxisSpacing: 10.0, // Increased spacing
        mainAxisSpacing: 10.0, // Increased spacing
        childAspectRatio: 0.85, // Adjusted aspect ratio
      ),
      itemCount: meals.length,
      itemBuilder: (context, index) {
        final meal = meals[index];
        // Use lowercase keys to match API response
        String title = meal['meal_name'] ?? 'Unknown Meal';
        String imagePath =
            meal['image_link'] ?? 'assets/images/mealimageplaceholder.jpg';
        String mealId = meal['meal_id']?.toString() ?? 'unknown-$index';

        // Use helper to process image path (Handles GDrive, HTTP, Assets, Placeholders)
        String displayImagePath = _processImagePath(imagePath, title);

        return GestureDetector(
          // Use GestureDetector for tap without ink splash
          onTap: () => _navigateToMealDetail(meal), // Use helper for navigation
          child: Hero(
            tag: 'meal-$mealId',
            flightShuttleBuilder: (flightContext, animation, flightDirection,
                fromHeroContext, toHeroContext) {
              // Use a scale+fade transition for extra polish
              return ScaleTransition(
                scale: animation.drive(Tween<double>(begin: 0.95, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeInOut))),
                child: FadeTransition(
                  opacity: animation,
                  child: toHeroContext.widget,
                ),
              );
            },
            child: _buildMealItem(title, displayImagePath),
          ),
        );
      },
    );
  }

  // Refined Meal Item Widget
  Widget _buildMealItem(String title, String imagePath) {
    Widget imageWidget;
    if (imagePath.startsWith('http')) {
      imageWidget = CachedNetworkImage(
        imageUrl: imagePath,
        fit: BoxFit.cover,
        placeholder: (context, url) => Shimmer.fromColors(
          baseColor: kShimmerBaseColor,
          highlightColor: kShimmerHighlightColor,
          child: Container(color: kColorSurface),
        ),
        errorWidget: (context, url, error) => Image.asset(
          'assets/images/mealimageplaceholder.jpg',
          fit: BoxFit.cover,
        ),
      );
    } else {
      // Assume asset path or placeholder path
      imageWidget = Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/mealimageplaceholder.jpg',
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: kColorSurface, // White background for the item
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          // Subtle shadow for depth
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        // Optional: Add subtle border
        // border: Border.all(color: kColorBorder.withOpacity(0.5), width: 0.5),
      ),
      child: ClipRRect(
        // Clip image and overlay to rounded corners
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Image takes full space
            Positioned.fill(child: imageWidget),
            // Gradient overlay at the bottom for text
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6), // Adjusted padding
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    // Use Google Fonts
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600, // Slightly bolder
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to process image paths (GDrive, HTTP, Asset, Placeholder)
  String _processImagePath(String rawPath, String mealName) {
    if (rawPath.startsWith('http')) {
      // Process HTTP/HTTPS URLs, especially Google Drive links
      return ImageUtils.processImageUrl(rawPath);
    } else if (rawPath.startsWith('assets/')) {
      return rawPath; // It's a valid asset path
    } else {
      // If it's not a recognized format, use placeholder
      print("Invalid or unrecognized image path for $mealName: $rawPath");
      return 'assets/images/mealimageplaceholder.jpg';
    }
  }

  // Helper function for navigation to detail page
  void _navigateToMealDetail(Map<String, dynamic> mealFromGrid) {
    try {
      // Create a deep copy of the meal data to avoid modifying the original
      final Map<String, dynamic> mealToSend = Map<String, dynamic>.from(mealFromGrid);
      
      // Ensure consistent key casing (PascalCase)
      final Map<String, dynamic> normalizedMeal = {};
      mealToSend.forEach((key, value) {
        // Convert first letter to uppercase for consistency
        final normalizedKey = key.isNotEmpty 
            ? key[0].toUpperCase() + key.substring(1)
            : key;
        normalizedMeal[normalizedKey] = value;
      });

      // Ensure all required fields have values
      normalizedMeal['Meal_name'] = normalizedMeal['Meal_name'] ?? 'Unknown Meal';
      normalizedMeal['Image_link'] = normalizedMeal['Image_link'] ?? 'assets/images/mealimageplaceholder.jpg';
      normalizedMeal['Description'] = normalizedMeal['Description'] ?? 'No description available';
      
      // Handle price field
      if (normalizedMeal['price'] == null && normalizedMeal['Price'] != null) {
        normalizedMeal['price'] = normalizedMeal['Price'];
      }
      normalizedMeal['price'] = double.tryParse(normalizedMeal['price']?.toString() ?? '0') ?? 0.0;
      normalizedMeal['Price'] = normalizedMeal['price']; // Ensure both cases are set

      // Remove all complementary dishes related data
      normalizedMeal.remove('Complementary_dishes');
      normalizedMeal.remove('complementary_images');
      normalizedMeal.remove('complementary_dishes');
      normalizedMeal.remove('best_served_with');
      
      // Debug log the meal data being passed
      debugPrint('=== NAVIGATING TO MEAL DETAIL ===');
      debugPrint('Meal ID: ${normalizedMeal['Meal_id']}');
      debugPrint('Meal Name: ${normalizedMeal['Meal_name']}');
      debugPrint('All Meal Data: $normalizedMeal');
      debugPrint('===============================');

      // Navigate to the meal detail screen with the complete meal data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => meal_detail.MealDetailScreen(meal: normalizedMeal),
        ),
      ).then((_) {
        debugPrint('=== RETURNED FROM MEAL DETAIL ===');
      });
    } catch (e) {
      print('Error navigating to meal detail: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading meal details. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
