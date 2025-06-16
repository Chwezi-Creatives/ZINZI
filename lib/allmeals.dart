//cspell:disable
// cspell:disable
import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image/cached_network_image.dart' as cn;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:zinzi/onlymeals.dart';
import 'package:zinzi/app_drawer_unified.dart';
import 'package:zinzi/meal_detail.dart' as meal_detail;
import 'package:zinzi/user_cache.dart';
import 'package:zinzi/utils/image_utils.dart';
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

  /// Preload meals data if cache is invalid
  /// Returns true if new data was loaded, false if using cache
  static Future<bool> preloadMealsIfNeeded() =>
      _AllMealsScreenState.preloadMealsIfNeeded();

  @override
  _AllMealsScreenState createState() => _AllMealsScreenState();
}

class _AllMealsScreenState extends State<AllMealsScreen>
    with SingleTickerProviderStateMixin {
  // --- Caching ---
  static List<Map<String, dynamic>> _mealsCache = [];
  static DateTime? _mealsCacheTimestamp;

  static const String _mealsCacheKey = 'all_meals_cache';
  static const String _mealsCacheTimestampKey = 'all_meals_cache_timestamp';

  /// Load cache from SharedPreferences (persistent storage)
  /// Returns true if cache was loaded successfully
  static Future<bool> loadMealsCacheFromPrefs() async {
    try {
      final cachedData = await UserCache.getData(_mealsCacheKey);
      final timestampData = await UserCache.getData(_mealsCacheTimestampKey);

      if (cachedData != null && timestampData != null) {
        _mealsCache = List<Map<String, dynamic>>.from(cachedData);
        _mealsCacheTimestamp = DateTime.parse(timestampData);
        print('[AllMeals] Cache loaded with ${_mealsCache.length} items');
        return _mealsCache.isNotEmpty;
      }
    } catch (e) {
      print('[AllMeals] Error loading cache: $e');
    }
    _mealsCache = [];
    _mealsCacheTimestamp = null;
    return false;
  }

  /// Check if the cache is invalid (either empty or too old)
  static bool get isCacheInvalid {
    if (_mealsCache.isEmpty) return true;
    if (_mealsCacheTimestamp == null) return true;

    // Consider cache invalid if older than 1 day
    final cacheAge = DateTime.now().difference(_mealsCacheTimestamp!);
    return cacheAge.inDays >= 1;
  }

  /// Preload meals data if cache is invalid
  /// Returns true if new data was loaded, false if using cache
  static Future<bool> preloadMealsIfNeeded() async {
    try {
      // First try to load existing cache
      final hasCache = await loadMealsCacheFromPrefs();

      // If cache is valid, no need to refresh
      if (hasCache && !isCacheInvalid) {
        print('[AllMeals] Using valid cache');
        return false;
      }

      print('[AllMeals] Cache invalid or empty, fetching fresh data...');

      // Fetch fresh data
      final instance = _AllMealsScreenState();
      final meals = await instance._fetchMeals();

      // Update cache
      _mealsCache = List<Map<String, dynamic>>.from(meals);
      _mealsCacheTimestamp = DateTime.now();

      // Save to persistent storage
      await UserCache.saveData(_mealsCacheKey, _mealsCache);
      await UserCache.saveData(
          _mealsCacheTimestampKey, _mealsCacheTimestamp!.toIso8601String());

      print('[AllMeals] Successfully preloaded ${meals.length} meals');
      return true;
    } catch (e) {
      print('[AllMeals] Error preloading meals: $e');
      return false; // Return false to indicate we're using existing cache
    }
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

  bool _isLoadingMeals = true; // Track meal loading state separately
  String _fetchError = ''; // Store fetch error message

  late final AnimationController _refreshIconController;
  final ScrollController _scrollController = ScrollController();
  final int _preloadThreshold =
      25; // Number of items before the end to start preloading
  bool _isPreloadingEnabled =
      true; // Always enable preloading regardless of connection type

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Initialize scroll controller and add listener
    _scrollController.addListener(_onScroll);

    // Preloading is always enabled now

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
            _isLoadingMeals = false; // Show cached data immediately
          });
        }

        // Only fetch new data if cache is invalid
        if (_AllMealsScreenState.isCacheInvalid) {
          _fetchMealsAndPreprocess();
        }
      } else {
        // If no cache, show loading shimmer and fetch data
        if (mounted) {
          setState(() {
            _isLoadingMeals = true;
          });
        }
        _fetchMealsAndPreprocess();
      }

      _searchController.addListener(_onSearchChanged);
    })();
  }

  /// Force refresh meals data, invalidating cache
  Future<void> _forceRefreshMeals() async {
    if (_isLoadingMeals) {
      print('[AllMeals] Refresh already in progress, skipping duplicate request');
      return; // Prevent multiple simultaneous refreshes
    }

    print('[AllMeals] Starting forced refresh of meals data...');
    
    // Store current data to restore if fetch fails
    final List<Map<String, dynamic>> currentMeals = List.from(_allMeals);
    
    // Show refresh indicator in app bar
    _startRefreshAnimation();
    
    // Show a snackbar to indicate refresh is happening
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refreshing meals...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
        ),
      );
    }

    try {
      setState(() {
        _isLoadingMeals = true;
        _fetchError = '';
      });
      
      final meals = await _fetchMeals();

      if (mounted) {
        // Only update if we got new data
        if (meals.isNotEmpty) {
          _allMeals = meals;
          _AllMealsScreenState._mealsCache = List<Map<String, dynamic>>.from(meals);
          _AllMealsScreenState._mealsCacheTimestamp = DateTime.now();

          // Persist updated cache
          await UserCache.saveData(
              _mealsCacheKey, _AllMealsScreenState._mealsCache);
          await UserCache.saveData(_mealsCacheTimestampKey,
              _AllMealsScreenState._mealsCacheTimestamp!.toIso8601String());

          _buildMealLookupMap();
          _filterMeals(_searchController.text);
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Meals updated'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
              ),
            );
          }
        }
        
        if (mounted) {
          setState(() {
            _isLoadingMeals = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        print('Error during force refresh: $e');
        
        // Restore previous data
        if (currentMeals.isNotEmpty) {
          _allMeals = currentMeals;
          _buildMealLookupMap();
          _filterMeals(_searchController.text);
        }
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh. Using last loaded data.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
          ),
        );
        
        setState(() {
          _isLoadingMeals = false;
          _fetchError = currentMeals.isEmpty 
              ? 'Failed to load meals. Please check your connection.'
              : 'Failed to refresh. Using cached data.';
        });
      }
    } finally {
      if (mounted) {
        _stopRefreshAnimation();
      }
    }
  }

  Future<void> _fetchMealsAndPreprocess() async {
    // Don't fetch if already loading
    if (_isLoadingMeals) return;
    
    // Check if we have valid cache (less than 24 hours old)
    final bool hasValidCache = _AllMealsScreenState._mealsCache.isNotEmpty && 
                              _AllMealsScreenState._mealsCacheTimestamp != null &&
                              DateTime.now().difference(_AllMealsScreenState._mealsCacheTimestamp!).inHours < 24;
    
    // If we have no data at all, we need to show loading
    final bool hasNoData = _allMeals.isEmpty;
    
    // If we have valid cache and data, no need to fetch
    if (hasValidCache && !hasNoData) {
      print('[AllMeals] Using valid cache');
      return;
    }
    
    // If we have no data, show loading state
    if (hasNoData) {
      setState(() {
        _isLoadingMeals = true;
      });
    } else {
      // Show refresh indicator for background refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refreshing meals...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
        ),
      );
    }

    _fetchError = ''; // Reset error on new fetch

    try {
      print('[AllMeals] Fetching fresh meals data...');
      final meals = await _fetchMeals();
      
      if (mounted) {
        // Only update if we got new data
        if (meals.isNotEmpty) {
          _allMeals = meals;
          _AllMealsScreenState._mealsCache = List<Map<String, dynamic>>.from(meals);
          _AllMealsScreenState._mealsCacheTimestamp = DateTime.now();

          // Persist cache using UserCache
          await UserCache.saveData(
              _mealsCacheKey, _AllMealsScreenState._mealsCache);
          await UserCache.saveData(
              _mealsCacheTimestampKey, _AllMealsScreenState._mealsCacheTimestamp!.toIso8601String());

          _buildMealLookupMap();
          _filterMeals(_searchController.text); // Re-apply current search filter
        }

        if (mounted) {
          setState(() {
            _isLoadingMeals = false;
          });
          
          // Show success message if we refreshed the data
          if (!hasValidCache && meals.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Meals updated'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        print('Error fetching new meals in background: $e');
        
        // If we have no data at all, show error state
        if (hasNoData) {
          setState(() {
            _isLoadingMeals = false;
            _fetchError = "Failed to load meals. Please try again.";
            _filteredMealsNotifier.value = [];
          });
        } else {
          // If we have cached data, just show a subtle error message
          print('Using cached data due to fetch error');
          if (mounted) {
            setState(() {
              _isLoadingMeals = false;
            });
            
            if (!hasValidCache) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Using cached data. Could not refresh.'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
                ),
              );
            }
          }
        }
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

  // Removed connection type checking as preloading is now always enabled

  void _onScroll() {
    if (!_isPreloadingEnabled || _allMeals.isEmpty) return;

    // Check if we're near the bottom of the list
    if (!_scrollController.hasClients) return;

    final threshold = 0.7; // Start preloading when 80% scrolled
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll == 0.0) return; // List not yet laid out

    if (currentScroll >= (maxScroll * threshold)) {
      _preloadImages();
    }
  }

  void _preloadImages() async {
    if (_allMeals.isEmpty || !_isPreloadingEnabled) return;

    final firstVisibleIndex = (_scrollController.position.pixels / 200).floor();
    final lastVisibleIndex = ((_scrollController.position.pixels +
                MediaQuery.of(context).size.height) /
            200)
        .ceil();

    // Preload images for items slightly beyond the visible area
    final preloadStart = firstVisibleIndex.clamp(0, _allMeals.length - 1);
    final preloadEnd =
        (lastVisibleIndex + _preloadThreshold).clamp(0, _allMeals.length - 1);

    for (int i = preloadStart; i <= preloadEnd; i++) {
      if (i >= 0 && i < _allMeals.length) {
        final meal = _allMeals[i];
        final imageUrl = _processImagePath(
            meal['Image_link'] ?? '', meal['Meal_name'] ?? '');

        if (imageUrl.startsWith('http')) {
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

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _refreshIconController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _filteredMealsNotifier.dispose();
    super.dispose();
  }

  void _startRefreshAnimation() {
    if (!_refreshIconController.isAnimating) {
      _refreshIconController.repeat(
        period: const Duration(seconds: 1),
      );
    }
  }

  void _stopRefreshAnimation() {
    if (_refreshIconController.isAnimating) {
      _refreshIconController.stop();
      _refreshIconController.reset();
    }
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
                        _forceRefreshMeals();
                      },
              );
            },
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: "Recommended Meals",
              padding: const EdgeInsets.all(8.0),
              icon: Image.asset(
                'assets/images/rec_trans-picsay.png',
                width: 27,
                height: 27,
                color: Colors.white,
                colorBlendMode: BlendMode.srcIn,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const OnlymealsScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeInOutCubic;
                      
                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                      var offsetAnimation = animation.drive(tween);
                      
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        ),
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 500),
                    reverseTransitionDuration: const Duration(milliseconds: 300),
                  ),
                );
              },
            ),
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
    // Trigger initial preload when the grid is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isPreloadingEnabled) {
        _preloadImages();
      }
    });

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: meals.length,
      itemBuilder: (context, index) {
        final meal = meals[index];
        // Use PascalCase keys
        String title = meal['Meal_name'] ?? 'Unknown Meal';
        String imagePath =
            meal['Image_link'] ?? 'assets/images/mealimageplaceholder.png';
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
          'assets/images/mealimageplaceholder.png',
          fit: BoxFit.cover,
        ),
      );
    } else {
      // Assume asset path or placeholder path
      imageWidget = Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/mealimageplaceholder.png',
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
      return 'assets/images/mealimageplaceholder.png';
    }
  }

  // Helper function for navigation to detail page
  void _navigateToMealDetail(Map<String, dynamic> mealFromGrid) {
    try {
      // Find the full meal data from the original list to ensure all fields are present
      final fullMealData = _allMeals.firstWhere(
        (m) => m['Meal_id'] == mealFromGrid['Meal_id'],
        orElse: () {
          print("Warning: Could not find full meal data for ID ${mealFromGrid['Meal_id']}. Using grid data.");
          return mealFromGrid;
        },
      );

      // Create a deep copy of the meal data to avoid modifying the original
      final Map<String, dynamic> mealToSend = Map<String, dynamic>.from(fullMealData);

      // Process complementary dishes
      List<String> complementaryDishNames = [];
      final dynamic complementaryDishesData = mealToSend['Complementary_dishes'];

      // Handle different formats of complementary dishes data
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

      // Process complementary dish images
      final List<String> complementaryImageLinks = [];
      
      // Build a lookup map from meal name (lowercased) to meal data for all meals
      final Map<String, Map<String, dynamic>> mealNameToMealMap = {
        for (final m in _allMeals)
          if ((m['Meal_name'] ?? '').toString().trim().isNotEmpty)
            m['Meal_name'].toString().toLowerCase(): m
      };

      // Get image links for complementary dishes
      for (String dishName in complementaryDishNames) {
        final complementaryMeal = mealNameToMealMap[dishName.toLowerCase()];
        String imageUrl = 'assets/images/cover.png'; // Default placeholder

        if (complementaryMeal != null && complementaryMeal['Image_link'] != null) {
          imageUrl = _processImagePath(complementaryMeal['Image_link'], dishName);
        } else {
          print("Complementary dish '$dishName' or its image not found. Using placeholder.");
        }
        complementaryImageLinks.add(imageUrl);
      }

      // Add the processed complementary images to the meal data
      mealToSend['complementary_images'] = complementaryImageLinks;

      // Ensure the meal has all required fields with default values if missing
      mealToSend['Meal_name'] = mealToSend['Meal_name'] ?? 'Unknown Meal';
      mealToSend['Image_link'] = mealToSend['Image_link'] ?? 'assets/images/mealimageplaceholder.png';
      mealToSend['Description'] = mealToSend['Description'] ?? 'No description available';
      mealToSend['Price'] = mealToSend['Price'] ?? 0.0;
      mealToSend['Rating'] = mealToSend['Rating'] ?? 0.0;
      mealToSend['Best_served_with'] = mealToSend['Best_served_with'] ?? [];

      // Navigate to the meal detail screen with the complete meal data
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => meal_detail.MealDetailScreen(meal: mealToSend),
        ),
      );
    } catch (e) {
      print('Error navigating to meal detail: $e');
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading meal details. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
