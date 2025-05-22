// chef_net.dart (Code with Loading/Caching logic from Source File, Target UI/Nav retained)

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For jsonEncode and jsonDecode
// Ensure cart prefix is consistently used or remove if not needed elsewhere
// import 'package:zinzi2/cart.dart' as cart;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Needed for caching & user_id check
import 'dart:async';
import 'dart:math'; // Added for max used in _extractHumanReadableLocation (from target)
import 'package:zinzi2/app_drawer_unified.dart'; // Import the AppDrawer
import 'package:zinzi2/user_cache.dart'; // Import UserCache for caching

// Import your actual Gig Creation Screen
import 'package:zinzi2/create_gig_screen.dart'; // <-- MAKE SURE THIS PATH IS CORRECT
// Import Cart and Landing Page if needed for navigation
import 'package:zinzi2/cart.dart'; // <-- MAKE SURE THIS PATH IS CORRECT
import 'package:zinzi2/onboard.dart'; // <-- MAKE SURE THIS PATH IS CORRECT (Replace with your actual home/landing page import)
import 'package:zinzi2/signup_or_login.dart'; // Import SignUpOrLoginPage - Added from Source

// --- Color System --- (Using Target's Colors)
const Color kColorPrimaryDarkest = Color(0xFF00352C);
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFFAFAFA);
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary =
    Color(0xFF757575); // Corrected from target's 757570
const Color kColorTextOnPrimary = Colors.white;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFEEEEEE);
const Color kColorAccent = Color(0xFF00BFA5);
final Color kShimmerBaseColor = Colors.grey.shade200;
final Color kShimmerHighlightColor = Colors.grey.shade100;
const Color kColorStar = Color(0xFFFFB900);

// --- Styles & Constants --- (Using Target's Styles)
final BoxShadow kElevationShadow = BoxShadow(
  color: Colors.black.withOpacity(0.06),
  blurRadius: 8,
  offset: const Offset(0, 3),
);
final BoxShadow kSubtleElevationShadow = BoxShadow(
  color: Colors.black.withOpacity(0.04),
  blurRadius: 5,
  offset: const Offset(0, 2),
);
const double kRadiusSmall = 8.0;
const double kRadiusMedium = 12.0;
const double kRadiusLarge = 16.0;
const Duration kDurationShort = Duration(milliseconds: 150);
const Duration kDurationMedium = Duration(milliseconds: 300);
final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/api'; // Replace

// --- Cache Constants --- (Copied from Source)
const String kCacheKeyChefs = 'cached_chefs_data';
const String kCacheKeyTimestamp = 'cached_chefs_timestamp';
const Duration kCacheDuration =
    Duration(days: 2); // Cache validity period (e.g., 2 days) <- FROM SOURCE
const String kPlaceholderChefAsset =
    'assets/images/placeholderchef.jpeg'; // Define placeholder asset path
const String kChefSortField =
    'created_at'; // <<< FIELD TO SORT BY (e.g., 'created_at', 'updated_at') - MUST EXIST IN API RESPONSE <- FROM SOURCE

// --- Chef List Screen ---
class ChooseChefNetwork extends StatefulWidget {
  /// Preload the chef network cache for splash screen (no UI, no context needed)
  static Future<void> preloadCacheForSplash() async {
    const String kCacheKeyChefs = 'cached_chefs_data';
    const String kCacheKeyTimestamp = 'cached_chefs_timestamp';
    const Duration kCacheDuration = Duration(days: 2);
    final cachedData = await UserCache.getData(kCacheKeyChefs);
    final cachedTs = await UserCache.getData(kCacheKeyTimestamp);
    final now = DateTime.now();
    bool cacheValid = false;
    if (cachedData != null && cachedTs != null) {
      final cacheTime = DateTime.tryParse(cachedTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < kCacheDuration) {
        cacheValid = true;
      }
    }
    if (!cacheValid) {
      try {
        final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? dotenv.env['API_BASE_URL-intranet'] ?? 'https://your.default.api.url/api';
        final response = await http.get(Uri.parse('$apiBaseUrl/rr/rchefs')).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final dataList = jsonDecode(response.body);
          await UserCache.saveData(kCacheKeyChefs, dataList);
          await UserCache.saveData(kCacheKeyTimestamp, now.toIso8601String());
        }
      } catch (e) { print('[Splash][ChefNet] preload error: $e'); }
    }
  }
  const ChooseChefNetwork({super.key});
  @override
  _ChooseChefNetworkState createState() => _ChooseChefNetworkState();
}

