//cspell:disable
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting
import 'package:zinzi/allmeals.dart';
import 'package:zinzi/app_drawer_unified.dart'
    as drawer; // Import the unified AppDrawer widget with prefix

import 'package:google_fonts/google_fonts.dart';
import 'package:zinzi/checkout.dart';
import 'app_drawer_unified.dart'; // May be redundant if drawer.AppDrawer is used

// ***************************************************************
// *          SINGLE SOURCE OF TRUTH FOR CART & FAVORITES        *
// ***************************************************************

// Shopping Cart Management - Defined ONCE here
class ShoppingCart {
  // Use static list - THIS IS THE SHARED STATE
  // Items can be meals ('type': 'meal') or gigs ('type': 'gig')
  static List<Map<String, dynamic>> items = [];

  // --- NEW: ValueNotifier for reactivity ---
  static final ValueNotifier<List<Map<String, dynamic>>> itemsNotifier =
      ValueNotifier(items);

  // --- NEW: Helper to find item index ---
  static int findItemIndex(String title) {
    return items
        .indexWhere((item) => item['type'] == 'meal' && item['title'] == title);
  }

  // Adds or Updates a MEAL item in the cart
  static void addItem(
    String title,
    double pricePerUnit, {
    int quantity = 1,
    Map<String, dynamic>? selectedchef,
    Map<String, dynamic>? selectedproducer,
    required Map<String, dynamic> meal,
    required List<Map<String, dynamic>> bestservedwith,
    // Price breakdown fields
    double? basePrice,
    double? complementaryTotal,
    // Bulk order fields
    bool isBulkOrder = false,
    DateTime? planStartDate,
    DateTime? planEndDate,
    String? planFrequency,
    Set<String>? planSelectedDays,
  }) {
    const itemType = 'meal';
    final hasChef = selectedchef != null && selectedchef.isNotEmpty;
    final hasProducer = selectedproducer != null && selectedproducer.isNotEmpty;

    // Calculate complementary total if not provided
    final calculatedComplementaryTotal = complementaryTotal ?? 
        (bestservedwith.fold<double>(0.0, (double sum, item) {
          final price = item['price'];
          return sum + (price is num ? price.toDouble() : 0.0);
        }));
    
    // Calculate base price if not provided (for backward compatibility)
    final calculatedBasePrice = basePrice ?? 
        (meal['Price'] != null && meal['Price'] is num 
            ? (meal['Price'] as num).toDouble() 
            : 0.0);

    // Calculate chef price if selected (hasChef ensures selectedchef is not null)
    final calculatedChefPrice = hasChef 
        ? _parsePrice(selectedchef['price'])
        : 0.0;

    // Calculate total price (base + chef + complementary)
    final calculatedTotalPrice = calculatedBasePrice + calculatedChefPrice + calculatedComplementaryTotal;

    // Use the helper method
    final existingItemIndex = findItemIndex(title);

    final Map<String, dynamic> newItemData = {
      'title': title,
      'price': calculatedTotalPrice, // Total price (base + complementary)
      'basePrice': calculatedBasePrice, // Base meal price only
      'complementaryTotal': calculatedComplementaryTotal, // Total of all complements
      'complementaryItems': bestservedwith.map((item) => {
        'name': item['name'] ?? '',
        'price': item['price'] is num ? (item['price'] as num).toDouble() : 0.0,
        'image': item['image'] ?? '',
      }).toList(),
      'quantity': quantity,
      'selectedchef': hasChef ? selectedchef : null,
      'selectedproducer': hasProducer ? selectedproducer : null,
      'meal': meal,
      'bestservedwith': bestservedwith,
      'type': itemType,
      // Bulk order details
      'isBulkOrder': isBulkOrder,
      'planStartDate': planStartDate?.toIso8601String(),
      'planEndDate': planEndDate?.toIso8601String(),
      'planFrequency': planFrequency,
      'planSelectedDays': planSelectedDays?.toList(),
    };

    if (existingItemIndex != -1) {
      // Item exists - Update it completely
      items[existingItemIndex] = newItemData;
      print("Updated item in cart: $title");
    } else {
      // Item is new - Add it
      items.add(newItemData);
      print("Added new item to cart: $title");
    }

    // --- Notify listeners ---
    itemsNotifier.value = List.from(items);

    // Debug log
    // print("Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
  }

  static List<Map<String, dynamic>> getItems() {
    // Return a modifiable list? No, keep it unmodifiable for safety.
    // If UI needs modification, it should use ValueNotifier.
    return List.unmodifiable(items);
  }

