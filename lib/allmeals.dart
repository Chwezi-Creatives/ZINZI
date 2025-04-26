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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:zinzi2/user_cache.dart'; // Import UserCache
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

class AllMealsScreen extends StatefulWidget {
  const AllMealsScreen({super.key}); // Use super parameters

  // Public static cache loader for splash screen
  static Future<void> loadMealsCacheFromPrefs() =>
      _AllMealsScreenState.loadMealsCacheFromPrefs();

  @override
  _AllMealsScreenState createState() => _AllMealsScreenState();
}

class _AllMealsScreenState extends State<AllMealsScreen> {
  // --- Caching ---
  List<Map<String, dynamic>> _meals = [];
  static List<Map<String, dynamic>> _mealsCache = [];
  static DateTime? _mealsCacheTimestamp;

  static const String _mealsCacheKey = 'all_meals_cache';
  static const String _mealsCacheTimestampKey = 'all_meals_cache_timestamp';

  // Load cache from SharedPreferences (persistent storage)
  static Future<void> loadMealsCacheFromPrefs() async {
    final cachedData = await UserCache.getData(_mealsCacheKey);
    final timestampData = await UserCache.getData(_mealsCacheTimestampKey);

    if (cachedData != null && timestampData != null) {
      try {
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
  Timer? _debounce;
  // Use ValueNotifier for reactive state management of meals list
  final ValueNotifier<List<Map<String, dynamic>>> _filteredMealsNotifier =
      ValueNotifier([]);
  // Store all meals and lookup map internally
  List<Map<String, dynamic>> _allMeals = [];
  Map<String, Map<String, dynamic>> _mealMapByName = {};
  // Separate future for initial fetch state
  Future<void>? _initialFetchFuture; // Changed to Future<void>

  Map<String, dynamic> _userDetails = {};
  bool _isLoadingUserDetails = true;
  bool _isLoadingMeals = true; // Track meal loading state separately
  String _fetchError = ''; // Store fetch error message

  @override
  void initState() {
    super.initState();
    // Load persistent cache first (async)
    // Load persistent cache first (async)
    _initialFetchFuture = (() async {
      await AllMealsScreen.loadMealsCacheFromPrefs();

      // Always display cached data immediately if available
      if (_AllMealsScreenState._mealsCache.isNotEmpty) {
        _allMeals =
            List<Map<String, dynamic>>.from(_AllMealsScreenState._mealsCache);
        _buildMealLookupMap();
        _filterMeals('');
        if (mounted) {
          setState(() {
            _isLoadingMeals = false; // Assume not loading initially if cache is present
          });
        }
      } else {
         // If no cache, show loading shimmer initially
         if (mounted) {
            setState(() {
              _isLoadingMeals = true;
            });
         }
      }

      // Always fetch new data in the background
      // We don't await this fetch here so the UI can show cached data immediately
      _fetchMealsAndPreprocess();

      _searchController.addListener(_onSearchChanged);
      _fetchUserDetails();
    })();
  }

  Future<void> _fetchMealsAndPreprocess() async {
    // Do not set _isLoadingMeals to true here.
    // The loading state is managed by initState based on cache availability.
    _fetchError = ''; // Reset error on new fetch
    try {
      final meals = await _fetchMeals();
      if (mounted) {
        // Check if widget is still mounted
        _allMeals = meals;
        _AllMealsScreenState._mealsCache =
            List<Map<String, dynamic>>.from(meals); // Update cache
        _AllMealsScreenState._mealsCacheTimestamp = DateTime.now();
        // Persist cache using UserCache
        await UserCache.saveData(_mealsCacheKey, _AllMealsScreenState._mealsCache);
        await UserCache.saveData(_mealsCacheTimestampKey, _AllMealsScreenState._mealsCacheTimestamp!.toIso8601String());

        _buildMealLookupMap();
        _filterMeals(''); // Initialize filter with all meals and trigger UI update

        // If we were showing a loading indicator (because there was no cache), hide it now.
        if (_isLoadingMeals) {
           setState(() {
             _isLoadingMeals = false;
           });
        }
      }
    } catch (e) {
      if (mounted) {
        print('Error fetching new meals in background: $e');
        // If there was no cached data, show the error state.
        if (_allMeals.isEmpty) {
           setState(() {
             _isLoadingMeals = false;
             _fetchError = "Failed to load meals. Please try again.";
             _filteredMealsNotifier.value = []; // Clear meals on error
           });
        }
        // If cached data is present, just log the error and keep showing cached data.
      }
    }
  }

  void _buildMealLookupMap() {
    _mealMapByName = Map.fromEntries(
      _allMeals
          .where((m) => m['Meal_name'] != null) // Use PascalCase key
          .map((m) => MapEntry(m['Meal_name'].toString().toLowerCase(),
              m)), // Use PascalCase key
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMeals() async {
    // Keep _fetchMeals implementation as before, but ensure it throws
    // an exception on HTTP error or parsing failure for better handling.
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/rr/meals'))
          .timeout(const Duration(seconds: 15)); // Add timeout
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        // Expect structure like {"data": [...]}
        if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
          final dataList = decoded['data'];
          if (dataList is List) {
            // Ensure price is parsed correctly (assuming it might be int or double)
            return List<Map<String, dynamic>>.from(dataList.map((item) {
              final mapItem = Map<String, dynamic>.from(item);
              if (mapItem.containsKey('Price') && mapItem['Price'] is num) {
                // Keep price as num (int or double)
              } else {
                // Handle potential string price or missing price - default to 0.0
                mapItem['Price'] =
                    double.tryParse(mapItem['Price']?.toString() ?? '0.0') ??
                        0.0;
              }
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
      _filteredMealsNotifier.value = List.from(_allMeals);
    } else {
      _filteredMealsNotifier.value = _allMeals.where((meal) {
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
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _filteredMealsNotifier.dispose(); // Dispose the notifier
    super.dispose();
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMealsAndPreprocess,
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
            if (_isLoadingMeals && _allMeals.isEmpty) {
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
          hintText: 'Search meals, cuisines...',
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
                : "No meals available right now.",
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

  // Actual Meal Grid
  Widget _buildMealGrid(
      BuildContext context, List<Map<String, dynamic>> meals) {
    return GridView.builder(
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
        // Use PascalCase keys
        String title = meal['Meal_name'] ?? 'Unknown Meal';
        String imagePath =
            meal['Image_link'] ?? 'assets/images/mealimageplaceholder.jpg';
        String mealId = meal['Meal_id']?.toString() ?? 'unknown-$index';

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
    if (rawPath.contains('drive.google.com')) {
      try {
        String fileId = rawPath.split('/d/')[1].split('/')[0];
        return 'https://drive.google.com/uc?export=view&id=$fileId';
      } catch (e) {
        print("Error parsing GDrive link for $mealName: $rawPath");
        return 'assets/images/mealimageplaceholder.jpg'; // Fallback
      }
    } else if (rawPath.startsWith('http')) {
      return rawPath; // It's already a usable URL
    } else if (rawPath.startsWith('assets/')) {
      return rawPath; // Assume it's a valid asset path
    } else {
      // If it's not a recognized format, use placeholder
      print("Invalid or unrecognized image path for $mealName: $rawPath");
      return 'assets/images/mealimageplaceholder.jpg';
    }
  }

  // Helper function for navigation to detail page
  void _navigateToMealDetail(Map<String, dynamic> mealFromGrid) {
    // Find the full meal data from the original list to ensure all fields are present
    final fullMealData = _allMeals.firstWhere(
      (m) => m['Meal_id'] == mealFromGrid['Meal_id'], // Use PascalCase key
      orElse: () {
        print(
            "Warning: Could not find full meal data for ID ${mealFromGrid['Meal_id']}. Using potentially incomplete data from grid."); // Use PascalCase key
        return mealFromGrid; // Fallback to potentially incomplete data
      },
    );

    // --- Prepare complementary images ---
    List<String> complementaryDishNames = [];
    final dynamic complementaryDishesData =
        fullMealData['Complementary_dishes']; // Use PascalCase key

    if (complementaryDishesData is String) {
      complementaryDishNames = complementaryDishesData
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (complementaryDishesData is List) {
      complementaryDishNames = List<String>.from(complementaryDishesData
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty));
    }

    List<String> complementaryImageLinks = [];
    const String placeholderImage =
        'assets/images/cover.png'; // Define placeholder

    for (String dishName in complementaryDishNames) {
      // Find the complementary dish in the lookup map
      final complementaryMeal = _mealMapByName[dishName.toLowerCase()];
      String imageUrl = placeholderImage; // Default to placeholder

      // Use PascalCase key for image link lookup
      if (complementaryMeal != null &&
          complementaryMeal['Image_link'] != null) {
        imageUrl = _processImagePath(
            complementaryMeal['Image_link'], dishName); // Use PascalCase key
      } else {
        // Log if complementary meal or its image link wasn't found
        print(
            "Complementary dish '$dishName' or its image not found. Using placeholder.");
      }
      complementaryImageLinks.add(imageUrl);
    }

    // Create a mutable copy to add the processed images
    final Map<String, dynamic> mealToSend = Map.from(fullMealData);

    // Efficient complementary image extraction
    // Build a lookup map from meal name (lowercased) to image link for all main meals
    final Map<String, String> mealNameToImageLink = {
      for (final m in _allMeals)
        if ((m['Meal_name'] ?? '').toString().trim().isNotEmpty)
          m['Meal_name'].toString().toLowerCase():
              m['Image_link'] ?? 'assets/images/cover.png'
    };

    // For each complementary dish, get its image link from the map, else use placeholder
    final List<String> complementary_image_links =
        complementaryDishNames.map((dishName) {
      final key = dishName.toLowerCase();
      return mealNameToImageLink[key] ?? 'assets/images/cover.png';
    }).toList();

    mealToSend['complementary_images'] = complementary_image_links;

    // Navigate
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => meal_detail.MealDetailScreen(meal: mealToSend),
      ),
    );
  }
}