class _ChooseChefNetworkState extends State<ChooseChefNetwork>
    with SingleTickerProviderStateMixin {
  // --- State Variables (Copied from Source) ---
  List<dynamic> chefs =
      []; // Holds the currently displayed chefs (from cache or fetch), sorted
  List<dynamic> allFetchedChefs =
      []; // Holds the last successfully fetched list, sorted
  bool isLoading = true; // Controls overall loading state (shimmer)
  bool isFetchingInBackground = false; // Controls background refresh indicator
  String? fetchError;
  late AnimationController _refreshIconController;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> filteredChefs =
      []; // Derived from 'chefs' list based on filters
  String activeFilter = 'All';
  Set<String> cuisineTypes = {'All'};

  // --- initState (Copied from Source) ---
  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _loadChefsFromCacheOrFetch(); // Load initial data
    _searchController.addListener(() {
      _applyFilters(); // Apply filters whenever search text changes
    });
  }

  // --- dispose (Copied from Source) ---
  @override
  void dispose() {
    _refreshIconController.dispose();
    _searchController.removeListener(_applyFilters); // Ensure listener removal
    _searchController.dispose();
    super.dispose();
  }

  // --- Caching Logic (Copied from Source) ---

  Future<void> _loadChefsFromCacheOrFetch() async {
    if (!context.mounted) return;

    setState(() {
      isLoading = true; // Show initial loading shimmer
      fetchError = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString(kCacheKeyChefs);
    final String? cachedTimestampString = prefs.getString(kCacheKeyTimestamp);
    print('[ChefNet] Cached timestamp string: $cachedTimestampString');
    if (cachedData != null && cachedTimestampString != null) {
      print('[ChefNet] Cache found, checking validity...');
      DateTime? cachedTimestamp = _parseDate(cachedTimestampString);
      if (cachedTimestamp == null) {
        print('[ChefNet] Invalid cache timestamp: $cachedTimestampString, error: FormatException');
      }
      if (cachedTimestamp != null) {
        print('[ChefNet] Cache timestamp: $cachedTimestamp');
        final DateTime now = DateTime.now();
        print('[ChefNet] Now: $now');
        if (now.difference(cachedTimestamp) < kCacheDuration) {
          print("Cache valid, loading chefs from cache.");
          try {
            final List<dynamic> cachedListRaw = json.decode(cachedData);
            if (cachedListRaw is List) {
              List<Map<String, dynamic>> cachedList =
                  List<Map<String, dynamic>>.from(
                      cachedListRaw.whereType<Map<String, dynamic>>());
              print('[ChefNet] Loaded ${cachedList.length} chefs from cache');
              if (cachedList.isNotEmpty) {
                print('[ChefNet] First chef from cache: ' + cachedList.first.toString());
              }
              _sortChefList(cachedList); // Sort cached data

              if (mounted) {
                setState(() {
                  chefs = cachedList; // Assign sorted list
                  allFetchedChefs =
                      List.from(chefs); // Update allFetchedChefs as well
                  _extractCuisineTypes(); // Extract types from cached data
                  _applyFilters(); // Apply filters to cached data
                  isLoading = false; // Hide shimmer
                });
              }
              // Optional: Trigger background fetch to update cache silently
              fetchChefs(
                  isBackground:
                      true); // Always fetch in background if cache is valid
              return; // Exit after loading from cache
            } else {
              print(
                  "Cached data format error: Expected a List, got ${cachedListRaw.runtimeType}");
              await _clearCache(prefs); // Clear corrupted cache
            }
          } catch (e) {
            print("Error decoding or processing cached chefs: $e");
            await _clearCache(prefs); // Clear potentially corrupted cache
          }
        } else {
          print("Cache expired, fetching fresh data.");
        }
      } else {
        print("Cache timestamp missing or invalid, fetching fresh data.");
      }
    } else {
      print("No cache found, fetching fresh data.");
    }

    // If cache is invalid or not found, show loading and fetch fresh data
    if (mounted) {
      setState(() {
        isLoading = true; // Show shimmer for initial fetch
        fetchError = null;
      });
    }
    await fetchChefs(); // Foreground fetch
  }

  Future<void> _saveChefsToCache(List<dynamic> chefsToCache) async {
    if (chefsToCache.isEmpty) return; // Don't cache empty lists
    // Ensure list is sorted before saving
    List<Map<String, dynamic>> sortedList = List<Map<String, dynamic>>.from(
        chefsToCache.whereType<Map<String, dynamic>>());
    _sortChefList(sortedList);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String dataToStore =
          json.encode(sortedList); // Store the sorted list
      await prefs.setString(kCacheKeyChefs, dataToStore);
      await prefs.setString(kCacheKeyTimestamp, DateTime.now().toIso8601String());
      print("Sorted chefs data saved to cache.");
    } catch (e) {
      print("Error saving chefs to cache: $e");
    }
  }

  Future<void> _clearCache(SharedPreferences prefs) async {
    await prefs.remove(kCacheKeyChefs);
    await prefs.remove(kCacheKeyTimestamp);
    print("Chef cache cleared.");
  }

  // --- Sorting Logic (Copied from Source) ---
  void _sortChefList(List<Map<String, dynamic>> listToSort) {
  print('[ChefNet] _sortChefList called. List length: ${listToSort.length}');
    listToSort.sort((a, b) {
      // Attempt to parse the sort field (e.g., 'created_at')
      DateTime? dateA = _parseDate(a[kChefSortField]);
      DateTime? dateB = _parseDate(b[kChefSortField]);

      // Handle null dates (treat them as older)
      if (dateA == null && dateB == null)
        return 0; // Keep original order if both invalid
      if (dateA == null)
        return 1; // Place nulls (a) after non-nulls (b) -> older
      if (dateB == null)
        return -1; // Place non-nulls (a) before nulls (b) -> newer

      // Compare valid dates in descending order (latest first)
      return dateB.compareTo(dateA);
    });
  }

  // Helper to parse date strings robustly (Copied from Source)
  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is String) {
      return DateTime.tryParse(dateValue); // Handles ISO 8601 etc.
    }
    // Add handling for other potential date formats if needed (e.g., timestamps)
    // if (dateValue is int) {
    //   return DateTime.fromMillisecondsSinceEpoch(dateValue);
    // }
    return null; // Return null if format is unexpected
  }

  // --- Data Fetching (Copied from Source) ---

  // isBackground: If true, fetches data without showing the main loading shimmer.
  Future<void> fetchChefs({bool isBackground = false}) async {
    if (!context.mounted) return;

    // Only show main shimmer if not a background fetch and not already loading cache
    if (!isBackground) {
      setState(() {
        isLoading = true; // Show shimmer for foreground fetch
        fetchError = null;
      });
    } else {
      setState(() {
        isFetchingInBackground = true; // Indicate background activity if needed
      });
    }

    // Start refresh icon animation for foreground fetches
    if (!isBackground && !_refreshIconController.isAnimating) {
      _refreshIconController.repeat();
    }

    final url = '$apiBaseUrl/rr/rchefs';
    print("Fetching Chefs from URL: $url (Background: $isBackground)");

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20)); // Increased timeout slightly
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        // Adapt based on actual API response structure ('data' or 'chefs')
        final List<dynamic>? chefsListRaw = responseData.containsKey('data') &&
                responseData['data'] is List
            ? responseData['data']
            : responseData.containsKey('chefs') && responseData['chefs'] is List
                ? responseData['chefs']
                : null;

        if (chefsListRaw != null) {
          List<Map<String, dynamic>> validChefs =
              chefsListRaw.whereType<Map<String, dynamic>>().toList();

          // <<< SORTING: Sort the newly fetched data
          _sortChefList(validChefs);

          if (mounted) {
            setState(() {
              // Update the main list for display and the fetched list for caching
              chefs = validChefs; // Assign sorted list
              allFetchedChefs =
                  List.from(chefs); // Keep a copy of the latest fetch
              print('[ChefNet] Loaded ${chefs.length} chefs from API');
              if (chefs.isNotEmpty) {
                print('[ChefNet] First chef from API: ' + chefs.first.toString());
              }
              _extractCuisineTypes(); // Re-extract cuisines from fresh data
              _applyFilters(); // Apply filters to fresh data
              fetchError = null; // Clear any previous error
              if (!isBackground)
                isLoading = false; // Stop shimmer on foreground success
            });
            await _saveChefsToCache(
                validChefs); // Save the newly fetched *sorted* data
          }
        } else {
          throw Exception(
              'API response format error: Expected a list under "data" or "chefs" key.');
        }
      } else {
        throw Exception('Request failed (Status: ${response.statusCode})');
      }
    } on TimeoutException {
      print('Error fetching chefs: Request timed out.');
      if (mounted) {
        setState(() {
          fetchError = "Server connection timed out.";
          if (!isBackground) isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching chefs: $e');
      if (mounted) {
        setState(() {
          // Only show error if it's a foreground fetch or if there's no cached data
          if (!isBackground || chefs.isEmpty) {
            fetchError = "Could not load chefs. Check connection.";
            if (!isBackground) isLoading = false;
          } else {
            // Keep showing cached data on background fetch error
            print("Background fetch failed, keeping cached data.");
          }
        });
      }
    } finally {
      if (mounted) {
        // Stop refresh icon
        if (_refreshIconController.isAnimating) {
          _refreshIconController.stop();
          _refreshIconController.reset();
        }
        // Reset background fetch indicator
        if (isFetchingInBackground) {
          setState(() => isFetchingInBackground = false);
        }
      }
    }
  }

  // --- Filtering and UI Logic (Copied from Source) ---

  void _extractCuisineTypes() {
    final Set<String> extractedTypes = {'All'};
    // Use allFetchedChefs which holds the complete list from the last successful fetch/cache
    for (var chef in allFetchedChefs) {
      final specialties = chef['specialties'];
      if (specialties is List) {
        for (var specialty in specialties) {
          if (specialty != null) {
            String cat = specialty.toString().trim().split(' ').first;
            if (cat.isNotEmpty)
              extractedTypes.add(cat[0].toUpperCase() + cat.substring(1));
          }
        }
      } else if (specialties is String && specialties.isNotEmpty) {
        // Handle comma-separated strings as well
        final parts = specialties.split(',');
        for (String part in parts) {
          String cat = part.trim().split(' ').first;
          if (cat.isNotEmpty)
            extractedTypes.add(cat[0].toUpperCase() + cat.substring(1));
        }
      }
    }
    // Update state only if cuisine types actually changed
    if (cuisineTypes.length != extractedTypes.length ||
        !cuisineTypes.containsAll(extractedTypes)) {
      if (mounted) {
        setState(() {
          cuisineTypes = extractedTypes;
          // Ensure activeFilter is still valid, reset if not
          if (!cuisineTypes.contains(activeFilter)) {
            activeFilter = 'All';
          }
        });
      }
    }
  }

  // Applies search query and active category filter to the 'chefs' list (Copied from Source)
  void _applyFilters() {
    print('[ChefNet] _applyFilters called. Query: ' +
        _searchController.text +
        ', ActiveFilter: ' +
        activeFilter);
    final query = _searchController.text.toLowerCase().trim();
    // Filter the *currently displayed* chefs list if not empty,
    // otherwise filter the full list from last fetch/cache.
    // Both 'chefs' and 'allFetchedChefs' should be sorted now.
    final listToFilter = chefs.isNotEmpty ? chefs : allFetchedChefs;
    print('[ChefNet] Filtering list. chefs.length: ${chefs.length}, allFetchedChefs.length: ${allFetchedChefs.length}');

    if (!context.mounted) return;

    setState(() {
      print('[ChefNet] Setting filteredChefs for display. Query empty: ${query.isEmpty}, ActiveFilter: $activeFilter');
      if (query.isEmpty && activeFilter == 'All') {
        // No filters active, show all chefs from the current source
        filteredChefs = List.from(listToFilter);
        print('[ChefNet] FilteredChefs updated. Count: ${filteredChefs.length}');
        if (filteredChefs.isNotEmpty) {
          print('[ChefNet] First filtered chef: ' + filteredChefs.first.toString());
        } else {
          print('[ChefNet] FilteredChefs is empty after filtering.');
        }
      } else {
        // Apply filters
        filteredChefs = listToFilter.where((chef) {
          // Search Logic (Name, Bio, Location, Specialties)
          final name = chef['name']?.toString().toLowerCase() ?? '';
          final specialtiesRaw = chef['specialties'];
          final bio = chef['bio']?.toString().toLowerCase() ?? '';
          final location = chef['location']?.toString().toLowerCase() ?? '';

          bool matchesSearch = query.isEmpty || // Match if query is empty
              name.contains(query) ||
              bio.contains(query) ||
              location.contains(query);

          if (!matchesSearch && specialtiesRaw != null) {
            if (specialtiesRaw is List) {
              matchesSearch = specialtiesRaw.any(
                  (s) => s?.toString().toLowerCase().contains(query) ?? false);
            } else if (specialtiesRaw is String) {
              matchesSearch = specialtiesRaw.toLowerCase().contains(query);
            }
          }

          // Filter Logic (Active Category)
          bool matchesFilter =
              activeFilter == 'All'; // Match if filter is 'All'
          if (!matchesFilter && specialtiesRaw != null) {
            if (specialtiesRaw is List) {
              matchesFilter = specialtiesRaw.any((s) {
                String cat = s?.toString().trim().split(' ').first ?? '';
                return cat.isNotEmpty &&
                    cat.toLowerCase() == activeFilter.toLowerCase();
              });
            } else if (specialtiesRaw is String) {
              final parts = specialtiesRaw.split(',');
              matchesFilter = parts.any((part) {
                String cat = part.trim().split(' ').first;
                return cat.isNotEmpty &&
                    cat.toLowerCase() == activeFilter.toLowerCase();
              });
            }
          }

          return matchesSearch && matchesFilter;
        }).toList();
      }
    });
  }

  void _applyCategoryFilter(String category) {
  print('[ChefNet] _applyCategoryFilter called with: $category');
    if (!context.mounted) return;
    setState(() {
      activeFilter = category;
      print('[ChefNet] Category filter set to: $category');
      _applyFilters(); // Re-apply all filters (search + new category)
    });
  }

  void _clearFiltersAndSearch() {
  print('[ChefNet] _clearFiltersAndSearch called');
    if (!context.mounted) return;
    _searchController
        .clear(); // This will trigger the listener -> _applyFilters
    setState(() {
      activeFilter = 'All';
      _applyFilters(); // Explicitly call again to ensure filter reset is applied
    });
  }

  // --- Helper Function (Kept from Target, used in Target's UI) ---
  String _extractHumanReadableLocation(String? fullLocation) {
    if (fullLocation == null || fullLocation.isEmpty) return 'Location N/A';
    final parts = fullLocation.split(', ');
    // Try to get the last two parts (e.g., "City, State" or "Neighborhood, City")
    if (parts.length >= 2)
      return parts.sublist(max(0, parts.length - 2)).join(', ');
    // Fallback to the original (trimmed) if fewer than 2 parts
    return fullLocation.trim();
  }

  // --- build Method (Kept from Target) ---
  @override
  Widget build(BuildContext context) {
    List<String> sortedCuisineTypes = cuisineTypes.toList();
    // Ensure 'All' is always first
    sortedCuisineTypes.remove('All');
    sortedCuisineTypes
        .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    sortedCuisineTypes.insert(0, 'All');

    bool showClearButton =
        activeFilter != 'All' || _searchController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Find Your Chef',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 20)),
        centerTitle: true,
        backgroundColor: kColorSurface,
        foregroundColor: kColorPrimaryDarkest,
        elevation: 1.0,
        actions: [
          // Refresh button uses the new _refreshIconController and fetchChefs from source
          IconButton(
              icon: AnimatedBuilder(
                  animation: _refreshIconController,
                  builder: (_, child) => Transform.rotate(
                      angle: _refreshIconController.value * 2 * pi,
                      child: child),
                  child: Icon(Icons.refresh,
                      color: (isLoading || isFetchingInBackground)
                          ? Colors.grey
                          : kColorPrimary)),
              // Call the new fetchChefs (foreground)
              onPressed: (isLoading || isFetchingInBackground)
                  ? null
                  : () => fetchChefs(isBackground: false),
              tooltip: 'Refresh'),
          const SizedBox(width: 8)
        ],
      ),
      drawer: const AppDrawer(),
      backgroundColor: kColorBackground,
      body: Column(children: [
        // --- Search Bar (Target's UI) ---
        Container(
            color: kColorSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Material(
                color: kColorBackground,
                borderRadius: BorderRadius.circular(kRadiusMedium),
                child: TextField(
                    controller:
                        _searchController, // Uses controller from source logic
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: kColorTextPrimary),
                    decoration: InputDecoration(
                        hintText: 'Search chefs, cuisines, location...',
                        hintStyle: GoogleFonts.poppins(
                            color: kColorTextSecondary.withOpacity(0.7),
                            fontSize: 14),
                        prefixIcon: const Icon(Icons.search,
                            color: kColorPrimary, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: kColorTextSecondary, size: 20),
                                onPressed: _searchController
                                    .clear // Listener will handle filter update
                                )
                            : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusMedium),
                            borderSide: BorderSide(
                                color: kColorBorder.withOpacity(0.5),
                                width: 1)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusMedium),
                            borderSide: BorderSide(
                                color: kColorBorder.withOpacity(0.5),
                                width: 1)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusMedium),
                            borderSide: const BorderSide(
                                color: kColorPrimary, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16))))),

        // --- Cuisine Filters (Target's UI, uses state from source logic) ---
        if (!isLoading && fetchError == null && cuisineTypes.length > 1)
          Container(
              height: 50,
              color: kColorSurface,
              padding: const EdgeInsets.only(bottom: 8),
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sortedCuisineTypes.length,
                  itemBuilder: (context, index) {
                    final cuisine = sortedCuisineTypes[index];
                    final bool isSelected = activeFilter ==
                        cuisine; // Uses activeFilter from source
                    return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label: Text(cuisine),
                            selected: isSelected,
                            onSelected: (_) => _applyCategoryFilter(
                                cuisine), // Calls filter func from source
                            backgroundColor: kColorBackground,
                            selectedColor: kColorPrimaryLightest,
                            labelStyle: GoogleFonts.poppins(
                                color: isSelected
                                    ? kColorPrimaryDark
                                    : kColorTextSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13),
                            side: isSelected
                                ? const BorderSide(
                                    color: kColorPrimary, width: 1.0)
                                : BorderSide(color: kColorDivider),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(kRadiusLarge))));
                  })),

        // --- Results Count & Clear Button (Target's UI, uses state from source logic) ---
        if (!isLoading &&
            fetchError == null &&
            allFetchedChefs // Uses allFetchedChefs from source
                .isNotEmpty)
          Container(
              color: kColorSurface,
              padding: EdgeInsets.fromLTRB(16, 0, 16, showClearButton ? 0 : 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        // Uses filteredChefs count from source
                        '${filteredChefs.length} chef${filteredChefs.length != 1 ? 's' : ''} found',
                        style: GoogleFonts.poppins(
                            color: kColorTextSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    if (showClearButton)
                      TextButton.icon(
                          icon: const Icon(Icons.clear_all_rounded,
                              size: 18, color: kColorPrimary),
                          label: Text('Clear',
                              style: GoogleFonts.poppins(
                                  color: kColorPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          onPressed:
                              _clearFiltersAndSearch, // Calls clear func from source
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact))
                  ])),

        // Divider (Target's UI)
        if (!isLoading && fetchError == null && allFetchedChefs.isNotEmpty)
          const Divider(height: 1, thickness: 1, color: kColorDivider),

        // --- Main Content Area (Target's UI, uses state from source logic) ---
        Expanded(
            child: isLoading // Uses isLoading from source
                ? _buildLoadingShimmerList() // Target's shimmer
                : fetchError != null // Uses fetchError from source
                    ? _buildErrorState(fetchError!) // Target's error state
                    : filteredChefs // Uses filteredChefs from source
                            .isEmpty
                        ? _buildEmptyState() // Target's empty state
                        : _buildChefListView() // Target's list view builder
            ),
      ]),
      // Floating Action Button - Added from Source file (as it was present there)
    );
  }

  // --- Build Widgets for Different States (Kept from Target) ---

  Widget _buildLoadingShimmerList() {
    print('[ChefNet] Showing loading shimmer list');
    return Shimmer.fromColors(
        baseColor: kShimmerBaseColor,
        highlightColor: kShimmerHighlightColor,
        child: ListView.builder(
            itemCount: 5, // Show several shimmer items
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, __) => Container(
                margin: const EdgeInsets.only(bottom: 16.0),
                decoration: BoxDecoration(
                    color: Colors.white, // Base color for shimmer container
                    borderRadius: BorderRadius.circular(kRadiusMedium)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shimmer Image Placeholder
                      Container(height: 180, color: Colors.white),
                      // Shimmer Text/Chip Placeholders
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    height: 20,
                                    width: double.infinity,
                                    color: Colors.white),
                                const SizedBox(height: 12),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                          height: 24,
                                          width: 150,
                                          color: Colors.white),
                                      Container(
                                          height: 24,
                                          width: 60,
                                          color: Colors.white)
                                    ]),
                                const SizedBox(height: 10),
                                Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: List.generate(
                                        3,
                                        (i) => Container(
                                            height: 28,
                                            width: 80,
                                            decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        kRadiusSmall)))))
                              ]))
                    ]))));
  }

  Widget _buildErrorState(String message) {
    print('[ChefNet] Showing error state: ' + message);
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24.0),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red.shade100, width: 2)),
                  child: Icon(Icons.wifi_off_rounded,
                      size: 50, color: Colors.red.shade400)),
              const SizedBox(height: 24),
              Text("Connection Issue",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: kColorTextPrimary)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 15, color: kColorTextSecondary, height: 1.4)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text("Try Again"),
                  // Calls the new fetchChefs (foreground) on retry
                  onPressed: () => fetchChefs(isBackground: false),
                  style: ElevatedButton.styleFrom(
                      foregroundColor: kColorTextOnPrimary,
                      backgroundColor: kColorPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kRadiusLarge)),
                      textStyle: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w500)))
            ])));
  }

  Widget _buildEmptyState() {
    print('[ChefNet] Showing empty state (no chefs to display)');
    final bool isFiltering = activeFilter != 'All' ||
        _searchController.text.isNotEmpty; // Uses state from source
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24.0),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: kColorPrimaryLightest.withOpacity(0.6),
                      shape: BoxShape.circle),
                  child: Icon(
                      isFiltering
                          ? Icons.search_off_rounded
                          : Icons.person_search_outlined,
                      size: 50,
                      color: kColorPrimary)),
              const SizedBox(height: 24),
              Text(isFiltering ? "No Matching Chefs" : "No Chefs Available",
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: kColorTextPrimary)),
              const SizedBox(height: 8),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                      isFiltering
                          ? "Try adjusting your search or filter criteria."
                          : "No chefs listed right now. Pull down to refresh or check back later.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: kColorTextSecondary,
                          height: 1.4))),
              const SizedBox(height: 32),
              if (isFiltering) // Only show clear button if filtering resulted in empty
                ElevatedButton.icon(
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text("Clear Search & Filters"),
                    onPressed:
                        _clearFiltersAndSearch, // Calls clear func from source
                    style: ElevatedButton.styleFrom(
                        foregroundColor: kColorTextOnPrimary,
                        backgroundColor: kColorPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kRadiusLarge)),
                        textStyle: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w500)))
            ])));
  }

  Widget _buildChefListView() {
    print('[ChefNet] _buildChefListView called. filteredChefs.length: '
        + filteredChefs.length.toString());
    // Uses filteredChefs which is updated by _applyFilters (derived from sorted 'chefs')
    return RefreshIndicator(
        color: kColorPrimary,
        backgroundColor: kColorSurface,
        // Calls the new fetchChefs (foreground) on pull-to-refresh
        onRefresh: () => fetchChefs(isBackground: false),
        child: ListView.builder(
            // Using filteredChefs from source logic
            padding: const EdgeInsets.all(16),
            itemCount: filteredChefs.length,
            itemBuilder: (context, index) {
              final chef = filteredChefs[index];
              // Use a stable key based on chef ID if available, otherwise index
              final Key itemKey = ValueKey(chef['chefid'] ?? 'chef_$index');
              return _buildChefCard(
                  context, chef, index, itemKey); // Target's card builder
            }));
  }

  // Builds individual chef card (Kept from Target)
  Widget _buildChefCard(
      BuildContext context, Map<String, dynamic> chef, int index, Key key) {
    print('[ChefNet] _buildChefCard: index=$index, chef=${chef['name'] ?? chef.toString()}');
    final chefName = chef['name']?.toString() ?? 'Unknown Chef';
    final chefImage = chef['image']?.toString(); // Keep as nullable string
    final chefId = chef['chefid']?.toString() ??
        'chef_${Uri.encodeComponent(chefName)}_$index';
    final fullLocation = chef['location']?.toString(); // Keep nullable
    // Uses the target's helper function
    final humanReadableLocation = _extractHumanReadableLocation(fullLocation);
    final priceStr = chef['price']?.toString() ?? '0';
    final chefPrice = double.tryParse(priceStr) ?? 0.0;
    final ratingDouble =
        double.tryParse(chef['rating']?.toString() ?? '0.0') ?? 0.0;

    List<String> specialtiesList = [];
    final specialties = chef['specialties'];
    if (specialties is List) {
      specialtiesList = specialties
          .where((item) => item != null)
          .map((item) => item.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (specialties is String && specialties.isNotEmpty) {
      specialtiesList = specialties
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (specialtiesList.isEmpty)
      specialtiesList.add('Diverse Cuisine'); // Default if empty

    final bool isFeatured = ratingDouble >= 4.5;
    final bool hasValidImage = chefImage != null &&
        chefImage.isNotEmpty &&
        (chefImage.startsWith('http://') || chefImage.startsWith('https://'));

    return Hero(
        tag: 'chef-card-$chefId',
        child: Material(
            type: MaterialType.transparency,
            child: Container(
                key: key,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: kColorSurface,
                    borderRadius: BorderRadius.circular(kRadiusMedium),
                    boxShadow: [kElevationShadow]),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: () async {
                      // Precache network image if valid
                      if (hasValidImage) {
                        try {
                          // Use context check for safety
                          if (mounted) {
                            await precacheImage(
                                CachedNetworkImageProvider(chefImage!),
                                context);
                          }
                        } catch (e) {
                          print("Precache error for $chefImage: $e");
                        }
                      }
                      // Navigate to detail screen (Target's navigation)
                      if (mounted) {
                        Navigator.push(
                            context,
                            PageRouteBuilder(
                                transitionDuration: kDurationMedium,
                                pageBuilder: (_, __, ___) => ChefDetailScreen(
                                    // Target's Detail Screen
                                    chef: chef,
                                    heroTag: 'chef-card-$chefId'),
                                transitionsBuilder: (_, animation, __, child) =>
                                    FadeTransition(
                                        opacity: animation, child: child)));
                      }
                    },
                    splashColor: kColorPrimaryLight.withOpacity(0.1),
                    highlightColor: kColorPrimaryLightest.withOpacity(0.5),
                    child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [ 
                          // --- Image Section with Placeholder ---
                          Stack(children: [
                            AspectRatio(
                              aspectRatio: 16 / 10,
                              child: hasValidImage
                                  ? CachedNetworkImage(
                                      imageUrl: chefImage!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                          color: kColorPrimaryLightest,
                                          child: Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: kColorPrimary))),
                                      errorWidget: (context, url, error) =>
                                          _buildPlaceholderImage(), // Use placeholder on error
                                    )
                                  : _buildPlaceholderImage(), // Use placeholder if no valid URL
                            ),
                            // Gradient Overlay
                            Positioned.fill(
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.1),
                                  Colors.black.withOpacity(0.6)
                                ],
                                            stops: const [
                                  0.5,
                                  0.8,
                                  1.0
                                ])))),
                            // Top Badges (Featured, Price)
                            if (isFeatured)
                              Positioned(
                                  top: 12,
                                  left: 12,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: kColorPrimaryDark
                                              .withOpacity(0.85),
                                          borderRadius: BorderRadius.circular(
                                              kRadiusSmall)),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star,
                                                color: kColorStar, size: 14),
                                            const SizedBox(width: 4),
                                            Text('Top Chef',
                                                style: GoogleFonts.poppins(
                                                    color: kColorTextOnPrimary,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w500))
                                          ]))),
                            if (chefPrice > 0)
                              Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color:
                                              kColorSurface.withOpacity(0.95),
                                          borderRadius: BorderRadius.circular(
                                              kRadiusSmall),
                                          boxShadow: [kSubtleElevationShadow]),
                                      child: Text(
                                          'ugx ${chefPrice.toStringAsFixed(0)}',
                                          style: GoogleFonts.poppins(
                                              color: kColorPrimaryDark,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)))),
                            // Bottom Info (Name, Rating)
                            Positioned(
                                bottom: 12,
                                left: 16,
                                right: 16,
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                          child: Text(chefName,
                                              style: GoogleFonts.poppins(
                                                  fontSize: 19,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                  shadows: [
                                                    Shadow(
                                                        color: Colors.black
                                                            .withOpacity(0.7),
                                                        blurRadius: 2,
                                                        offset:
                                                            const Offset(0, 1))
                                                  ]),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis)),
                                      const SizedBox(width: 8),
                                      if (ratingDouble > 0)
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color:
                                                    kColorStar.withOpacity(0.9),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        kRadiusSmall)),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                      ratingDouble
                                                          .toStringAsFixed(1),
                                                      style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              kColorTextPrimary)),
                                                  const SizedBox(width: 3),
                                                  const Icon(Icons.star_rounded,
                                                      color: kColorTextPrimary,
                                                      size: 16)
                                                ]))
                                    ]))
                          ]),
                          // --- Details Section (Location, Specialties) ---
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(Icons.location_on_outlined,
                                          color: kColorPrimary, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              humanReadableLocation, // Already handles N/A case
                                              style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  color: kColorTextSecondary),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis))
                                    ]),
                                    const SizedBox(height: 12),
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: specialtiesList
                                            .take(3)
                                            .map((specialty) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                    color: kColorPrimaryLightest
                                                        .withOpacity(0.7),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            kRadiusSmall),
                                                    border: Border.all(
                                                        color: kColorPrimaryLighter
                                                            .withOpacity(0.5))),
                                                child: Text(specialty,
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 12,
                                                        color: kColorPrimaryDark,
                                                        fontWeight: FontWeight.w500))))
                                            .toList()),
                                    if (specialtiesList.length > 3) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                          "+${specialtiesList.length - 3} more",
                                          style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: kColorTextSecondary,
                                              fontStyle: FontStyle.italic))
                                    ]
                                  ]))
                        ]))))));
  }

  // Helper to build the placeholder image (Kept from Target)
  Widget _buildPlaceholderImage() {
    return Container(
      color: kColorPrimaryLightest, // Background color for placeholder
      child: Center(
        child: Image.asset(
          kPlaceholderChefAsset, // Use the defined constant
          fit: BoxFit.cover, // Ensure asset covers the area
          // Optional: Add error handling for the asset itself
          errorBuilder: (context, error, stackTrace) {
            print("Error loading placeholder asset: $error");
            return Container(
                // Fallback solid color if asset fails
                color: kColorPrimaryLighter,
                child: Center(
                    child: Icon(Icons.broken_image,
                        color: kColorPrimary.withOpacity(0.5), size: 40)));
          },
        ),
      ),
    );
  }
} // End of _ChooseChefNetworkState

