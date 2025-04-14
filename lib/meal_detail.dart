
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:zinzi2/allmeals.dart'; // Assuming this screen exists
import 'package:zinzi2/cart.dart'; // Import the SHARED cart and favorites
import 'package:zinzi2/checkout.dart'; // Assuming this screen exists
import 'package:zinzi2/useranalytics.dart'; // Assuming this screen exists if needed
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart'; // For consistent font

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

  @override
  _MealDetailScreenState createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  bool _ingredientsExpanded = false;
  bool isFavorite = false;
  bool isChefSelected = true; // Default view to 'Cooked' (Chefs)
  // Use static cache for chefs and producers
  static List<dynamic> _chefsCache = [];
  static List<dynamic> _producersCache = [];
  List<dynamic> chefs = [];
  List<dynamic> producers = [];
  bool isLoadingChefs = true;
  bool isLoadingProducers = true;
  Map<String, dynamic>? selectedChef;
  Map<String, dynamic>? selectedProducer;
  bool isInCart = false;
  List<bool> complementaryInCartStatus = [];
  bool _isFetchingChefs = false; // Prevent overlapping chef fetches
  bool _isFetchingProducers = false; // Prevent overlapping producer fetches

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
  static const Color kColorBackground = Color(0xFFF5F5F5); // Light Grey Background
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
    final mealTitle = widget.meal['Meal_name'] ?? 'Unknown Meal'; // Use PascalCase

    // --- CRITICAL: Use the imported (shared) Favorites and ShoppingCart ---
    isFavorite = Favorites.isFavorite(mealTitle);
    var currentItemInCart = ShoppingCart.getItems().firstWhere(
          (item) => item['title'] == mealTitle,
      orElse: () => {}, // Return an empty map if not found
    );
    if (currentItemInCart != null) {
      isInCart = true;
      // Pre-select chef/producer if already in cart
      selectedChef = currentItemInCart['selectedchef'];
      selectedProducer = currentItemInCart['selectedproducer'];
      if (selectedProducer != null) {
        isChefSelected = false; // Show producer list if producer is selected
      } else {
        isChefSelected = true; // Default to chef list otherwise
      }
    } else {
      isInCart = false;
      selectedChef = null;
      selectedProducer = null;
      isChefSelected = true; // Default to chef
    }
    // --- End Critical Section ---

    // Use cache if available, otherwise fetch
    if (_chefsCache.isNotEmpty) {
      chefs = _chefsCache;
      isLoadingChefs = false;
    } else {
      fetchChefsWithRetry();
    }
    if (_producersCache.isNotEmpty) {
      producers = _producersCache;
      isLoadingProducers = false;
    } else {
      fetchProducers();
    }
  }

  // --- Fetch Chefs Logic ---
  Future<void> fetchChefs() async {
    if (_isFetchingChefs) return; // Prevent overlapping fetches
    if (mounted) {
      setState(() {
        _isFetchingChefs = true;
        isLoadingChefs = true; // Show loading indicator
      });
    }
    final url = '$apibaseurl/rr/rchefs';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 10));

      List<dynamic> chefsList = []; // Initialize outside conditional blocks

      if (mounted && response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Handle both direct list and nested map responses
        if (responseData is List) {
          chefsList = responseData.asMap().entries.map((entry) {
            final index = entry.key;
            final chef = entry.value;
            return _mapChefData(chef, index);
          }).toList();
        } else if (responseData is Map<String, dynamic> &&
            responseData['data'] != null && responseData['data'] is List) {
          chefsList = (responseData['data'] as List).asMap().entries.map((entry) {
            final index = entry.key;
            final chef = entry.value;
            return _mapChefData(chef, index);
          }).toList();
        } else {
           print('Unexpected response format for chefs: $responseData');
           chefsList = ChefData.chefs; // Fallback if format is wrong
        }
      } else {
         // Use fallback for non-200 status codes as well
        chefsList = ChefData.chefs;
        print('Failed to load chefs. Status code: ${response.statusCode}. Using default list.');
        // showCustomSnackBar(context, 'Failed to load chefs. Using default list.');
      }

      if (mounted) {
        setState(() {
          chefs = chefsList;
          _chefsCache = chefsList; // Update cache
        });
      }
    } on TimeoutException {
       if (mounted) {
         setState(() {
           chefs = ChefData.chefs; // Fallback on timeout
         });
       }
       print('Chef fetch timed out. Using default list.');
       // showCustomSnackBar(context, 'Chef request timed out. Using default list.');
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          chefs = ChefData.chefs; // Fallback to static data on any other error
        });
      }
      print('Error fetching chefs: $e');
      if(mounted) showCustomSnackBar(context, 'Unable to load chefs. Using default list.');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingChefs = false; // Always stop loading indicator
          _isFetchingChefs = false; // Reset fetching flag
        });
      }
    }
  }

  // Helper to map chef data consistently
  Map<String, dynamic> _mapChefData(dynamic chef, int index) {
      // Ensure chef is a Map
    if (chef is! Map<String, dynamic>) {
      print('Warning: Expected chef data to be a Map, but got ${chef.runtimeType}');
      // Return a default placeholder chef using data from ChefData if possible, or hardcoded defaults
      var fallbackChef = ChefData.chefs.firstWhere((c) => c['name'] == 'Default Chef', orElse: () => ChefData.chefs[0]);
       return {
          'image': fallbackChef['image'] ?? 'assets/images/placeholderchef.jpeg',
          'name': fallbackChef['name'] ?? 'Unknown Chef $index',
          'price': fallbackChef['price'] ?? 0.0,
          'rating': fallbackChef['rating'] ?? 0.0,
          'location': fallbackChef['location'] ?? 'Unknown Location',
          'chefid': fallbackChef['chefid'] ?? index, // Use default chefid or index
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
        showCustomSnackBar(context, 'Failed to load chefs after multiple attempts.');
     }
  }


  // --- Fetch Producers Logic ---
  Future<void> fetchProducers() async {
    if (_isFetchingProducers || !mounted) return; // Prevent overlapping fetches or running if disposed
    setState(() {
      _isFetchingProducers = true;
      isLoadingProducers = true; // Show loading indicator
    });
    final url = '$apibaseurl/rr/rproducers';
    try {
      final response = await http.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      }).timeout(Duration(seconds: 10));

      if (mounted) { // Check if widget is still in the tree before processing response
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          List<dynamic> producerRawList = [];

          if (responseData is List) {
            producerRawList = responseData;
          } else if (responseData is Map<String, dynamic> && responseData['data'] is List) {
            producerRawList = responseData['data'];
          } else {
            print('Unexpected response format for producers: $responseData');
            // Keep producers list empty or assign a default empty list
            producers = [];
            throw Exception('Unexpected response format for producers');
          }

          final mappedProducers = producerRawList.map((producer) {
             // Ensure producer is a Map
             if (producer is! Map<String, dynamic>) {
               print('Warning: Expected producer data to be a Map, but got ${producer.runtimeType}');
                // Return a default placeholder producer
                 return {
                    'producer_id': -1, // Default ID
                    'name': 'Unknown Producer',
                    'image': 'assets/images/producerHolder.png',
                    'Location': 'Unknown Location', // Ensure keys match expected usage
                    'Rating': 0.0,
                 };
             }
             // Proceed with mapping if it's a Map
            final name = (producer['name'] != null && producer['name'].toString().trim().isNotEmpty)
                ? producer['name'].toString()
                : 'Unknown Producer';
            final image = (producer['image'] != null && producer['image'].toString().trim().isNotEmpty)
                ? producer['image'].toString()
                : 'assets/images/producerHolder.png'; // Default placeholder
            final location = (producer['location'] != null && producer['location'].toString().trim().isNotEmpty)
                ? producer['location'].toString()
                : 'Unknown Location'; // Default location text
            final rating = producer['rating'] != null
                ? double.tryParse(producer['rating'].toString()) ?? 0.0
                : 0.0;
            // IMPORTANT: Ensure 'producer_id' exists and provide a fallback
            final id = producer['producer_id'] ?? DateTime.now().millisecondsSinceEpoch; // Use timestamp as fallback ID

            return {
              'producer_id': id,
              'name': name,
              'image': image,
              'Location': location, // Using CamelCase 'Location' as key (match usage in _buildProducerList)
              'Rating': rating,     // Using CamelCase 'Rating' as key (match usage in _buildProducerList)
            };
          }).toList();

          setState(() {
            producers = mappedProducers;
            _producersCache = mappedProducers; // Update cache
          });
        } else {
          setState(() {
            producers = []; // Fallback to empty list on non-200 status
          });
          print('Failed to load producers. Status code: ${response.statusCode}');
          showCustomSnackBar(context, 'Failed to load producers. Please try again.');
        }
      }
    } on TimeoutException {
       if (mounted) {
        setState(() {
          producers = []; // Fallback on timeout
        });
        print('Producer fetch timed out.');
        showCustomSnackBar(context, 'Producer request timed out.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          producers = []; // Fallback to empty list on error
        });
        print('Error fetching producers: $e');
        showCustomSnackBar(context, 'Unable to load producers. An error occurred.');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingProducers = false; // Always stop loading indicator
          _isFetchingProducers = false; // Reset fetching flag
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
      isFavorite = !isFavorite; // Toggle local state AFTER updating shared state
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
        selectedproducer: null,    // Ensure producer is null
        meal: widget.meal, bestservedwith: [],         // Pass the full meal data
      );
      isInCart = true; // Ensure cart status reflects the addition/update
      // --- End ShoppingCart ---
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
      if (!producerWithId.containsKey('producer_id') && producerWithId.containsKey('id')) {
        producerWithId['producer_id'] = producerWithId['id'];
      }
      selectedProducer = producerWithId;
      selectedChef = null; // Deselect chef
      isChefSelected = false; // Update the selection state for UI

      // Always add/update the item. The addItem method in cart.dart handles replacement.
       ShoppingCart.addItem(
        mealTitle,
        price,
        selectedchef: null,            // Ensure chef is null
        selectedproducer: selectedProducer, // Pass the newly selected producer
        meal: widget.meal, bestservedwith: [],             // Pass the full meal data
      );
       isInCart = true; // Ensure cart status reflects the addition/update
    });
     // --- End ShoppingCart ---
    showCustomSnackBar(context, '${producer['name']} selected!');
    Navigator.pop(context); // Close the bottom sheet after selection
  }


  void _toggleCart(String title) {
     // Check if a chef or producer is selected *before* toggling cart status for the main item
    if (selectedChef == null && selectedProducer == null && !isInCart) { // Only prevent adding, allow removal
       showCustomSnackBar(context, 'Please select a Cooked or Fresh option first!');
       return; // Prevent adding to cart without selection
    }

    // --- Use the imported (shared) ShoppingCart ---
    setState(() {
      if (isInCart) {
        ShoppingCart.removeItemFromCart(title);
        isInCart = false;
        // Clear local selection when removing from cart
        selectedChef = null;
        selectedProducer = null;
        // Optional: Reset isChefSelected to default (e.g., true) if desired
        isChefSelected = true;
        showCustomSnackBar(context, '$title removed from cart!');
      } else {
        // Add item (chef/producer MUST be selected due to check above)
         double price = _parsePrice(widget.meal['Price']);

         ShoppingCart.addItem(
          title,
          price,
          selectedchef: selectedChef, // Will be null if producer is selected
          selectedproducer: selectedProducer, // Will be null if chef is selected
          meal: widget.meal, bestservedwith: [],
        );
        isInCart = true;
        showCustomSnackBar(context, '$title added to cart!');
      }
    });
     // --- End ShoppingCart ---
  }


  // Simplified complementary item handling - assumes they are added independently
  void _toggleComplementary(String title, int index, String imageUrl) {
      double complementaryPrice = 2.00; // Example price

       // --- Use the imported (shared) ShoppingCart ---
       // Check if the complementary item is already in the cart
       bool isComplementaryInCart = ShoppingCart.getItems().any((item) => item['title'] == title);

       setState(() { // Update local state for the checkmark icon
         complementaryInCartStatus[index] = !isComplementaryInCart;

         if (isComplementaryInCart) {
           ShoppingCart.removeItemFromCart(title); // Remove from shared cart
           showCustomSnackBar(context, '$title removed from cart!');
         } else {
           // Add the complementary item as a separate cart entry
           ShoppingCart.addItem(
             title,
             complementaryPrice,
             // Complementary items don't have chef/producer selected *in this context*
             // Pass minimal required info, including image for the cart display
             meal: {'image_link': imageUrl, 'meal_name': title, 'price': complementaryPrice}, bestservedwith: [],
           ); // Add to shared cart
           showCustomSnackBar(context, '$title added to cart!');
         }
       });
        // --- End ShoppingCart ---
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
      } else if (imageUrl.contains('drive.google.com') && imageUrl.contains('/d/')) {
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
    final mealDescription = widget.meal['Meal_description'] ?? 'No description available.';
    final List<String> ingredients = _parseListFromString(widget.meal['Ingredients']);
    final List<String> complementaries = _parseListFromString(widget.meal['Complementary_dishes']);
    final List<String> complementaryImages = _parseListFromString(widget.meal['complementary_images']); // Keep snake_case (added locally)

    // Initialize complementaryInCartStatus based on actual cart state (more reliable)
    // --- Use imported (shared) ShoppingCart ---
     complementaryInCartStatus = List.generate(complementaries.length, (index) {
       final title = complementaries[index];
       return ShoppingCart.getItems().any((item) => item['title'] == title);
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
        displayColor: kColorTextPrimary
    );

    return Theme(
      data: Theme.of(context).copyWith(textTheme: textTheme),
      child: Scaffold(
        appBar: AppBar(
          title: Text(mealTitle, style: GoogleFonts.poppins()),
          foregroundColor: Colors.white,
          backgroundColor: kColorPrimaryDark,
          elevation: 2,
          actions: [
            IconButton(
              tooltip: 'View Favorites',
              icon: Icon(Icons.favorite),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => FavoritesScreen()))
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
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (context) => ShoppingCartScreen()))
                      .then((_) => setState(() {
                            var currentItemInCart = ShoppingCart.getItems().firstWhere(
                                (item) => item['title'] == mealTitle,
                                orElse: () => {},
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
                            complementaryInCartStatus = List.generate(complementaries.length, (index) {
                                final title = complementaries[index];
                                return ShoppingCart.getItems().any((item) => item['title'] == title);
                             });
                        })),
                ),
                if (ShoppingCart.getItems().isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '${ShoppingCart.getItems().length}',
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 10),
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
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Meal Image ---
                Hero(
                  tag: 'meal-${widget.meal['Meal_id'] ?? mealTitle}',
                  flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                    // Use a scale+fade transition for both directions
                    final Widget heroWidget = (flightDirection == HeroFlightDirection.push)
                        ? toHeroContext.widget
                        : fromHeroContext.widget;
                    return ScaleTransition(
                      scale: animation.drive(Tween<double>(begin: 0.95, end: 1.0).chain(CurveTween(curve: Curves.easeInOut))),
                      child: FadeTransition(
                        opacity: animation,
                        child: heroWidget,
                      ),
                    );
                  },
                  child: Container(
                    height: 250, width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_cardCornerRadius),
                      boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.15), spreadRadius: 1, blurRadius: 5, offset: Offset(0, 2)) ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_cardCornerRadius),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        placeholder: (context, url) => Center(child: CircularProgressIndicator(color: kColorPrimary)),
                        errorWidget: (context, url, error) => Image.asset('assets/images/cover.png', fit: BoxFit.cover),
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
                       Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                           Text(mealTitle, style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.bold, color: kColorPrimaryDark)),
                           SizedBox(height: 6),
                           Text(mealDescription, style: GoogleFonts.poppins(fontSize: 15, height: 1.4, color: kColorTextSecondary)),
                           SizedBox(height: 8),
                           Text('Price: \$${price.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: kColorPrimary)),
                         ])),
                         SizedBox(width: 10),
                         Column( children: [
                           Tooltip(
                             message: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                             child: IconButton(
                               icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: kColorPrimary),
                               iconSize: 30,
                               padding: EdgeInsets.zero,
                               constraints: BoxConstraints(),
                               onPressed: () => _toggleFavorite(mealTitle),
                             ),
                           ),
                           SizedBox(height: 8),
                           Tooltip(
                             message: (isInCart && (selectedChef != null || selectedProducer != null))
                               ? 'Remove from Cart'
                               : 'Add to Cart',
                             child: IconButton(
                               icon: Icon(
                                 (isInCart && (selectedChef != null || selectedProducer != null))
                                   ? Icons.shopping_cart
                                   : Icons.add_shopping_cart,
                                 color: (isInCart && (selectedChef != null || selectedProducer != null))
                                   ? kColorPrimary
                                   : kColorTextSecondary,
                               ),
                               iconSize: 30,
                               padding: EdgeInsets.zero,
                               constraints: BoxConstraints(),
                               onPressed: () => _toggleCart(mealTitle),
                             ),
                           ),
                         ]),
                     ]
                  ),
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
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorPrimaryDark),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.kitchen_outlined, size: 18),
                            label: Text('Cooked', style: GoogleFonts.poppins()),
                            onPressed: () {
                              setState(() { isChefSelected = true; });
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (context) => _buildChefSelectionSheet(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isChefSelected ? kColorPrimary : kColorSurface,
                              foregroundColor: isChefSelected ? kColorSurface : kColorTextSecondary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_buttonCornerRadius)),
                              side: isChefSelected ? null : BorderSide(color: kColorDivider),
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
                               setState(() { isChefSelected = false; });
                               showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (context) => _buildProducerSelectionSheet(),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !isChefSelected ? kColorPrimary : kColorSurface,
                              foregroundColor: !isChefSelected ? kColorSurface : kColorTextSecondary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_buttonCornerRadius)),
                              side: !isChefSelected ? null : BorderSide(color: kColorDivider),
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
              ],
            ),
          ),
        ),
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
       return data.split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
     }
     // If it's neither a List nor a String, return empty
     return [];
  }

  Widget _buildBestServedWith(List<String> complementaries, List<String> complementaryImages) {
     if (complementaries.isEmpty) {
       return SizedBox.shrink();
     }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Best Served With:', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorPrimaryDark)),
          SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: complementaries.length,
              itemBuilder: (context, index) {
                final itemTitle = complementaries[index];
                String rawImageUrl = (index < complementaryImages.length && complementaryImages[index].isNotEmpty)
                    ? complementaryImages[index]
                    : 'assets/images/cover.png';
                final String displayImageUrl = _formatImageUrl(rawImageUrl);

                bool currentInCartStatus = complementaryInCartStatus[index];

                return GestureDetector(
                  onTap: () {
                    _toggleComplementary(itemTitle, index, displayImageUrl);
                  },
                  child: Container(
                    width: 110,
                    margin: EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_buttonCornerRadius),
                      color: kColorSurface,
                      boxShadow: [BoxShadow(color: kColorDivider.withOpacity(0.3), blurRadius: 4, offset: Offset(0, 2))],
                      border: Border.all(color: kColorPrimaryLight.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(_buttonCornerRadius)),
                          child: CachedNetworkImage(
                            imageUrl: displayImageUrl,
                            width: 110,
                            height: 75,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              height: 75,
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kColorPrimary)),
                            ),
                            errorWidget: (context, url, error) => Image.asset('assets/images/cover.png', height: 75, width: 110, fit: BoxFit.cover),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(itemTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: kColorPrimaryDark, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Row(
                                children: [
                                  Expanded(child: Text('\$2.00', style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 12))),
                                  Icon(
                                    currentInCartStatus ? Icons.check_circle : Icons.add_circle_outline,
                                    color: currentInCartStatus ? kColorSuccess : kColorPrimary,
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
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)),
       color: kColorSurface,
       child: InkWell(
         onTap: () => setState(() { _ingredientsExpanded = !_ingredientsExpanded; }),
         borderRadius: BorderRadius.circular(_cardCornerRadius),
         child: Padding(
           padding: EdgeInsets.all(_verticalPadding * 0.8),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text('Ingredients', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorPrimaryDark)),
               SizedBox(height: 10),
               Wrap(
                 spacing: 8.0, runSpacing: 4.0,
                 children: (_ingredientsExpanded ? ingredients : ingredients.take(6)).map((ingredient) {
                   return Chip(
                     label: Text(ingredient, style: GoogleFonts.poppins(color: kColorPrimaryDark, fontWeight: FontWeight.w500)),
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
                 Center(child: Icon(_ingredientsExpanded ? Icons.expand_less : Icons.expand_more, color: kColorPrimary)),
               ]
             ],
           ),
         ),
       ),
     );
   }

   Widget _buildPropertiesSection() {
    final healthGoal = widget.meal['Goal']?.toString() ?? 'General Health';
    final List<String> allergens = _parseListFromString(widget.meal['Allergies']);
    final List<String> diseasesManaged = _parseListFromString(widget.meal['Disease_management']);

    bool hasHealthGoal = healthGoal != 'General Health' && healthGoal.isNotEmpty;
    bool hasAllergens = allergens.isNotEmpty;
    bool hasDiseases = diseasesManaged.isNotEmpty;

    if (!hasHealthGoal && !hasAllergens && !hasDiseases) return SizedBox.shrink();

    return Card(
      elevation: _cardElevation,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)),
      color: kColorSurface,
      child: Padding(
        padding: EdgeInsets.all(_verticalPadding * 0.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Health Information', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorPrimaryDark)),
            SizedBox(height: 12),
            Wrap( spacing: 8.0, runSpacing: 8.0, children: [
                 if (hasHealthGoal) _buildPropertyChip(Icons.track_changes, 'Health Goal', healthGoal),
                 if (hasAllergens) _buildPropertyChip(Icons.warning_amber_rounded, 'Allergens', allergens.join(', ')),
                 if (hasDiseases) _buildPropertyChip(Icons.healing, 'Helps Manage', diseasesManaged.join(', ')),
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
      label: Text(label, style: GoogleFonts.poppins(color: kColorPrimaryDark, fontWeight: FontWeight.w500)),
      backgroundColor: kColorPrimaryLight.withOpacity(0.2),
      onPressed: () { _showPopup(context, label, data); },
      tooltip: data,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: kColorPrimary.withOpacity(0.3))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(title, style: TextStyle(color: Colors.teal[900], fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ListBody(
              children: content.split(',').map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(item.trim(), style: TextStyle(color: Colors.teal[800], fontSize: 15)),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold)),
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
      case 'beginner': return 0.25;
      case 'intermediate': return 0.60;
      case 'advanced': return 1.0;
      default: return 0.60;
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
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)),
     color: kColorSurface,
     child: Padding(
       padding: EdgeInsets.all(_verticalPadding * 0.8),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text('Cooking Info', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorPrimaryDark)),
           SizedBox(height: 12),

            if (skillLevel != null) ...[
             Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                 Text('Skill Level:', style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 14)),
                 Text(skillLevel, style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
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
             Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Prep Time:', style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 14)),
                  Text('$prepTime', style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
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
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: _horizontalPadding,
        right: _horizontalPadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + _verticalPadding,
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: kBottomSheetBgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Select a Chef", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: kColorPrimaryDark)),
          ),
          Divider(color: kColorDivider),
          Flexible(
            child: isLoadingChefs
                ? Center(key: ValueKey('chef_loading'), child: CircularProgressIndicator(color: kColorPrimary))
                : (chefs.isEmpty
                    ? Center(key: ValueKey('chef_empty'), child: Text("No chefs available.", style: GoogleFonts.poppins(color: kColorTextSecondary)))
                    : _buildChefList()
                  ),
          ),
        ],
      ),
    );
 }

 // --- Producer Selection Sheet ---
 Widget _buildProducerSelectionSheet() {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: _horizontalPadding,
        right: _horizontalPadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + _verticalPadding,
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: kBottomSheetBgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Select a Producer", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: kColorPrimaryDark)),
          ),
          Divider(color: kColorDivider),
          Flexible(
            child: isLoadingProducers
                ? Center(key: ValueKey('producer_loading'), child: CircularProgressIndicator(color: kColorPrimary))
                : (producers.isEmpty
                    ? Center(key: ValueKey('producer_empty'), child: Text("No fresh producers available.", style: GoogleFonts.poppins(color: kColorTextSecondary)))
                    : _buildProducerList()
                  ),
          ),
        ],
      ),
    );
 }


  // --- Chef List Builder (for Bottom Sheet) ---
 Widget _buildChefList() {
    return ListView.builder(
      itemCount: chefs.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final chef = chefs[index];
        final chefName = chef['name'] ?? 'Unknown Chef';
        final chefImage = _formatImageUrl(chef['image'] ?? 'assets/images/placeholderchef.jpeg');
        final chefRating = (chef['rating'] as double?) ?? 0.0;
        final chefLocation = chef['location'] ?? 'Unknown Location';
        final chefId = chef['chefid'];

        final bool isSelected = selectedChef != null && selectedChef!['chefid'] == chefId;

        return Card(
          elevation: isSelected ? 3.0 : _cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonCornerRadius),
            side: BorderSide(color: isSelected ? kColorPrimary : kColorDivider, width: isSelected ? 2.0 : 0.8),
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
                      width: 50, height: 50, fit: BoxFit.cover,
                      placeholder: (context, url) => Container(width: 50, height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kColorPrimary))),
                      errorWidget: (context, url, error) => Image.asset('assets/images/placeholderchef.jpeg', width: 50, height: 50, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(chefName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: kColorPrimary)),
                        SizedBox(height: 3),
                        Row(children: List.generate(5, (i) => Icon(
                          i < chefRating.round() ? Icons.star : Icons.star_border,
                          color: kColorPrimary, // Always teal
                          size: 15))),
                        SizedBox(height: 3),
                        Row(children: [
                            Icon(Icons.location_on_outlined, color: kColorPrimary, size: 13), SizedBox(width: 4),
                            Expanded(child: Text(getShortLocation(chefLocation), style: GoogleFonts.poppins(fontSize: 12, color: kColorPrimary), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 28),
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
    return ListView.builder(
      itemCount: producers.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final producer = producers[index];
        final producerName = producer['name'] ?? 'Unknown Producer';
        final producerImage = _formatImageUrl(producer['image'] ?? 'assets/images/producerHolder.png');
        final producerLocation = producer['Location'] ?? 'NA';
        final producerRating = (producer['Rating'] as double?) ?? 0.0;
        final producerId = producer['producer_id'];

        final bool isSelected = selectedProducer != null && selectedProducer!['producer_id'] == producerId;

        return Card(
          elevation: isSelected ? 3.0 : _cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonCornerRadius),
            side: BorderSide(color: isSelected ? kColorPrimary : kColorDivider, width: isSelected ? 2.0 : 0.8),
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
                      width: 50, height: 50, fit: BoxFit.cover,
                      placeholder: (context, url) => Container(width: 50, height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kColorPrimary))),
                      errorWidget: (context, url, error) => Image.asset('assets/images/producerHolder.png', width: 50, height: 50, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(producerName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: kColorPrimary)),
                        SizedBox(height: 3),
                        Row(children: List.generate(5, (i) => Icon(
                          i < producerRating.round() ? Icons.star : Icons.star_border,
                          color: kColorPrimary, // Always teal
                          size: 15))),
                        SizedBox(height: 3),
                        Row(children: [
                            Icon(Icons.location_on_outlined, color: kColorPrimary, size: 13), SizedBox(width: 4),
                            Expanded(child: Text(getShortLocation(producerLocation), style: GoogleFonts.poppins(fontSize: 12, color: kColorPrimary), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 28),
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
   final image = _formatImageUrl(data['image'] ?? (isChef ? 'assets/images/placeholderchef.jpeg' : 'assets/images/producerHolder.png'));
   final location = getShortLocation(data[isChef ? 'location' : 'Location'] ?? 'Unknown Location'); // Use correct location key
   final rating = (data[isChef ? 'rating' : 'Rating'] as double?) ?? 0.0; // Use correct rating key
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
            Text(typeLabel, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            SizedBox(height: 8),
           Row(
             children: [
               ClipOval(
                 child: CachedNetworkImage(
                   imageUrl: image,
                   width: 45, height: 45, fit: BoxFit.cover,
                   placeholder: (context, url) => Container(width: 45, height: 45, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal))),
                   errorWidget: (context, url, error) => Image.asset(isChef ? 'assets/images/placeholderchef.jpeg' : 'assets/images/producerHolder.png', width: 45, height: 45, fit: BoxFit.cover),
                 ),
               ),
               const SizedBox(width: 10),
               Expanded(
                 child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                     Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[900])),
                     SizedBox(height: 2),
                     Row(children: List.generate(5, (i) => Icon( i < rating.round() ? Icons.star : Icons.star_border, color: i < rating.round() ? Colors.teal : Colors.grey, size: 14))),
                     SizedBox(height: 2),
                     Row(children: [
                         Icon(Icons.location_on, color: Colors.grey[600], size: 12), SizedBox(width: 3),
                         Expanded(child: Text(location, style: TextStyle(fontSize: 12, color: Colors.grey[700]), overflow: TextOverflow.ellipsis)),
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
    int cartItemCount = ShoppingCart.getItems().length; // Get total items for badge
    // --- End ShoppingCart ---

    return Container(
      padding: EdgeInsets.fromLTRB(_horizontalPadding, 10.0, _horizontalPadding, _verticalPadding),
      decoration: BoxDecoration(
        color: kColorSurface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), spreadRadius: 0, blurRadius: 4, offset: Offset(0, -1))],
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
                Navigator.push(context, MaterialPageRoute(builder: (context) => ShoppingCartScreen()))
                    .then((_) => setState(() {
                          var currentItemInCart = ShoppingCart.getItems().firstWhere(
                              (item) => item['title'] == (widget.meal['Meal_name'] ?? ''),
                              orElse: () => {},
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
                          final complementaries = _parseListFromString(widget.meal['Complementary_dishes']);
                          complementaryInCartStatus = List.generate(complementaries.length, (index) {
                            final title = complementaries[index];
                            return ShoppingCart.getItems().any((item) => item['title'] == title);
                          });
                        }));
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: cartItemCount > 0 ? kColorPrimaryDark : Colors.grey.shade400,
          foregroundColor: kColorSurface,
          padding: EdgeInsets.symmetric(vertical: 14),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_buttonCornerRadius)),
          minimumSize: Size(double.infinity, 50),
        ),
      ),
    );
  }
}


// --- Custom SnackBar Utility ---
void showCustomSnackBar(BuildContext context, String message) {
  // Check if the widget associated with the context is still mounted
  if (!Navigator.of(context).mounted) return;

   // Ensure context is associated with a ScaffoldMessenger
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  if (scaffoldMessenger == null) {
     print("Warning: Could not find ScaffoldMessenger to show SnackBar.");
     return;
  }


  scaffoldMessenger.hideCurrentSnackBar(); // Hide previous snackbar
  final snackBar = SnackBar(
    content: Text(message, style: TextStyle(color: Color(0xFF212121))), // Use explicit color
    duration: Duration(seconds: 2),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(15, 60, 15, 0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    backgroundColor: Color(0xFFB2DFDB), // Lighter teal
    action: SnackBarAction(
      label: 'OK',
      textColor: Color(0xFF004D40), // Dark teal
      onPressed: () {
        scaffoldMessenger.hideCurrentSnackBar();
      },
    ),
  );
  scaffoldMessenger.showSnackBar(snackBar);
}


// --- *** DELETED THE DUPLICATE ShoppingCart and Favorites CLASSES *** ---
// These are now correctly imported from cart.dart
