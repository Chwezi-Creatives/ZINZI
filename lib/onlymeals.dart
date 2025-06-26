// cspell:disable
import 'dart:convert';
import 'dart:async'; // For Timer
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi/meal_detail.dart' as meal_detail;
import 'package:zinzi/cart.dart' as cart;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts
import 'package:flutter/material.dart' show precacheImage, ScrollController, NetworkImage;
import 'package:zinzi/app_drawer_unified.dart';
import 'package:zinzi/utils/image_utils.dart'; // Import ImageUtils
// Import CacheConfig

// --- NEW IMPORTS FOR BETTER LOADING ANIMATION ---
import 'package:lottie/lottie.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
// --- END NEW IMPORTS ---


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

  // No cache loading for meals - always fetch fresh from API
  static Future<void> loadMealsCacheFromPrefs() async {
    // No-op as we're not caching meal data
  }

  @override
  _OnlymealsScreenState createState() => _OnlymealsScreenState();
}

class _OnlymealsScreenState extends State<OnlymealsScreen>
    with SingleTickerProviderStateMixin {
  // No meal data caching - always fetch fresh from API
  List<Map<String, dynamic>> _meals = [];

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

      // No caching - just update UI
      _buildMealLookupMap();
      _filterMeals('');

      setState(() {
        _isLoadingMeals = false;
      });

    } catch (e) {
      print('Error fetching meals: $e');
      if (!mounted) return;

      // No fallback to cache - just show error
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


  Future<List<Map<String, dynamic>>> _fetchMeals(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/rr/meals2/$userId'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic> && decoded.containsKey('recommended_meals')) {
          final dataList = decoded['recommended_meals'];
          if (dataList is List) {
            return List<Map<String, dynamic>>.from(dataList.map((item) {
              final mapItem = Map<String, dynamic>.from(item);
              dynamic priceValue;
              if (mapItem.containsKey('price')) {
                priceValue = mapItem['price'];
              } else if (mapItem.containsKey('Price')) {
                priceValue = mapItem['Price'];
              }
              if (priceValue is num) {
                mapItem['price'] = priceValue;
              } else if (priceValue != null) {
                mapItem['price'] = double.tryParse(priceValue.toString()) ?? 0.0;
              } else {
                mapItem['price'] = 0.0;
              }
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
      throw Exception('An error occurred while fetching meals: $e');
    }
  }

  Future<void> _fetchUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) {
      setState(() => _isLoadingUserDetails = false);
      print("No user ID found in SharedPreferences.");
      return;
    }
    final url =
        '$apiBaseUrl/rr/rusers/$userId';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Content-Type': 'application/json'
      }).timeout(const Duration(seconds: 20));

      if (mounted) {
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          Map<String, dynamic>? userDetailsMap;
          if (responseData is Map<String, dynamic>) {
            if (responseData.containsKey('data') &&
                responseData['data'] is Map) {
              userDetailsMap = Map<String, dynamic>.from(responseData['data']);
            } else if (!responseData.containsKey('message')) {
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
      _filterMeals(_searchController.text);
    });
  }

  void _filterMeals(String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) {
      _filteredMealsNotifier.value = List.from(_Onlymeals);
    } else {
      _filteredMealsNotifier.value = _Onlymeals.where((meal) {
        final mealName = meal['Meal_name']?.toString().toLowerCase() ?? '';
        final cuisine =
            meal['Cuisine_preferences']?.toString().toLowerCase() ?? '';
        final dietPreference =
            meal['Dietary_preference']?.toString().toLowerCase() ?? '';
        return mealName.contains(cleanQuery) ||
            cuisine.contains(cleanQuery) ||
            dietPreference
                .contains(cleanQuery);
      }).toList();
    }
  }

  void _clearSearch() {
    _searchController.clear();
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _filteredMealsNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startRefreshAnimation() {
    if (mounted && !_refreshIconController.isAnimating) {
      _refreshIconController.repeat();
    }
  }

  void _stopRefreshAnimation() {
    _refreshIconController.stop();
    _refreshIconController.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: _buildSearchField(),
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0,
        iconTheme: const IconThemeData(
            color: kColorTextOnPrimary),
        actions: [
          AnimatedBuilder(
            animation: _refreshIconController,
            builder: (context, child) {
              return IconButton(
                icon: Transform.rotate(
                  angle: _isLoadingMeals
                      ? _refreshIconController.value * 6.3
                      : 0,
                  child: const Icon(Icons.refresh),
                ),
                tooltip: _isLoadingMeals ? 'Refreshing...' : 'Refresh',
                onPressed: _isLoadingMeals
                    ? null
                    : () async {
                        // Set loading state to show Lottie animation
                        setState(() {
                          _isLoadingMeals = true;
                          _fetchError = '';
                        });
                        
                        _startRefreshAnimation();
                        
                        try {
                          await _fetchMealsAndPreprocess();
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _fetchError = 'Failed to refresh: ${e.toString()}';
                            });
                          }
                        } finally {
                          _stopRefreshAnimation();
                          if (mounted) {
                            setState(() {
                              _isLoadingMeals = false;
                            });
                          }
                        }
                      },
              );
            },
          ),
          IconButton(
            tooltip: "Shopping Cart",
            icon: const Icon(Icons.shopping_cart_outlined),
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
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _fetchMealsAndPreprocess,
        color: kColorPrimary,
        child: FutureBuilder<void>(
          future: _initialFetchFuture,
          builder: (context, snapshot) {
            // Show engaging loader whenever we're loading, whether it's the initial load or a manual refresh
            if (_isLoadingMeals) {
              return _buildEngagingLoadingIndicator();
            }
            if (snapshot.connectionState == ConnectionState.done &&
                _fetchError.isNotEmpty) {
              return _buildErrorState(_fetchError);
            }
            return ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _filteredMealsNotifier,
              builder: (context, filteredMeals, _) {
                if (!_isLoadingMeals && filteredMeals.isEmpty) {
                  return _buildEmptyState(
                      isSearching: _searchController.text.isNotEmpty);
                }
                return _buildMealGrid(context, filteredMeals);
              },
            );
          },
        ),
      ),
    );
  }

  // Helper for AppBar Search Field (no changes)
  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
            color: kColorTextOnPrimary, fontSize: 15),
        cursorColor: kColorPrimaryLight,
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
          fillColor: kColorTextOnPrimary.withOpacity(0.15),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 0, horizontal: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(
                color: kColorPrimaryLight,
                width: 1.5),
          ),
        ),
      ),
    );
  }

  // *** NEW WIDGET: THE ENGAGING LOADING INDICATOR ***
  Widget _buildEngagingLoadingIndicator() {
    const colorizeTextStyle = TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.w600,
    );
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lottie animation from assets
          Lottie.asset(
            'assets/cooking.json', // Your downloaded Lottie file
            width: 200,
            height: 200,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          // Animated text kit
          AnimatedTextKit(
            animatedTexts: [
              FadeAnimatedText(
                'Finding recommendations for you...',
                textStyle: GoogleFonts.poppins(textStyle: colorizeTextStyle, color: kColorTextSecondary),
                textAlign: TextAlign.center,
              ),
              FadeAnimatedText(
                'Analyzing your tastes...',
                textStyle: GoogleFonts.poppins(textStyle: colorizeTextStyle, color: kColorTextSecondary),
                textAlign: TextAlign.center,
              ),
              FadeAnimatedText(
                'Stirring up the perfect meals...',
                textStyle: GoogleFonts.poppins(textStyle: colorizeTextStyle, color: kColorTextSecondary),
                textAlign: TextAlign.center,
              ),
               FadeAnimatedText(
                'Good food takes a moment!',
                textStyle: GoogleFonts.poppins(textStyle: colorizeTextStyle, color: kColorTextSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            repeatForever: true, // Loop the text animations
            pause: const Duration(milliseconds: 200), // Pause between texts
          ),
        ],
      ),
    );
  }

  // Empty State Widget (no changes)
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
          if (!isSearching)
            Text(
              "Pull down to refresh.",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }
  
  // Error State Widget (no changes)
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
  
  // All remaining code from this point down is unchanged.
  // ... (onScroll, preloadImages, buildMealGrid, etc.) ...
  
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = 0.7;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll == 0.0) return;
    if (currentScroll >= (maxScroll * threshold)) {
      _preloadImages();
    }
  }

  void _preloadImages() {
    if (!_scrollController.hasClients || _filteredMealsNotifier.value.isEmpty) return;
    final firstVisibleIndex = (_scrollController.position.pixels / 200).floor();
    final lastVisibleIndex = ((_scrollController.position.pixels + 
        _scrollController.position.viewportDimension) / 200).ceil();
    for (int i = firstVisibleIndex; i <= lastVisibleIndex + 5; i++) {
      if (i >= 0 && i < _filteredMealsNotifier.value.length) {
        final meal = _filteredMealsNotifier.value[i];
        String imagePath = meal['image_link'] ?? '';
        if (imagePath.isNotEmpty && imagePath.startsWith('http')) {
          precacheImage(NetworkImage(imagePath), context);
        }
      }
    }
  }

  void _preloadInitialImages() {
    if (_filteredMealsNotifier.value.isEmpty) return;
    final count = _filteredMealsNotifier.value.length > 10 ? 10 : _filteredMealsNotifier.value.length;
    for (int i = 0; i < count; i++) {
      final meal = _filteredMealsNotifier.value[i];
      String imagePath = meal['image_link'] ?? '';
      if (imagePath.isNotEmpty && imagePath.startsWith('http')) {
        precacheImage(NetworkImage(imagePath), context);
      }
    }
  }

  Widget _buildMealGrid(
      BuildContext context, List<Map<String, dynamic>> meals) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadInitialImages();
    });
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.0,
        mainAxisSpacing: 10.0,
        childAspectRatio: 0.85,
      ),
      itemCount: meals.length,
      itemBuilder: (context, index) {
        final meal = meals[index];
        String title = meal['meal_name'] ?? 'Unknown Meal';
        String imagePath =
            meal['image_link'] ?? 'assets/images/mealimageplaceholder.png';
        String mealId = meal['meal_id']?.toString() ?? 'unknown-$index';
        String displayImagePath = _processImagePath(imagePath, title);
        return GestureDetector(
          onTap: () => _navigateToMealDetail(meal),
          child: Hero(
            tag: 'meal-$mealId',
            flightShuttleBuilder: (flightContext, animation, flightDirection,
                fromHeroContext, toHeroContext) {
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
        color: kColorSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(child: imageWidget),
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
                    horizontal: 8, vertical: 6),
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
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

  String _processImagePath(String rawPath, String mealName) {
    if (rawPath.startsWith('http')) {
      return ImageUtils.processImageUrl(rawPath);
    } else if (rawPath.startsWith('assets/')) {
      return rawPath;
    } else {
      print("Invalid or unrecognized image path for $mealName: $rawPath");
      return 'assets/images/mealimageplaceholder.png';
    }
  }

  void _navigateToMealDetail(Map<String, dynamic> mealFromGrid) {
    try {
      final Map<String, dynamic> mealToSend = Map<String, dynamic>.from(mealFromGrid);
      final Map<String, dynamic> normalizedMeal = {};
      mealToSend.forEach((key, value) {
        final normalizedKey = key.isNotEmpty 
            ? key[0].toUpperCase() + key.substring(1)
            : key;
        normalizedMeal[normalizedKey] = value;
      });
      normalizedMeal['Meal_name'] = normalizedMeal['Meal_name'] ?? 'Unknown Meal';
      normalizedMeal['Image_link'] = normalizedMeal['Image_link'] ?? 'assets/images/mealimageplaceholder.png';
      normalizedMeal['Description'] = normalizedMeal['Description'] ?? 'No description available';
      if (normalizedMeal['price'] == null && normalizedMeal['Price'] != null) {
        normalizedMeal['price'] = normalizedMeal['Price'];
      }
      normalizedMeal['price'] = double.tryParse(normalizedMeal['price']?.toString() ?? '0') ?? 0.0;
      normalizedMeal['Price'] = normalizedMeal['price'];
      normalizedMeal.remove('Complementary_dishes');
      normalizedMeal.remove('complementary_images');
      normalizedMeal.remove('complementary_dishes');
      normalizedMeal.remove('best_served_with');
      debugPrint('=== NAVIGATING TO MEAL DETAIL ===');
      debugPrint('Meal ID: ${normalizedMeal['Meal_id']}');
      debugPrint('Meal Name: ${normalizedMeal['Meal_name']}');
      debugPrint('All Meal Data: $normalizedMeal');
      debugPrint('===============================');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error loading meal details. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}