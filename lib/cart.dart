import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';

class ShoppingCart {
  static List<Map<String, dynamic>> items = [];

  static void addItem(String title, double price) {
    items.add({'title': title, 'price': price});
  }

  static List<Map<String, dynamic>> getItems() {
    return items;
  }

  static double getTotal() {
    return items.fold(0, (sum, item) => sum + item['price']);
  }

  static void clearCart() {
    items.clear();
  }

  static void removeItemFromCart(String title) {
    items.removeWhere((item) => item['title'] == title);
  }
}

class Favorites {
  static List<Map<String, dynamic>> items =
      []; // Updated to hold title and price

  static void addItem(String title, double price) {
    if (!items.any((item) => item['title'] == title)) {
      items.add({'title': title, 'price': price});
    }
  }

  static void addToCart(String title, double price) {
    ShoppingCart.addItem(title, price);
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

class ShoppingCartScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cartItems = ShoppingCart.getItems();

    return Scaffold(
      appBar: AppBar(
        title: Text('Shopping Cart'),
      ),
      body: cartItems.isEmpty
          ? Center(child: Text('No items in your cart.'))
          : ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(cartItems[index]['title']),
                  trailing:
                      Text('\$${cartItems[index]['price'].toStringAsFixed(2)}'),
                  leading: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () {
                      ShoppingCart.removeItemFromCart(
                          cartItems[index]['title']);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShoppingCartScreen(),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      bottomNavigationBar: BottomAppBar(
        child: ShoppingCartScreenButton(
          cartItems: cartItems,
          onPressed: () {
            if (cartItems.isEmpty) {
              // Show a Snackbar if the cart is empty
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('Your cart is empty. Please add items to checkout.'),
                ),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => CheckoutScreen(cartItems: cartItems),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

class ShoppingCartScreenButton extends StatelessWidget {
  final List<Map<String, dynamic>> cartItems;
  final VoidCallback onPressed;

  ShoppingCartScreenButton({required this.cartItems, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Text('Checkout'),
      onPressed: cartItems.isNotEmpty ? onPressed : null,
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
      ),
      body: favoritesItems.isEmpty
          ? Center(child: Text('No favorites added.'))
          : ListView.builder(
              itemCount: favoritesItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(favoritesItems[index]['title']),
                  trailing: ElevatedButton(
                    onPressed: () {
                      double itemPrice = favoritesItems[index]
                          ['price']; // Get price from favorites
                      Favorites.addToCart(
                          favoritesItems[index]['title'], itemPrice);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${favoritesItems[index]['title']} added to cart!'),
                        ),
                      );
                    },
                    child: Text('Add to cart'),
                  ),
                );
              },
            ),
    );
  }
}
