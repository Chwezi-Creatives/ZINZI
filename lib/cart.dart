import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinzi2/checkout.dart'; // Import your checkout screen
import 'package:zinzi2/widgets/app_drawer.dart'; // Import the AppDrawer
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ***************************************************************
// *          SINGLE SOURCE OF TRUTH FOR CART & FAVORITES        *
// ***************************************************************

// Shopping Cart Management - Defined ONCE here
class ShoppingCart {
  // Use static list - THIS IS THE SHARED STATE
  // Items can be meals ('type': 'meal') or gigs ('type': 'gig')
  static List<Map<String, dynamic>> items = [];

  // Adds a MEAL item to the cart
  static void addItem(
    String title,
    double price, {
    int quantity = 1,
    Map<String, dynamic>?
        selectedchef, // EXPECTS { 'id': ..., 'name': 'Chef Name', ... }
    Map<String, dynamic>?
        selectedproducer, // EXPECTS { 'id': ..., 'name': 'Producer Name', ... }
    required Map<String, dynamic> meal,
    // **** CLARIFICATION: 'bestservedwith' holds the list of *potential* COMPLEMENTARY items. ****
    // These items are associated with the main meal but are NOT added as separate cart items here.
    // The checkout process needs to handle which of these (if any) were actually selected by the user.
    required List<Map<String, dynamic>> bestservedwith,
  }) {
    const itemType = 'meal';
    final hasChef = selectedchef != null && selectedchef.isNotEmpty;
    final hasProducer = selectedproducer != null && selectedproducer.isNotEmpty;

    final existingItemIndex = items
        .indexWhere((item) => item['type'] == 'meal' && item['title'] == title);

    if (existingItemIndex != -1) {
      // Item exists - Update it
      items[existingItemIndex]['quantity'] = quantity;
      items[existingItemIndex]['price'] = price;
      items[existingItemIndex]['selectedchef'] =
          hasChef ? selectedchef : null; // Store map {id, name}
      items[existingItemIndex]['selectedproducer'] =
          hasProducer ? selectedproducer : null; // Store map {id, name}
      items[existingItemIndex]['meal'] = meal;
      // Store the list of complementary items data with the meal
      items[existingItemIndex]['bestservedwith'] = bestservedwith;
      print("Updated item in cart: $title");
    } else {
      // Item is new - Add it
      items.add({
        'title': title,
        'price': price,
        'quantity': quantity,
        'selectedchef': hasChef ? selectedchef : null, // Store map {id, name}
        'selectedproducer':
            hasProducer ? selectedproducer : null, // Store map {id, name}
        'meal': meal,
        // Store the list of complementary items data with the meal
        'bestservedwith': bestservedwith,
        'type': itemType,
      });
      print("Added new item to cart: $title");
    }
    print(
        "Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
  }

  static List<Map<String, dynamic>> getItems() {
    return List.unmodifiable(items);
  }

  static double get totalPrice {
    return items.fold(0.0, (sum, item) {
      if (item['type'] == 'meal') {
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        return sum + (price * quantity);
      } else if (item['type'] == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        final price = (gigDetails['price'] as num?)?.toDouble() ?? 0.0;
        return sum + price;
      }
      return sum;
    });
  }

  static void clearCart() {
    items.clear();
    print("Cart Cleared");
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
        // Log with name if possible
        final chefName = details['chef_name'];
        final producerName = details['producer_name'];
        if (chefName != null && chefName.isNotEmpty)
          itemIdentifier = '$type (Chef: $chefName)';
        else if (producerName != null && producerName.isNotEmpty)
          itemIdentifier = '$type (Producer: $producerName)';
        else
          itemIdentifier = type; // Fallback to just type
      } else {
        itemIdentifier = 'Unknown Item';
      }
      print("Removed item from cart at index $index: $itemIdentifier");
      print(
          "Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
    } else {
      print("Attempted to remove item at invalid index: $index");
    }
  }

  static void updateMealQuantity(String title, int newQuantity) {
    final existingItemIndex = items
        .indexWhere((item) => item['type'] == 'meal' && item['title'] == title);
    if (existingItemIndex != -1) {
      if (newQuantity > 0) {
        items[existingItemIndex]['quantity'] = newQuantity;
        print("Updated quantity for meal '$title' to $newQuantity");
      } else {
        removeItemByIndex(existingItemIndex); // Remove if quantity <= 0
      }
    }
  }