// --- Chef Detail Screen (Kept Entirely from Target) ---
// --- Includes the Post-Gig Navigation Logic ---
class ChefDetailScreen extends StatelessWidget {
  final Map<String, dynamic> chef;
  final String heroTag;

  const ChefDetailScreen(
      {super.key, required this.chef, required this.heroTag});

  List<String> _getListFromStringOrList(dynamic data) {
    if (data is List) {
      return data
          .where((item) => item != null && item.toString().trim().isNotEmpty)
          .map((item) => item.toString().trim())
          .toList();
    } else if (data is String && data.trim().isNotEmpty) {
      return data
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  // --- Helper to check if user is logged in ---
  Future<bool> _isUserLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Object? rawUserId = prefs.get('user_id');
      print('[ChefNet] _isUserLoggedIn: rawUserId= ${rawUserId.runtimeType}: $rawUserId');
      if (rawUserId == null) return false;
      if (rawUserId is int) {
        return true;
      } else if (rawUserId is String) {
        if (rawUserId.isNotEmpty) {
          // Optionally check if string is int-like
          final parsed = int.tryParse(rawUserId);
          print('[ChefNet] _isUserLoggedIn: user_id string parses to int? $parsed');
          return true;
        }
        return false;
      } else {
        print('[ChefNet] _isUserLoggedIn: user_id is unexpected type: ${rawUserId.runtimeType}');
        return false;
      }
    } catch (e) {
      print("Error checking login status: $e");
      return false; // Assume not logged in on error
    }
  }

