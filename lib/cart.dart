import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinzi2/checkout.dart'; // Import your checkout screen

// ***************************************************************
// *          SINGLE SOURCE OF TRUTH FOR CART & FAVORITES        *
// ***************************************************************

// Shopping Cart Management - Defined ONCE here
class ShoppingCart {
  // Use static list - THIS IS THE SHARED STATE
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price, {
    int quantity = 1,
    // 'bestservedwith' is not typically added directly via addItem here,
    // it's part of the 'meal' data. Complementary items are added separately.
    // List<Map<String, dynamic>>? bestservedwith,
    Map<String, dynamic>? selectedchef,
    Map<String, dynamic>? selectedproducer,
    required Map<String, dynamic> meal, required List<Map<String, String>> bestservedwith, // Contains image_link, description etc.
  }) {
    // Enforce mutual exclusivity: only one of selectedchef or selectedproducer should be passed
    final hasChef = selectedchef != null && selectedchef.isNotEmpty;
    final hasProducer = selectedproducer != null && selectedproducer.isNotEmpty;
    // Allow adding item without chef/producer (e.g., complementary)
    // if (hasChef && hasProducer) {
    //   print('Warning: Attempted to add item with both chef and producer. Prioritizing chef.');
    //    selectedproducer = null; // Example: prioritize chef if both provided
    // }

    // Check if item ALREADY exists (regardless of chef/producer for quantity update)
    final existingItemIndex = items.indexWhere((item) => item['title'] == title);

    if (existingItemIndex != -1) {
      // Item exists - Update it (e.g., change chef/producer or quantity)
      // If only quantity changes, increment. If chef/producer changes, replace them.
      // If the new selection is the same as the old, just increment quantity? Let's replace for simplicity of update.
      items[existingItemIndex]['quantity'] = quantity; // Set quantity (could be +=1 if needed)
      items[existingItemIndex]['price'] = price; // Update price just in case
      items[existingItemIndex]['selectedchef'] = hasChef ? selectedchef : null;
      items[existingItemIndex]['selectedproducer'] = hasProducer ? selectedproducer : null;
      items[existingItemIndex]['meal'] = meal; // Update meal data if needed
       print("Updated item in cart: $title"); // Debug log
    } else {
      // Item is new - Add it
      items.add({
        'title': title,
        'price': price,
        'quantity': quantity,
        // 'bestservedwith': bestservedwith ?? [], // Not needed here
        'selectedchef': hasChef ? selectedchef : null,
        'selectedproducer': hasProducer ? selectedproducer : null,
        'meal': meal, // Store the entire meal object
      });
       print("Added new item to cart: $title"); // Debug log
    }
      print("Current Cart: ${items.map((e) => e['title'])}"); // Debug log
  }

  // No need for replaceChef - addItem handles updates now

  static List<Map<String, dynamic>> getItems() {
    return List.unmodifiable(items); // Return unmodifiable list
  }

  static double getTotal() {
    if (items.isEmpty) {
      return 0.0;
    }
    return items.fold(0.0, (sum, item) {
       final price = item['price'] is num ? item['price'] : 0.0;
       final quantity = item['quantity'] is num ? item['quantity'] : 0;
       return sum + (price * quantity);
    });
  }

  static void clearCart() {
    items.clear();
    print("Cart Cleared"); // Debug log
  }

  static void removeItemFromCart(String title) {
    int initialLength = items.length;
    items.removeWhere((item) => item['title'] == title);
     if (items.length < initialLength) {
       print("Removed item from cart: $title"); // Debug log
     }
      print("Current Cart: ${items.map((e) => e['title'])}"); // Debug log
  }

  static void updateQuantity(String title, int newQuantity) {
    final existingItemIndex = items.indexWhere((item) => item['title'] == title);
    if (existingItemIndex != -1) {
      if (newQuantity > 0) {
        items[existingItemIndex]['quantity'] = newQuantity;
         print("Updated quantity for $title to $newQuantity"); // Debug log
      } else {
        // Remove item if quantity is 0 or less
        removeItemFromCart(title);
      }
    }
  }
}