  // Method to add a Gig
  // Expects 'gigDetails' to contain 'chef_id'/'producer_id' AND optionally 'chef_name'/'producer_name'
  static void addGig(Map<String, dynamic> gigDetails) {
    // Basic Validation
    final userId = gigDetails['user_id'];
    final chefId = gigDetails['chef_id'];
    final producerId = gigDetails['producer_id'];
    final price = gigDetails['price'];
    final chefName = gigDetails['chef_name']; // Name is expected here now
    final producerName = gigDetails[
        'producer_name']; // Name is expected here now (if applicable)

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
      'gigDetails': gigDetails, // Store the map which now contains ID and Name
    });
    print(
        "Added new gig to cart: ${gigDetails['gig_type']} with Chef: $chefName, Producer: $producerName");
    print(
        "Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
  }

  // Method to remove a specific list of items
  static void removeItems(List<Map<String, dynamic>> itemsToRemove) {
    if (itemsToRemove.isEmpty) return;
    int initialLength = items.length;
    final Set<Map<String, dynamic>> removalSet = Set.identity()
      ..addAll(itemsToRemove);
    items.removeWhere((item) => removalSet.contains(item));
    if (items.length < initialLength) {
      print(
          "Removed ${initialLength - items.length} item(s) from cart based on provided list.");
      print(
          "Current Cart Titles: ${items.map((e) => e['title'] ?? e['gigDetails']?['gig_type'] ?? 'Unknown')} ");
    } else {
      print(
          "No items removed. Items to remove might not have been found in the cart.");
    }
  }
}

// Favorites Management - Defined ONCE here
class Favorites {
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price, String image) {
    if (!items.any((item) => item['title'] == title)) {
      items.add({'title': title, 'price': price, 'image': image});
      print("Added item to favorites: $title");
    }
  }

  static void addToCart(
      BuildContext context, String title, double price, String image) {
    // Adding from favorites - pass empty list for complementary items ('bestservedwith')
    ShoppingCart.addItem(title, price,
        selectedchef: null,
        selectedproducer: null,
        meal: {'meal_name': title, 'price': price, 'image_link': image},
        bestservedwith: []);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$title added to cart from favorites!'),
      duration: Duration(seconds: 2),
    ));
  }

  static List<Map<String, dynamic>> getItems() {
    return List.unmodifiable(items);
  }

  static void clearFavorites() {
    items.clear();
    print("Favorites Cleared");
  }

  static void removeItem(String title) {
    int initialLength = items.length;
    items.removeWhere((item) => item['title'] == title);
    if (items.length < initialLength) {
      print("Removed item from favorites: $title");
    }
  }

  static bool isFavorite(String title) {
    return items.any((meal) => meal['title'] == title);
  }
}

// ***************************************************************
// *                      UI SCREENS                             *
// ***************************************************************

// Shopping Cart Screen UI
class ShoppingCartScreen extends StatefulWidget {
  @override
  _ShoppingCartScreenState createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  void _refreshCart() {
    if (mounted) {
      setState(() {});
      print("Cart Screen refreshed");
    }
  }

  String _formatImageUrl(String? imageUrl) {
    imageUrl ??= 'assets/images/cover.png';
    if (imageUrl.contains('drive.google.com/uc?export=view&id='))
      return imageUrl;
    if (imageUrl.contains('drive.google.com') && imageUrl.contains('/d/')) {
      final parts = imageUrl.split('/d/');
      if (parts.length > 1) {
        final idPart = parts[1].split('/')[0];
        return 'https://drive.google.com/uc?export=view&id=$idPart';
      }
    }
    return imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ShoppingCart.getItems();
    final totalAmount = ShoppingCart.totalPrice;

    print("Building Cart Screen with ${cartItems.length} items.");

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text('Shopping Cart (${cartItems.length})',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep, size: 24),
            tooltip: 'Clear Cart',
            onPressed:
                cartItems.isNotEmpty ? () => _confirmClearCart(context) : null,
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
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(0.95),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCartHeader(cartItems, totalAmount),
            // **** CLARIFICATION: Complementary items ('bestservedwith') data is stored ****
            // **** within each meal item but not displayed separately here. Checkout uses it. ****
            Expanded(
              child: cartItems.isEmpty
                  ? _buildEmptyCart()
                  : ListView.separated(
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      itemCount: cartItems.length,
                      separatorBuilder: (context, index) => SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _buildCartItemCard(
                            cartItems[index], index, context);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildCheckoutButton(cartItems),
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
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
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
            '\$${totalAmount.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(List<Map<String, dynamic>> cartItems) {
    final totalAmount = ShoppingCart.totalPrice;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        label: Text('Checkout (\$${totalAmount.toStringAsFixed(2)})'),
        style: ElevatedButton.styleFrom(
            backgroundColor:
                cartItems.isNotEmpty ? Colors.teal[700] : Colors.grey,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48),
            padding: EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        onPressed: cartItems.isNotEmpty ? () => _handleCheckout(context) : null,
      ),
    );
  }