  // --- UPDATED: totalPrice calculation ---
  // Assumes item['price'] is the price per unit (meal + selected complementaries)
  // Helper method to parse price from dynamic value
  static double _parsePrice(dynamic price) {
    if (price == null) return 0.0;
    if (price is num) return price.toDouble();
    if (price is String) {
      // Remove any non-numeric characters except decimal point
      final numericString = price.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(numericString) ?? 0.0;
    }
    return 0.0;
  }
  // **** START FIX: Correctly calculate total price for bulk and regular orders ****
  static double get totalPrice {
    return items.fold(0.0, (sum, item) {
      double itemTotal = 0.0;
      if (item['type'] == 'meal') {
        // Get base price, chef price, and complementary total
        final basePrice = (item['basePrice'] as num?)?.toDouble() ?? 0.0;
        final chefPrice = (item['selectedchef']?['price'] as num?)?.toDouble() ?? 0.0;
        final complementaryTotal = (item['complementaryTotal'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
        
        // Calculate price per unit including all components
        final pricePerUnit = basePrice + chefPrice + complementaryTotal;
        
        // Check if it's a bulk order
        final bool isBulkOrder = item['isBulkOrder'] as bool? ?? false;
        if (isBulkOrder) {
          // For bulk orders, total is (total_price_per_meal * qty_per_day * num_of_days)
          final planDays = item['planSelectedDays'] as List?;
          final numberOfDays = planDays?.length ?? 0;
          itemTotal = pricePerUnit * quantity * numberOfDays;
        } else {
          // For regular orders, it's just (total_price_per_meal * quantity)
          itemTotal = pricePerUnit * quantity;
        }
      } else if (item['type'] == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        itemTotal = (gigDetails['price'] as num?)?.toDouble() ?? 0.0;
      }
      return sum + itemTotal;
    });
  }
  // **** END FIX ****

  // --- NEW: Get specific item quantity ---
  static int getItemQuantity(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      return (items[index]['quantity'] as num?)?.toInt() ?? 1;
    }
    return 0; // Return 0 if item not in cart
  }

  // --- NEW: Check if item is bulk order ---
  static bool isBulkOrder(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      return items[index]['isBulkOrder'] as bool? ?? false;
    }
    return false;
  }