  // --- Function to show post-gig navigation options ---
  void _showPostGigNavigationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must choose an option
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusMedium)),
          title: Text("Booking Request Sent!",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Text("What would you like to do next?",
              style: GoogleFonts.poppins()),
          actions: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.shopping_cart_outlined,
                  size: 18, color: kColorPrimary),
              label: Text("View Cart",
                  style: GoogleFonts.poppins(
                      color: kColorPrimary, fontWeight: FontWeight.w500)),
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                // Ensure ShoppingCartScreen is imported correctly
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ShoppingCartScreen())); // Navigate to Cart
                // Or use Navigator.pushNamed(context, '/cart'); if using named routes
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.list_alt_outlined,
                  size: 18, color: kColorTextSecondary),
              label: Text("Back to Chefs",
                  style: GoogleFonts.poppins(
                      color: kColorTextSecondary, fontWeight: FontWeight.w500)),
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                Navigator.pop(
                    context); // Pop ChefDetailScreen to return to list
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.home_outlined,
                  size: 18, color: kColorTextSecondary),
              label: Text("Go Home",
                  style: GoogleFonts.poppins(
                      color: kColorTextSecondary, fontWeight: FontWeight.w500)),
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                // Ensure LandingPage is imported correctly
                // Navigate to Home and remove all previous routes
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          LandingPage()), // Replace LandingPage with your actual home screen widget
                  (Route<dynamic> route) =>
                      false, // Predicate to remove all routes
                );
                // Or use Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false); if using named routes
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- Data Extraction ---
    final chefName = chef['name']?.toString() ?? 'Unknown Chef';
    final chefImage = chef['image']?.toString(); // Keep nullable
    final bio = chef['bio']?.toString() ?? 'No detailed biography available.';
    final certificationsList = _getListFromStringOrList(chef['certifications']);
    final availabilityList = _getListFromStringOrList(chef['availability']);
    final specialtiesList = _getListFromStringOrList(chef['specialties']);
    final sampleMenuList = _getListFromStringOrList(chef['samplemenu']);
    final reviewsList = chef['reviews'] is List
        ? List<Map<String, dynamic>>.from(
            chef['reviews'].whereType<Map<String, dynamic>>())
        : <Map<String, dynamic>>[];
    final experience = chef['experience']?.toString();
    final serviceRadius = chef['serviceradius']?.toString();
    final responseTime = chef['responsetime']?.toString();
    final minNotice = chef['minnotice']?.toString();
    Map<String, dynamic>? pricingData;
    final dynamic pricingRaw = chef['pricing'];
    if (pricingRaw is String) {
      try {
        pricingData = json.decode(pricingRaw);
      } catch (e) {
        print("Error decoding pricing JSON string: $e");
        pricingData = null; // Set to null if decoding fails
      }
    } else if (pricingRaw is Map<String, dynamic>) {
      pricingData = pricingRaw;
    } else {
      pricingData = null;
    }

    final Map<String, dynamic>? perGigPricing =
        pricingData?['per_gig'] is Map<String, dynamic>
            ? pricingData!['per_gig']
            : null;
    final bool canBookGig = perGigPricing != null && perGigPricing.isNotEmpty;
    final bool hasValidImage = chefImage != null &&
        chefImage.isNotEmpty &&
        (chefImage.startsWith('http://') || chefImage.startsWith('https://'));

    return Scaffold(
      drawer: const AppDrawer(), // Add the drawer here
      backgroundColor: kColorBackground,
      body: CustomScrollView(
        slivers: [
          // --- SliverAppBar ---
          SliverAppBar(
            expandedHeight: 300.0,
            floating: false,
            pinned: true,
            stretch: true,
            backgroundColor: kColorSurface,
            foregroundColor: kColorPrimaryDark,
            elevation: 1.0,
            iconTheme: const IconThemeData(
                color: kColorPrimaryDark), // Adjust icon color if needed
            flexibleSpace: FlexibleSpaceBar(
              title: Text(chefName,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: kColorPrimaryDark,
                      fontSize: 18)),
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: 50, vertical: 14),
              centerTitle: true,
              background: Hero(
                  tag: heroTag,
                  child: Stack(fit: StackFit.expand, children: [
                    // Display Chef Image or Placeholder
                    hasValidImage
                        ? CachedNetworkImage(
                            imageUrl: chefImage!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: kColorPrimaryLighter),
                            errorWidget: (context, url, error) =>
                                _buildDetailPlaceholderImage(), // Use placeholder on error
                          )
                        : _buildDetailPlaceholderImage(), // Use placeholder if no valid URL

                    // Gradient Overlay
                    DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.7)
                        ],
                                stops: const [
                          0.0,
                          0.6,
                          1.0
                        ]))),
                    // Chef Name at Bottom
                    Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Text(chefName,
                            style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: kColorTextOnPrimary,
                                shadows: [
                                  Shadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2))
                                ]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis))
                  ])),
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.fadeTitle
              ],
            ),
          ),

          // --- Main Content Area ---
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              // At a Glance Section
              if (experience != null ||
                  serviceRadius != null ||
                  responseTime != null ||
                  minNotice != null) ...[
                _buildSectionHeader('At a Glance', icon: Icons.bolt_outlined),
                GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 3.5, // Adjust aspect ratio for better fit
                    children: [
                      if (experience != null && experience.isNotEmpty)
                        _buildInfoChip(Icons.workspace_premium_outlined,
                            '$experience yrs experience'),
                      if (serviceRadius != null && serviceRadius.isNotEmpty)
                        _buildInfoChip(
                            Icons.map_outlined, '$serviceRadius km radius'),
                      if (responseTime != null && responseTime.isNotEmpty)
                        _buildInfoChip(Icons.access_time_rounded, responseTime),
                      if (minNotice != null && minNotice.isNotEmpty)
                        _buildInfoChip(Icons.notifications_active_outlined,
                            '$minNotice notice'),
                    ]
                        .where((w) => w != null)
                        .cast<Widget>()
                        .toList()), // Filter out nulls if any value is empty
                const SizedBox(height: 24)
              ],
              // Specialties Section
              if (specialtiesList.isNotEmpty) ...[
                _buildSectionHeader('Specialties',
                    icon: Icons.restaurant_menu_rounded),
                Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: specialtiesList
                        .map((specialty) => Chip(
                            label: Text(specialty),
                            backgroundColor: kColorPrimaryLightest,
                            labelStyle: GoogleFonts.poppins(
                                color: kColorPrimaryDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            side: BorderSide(
                                color: kColorPrimaryLighter.withOpacity(0.7)),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(kRadiusLarge)),
                            visualDensity: VisualDensity.compact))
                        .toList()),
                const SizedBox(height: 24)
              ],
              // About Section
              _buildSectionHeader('About $chefName',
                  icon: Icons.person_outline_rounded),
              Text(bio,
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: kColorTextPrimary.withOpacity(0.85),
                      height: 1.6)),
              const SizedBox(height: 24),
              // Certifications Section
              if (certificationsList.isNotEmpty) ...[
                _buildSectionHeader('Certifications & Awards',
                    icon: Icons.verified_outlined),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: certificationsList
                        .map((cert) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      color: kColorPrimary, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(cert,
                                          style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: kColorTextPrimary)))
                                ])))
                        .toList()),
                const SizedBox(height: 24)
              ],
              // Availability Section
              if (availabilityList.isNotEmpty) ...[
                _buildSectionHeader('Typical Availability',
                    icon: Icons.event_available_outlined),
                Text(availabilityList.join(' • '),
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: kColorTextPrimary)),
                const SizedBox(height: 24)
              ],
              // Sample Menu Section
              if (sampleMenuList.isNotEmpty) ...[
                _buildSectionHeader('Sample Menu Highlights',
                    icon: Icons.menu_book_outlined),
                Wrap(
                    spacing: 10.0,
                    runSpacing: 10.0,
                    children: sampleMenuList
                        .map((item) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: kColorSurface,
                                borderRadius:
                                    BorderRadius.circular(kRadiusSmall),
                                border:
                                    Border.all(color: kColorDivider, width: 1),
                                boxShadow: [kSubtleElevationShadow]),
                            child: Text(item,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: kColorTextPrimary,
                                    fontWeight: FontWeight.w500))))
                        .toList()),
                const SizedBox(height: 24)
              ],
              // Reviews Section
              _buildSectionHeader('Reviews (${reviewsList.length})',
                  icon: Icons.reviews_outlined),
              if (reviewsList.isNotEmpty)
                ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount:
                        min(reviewsList.length, 3), // Show max 3 initially
                    itemBuilder: (context, index) =>
                        _buildReviewItem(reviewsList[index]),
                    separatorBuilder: (_, __) => const Divider(
                        height: 24, thickness: 1, color: kColorDivider))
              else
                Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("No reviews yet.",
                        style: GoogleFonts.poppins(
                            color: kColorTextSecondary,
                            fontStyle: FontStyle.italic))),
              if (reviewsList.length > 3) ...[
                const SizedBox(height: 16),
                Center(
                    child: TextButton(
                        onPressed: () {
                          // Placeholder for showing all reviews
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Full reviews page not implemented yet.'),
                                  duration: Duration(seconds: 2)));
                        },
                        child: Text("View all ${reviewsList.length} reviews",
                            style: GoogleFonts.poppins(
                                color: kColorPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8)))),
              ],
              const SizedBox(
                  height: 80), // Bottom spacing for button visibility
            ])),
          ),
        ],
      ),
      // --- Bottom Navigation Bar ---
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0).copyWith(top: 8),
        decoration: BoxDecoration(color: kColorSurface, boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -3))
        ]),
        child: ElevatedButton.icon(
          icon: Icon(
              canBookGig
                  ? Icons.event_available_outlined
                  : Icons.event_busy_outlined,
              size: 20),
          label: Text(
              canBookGig ? 'Request Booking' : 'unavailable for this chef'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canBookGig ? kColorPrimaryDark : Colors.grey.shade500,
            foregroundColor: kColorTextOnPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadiusMedium)),
            textStyle:
                GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
            elevation: 2,
          ),
          // Updated onPressed Logic with Post-Gig Navigation
          onPressed: !canBookGig
              ? null // Disable button if cannot book
              : () async {
                  // 1. Check if user is logged in
                  bool loggedIn = await _isUserLoggedIn();
                  if (!loggedIn) {
                    if (!context.mounted)
                      return; // Check context before showing snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Please log in to book a chef.'),
                        action: SnackBarAction(
                            label: 'Log In',
                            onPressed: () {
                              // Navigate to SignUpOrLoginPage if not logged in
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          SignUpOrLoginPage()), // Navigate to login/signup
                                );
                              }
                            }),
                        backgroundColor: Colors.orange.shade800,
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kRadiusSmall)),
                      ),
                    );
                    return; // Stop execution if not logged in
                  }

                  // 2. Navigate to the CreateGigScreen and wait for result
                  if (!context.mounted)
                    return; // Check context before navigation
                  print(
                      "Navigating to Create Gig Screen for Chef: ${chef['name']}");
                  final gigAddedSuccessfully = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CreateGigScreen(chefData: chef), // Pass the chef data
                    ),
                  );

                  // 3. Handle the result after returning
                  if (gigAddedSuccessfully == true) {
                    if (!context.mounted)
                      return; // Check context before navigation
                    print(
                        "Returned from CreateGigScreen. Gig added successfully. Navigating to Cart.");
                    // Navigate directly to the ShoppingCartScreen
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ShoppingCartScreen()),
                    );
                  } else {
                    print(
                        "Returned from CreateGigScreen. Gig not added (cancelled or failed).");
                    // Optionally show a message if needed, e.g., booking cancelled
                    // if (mounted) {
                    //   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
                    // }
                  }
                },
        ),
      ),
    );
  }

  // Helper to build the placeholder image for detail screen
  Widget _buildDetailPlaceholderImage() {
    return Container(
      color: kColorPrimaryLightest, // Background color for placeholder
      child: Center(
        child: Image.asset(
          kPlaceholderChefAsset, // Use the defined constant
          fit: BoxFit.cover, // Ensure asset covers the area
          errorBuilder: (context, error, stackTrace) {
            print("Error loading placeholder asset (Detail): $error");
            return Container(
                // Fallback solid color if asset fails
                color: kColorPrimaryLighter,
                child: Center(
                    child: Icon(Icons.broken_image,
                        color: kColorPrimary.withOpacity(0.5), size: 40)));
          },
        ),
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildSectionHeader(String title, {required IconData icon}) {
    return Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 12.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, color: kColorPrimary, size: 22),
          const SizedBox(width: 10),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: kColorPrimaryDark))
        ]));
  }

  Widget _buildInfoChip(IconData icon, String text) {
    if (text.isEmpty || text.toLowerCase() == 'n/a')
      return const SizedBox.shrink();
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: kColorSurface,
            borderRadius: BorderRadius.circular(kRadiusMedium),
            border: Border.all(color: kColorDivider, width: 1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: kColorPrimary, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: kColorTextPrimary,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1))
        ]));
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final userName = review['user']?.toString() ?? 'Anonymous User';
    final comment = review['comment']?.toString() ?? 'No comment.';
    final ratingDouble =
        double.tryParse(review['rating']?.toString() ?? '0.0') ?? 0.0;
    final rating = ratingDouble.round().clamp(0, 5);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text(userName,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: kColorTextPrimary))),
                const SizedBox(width: 10),
                _buildRatingStars(rating)
              ]),
          const SizedBox(height: 8),
          Text(comment,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: kColorTextSecondary, height: 1.5))
        ]));
  }

  Widget _buildRatingStars(int rating) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
            5,
            (index) => Icon(
                index < rating ? Icons.star_rounded : Icons.star_border_rounded,
                color: index < rating ? kColorStar : kColorBorder,
                size: 18)));
  }
}