  // Builds the card for EITHER a meal or a gig
  Widget _buildCartItemCard(
      Map<String, dynamic> item, int index, BuildContext context) {
    final String itemType = item['type'] ?? 'meal';

    if (itemType == 'meal') {
      // --- Render Meal Item ---
      final String title = item['title'] ?? 'Unknown Item';
      final int quantity =
          (item['quantity'] as num?)?.toInt() ?? 0; // Safer casting
      final double price =
          (item['price'] as num?)?.toDouble() ?? 0.0; // Safer casting
      final Map<String, dynamic>? chef =
          item['selectedchef'] as Map<String, dynamic>?; // Explicit cast
      final Map<String, dynamic>? producer =
          item['selectedproducer'] as Map<String, dynamic>?; // Explicit cast
      final Map<String, dynamic> mealData =
          (item['meal'] is Map<String, dynamic>) ? item['meal'] : {};
      final String imageUrl = _formatImageUrl(mealData['image_link']);
      final double itemTotal = price * quantity;
      // Note: item['bestservedwith'] (complementary items list) is available here but not displayed.

      String sourceInfo = '';
      // Prioritize Name, fallback to ID
      if (chef != null && chef['name'] != null && chef['name'].isNotEmpty) {
        sourceInfo = 'Cooked by: ${chef['name']}';
      } else if (producer != null &&
          producer['name'] != null &&
          producer['name'].isNotEmpty) {
        sourceInfo = 'Fresh from: ${producer['name']}';
      } else if (chef != null && chef['id'] != null) {
        sourceInfo = 'Cooked by: Chef ID ${chef['id']}';
      } else if (producer != null && producer['id'] != null) {
        sourceInfo = 'Fresh from: Producer ID ${producer['id']}';
      } else if (mealData['meal_name'] != null &&
          title != mealData['meal_name']) {
        // Basic check if it might be a complementary item added to cart
        sourceInfo = 'Complementary Item';
      }

      return _buildMealItemCardContent(context, index, title, quantity, price,
          itemTotal, imageUrl, sourceInfo, item);
    } else if (itemType == 'gig') {
      // --- Render Gig Item ---
      final Map<String, dynamic> gigDetails =
          item['gigDetails'] as Map<String, dynamic>? ?? {};
      final String gigType = gigDetails['gig_type'] ?? 'Unknown Gig';
      final double gigPrice =
          (gigDetails['price'] as num?)?.toDouble() ?? 0.0; // Safer casting
      final String? chefId =
          gigDetails['chef_id']?.toString(); // ID is still stored
      final String? producerId =
          gigDetails['producer_id']?.toString(); // ID is still stored

      // **** Logic to Display Name or ID ****
      final String? chefName = gigDetails['chef_name']?.toString();
      final String? producerName = gigDetails['producer_name']?.toString();

      String hiredParty = 'Unknown Provider';
      if (chefId != null) {
        // Prioritize Chef
        hiredParty = chefName != null && chefName.isNotEmpty
            ? 'Chef: $chefName' // Use Name if available
            : 'Chef ID: $chefId'; // Fallback to ID
      } else if (producerId != null) {
        // Then Producer
        hiredParty = producerName != null && producerName.isNotEmpty
            ? 'Producer: $producerName' // Use Name if available
            : 'Producer ID: $producerId'; // Fallback to ID
      }
      // **** End Logic ****

      final String location = gigDetails['location'] ?? 'Not specified';
      final String date = gigDetails['scheduled_date'] ?? 'Not set';
      final String time = gigDetails['time'] ?? 'Not set';

      final String numPeopleKey =
          gigDetails['number_of_people']?.toString() ?? '';
      int numPeople = 0;
      if (numPeopleKey.isNotEmpty) {
        final parts = numPeopleKey.split('_');
        numPeople = int.tryParse(parts.first) ?? 0;
      }

      return _buildGigItemCardContent(context, index, gigType, gigPrice,
          hiredParty, location, date, time, numPeople);
    } else {
      return Card(child: ListTile(title: Text('Unknown Item Type')));
    }
  }

