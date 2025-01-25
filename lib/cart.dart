import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';

class ShoppingCart {
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price, {int quantity = 1}) {
    final existingItemIndex =
        items.indexWhere((item) => item['title'] == title);
    if (existingItemIndex != -1) {
      items[existingItemIndex]['quantity'] += quantity;
    } else {
      items.add({'title': title, 'price': price, 'quantity': quantity});
    }
  }

  static List<Map<String, dynamic>> getItems() {
    return items;
  }

  static double getTotal() {
    return items.fold(
        0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  static void clearCart() {
    items.clear();
  }

  static void removeItemFromCart(String title) {
    items.removeWhere((item) => item['title'] == title);
  }

  static void updateQuantity(String title, int newQuantity) {
    final existingItemIndex =
        items.indexWhere((item) => item['title'] == title);
    if (existingItemIndex != -1) {
      if (newQuantity > 0) {
        items[existingItemIndex]['quantity'] = newQuantity;
      } else {
        removeItemFromCart(title);
      }
    }
  }
}

class Favorites {
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price, String image) {
    if (!items.any((item) => item['title'] == title)) {
      items.add({'title': title, 'price': price, 'image': image});
    }
  }

  static void addToCart(String title, double price, {int quantity = 1}) {
    ShoppingCart.addItem(title, price, quantity: quantity);
  }

  static List<Map<String, dynamic>> getItems() {
    return items;
  }

  static void clearFavorites() {
    items.clear();
  }

  static void removeItem(String title) {
    items.removeWhere((item) => item['title'] == title);
  }
}

class ShoppingCartScreen extends StatefulWidget {
  @override
  _ShoppingCartScreenState createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  void _refreshCart() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ShoppingCart.getItems();
    final totalAmount = ShoppingCart.getTotal();

    return Scaffold(
      appBar: AppBar(
        title: Text('Shopping Cart'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ShoppingCartScreen(),
                ),
              );
            },
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
        child: cartItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined,
                        size: 64, color: Colors.teal[300]),
                    SizedBox(height: 24),
                    Text('Your Cart is Empty',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: Colors.teal[800])),
                    SizedBox(height: 12),
                    Text('Explore our menu to add delicious meals!',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey[600])),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    child: Row(
                      children: [
                        Chip(
                          label: Text(
                              '${cartItems.length} ${cartItems.length > 1 ? 'Items' : 'Item'}',
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.teal[800],
                        ),
                        Spacer(),
                        Text('Estimated Total:',
                            style: TextStyle(color: Colors.grey[600])),
                        SizedBox(width: 8),
                        Text('\$${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[800])),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: cartItems.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 24, color: Colors.grey[200]),
                      itemBuilder: (context, index) {
                        return _buildCartItemCard(cartItems[index], context);
                      },
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: Container(
        height: 100,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: Icon(Icons.lock_outline, size: 20),
              label: Text('Secure Checkout', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[800],
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed:
                  cartItems.isNotEmpty ? () => _handleCheckout(context) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItemCard(Map<String, dynamic> item, BuildContext context) {
    return Dismissible(
      key: Key(item['title']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_forever, color: Colors.red[600], size: 32),
      ),
      confirmDismiss: (direction) =>
          _confirmItemRemoval(context, item['title']),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(Icons.check_circle_outline,
              color: Colors.teal[400], size: 28),
          title: Text(item['title'],
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          subtitle: Text('In Stock • Ready to Ship',
              style: TextStyle(color: Colors.green[600], fontSize: 12)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${(item['price'] * item['quantity']).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _buildQuantityControls(item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityControls(Map<String, dynamic> item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.remove, size: 18),
          onPressed: () {
            setState(() {
              ShoppingCart.updateQuantity(item['title'], item['quantity'] - 1);
            });
          },
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
        ),
        Text('${item['quantity']}', style: TextStyle(fontSize: 14)),
        IconButton(
          icon: Icon(Icons.add, size: 18),
          onPressed: () {
            setState(() {
              ShoppingCart.updateQuantity(item['title'], item['quantity'] + 1);
            });
          },
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
        ),
      ],
    );
  }

  Future<bool?> _confirmItemRemoval(BuildContext context, String title) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Item'),
        content: Text('Are you sure you want to remove $title from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.teal[800])),
          ),
          TextButton(
            onPressed: () {
              ShoppingCart.removeItemFromCart(title);
              Navigator.of(context).pop(true);
              _refreshCart();
            },
            child: Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void showCustomSnackBar(BuildContext context, String message) {
    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      margin:
          EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0, bottom: 110.0),
      backgroundColor: Colors.teal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      content: Text(
        message,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  void _handleCheckout(BuildContext context) {
    if (ShoppingCart.getItems().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your cart is empty. Please add items to checkout.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.teal[800],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CheckoutScreen(cartItems: ShoppingCart.getItems()),
        ),
      );
    }
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cart Help'),
        content:
            Text('Need assistance with your shopping cart? Contact support.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: TextStyle(color: Colors.teal[800])),
          ),
        ],
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final favoritesItems = Favorites.getItems();

    return Scaffold(
      appBar: AppBar(
        title: Text('Favorites'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ShoppingCartScreen(),
                ),
              );
            },
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
          children: [
            Expanded(
              child: favoritesItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border_rounded,
                              size: 64, color: Colors.teal[300]),
                          SizedBox(height: 24),
                          Text('No Favorites Yet',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.teal[800])),
                          SizedBox(height: 12),
                          Text('Tap the heart icon to save your favorite meals',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: favoritesItems.length,
                      itemBuilder: (context, index) {
                        return _buildFavoriteItemCard(
                            favoritesItems[index], context);
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ElevatedButton.icon(
                icon: Icon(Icons.shopping_cart, size: 20),
                label: Text('Go to Cart', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[800],
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShoppingCartScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteItemCard(
      Map<String, dynamic> item, BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              child: Image.asset(
                item['image'] ?? 'assets/images/meal_placeholder.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'],
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: 6),
                Text('\$${item['price'].toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 14, color: Colors.teal[800])),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal[800],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child:
                            Text('Add to Cart', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Favorites.addToCart(item['title'], item['price']);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${item['title']} added to cart!'),
                              backgroundColor: Colors.teal[800],
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(
                                  top: 16.0,
                                  left: 16.0,
                                  right: 16.0,
                                  bottom: 110.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child:
                            Text('Order Now', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Favorites.addToCart(item['title'], item['price']);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CheckoutScreen(
                                  cartItems: ShoppingCart.getItems()),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