// Favorites Management - Defined ONCE here
class Favorites {
  // Use static list - THIS IS THE SHARED STATE
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price, String image) {
    if (!items.any((item) => item['title'] == title)) {
      items.add({'title': title, 'price': price, 'image': image});
       print("Added item to favorites: $title"); // Debug log
    }
  }

  // This addToCart might need review - does it add a generic item or the specific favorite?
  // It currently adds with a 'defaultChef' and empty meal data. Might be better
  // to navigate to the meal detail screen from favorites. Let's keep it simple for now.
  static void addToCart(BuildContext context, String title, double price, String image) {
     // Add favorite item as a basic entry to the cart
    ShoppingCart.addItem(
      title,
      price,
      // No specific chef/producer when adding from favorites list directly
      selectedchef: null,
      selectedproducer: null,
      // Pass minimal meal data
      meal: {'meal_name': title, 'price': price, 'image_link': image}, bestservedwith: []
    );
      // Show feedback
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
       content: Text('$title added to cart from favorites!'),
       duration: Duration(seconds: 2),
     ));
  }

  static List<Map<String, dynamic>> getItems() {
    return List.unmodifiable(items); // Return unmodifiable list
  }

  static void clearFavorites() {
    items.clear();
     print("Favorites Cleared"); // Debug log
  }

  static void removeItem(String title) {
     int initialLength = items.length;
    items.removeWhere((item) => item['title'] == title);
      if (items.length < initialLength) {
       print("Removed item from favorites: $title"); // Debug log
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
  // No need for bestServedWithInCart state here, handle directly in build

  void _refreshCart() {
    // Trigger rebuild to reflect changes in ShoppingCart.items
    setState(() {});
    print("Cart Screen refreshed"); // Debug log
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

  @override
  Widget build(BuildContext context) {
    // Get the SHARED cart items
    final cartItems = ShoppingCart.getItems();
    final totalAmount = ShoppingCart.getTotal();

    print("Building Cart Screen with ${cartItems.length} items."); // Debug log

    return Scaffold(
      appBar: AppBar(
        title: Text('Shopping Cart (${cartItems.length})'), // Show count in title
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep, size: 24),
            tooltip: 'Clear Cart',
            onPressed: cartItems.isNotEmpty ? () => _confirmClearCart(context) : null, // Enable only if cart has items
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
              Colors.white.withOpacity(0.95), BlendMode.dstATop,
            ),
          ),
        ),
        // Use Column instead of Padding directly for better structure
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
            children: [
              // Cart Header outside Padding for full width potential
              _buildCartHeader(cartItems, totalAmount),
              // Removed _buildBestServedWith as complementary items are now added as regular cart items
              // If you need a specific "suggested items" section, it would need different logic.
              Expanded(
                child: cartItems.isEmpty
                    ? _buildEmptyCart()
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), // Add padding here
                        itemCount: cartItems.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.transparent), // Use transparent divider or SizedBox
                        itemBuilder: (context, index) {
                          return _buildCartItemCard(cartItems[index], context);
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
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.teal[800]),
          ),
          SizedBox(height: 12),
          Text(
            'Explore our menu to add delicious meals!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
             icon: Icon(Icons.restaurant_menu),
             label: Text("Browse Menu"),
             onPressed: () {
                // Navigate back or to the main menu screen
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
                // Example: Navigator.pushReplacementNamed(context, '/menu');
             },
             style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12)
             ),
          )
        ],
      ),
    );
  }

  Widget _buildCartHeader(List<Map<String, dynamic>> cartItems, double totalAmount) {
    return Padding(
      // Add padding around the header
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space items out
        children: [
          // No need for item count chip if it's in the title
          // Chip(
          //   label: Text('${cartItems.length} ${cartItems.length == 1 ? 'Item' : 'Items'}', style: TextStyle(color: Colors.white)),
          //   backgroundColor: Colors.teal[700],
          //   padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // ),
          Text('Estimated Total:', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
          // SizedBox(width: 8),
          Text(
            '\$${totalAmount.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal[800]),
          ),
        ],
      ),
    );
  }

  // Removed _buildBestServedWith - complementary items are treated as regular items


  Widget _buildCheckoutButton(List<Map<String, dynamic>> cartItems) {
     final totalAmount = ShoppingCart.getTotal(); // Recalculate for display

    return Container(
      // height: 60, // Fixed height might cause overflow, let it size naturally
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Consistent padding
      decoration: BoxDecoration(
        color: Colors.white, // Use white for contrast
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)), // Subtle top border
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: Offset(0,-2))] // Subtle shadow
      ),
      child: ElevatedButton.icon(
          icon: Icon(Icons.lock_outline, size: 20), // Lock icon
          label: Text('Checkout (\$${totalAmount.toStringAsFixed(2)})'), // Show total on button
          style: ElevatedButton.styleFrom(
            backgroundColor: cartItems.isNotEmpty ? Colors.teal[700] : Colors.grey, // Color depends on state
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48), // Full width, fixed height
            padding: EdgeInsets.symmetric(vertical: 12), // Vertical padding
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Rounded corners
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold) // Text style
          ),
          // Disable button if cart is empty
          onPressed: cartItems.isNotEmpty ? () => _handleCheckout(context) : null,
        ),
    );
  }

  Widget _buildCartItemCard(Map<String, dynamic> item, BuildContext context) {
     // Safely access data, provide defaults
    final String title = item['title'] ?? 'Unknown Item';
    final int quantity = (item['quantity'] as int?) ?? 0;
    final double price = (item['price'] as double?) ?? 0.0;
    final Map<String, dynamic>? chef = item['selectedchef'];
    final Map<String, dynamic>? producer = item['selectedproducer'];
     // Safely access nested meal data
    final Map<String, dynamic> mealData = (item['meal'] is Map<String, dynamic>) ? item['meal'] : {};
    final String imageUrl = _formatImageUrl(mealData['image_link']); // Use formatted URL from meal data

    String sourceInfo = '';
    if (chef != null) {
      sourceInfo = 'Cooked by: ${chef['name'] ?? 'Unknown'}';
    } else if (producer != null) {
      // *** FIX: Access 'name', not 'Name' ***
      sourceInfo = 'Fresh from: ${producer['name'] ?? 'Unknown'}';
    } else {
       sourceInfo = 'Complementary Item'; // Or leave blank for non-chef/producer items
    }

    // Calculate total price for this item line
    final double itemTotal = price * quantity;

    return Dismissible(
      key: Key(title + (chef?['chefid']?.toString() ?? producer?['producer_id']?.toString() ?? '')), // More unique key
      direction: DismissDirection.endToStart, // Swipe left to delete
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: Colors.red[700], size: 28),
      ),
      confirmDismiss: (direction) => _confirmItemRemoval(context, title),
      onDismissed: (direction) {
         // No need to call remove here, it's done in confirmDismiss callback
         // ShoppingCart.removeItemFromCart(title);
         // _refreshCart(); // Refresh happens after confirmation dialog pops
      },
      child: Card( // Wrap ListTile in a Card for better visual separation
        elevation: 1.5,
        margin: EdgeInsets.symmetric(vertical: 6), // Space between cards
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white, // White card background
        child: Padding( // Add padding inside the card
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row( // Use Row for more control over layout
            children: [
               // Image on the left
              ClipRRect(
                 borderRadius: BorderRadius.circular(8),
                 child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 65, height: 65, fit: BoxFit.cover,
                    placeholder: (context, url) => Container(width: 65, height: 65, color: Colors.grey[200], child: Center(child: Icon(Icons.image, color: Colors.grey[400]))),
                    errorWidget: (context, url, error) => Container(width: 65, height: 65, color: Colors.grey[200], child: Center(child: Icon(Icons.broken_image, color: Colors.grey[400]))),
                 ),
              ),
              SizedBox(width: 12),
              // Middle section (Title, Source) - Takes available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.teal[900]),
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
              // Right section (Price, Quantity Controls)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${itemTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
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

  Widget _buildQuantityControls(Map<String, dynamic> item) {
    final String title = item['title'] ?? '';
    final int quantity = (item['quantity'] as int?) ?? 0;

    return Container( // Wrap controls for better touch targets and visual grouping
       decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.circular(20), // Rounded border
       ),
       child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.remove, size: 18, color: Colors.red[700]), // Red minus
             // Disable if quantity is 1
            onPressed: quantity > 1 ? () {
                ShoppingCart.updateQuantity(title, quantity - 1);
                _refreshCart(); // Update UI
            } : null, // Disable button if quantity is 1 (or handle removal differently)
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4), // Adjust padding
            constraints: BoxConstraints(), // Remove default constraints
            splashRadius: 18, // Smaller splash
          ),
          Padding( // Add padding around the quantity text
             padding: const EdgeInsets.symmetric(horizontal: 6.0),
             child: Text(
               '$quantity',
               style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
             ),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 18, color: Colors.green[700]), // Green plus
            onPressed: () {
              ShoppingCart.updateQuantity(title, quantity + 1);
               _refreshCart(); // Update UI
            },
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4), // Adjust padding
            constraints: BoxConstraints(),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  // Confirmation Dialog for removing a single item
  Future<bool?> _confirmItemRemoval(BuildContext context, String title) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Item?'),
        content: Text('Are you sure you want to remove "$title" from your cart?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Return false (don't dismiss)
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              ShoppingCart.removeItemFromCart(title); // Actually remove the item
              Navigator.of(context).pop(true); // Return true (confirm dismiss)
              _refreshCart(); // Refresh the list AFTER dialog closes
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('"$title" removed from cart.'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.red[600],
               ));
            },
            child: Text('Remove', style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

   // Confirmation Dialog for clearing the entire cart
  Future<void> _confirmClearCart(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Cart?'),
        content: Text('Are you sure you want to remove all items from your cart? This cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true); // Confirm clear
            },
            child: Text('Clear All', style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
       ShoppingCart.clearCart();
       _refreshCart(); // Update UI
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text('Cart cleared successfully.'),
         duration: Duration(seconds: 2),
         backgroundColor: Colors.teal[700],
       ));
    }
  }


  void _handleCheckout(BuildContext context) {
    final cartItems = ShoppingCart.getItems();
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your cart is empty. Please add items to checkout.'),
          backgroundColor: Colors.orange[700], // Warning color
        ),
      );
    } else {
      print("Proceeding to checkout with ${cartItems.length} items."); // Debug log
      // Clear cart *before* navigating to checkout IF that's the desired flow
      // ShoppingCart.clearCart();
      Navigator.pushReplacement( // Use pushReplacement if cart should clear on back nav
        context,
        MaterialPageRoute(
          // Pass the SHARED cart items to the checkout screen
          builder: (context) => CheckoutScreen(cartItems: cartItems),
        ),
      ).then((_) => _refreshCart()); // Refresh cart screen if user navigates back from checkout somehow
    }
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cart Help'),
        content: Text('Swipe left on an item to remove it.\nUse the +/- buttons to adjust quantity.\nContact support@zinzi.app for further assistance.'), // Example help text
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Favorites UI Screen
class FavoritesScreen extends StatefulWidget { // Changed to StatefulWidget for refresh
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {

   void _refreshFavorites() {
      setState(() {});
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
      return imageUrl;
    }

  @override
  Widget build(BuildContext context) {
    // Get SHARED favorite items
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
            onPressed: favoriteItems.isNotEmpty ? () => _confirmClearFavorites(context) : null,
          ),
        ],
      ),
      body: Container( // Add background like cart screen
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(0.95), BlendMode.dstATop,
            ),
          ),
        ),
        child: favoriteItems.isEmpty
            ? Center(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Icon(Icons.favorite_border, size: 64, color: Colors.red[200]),
                     SizedBox(height: 24),
                     Text('No Favorites Yet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.teal[800])),
                     SizedBox(height: 12),
                     Text('Tap the ❤️ icon on meals to add them here!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                   ],
                 ),
               )
            : ListView.separated(
                padding: EdgeInsets.all(12),
                itemCount: favoriteItems.length,
                separatorBuilder: (context, index) => SizedBox(height: 8), // Space between cards
                itemBuilder: (context, index) {
                  final item = favoriteItems[index];
                  final String title = item['title'] ?? 'Unknown Item';
                  final double price = (item['price'] as double?) ?? 0.0;
                   final String imageUrl = _formatImageUrl(item['image']);


                  return Card( // Wrap in Card
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                       contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      leading: ClipRRect( // Rounded image
                         borderRadius: BorderRadius.circular(8),
                         child: CachedNetworkImage(
                           imageUrl: imageUrl,
                           width: 55, height: 55, fit: BoxFit.cover,
                           placeholder: (context, url) => Container(width: 55, height: 55, color: Colors.grey[200]),
                           errorWidget: (context, url, error) => Container(width: 55, height: 55, color: Colors.grey[200], child: Icon(Icons.broken_image, color: Colors.grey[400])),
                         ),
                      ),
                      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('\$${price.toStringAsFixed(2)}', style: TextStyle(color: Colors.teal[700])),
                      trailing: Row( // Use Row for multiple icons
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                             message: 'Add to Cart',
                             child: IconButton(
                              icon: Icon(Icons.add_shopping_cart, color: Colors.teal),
                              onPressed: () {
                                Favorites.addToCart(context, title, price, imageUrl); // Use the specific method
                                _refreshFavorites(); // Refresh UI potentially (e.g., show cart count)
                              },
                            ),
                          ),
                           Tooltip(
                             message: 'Remove Favorite',
                             child: IconButton(
                              icon: Icon(Icons.favorite, color: Colors.red), // Filled heart
                              onPressed: () {
                                 _confirmRemoveFavorite(context, title);
                              },
                            ),
                          ),
                        ],
                      ),
                      // Optional: Add onTap to navigate to meal details
                      // onTap: () { /* Navigate to MealDetailScreen for this item */ },
                    ),
                  );
                },
              ),
      ),
    );
  }

   // Confirmation Dialog for removing a single favorite
  Future<void> _confirmRemoveFavorite(BuildContext context, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Favorite?'),
        content: Text('Are you sure you want to remove "$title" from your favorites?'),
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true); // Confirm remove
            },
            child: Text('Remove', style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
       Favorites.removeItem(title);
       _refreshFavorites(); // Update UI
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text('"$title" removed from favorites.'),
         duration: Duration(seconds: 2),
         backgroundColor: Colors.red[600],
       ));
    }
  }

   // Confirmation Dialog for clearing all favorites
  Future<void> _confirmClearFavorites(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Favorites?'),
        content: Text('Are you sure you want to remove all items from your favorites?'),
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true); // Confirm clear
            },
            child: Text('Clear All', style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
       Favorites.clearFavorites();
       _refreshFavorites(); // Update UI
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text('Favorites cleared successfully.'),
         duration: Duration(seconds: 2),
         backgroundColor: Colors.teal[700],
       ));
    }
  }

}