  // Helper Widget for Meal Item Card Content
  Widget _buildMealItemCardContent(
      BuildContext context,
      int index,
      String title,
      int quantity,
      double price,
      double itemTotal,
      String imageUrl,
      String sourceInfo,
      Map<String, dynamic> item) {
    return Dismissible(
      key: Key('meal_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: Colors.red[700], size: 28),
      ),
      confirmDismiss: (direction) => _confirmItemRemoval(context, index, title),
      onDismissed: (direction) {/* Handled in confirmDismiss */},
      child: Card(
        elevation: 1.5,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 65,
                  height: 65,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(
                      width: 65,
                      height: 65,
                      color: Colors.grey[200],
                      child: Center(
                          child: Icon(Icons.image, color: Colors.grey[400]))),
                  errorWidget: (c, u, e) => Container(
                      width: 65,
                      height: 65,
                      color: Colors.grey[200],
                      child: Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.grey[400]))),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal[900]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sourceInfo.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        sourceInfo,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${itemTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800]),
                  ),
                  SizedBox(height: 6),
                  _buildQuantityControls(item),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Builds Quantity Controls ONLY for MEAL items
  Widget _buildQuantityControls(Map<String, dynamic> mealItem) {
    final String title = mealItem['title'] ?? '';
    final int quantity = (mealItem['quantity'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.remove, size: 18, color: Colors.red[700]),
            onPressed: quantity > 1
                ? () {
                    ShoppingCart.updateMealQuantity(title, quantity - 1);
                    _refreshCart();
                  }
                : null,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            constraints: BoxConstraints(),
            splashRadius: 18,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: Text(
              '$quantity',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 18, color: Colors.green[700]),
            onPressed: () {
              ShoppingCart.updateMealQuantity(title, quantity + 1);
              _refreshCart();
            },
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            constraints: BoxConstraints(),
            splashRadius: 18,
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
      int numPeople) {
    return Dismissible(
      key: Key('gig_$index'),
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
      onDismissed: (direction) {/* Handled in confirmDismiss */},
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
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal[900]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      hiredParty, // Displays Name or ID fallback
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Location: $location',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'When: $date at $time',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (numPeople > 0) ...[
                      SizedBox(height: 4),
                      Text(
                        'Guests: $numPeople',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8),
              Text(
                '\$${gigPrice.toStringAsFixed(2)}',
                style: TextStyle(
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
              ShoppingCart.removeItemByIndex(index);
              Navigator.of(context).pop(true);
              _refreshCart();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('"$itemIdentifier" removed from cart.'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.red[600],
              ));
            },
            child: Text('Remove',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
      ShoppingCart.clearCart();
      _refreshCart();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cart cleared successfully.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal[700],
      ));
    }
  }

  void _handleCheckout(BuildContext context) {
    if (!mounted) return;
    final cartItems = ShoppingCart.getItems();
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your cart is empty. Please add items to checkout.'),
          backgroundColor: Colors.orange[700],
        ),
      );
    } else {
      print("Proceeding to checkout with ${cartItems.length} items.");
      // Pass cart items (including complementary item data within meals) to checkout
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(
            items: cartItems,
            totalPrice: ShoppingCart.totalPrice,
          ),
        ),
      ).then((_) => _refreshCart());
    }
  }

  void _showHelpDialog(BuildContext context) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cart Help'),
        content: Text(
            'Swipe left on an item to remove it.\nUse +/- buttons for meal quantity.\nChef/Producer details (Name or ID) are shown below item name.\nComplementary items for meals are handled during checkout.\nContact support@zinzi.app for assistance.'), // Updated help
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
}

// Favorites UI Screen
class FavoritesScreen extends StatefulWidget {
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  void _refreshFavorites() {
    if (mounted) setState(() {});
  }

  String _formatImageUrl(String? imageUrl) {
    imageUrl ??= 'assets/images/cover.png';
    if (imageUrl.contains('drive.google.com/uc?export=view&id='))
      return imageUrl;
    if (imageUrl.contains('drive.google.com') && imageUrl.contains('/d/')) {
      final parts = imageUrl.split('/d/');
      if (parts.length > 1) {
        final idPart = parts[1].split('/')[0];
        return 'https://drive.google.com/uc?export=view&id=$idPart';
      }
    }
    return imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final favoriteItems = Favorites.getItems();
    return Scaffold(
      appBar: AppBar(
        title: Text('Favorites (${favoriteItems.length})'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
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
            image: AssetImage('assets/images/soft.jpg'),
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
                        size: 64, color: Colors.red[200]),
                    SizedBox(height: 24),
                    Text('No Favorites Yet',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: Colors.teal[800])),
                    SizedBox(height: 12),
                    Text('Tap the ❤️ icon on meals to add them here!',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey[600])),
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 55,
                          height: 55,
                          fit: BoxFit.cover,
                          placeholder: (c, u) => Container(
                              width: 55, height: 55, color: Colors.grey[200]),
                          errorWidget: (c, u, e) => Container(
                              width: 55,
                              height: 55,
                              color: Colors.grey[200],
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey[400])),
                        ),
                      ),
                      title: Text(title,
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('\$${price.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.teal[700])),
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
                                _refreshFavorites();
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Remove Favorite',
                            child: IconButton(
                              icon: Icon(Icons.favorite, color: Colors.red),
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
      Favorites.removeItem(title);
      _refreshFavorites();
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
      Favorites.clearFavorites();
      _refreshFavorites();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Favorites cleared successfully.'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.teal[700],
      ));
    }
  }
}