  // --- NEW: Get plan details ---
  static DateTime? getPlanStartDate(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      final dateString = items[index]['planStartDate'] as String?;
      return dateString != null ? DateTime.tryParse(dateString) : null;
    }
    return null;
  }

  static DateTime? getPlanEndDate(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      final dateString = items[index]['planEndDate'] as String?;
      return dateString != null ? DateTime.tryParse(dateString) : null;
    }
    return null;
  }

  static String? getPlanFrequency(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      return items[index]['planFrequency'] as String?;
    }
    return null;
  }

  static Set<String>? getPlanSelectedDays(String title) {
    final index = findItemIndex(title);
    if (index != -1) {
      final daysList = items[index]['planSelectedDays'] as List?;
      // Safely convert list elements to string before creating the set
      return daysList?.map((e) => e.toString()).toSet();
    }
    return null;
  }
  // --- End NEW Getters ---

  static void clearCart() {
    items.clear();
    print("Cart Cleared");
    // --- Notify listeners ---
    itemsNotifier.value = List.from(items);
  }

  static void removeItemByIndex(int index) {
    if (index >= 0 && index < items.length) {
      final removedItem = items.removeAt(index);
      String itemIdentifier;
      if (removedItem['type'] == 'meal') {
        itemIdentifier = removedItem['title'] ?? 'Unknown Meal';
      } else if (removedItem['type'] == 'gig') {
        final details =
            removedItem['gigDetails'] as Map<String, dynamic>? ?? {};
        final type = details['gig_type'] ?? 'Unknown Gig';
        final chefName = details['chef_name'];
        final producerName = details['producer_name'];
        if (chefName != null && chefName.isNotEmpty)
          itemIdentifier = '$type (Chef: $chefName)';
        else if (producerName != null && producerName.isNotEmpty)
          itemIdentifier = '$type (Producer: $producerName)';
        else
          itemIdentifier = type;
      } else {
        itemIdentifier = 'Unknown Item';
      }
      print("Removed item from cart at index $index: $itemIdentifier");
      // --- Notify listeners ---
      itemsNotifier.value = List.from(items);
      // print("Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
    } else {
      print("Attempted to remove item at invalid index: $index");
    }
  }

  static void updateMealQuantity(String title, int newQuantity) {
    // Use the helper method
    final existingItemIndex = findItemIndex(title);
    if (existingItemIndex != -1) {
      if (newQuantity > 0) {
        items[existingItemIndex]['quantity'] = newQuantity;
        print("Updated quantity for meal '$title' to $newQuantity");
        // --- Notify listeners ---
        itemsNotifier.value = List.from(items);
      } else {
        removeItemByIndex(
            existingItemIndex); // Remove if quantity <= 0 (removeItemByIndex notifies)
      }
    }
  }

  // Method to add a Gig
  static void addGig(Map<String, dynamic> gigDetails) {
    // Basic Validation... (remains the same)
    final userId = gigDetails['user_id'];
    final chefId = gigDetails['chef_id'];
    final producerId = gigDetails['producer_id'];
    final price = gigDetails['price'];
    final chefName = gigDetails['chef_name']; // Name is expected here now
    final producerName = gigDetails['producer_name'];

    if (userId == null) {
      print("Error adding gig: User ID is missing.");
      return;
    }
    if ((chefId == null && producerId == null) ||
        (chefId != null && producerId != null)) {
      print(
          "Error adding gig: Exactly one of chef_id or producer_id must be provided.");
      return;
    }
    if (price == null || price is! num || price <= 0) {
      print("Error adding gig: Valid price is missing.");
      return;
    }

    items.add({
      'type': 'gig',
      'gigDetails': gigDetails,
    });
    print(
        "Added new gig to cart: ${gigDetails['gig_type']} with Chef: $chefName, Producer: $producerName");
    // --- Notify listeners ---
    itemsNotifier.value = List.from(items);
    // print("Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
  }

  // Method to remove a specific list of items
  static void removeItems(List<Map<String, dynamic>> itemsToRemove) {
    if (itemsToRemove.isEmpty) return;
    int initialLength = items.length;
    // Use Set for efficient lookup if list is large, otherwise simple loop is fine
    int removedCount = 0;
    items.removeWhere((item) {
      // Check if the current item exists in the itemsToRemove list
      // This requires a reliable way to compare items (e.g., based on title or a unique ID)
      // Using identity check assumes the exact same map objects are passed.
      // A more robust check might be needed depending on how itemsToRemove is generated.
      bool shouldRemove = itemsToRemove.any((removeItem) =>
          item['type'] == removeItem['type'] &&
          ((item['type'] == 'meal' && item['title'] == removeItem['title']) ||
              (item['type'] == 'gig' &&
                  /* Compare relevant gig details */
                  item['gigDetails']?['booking_id'] ==
                      removeItem['gigDetails']?['booking_id']) // Example: Compare by a unique booking ID if available
          ));
      if (shouldRemove) removedCount++;
      return shouldRemove;
    });

    if (removedCount > 0) {
      print("Removed $removedCount item(s) from cart based on provided list.");
      // --- Notify listeners ---
      itemsNotifier.value = List.from(items);
      // print("Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
    } else {
      print(
          "No items removed. Items to remove might not have been found in the cart.");
    }
  }
} // End ShoppingCart Class

// ***************************************************************
// *                 FAVORITES MANAGEMENT                        *
// ***************************************************************

// Favorites Management - Defined ONCE here
class Favorites {
  static List<Map<String, dynamic>> items = [];
  // --- NEW: ValueNotifier for reactivity (Optional but good practice) ---
  static final ValueNotifier<List<Map<String, dynamic>>> favoritesNotifier =
      ValueNotifier(items);

  static void addItem(String title, double price, String image) {
    if (!items.any((item) => item['title'] == title)) {
      items.add({'title': title, 'price': price, 'image': image});
      print("Added item to favorites: $title");
      // --- Notify listeners ---
      favoritesNotifier.value = List.from(items);
    }
  }

  // Adds favorite item to the cart. NOTE: Requires a chef/producer selection later.
  static void addToCart(
      BuildContext context, String title, double price, String image) {
    // Adding from favorites - pass empty list for selected complementaries initially.
    // Chef/producer needs to be selected on the detail screen or cart screen.
    ShoppingCart.addItem(
      title,
      price, // Base price only
      selectedchef: null, // Not selected yet
      selectedproducer: null, // Not selected yet
      meal: {
        'Meal_name': title,
        'Price': price,
        'Image_link': image
      }, // Basic meal data
      bestservedwith: [], // No complementaries selected yet
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '$title added to cart! Select provider & options in cart or detail screen.'),
      duration: Duration(seconds: 3),
      backgroundColor: Colors.teal[700],
    ));
    // No need to call _refreshFavorites here, cart notifier handles cart UI updates.
  }

  static List<Map<String, dynamic>> getItems() {
    return List.unmodifiable(items);
  }

  static void clearFavorites() {
    items.clear();
    print("Favorites Cleared");
    // --- Notify listeners ---
    favoritesNotifier.value = List.from(items);
  }

  static void removeItem(String title) {
    int initialLength = items.length;
    items.removeWhere((item) => item['title'] == title);
    if (items.length < initialLength) {
      print("Removed item from favorites: $title");
      // --- Notify listeners ---
      favoritesNotifier.value = List.from(items);
    }
  }

  static bool isFavorite(String title) {
    return items.any((meal) => meal['title'] == title);
  }
} // End Favorites Class