// --- Placeholder/Example Widgets (Keep consistent with Target's dependencies) ---
// Assume CreateGigScreen pops with `true` on success
// Example placeholder:
/*
class CreateGigScreen extends StatelessWidget {
  final Map<String, dynamic> chefData;
  const CreateGigScreen({super.key, required this.chefData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book Gig with ${chefData['name'] ?? 'Chef'}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Text('Gig Creation Form Here'),
             SizedBox(height: 20),
             ElevatedButton(
                onPressed: () async {
                    // Simulate adding to cart or booking logic
                    print("Simulating successful gig booking...");
                    // bool success = await ShoppingCart.addGig(...); // Your actual logic
                    bool success = true; // Assume success for example
                    Navigator.pop(context, success); // Return true on success
                },
                child: Text("Confirm Booking")
             ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false); // Return false on cancellation
                },
                child: Text("Cancel"),
              )
          ],
        ),
      ),
    );
  }
}
*/

// Ensure you have a LandingPage widget defined and imported
// Example placeholder:
/*
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Home Page")),
      body: Center(child: Text("Welcome Home!")),
    );
  }
}
*/

// Ensure you have a ShoppingCartScreen widget defined and imported
// Example placeholder:
/*
class ShoppingCartScreen extends StatelessWidget {
  const ShoppingCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Shopping Cart")),
      body: Center(child: Text("Your Cart Items")),
    );
  }
}
*/

// Ensure you have a SignUpOrLoginPage widget defined and imported
// Example placeholder:
/*
class SignUpOrLoginPage extends StatelessWidget {
  const SignUpOrLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sign Up / Log In")),
      body: Center(child: Text("Login/Signup Form")),
    );
  }
}
*/