// ***************************************************************
// *                      UI SCREENS                             *
// ***************************************************************

// Shopping Cart Screen UI
class ShoppingCartScreen extends StatefulWidget {
  @override
  _ShoppingCartScreenState createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  // Use ValueListenableBuilder in build method instead of manual refresh

  String _formatImageUrl(String? imageUrl) {
    imageUrl ??= 'assets/images/cover.png';
    if (imageUrl.startsWith('assets/')) return imageUrl;
    if (imageUrl.contains('drive.google.com/uc?export=view&id='))
      return imageUrl;
    if (imageUrl.contains('drive.google.com') && imageUrl.contains('/d/')) {
      final parts = imageUrl.split('/d/');
      if (parts.length > 1) {
        final idPart = parts[1].split('/')[0];
        if (idPart.isNotEmpty)
          return 'https://drive.google.com/uc?export=view&id=$idPart';
      }
    }
    if (imageUrl.startsWith('http://'))
      return 'https://${imageUrl.substring(7)}';
    if (!imageUrl.startsWith('https://')) {
      print(
          "Warning: Formatting potentially invalid image URL in cart: $imageUrl");
      return 'assets/images/cover.png'; // Fallback
    }
    return imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    // Use ValueListenableBuilder to react to cart changes
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ShoppingCart.itemsNotifier,
      builder: (context, cartItems, child) {
        final totalAmount =
            ShoppingCart.totalPrice; // Recalculate based on current items
        print("Building Cart Screen with ${cartItems.length} items.");

        return Scaffold(
          drawer: const drawer.AppDrawer(), // Use prefixed import
          appBar: AppBar(
            title: Text('Shopping Cart (${cartItems.length})',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.teal[800],
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(Icons.delete_sweep, size: 24),
                tooltip: 'Clear Cart',
                onPressed: cartItems.isNotEmpty
                    ? () => _confirmClearCart(context)
                    : null,
              ),
              IconButton(
                icon: Icon(Icons.help_outline, size: 24),
                tooltip: 'Cart Help',
                onPressed: () => _showHelpDialog(context),
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.teal.shade50,
                  Colors.teal.shade50,
                  Colors.white,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCartHeader(cartItems, totalAmount),
                Expanded(
                  child: cartItems.isEmpty
                      ? _buildEmptyCart()
                      : ListView.separated(
                          padding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          itemCount: cartItems.length,
                          separatorBuilder: (context, index) =>
                              SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            // Pass the specific item from the builder's snapshot
                            return _buildCartItemCard(
                                cartItems[index], index, context);
                          },
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
              _buildCheckoutButton(cartItems, totalAmount), // Pass totalAmount
        );
      },
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.teal[300]),
          SizedBox(height: 24),
          Text(
            'Your Cart is Empty',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: Colors.teal[800]),
          ),
          SizedBox(height: 12),
          Text(
            'Explore our menu or book a chef!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            icon: Icon(Icons.restaurant_menu),
            label: Text("Browse Menu"),
            onPressed: () {
              // Navigate to the AllMealsScreen or equivalent
              Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => AllMealsScreen()));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          )
        ],
      ),
    );
  }

  Widget _buildCartHeader(
      List<Map<String, dynamic>> cartItems, double totalAmount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Estimated Total:',
              style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          Text(
            'ugx ${totalAmount.toStringAsFixed(0)}', // Format without decimals
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(
      List<Map<String, dynamic>> cartItems, double totalAmount) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12) +
          EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom *
                  0.5), // Adjust for safe area
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, -2))
        ],
      ),
      child: ElevatedButton.icon(
        icon: Icon(Icons.lock_outline, size: 20),
        label: Text(
            'Checkout (${totalAmount.toStringAsFixed(0)} UGX)'),
        style: ElevatedButton.styleFrom(
            backgroundColor:
                cartItems.isNotEmpty ? Colors.teal[700] : Colors.grey,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48),
            padding: EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        onPressed: cartItems.isNotEmpty
            ? () => _handleCheckout(context, cartItems, totalAmount)
            : null, // Pass necessary data
      ),
    );
  }

  // Builds the card for EITHER a meal or a gig
  Widget _buildCartItemCard(
      Map<String, dynamic> item, int index, BuildContext context) {
    // Use a unique key based on item type and identifier
    Key itemKey;
    final String itemType = item['type'] ?? 'meal';

    if (itemType == 'meal') {
      final String title = item['title'] ?? 'unknown_meal_$index';
      itemKey = Key('meal_$title'); // Key based on meal title

      final int quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final double pricePerUnit =
          (item['price'] as num?)?.toDouble() ?? 0.0; // Price per unit
      final Map<String, dynamic>? chef =
          item['selectedchef'] as Map<String, dynamic>?;
      final Map<String, dynamic>? producer =
          item['selectedproducer'] as Map<String, dynamic>?;
      final Map<String, dynamic> meal =
          item['meal'] as Map<String, dynamic>? ?? {};
      // Use 'bestservedwith' from the cart item (these are the *selected* ones)
      final List<Map<String, dynamic>> selectedComplementaries =
          (item['bestservedwith'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final String imageUrl = _formatImageUrl(
          meal['Image_link'] ?? meal['image_link']); // Check both keys

      // **** START FIX: Correctly calculate itemTotal for bulk and regular orders ****
      final bool isBulk = item['isBulkOrder'] as bool? ?? false;
      final double chefPrice = (chef != null && chef['price'] != null)
          ? ShoppingCart._parsePrice(chef['price'])
          : 0.0;

      double itemTotal;
      // The price for one "unit" is the meal price, plus its complementaries, plus the chef fee.
      final pricePerSingleUnit = pricePerUnit + chefPrice;

      if (isBulk) {
        final planDays = item['planSelectedDays'] as List?;
        final numberOfDays = planDays?.length ?? 0;
        // The total cost for the plan is (price_per_unit * quantity_per_day * number_of_days).
        itemTotal = pricePerSingleUnit * quantity * numberOfDays;
      } else {
        // The total cost for a regular item is (price_per_unit * quantity).
        itemTotal = pricePerSingleUnit * quantity;
      }
      // **** END FIX ****

      String sourceInfo = '';
      if (chef != null && chef['name'] != null && chef['name'].isNotEmpty)
        sourceInfo = 'Cooked by: ${chef['name']}';
      else if (producer != null &&
          producer['name'] != null &&
          producer['name'].isNotEmpty)
        sourceInfo = 'From: ${producer['name']}';
      else if (chef != null && chef['chefid'] != null)
        sourceInfo = 'Cooked by: Chef ID ${chef['chefid']}'; // Use chefid
      else if (producer != null && producer['producer_id'] != null)
        sourceInfo =
            'From: Producer ID ${producer['producer_id']}'; // Use producer_id

      return _buildMealItemCardContent(
          context,
          index,
          title,
          quantity,
          pricePerUnit,
          itemTotal,
          imageUrl,
          sourceInfo,
          item,
          selectedComplementaries,
          itemKey // Pass the key
          );
    } else if (itemType == 'gig') {
      final Map<String, dynamic> gigDetails =
          item['gigDetails'] as Map<String, dynamic>? ?? {};
      final String gigType = gigDetails['gig_type'] ?? 'Unknown Gig';
      // Try to get a unique ID for the gig key
      final gigKeyIdentifier = gigDetails['booking_id']?.toString() ??
          gigDetails['chef_id']?.toString() ??
          gigDetails['producer_id']?.toString() ??
          'unknown_gig_$index';
      itemKey = Key('gig_$gigKeyIdentifier'); // Key based on gig identifier

      final double gigPrice = (gigDetails['price'] as num?)?.toDouble() ?? 0.0;
      final String? chefId = gigDetails['chef_id']?.toString();
      final String? producerId = gigDetails['producer_id']?.toString();
      final String? chefName = gigDetails['chef_name']?.toString();
      final String? producerName = gigDetails['producer_name']?.toString();

      String hiredParty = 'Unknown Provider';
      if (chefId != null)
        hiredParty = chefName != null && chefName.isNotEmpty
            ? 'Chef: $chefName'
            : 'Chef ID: $chefId';
      else if (producerId != null)
        hiredParty = producerName != null && producerName.isNotEmpty
            ? 'Producer: $producerName'
            : 'Producer ID: $producerId';

      final String location = gigDetails['location'] ?? 'Not specified';
      final String date = gigDetails['scheduled_date'] ?? 'Not set';
      final String time = gigDetails['time'] ?? 'Not set';
      final int numPeople = int.tryParse(
              gigDetails['number_of_people']?.toString().split('_').first ??
                  '0') ??
          0;

      return _buildGigItemCardContent(context, index, gigType, gigPrice,
          hiredParty, location, date, time, numPeople, itemKey // Pass the key
          );
    } else {
      // Fallback for unknown item type
      itemKey = Key('unknown_$index');
      return Card(
          key: itemKey, child: ListTile(title: Text('Unknown Item Type')));
    }
  }

  // **** START FIX: Replaced widget for clean, aligned prices ****
  // Helper Widget for Meal Item Card Content
  Widget _buildMealItemCardContent(
      BuildContext context,
      int index,
      String title,
      int quantity,
      double pricePerUnit,
      double itemTotal,
      String imageUrl,
      String sourceInfo,
      Map<String, dynamic> item,
      List<Map<String, dynamic>> selectedComplementaries,
      Key dismissibleKey) {
    // Define colors
    final Color primaryColor = Colors.teal[800]!;
    final Color backgroundColor = Colors.white;
    final Color borderColor = Colors.grey[200]!;
    final Color textSecondary = Colors.grey[700]!;
    final Color textTertiary = Colors.grey[500]!;

    // Get price breakdown
    final double basePrice = (item['basePrice'] as num?)?.toDouble() ?? 0.0;
    final double chefPrice = (item['selectedchef']?['price'] != null)
        ? ShoppingCart._parsePrice(item['selectedchef']['price'])
        : 0.0;

    // Build chef/producer info
    Widget buildSourceInfo() {
      if (sourceInfo.isEmpty) return SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
        child: Row(
          children: [
            Icon(Icons.person_outline, size: 14, color: textTertiary),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                sourceInfo
                    .replaceAll('Cooked by: ', '')
                    .replaceAll('From: ', ''),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Dismissible(
      key: dismissibleKey,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_outline, color: Colors.red[400], size: 28),
      ),
      confirmDismiss: (direction) => _confirmItemRemoval(context, index, title),
      onDismissed: (direction) {},
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 1.0),
          ),
        ),
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  key: ValueKey(imageUrl),
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(
                    color: Colors.grey[100],
                    child: Center(
                        child: Icon(Icons.image, color: Colors.grey[300])),
                  ),
                  errorWidget: (c, u, e) => Container(
                    color: Colors.grey[100],
                    child: Center(
                        child:
                            Icon(Icons.broken_image, color: Colors.grey[300])),
                  ),
                ),
              ),
            ),

            SizedBox(width: 12),

            // Main content - ALL content and prices are now in here for alignment.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Title and Total Price for this line item in the cart
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        itemTotal.toStringAsFixed(0),
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),

                  // Chef/producer info
                  buildSourceInfo(),

                  SizedBox(height: 8),

                  // -- PRICE BREAKDOWN SECTION --
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Base price and chef service
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Base meal',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: textSecondary)),
                          Text(basePrice.toStringAsFixed(0),
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: textSecondary)),
                        ],
                      ),

                      if (chefPrice > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Chef service',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, color: textSecondary)),
                              Text(chefPrice.toStringAsFixed(0),
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, color: textSecondary)),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // Complementary items section with subtle separator
                  if (selectedComplementaries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
                      child: Text(
                        'Best served with:',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  ...selectedComplementaries.map((comp) {
                    final price = (comp['price'] as num?)?.toDouble() ?? 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '• ${comp['name']?.toString() ?? ''}',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            price.toStringAsFixed(0),
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: textSecondary),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    );
                  }).toList(),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Divider(height: 1, color: borderColor),
                  ),

                  // Total per meal (base + chef + complements)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total per meal',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primaryColor),
                      ),
                      Text(
                        (basePrice + chefPrice + ((item['complementaryTotal'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(0),
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: primaryColor),
                      ),
                    ],
                  ),

                  // -- END OF BREAKDOWN --

                  // Bulk order info if applicable
                  if (item['isBulkOrder'] as bool? ?? false)
                    _buildBulkOrderSummary(item),

                  // Quantity controls
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: _buildQuantityControls(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // **** END FIX ****

  // **** START FIX: Add a helper widget to display bulk order info ****
  Widget _buildBulkOrderSummary(Map<String, dynamic> item) {
    final startDateString = item['planStartDate'] as String?;
    final endDateString = item['planEndDate'] as String?;
    final planDays = item['planSelectedDays'] as List?;
    final numberOfDays = planDays?.length ?? 0;

    if (numberOfDays == 0) return SizedBox.shrink();

    String durationText = 'Plan Details';
    if (startDateString != null && endDateString != null) {
      try {
        final startDate = DateTime.parse(startDateString);
        final endDate = DateTime.parse(endDateString);
        // Format to be more compact e.g. "Nov 20 - Dec 4"
        durationText =
            '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d').format(endDate)}';
      } catch (e) {
        // Ignore parse error, will fallback to the default "Plan Details"
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.teal.shade100, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: Colors.teal[700]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '$numberOfDays deliveries ($durationText)',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.teal[800],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // **** END FIX ****

  // Builds the quantity controls for a cart item with a cleaner design
  Widget _buildQuantityControls(Map<String, dynamic> item) {
    final bool isBulk = item['isBulkOrder'] as bool? ?? false;
    final int quantity = (item['quantity'] as num?)?.toInt() ?? 1;
    final String title = item['title'] as String? ?? '';
    
    // Define colors
    final Color primaryColor = Colors.teal[700]!;
    final Color backgroundColor = Colors.grey[100]!;
    final Color iconColor = Colors.grey[700]!;

    // For bulk orders, show the quantity per day with a clean label
    if (isBulk) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal[100]!, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat, size: 14, color: primaryColor),
            SizedBox(width: 4),
            Text(
              '$quantity/day',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: primaryColor,
              ),
            ),
          ],
        ),
      );
    }

    // For regular items, show a clean + and - control
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Decrease button
          IconButton(
            icon: Icon(Icons.remove, size: 18, color: iconColor),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: 36,
              minHeight: 32,
            ),
            onPressed: () {
              if (quantity > 1) {
                ShoppingCart.updateMealQuantity(title, quantity - 1);
              } else {
                _confirmItemRemoval(context, -1, title);
              }
            },
          ),
          
          // Quantity display
          Container(
            width: 24,
            alignment: Alignment.center,
            child: Text(
              quantity.toString(),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ),
          
          // Increase button
          Container(
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: IconButton(
              icon: Icon(Icons.add, size: 18, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              onPressed: () {
                ShoppingCart.updateMealQuantity(title, quantity + 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget for Gig Item Card Content
  Widget _buildGigItemCardContent(
      BuildContext context,
      int index,
      String gigType,
      double gigPrice,
      String hiredParty, // Displays Name or ID fallback
      String location,
      String date,
      String time,
      int numPeople,
      Key dismissibleKey // Pass the key
      ) {
    return Dismissible(
      key: dismissibleKey, // Use the generated key
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: Colors.red[700], size: 28),
      ),
      confirmDismiss: (direction) =>
          _confirmItemRemoval(context, index, gigType),
      onDismissed: (direction) {/* Removal handled in confirmDismiss */},
      child: Card(
        elevation: 1.5,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(Icons.event_seat, size: 40, color: Colors.teal[600]),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gigType,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal[900]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      hiredParty, // Displays Name or ID fallback
                      style: GoogleFonts.poppins(
                          color: Colors.grey[700], fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Location: $location',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'When: $date at $time',
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (numPeople > 0) ...[
                      SizedBox(height: 4),
                      Text(
                        'Guests: $numPeople',
                        style: GoogleFonts.poppins(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8),
              Text(
                'ugx ${gigPrice.toStringAsFixed(0)}', // Format without decimals
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Confirmation Dialog for removing an item by index
  Future<bool?> _confirmItemRemoval(
      BuildContext context, int index, String itemIdentifier) async {
    // Check mounted status before showing dialog
    if (!mounted) return false;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Item?'),
        content: Text(
            'Are you sure you want to remove "$itemIdentifier" from your cart?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              // We don't remove here, just pop true
              Navigator.of(context).pop(true);
            },
            child: Text('Remove',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((confirmed) {
      // Perform removal AFTER dialog closes if confirmed
      if (confirmed == true && mounted) {
        // Check mounted again
        ShoppingCart.removeItemByIndex(index); // This notifies listeners
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$itemIdentifier" removed from cart.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red[600],
        ));
        return true; // Return true for Dismissible
      }
      return false; // Return false for Dismissible
    });
  }

  // Confirmation Dialog for clearing the entire cart
  Future<void> _confirmClearCart(BuildContext context) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Cart?'),
        content: Text(
            'Are you sure you want to remove all items from your cart? This cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Clear All',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) {
      ShoppingCart.clearCart(); // This notifies listeners
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cart cleared successfully.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal[700],
      ));
    }
  }

  void _handleCheckout(BuildContext context,
      List<Map<String, dynamic>> cartItems, double totalAmount) {
    if (!mounted) return;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your cart is empty. Please add items to checkout.'),
          backgroundColor: Colors.orange[700],
        ),
      );
    } else {
      print("Proceeding to checkout with ${cartItems.length} items.");
      // Pass the current cart items and total price to the CheckoutScreen
      Navigator.pushReplacement(
        // Use pushReplacement if you don't want users going back to the cart easily
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(
            items: cartItems, // Pass the current snapshot of items
            totalPrice: totalAmount, // Pass the rrent total
          ),
        ),
      );
      // No need for .then(_refreshCart) because ValueListenableBuilder handles UI updates
    }
  }

  void _showHelpDialog(BuildContext context) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cart Help'),
        content: Text(
            '• Swipe left on an item to remove it.\n• Use +/- buttons for meal quantity (not available for meal plans).\n• Chef/Producer details are shown below the item name.\n• Complementary items selected are listed below the meal.\n• Contact support@zinzi.app for assistance.', // Updated help
            style: GoogleFonts.poppins(height: 1.5) // Improve readability
            ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK',
                style: TextStyle(
                    color: Colors.teal[800], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
} // End _ShoppingCartScreenState

// ***************************************************************
// *                   FAVORITES UI SCREEN                       *
// ***************************************************************

// Favorites UI Screen
class FavoritesScreen extends StatefulWidget {
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  // Use ValueListenableBuilder for reactive UI

  String _formatImageUrl(String? imageUrl) {
    // Same formatting logic as in cart screen
    imageUrl ??= 'assets/images/cover.png';
    if (imageUrl.startsWith('assets/')) return imageUrl;
    if (imageUrl.contains('drive.google.com/uc?export=view&id='))
      return imageUrl;
    if (imageUrl.contains('drive.google.com') && imageUrl.contains('/d/')) {
      final parts = imageUrl.split('/d/');
      if (parts.length > 1) {
        final idPart = parts[1].split('/')[0];
        if (idPart.isNotEmpty)
          return 'https://drive.google.com/uc?export=view&id=$idPart';
      }
    }
    if (imageUrl.startsWith('http://'))
      return 'https://${imageUrl.substring(7)}';
    if (!imageUrl.startsWith('https://')) {
      print(
          "Warning: Formatting potentially invalid image URL in favorites: $imageUrl");
      return 'assets/images/cover.png'; // Fallback
    }
    return imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    // Use ValueListenableBuilder to react to favorite changes
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: Favorites.favoritesNotifier,
        builder: (context, favoriteItems, child) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Favorites (${favoriteItems.length})',
                  style: GoogleFonts.poppins()),
              backgroundColor: Colors.teal[800],
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: Icon(Icons.delete_sweep),
                  tooltip: 'Clear Favorites',
                  onPressed: favoriteItems.isNotEmpty
                      ? () => _confirmClearFavorites(context)
                      : null,
                ),
              ],
            ),
            body: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                      'assets/images/soft.jpg'), // Ensure this asset exists
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.white.withOpacity(0.95),
                    BlendMode.dstATop,
                  ),
                ),
              ),
              child: favoriteItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border,
                              size: 64, color: Colors.teal[200]),
                          SizedBox(height: 24),
                          Text('No Favorites Yet',
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.teal[800])),
                          SizedBox(height: 12),
                          Text('Tap the heart icon on meals to add them here!',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 15, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(12),
                      itemCount: favoriteItems.length,
                      separatorBuilder: (context, index) => SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = favoriteItems[index];
                        final String title = item['title'] ?? 'Unknown Item';
                        final double price =
                            (item['price'] as num?)?.toDouble() ?? 0.0;
                        final String imageUrl = _formatImageUrl(item['image']);
                        return Card(
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                key: ValueKey(imageUrl), // Add key
                                width: 55, height: 55, fit: BoxFit.cover,
                                placeholder: (c, u) => Container(
                                    width: 55,
                                    height: 55,
                                    color: Colors.grey[200]),
                                errorWidget: (c, u, e) => Container(
                                    width: 55,
                                    height: 55,
                                    color: Colors.grey[200],
                                    child: Icon(Icons.broken_image,
                                        color: Colors.grey[400])),
                              ),
                            ),
                            title: Text(title,
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text('ugx ${price.toStringAsFixed(0)}',
                                style: GoogleFonts.poppins(
                                    color: Colors.teal[700])), // Format price
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Add to Cart',
                                  child: IconButton(
                                    icon: Icon(Icons.add_shopping_cart,
                                        color: Colors.teal),
                                    onPressed: () {
                                      Favorites.addToCart(
                                          context, title, price, imageUrl);
                                      // No need to refresh, cart notifier handles cart UI
                                    },
                                  ),
                                ),
                                Tooltip(
                                  message: 'Remove Favorite',
                                  child: IconButton(
                                    icon:
                                        Icon(Icons.favorite, color: Colors.red),
                                    onPressed: () {
                                      _confirmRemoveFavorite(context, title);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          );
        });
  }

  Future<void> _confirmRemoveFavorite(
      BuildContext context, String title) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Favorite?'),
        content: Text(
            'Are you sure you want to remove "$title" from your favorites?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) {
      Favorites.removeItem(title); // This notifies listeners
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"$title" removed from favorites.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.red[600],
      ));
    }
  }

  Future<void> _confirmClearFavorites(BuildContext context) async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Favorites?'),
        content: Text(
            'Are you sure you want to remove all items from your favorites?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Clear All',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (mounted && confirm == true) {
      Favorites.clearFavorites(); // This notifies listeners
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Favorites cleared successfully.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal[700],
      ));
    }
  }
} // End _FavoritesScreenState