import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/useranalytics.dart';
import 'dart:math';

class RecommendedMealsScreen extends StatefulWidget {
  @override
  _RecommendedMealsScreenState createState() => _RecommendedMealsScreenState();
}

class _RecommendedMealsScreenState extends State<RecommendedMealsScreen> {
  String? selectedCategory;
  String searchQuery = '';
  TextEditingController _searchController = TextEditingController();
  final Random _random = Random();

  List<Map<String, dynamic>> _meals = [
    {
      'title': 'Chicken Sandwich',
      'description': 'Tender chicken with fresh vegetables.',
      'image': 'assets/images/meal1.jpg',
      'price': 8.99,
      'categories': ['Sandwich', 'Chicken', 'Weight Loss', 'Omnivore'],
    },
    {
      'title': 'Grilled Salmon',
      'description': 'Grilled salmon with lemon butter sauce.',
      'image': 'assets/images/meal2.jpg',
      'price': 12.50,
      'categories': ['Fish', 'Grilled', 'More Energy', 'Omnivore'],
    },
    {
      'title': 'Fried Cassava',
      'description': 'Crispy fried cassava served with dip.',
      'image': 'assets/images/fried_cassava.jpg',
      'price': 7.99,
      'categories': ['Snack', 'Vegan', 'Gluten-Free', 'Weight Loss'],
    },
    {
      'title': 'Quinoa Salad',
      'description': 'A healthy salad with quinoa and vegetables.',
      'image': 'assets/images/quinoa_salad.jpg',
      'price': 10.50,
      'categories': ['Bowl', 'Vegan', 'Gluten-Free', 'Muscle Gain'],
    },
    {
      'title': 'Beef Tacos',
      'description': 'Tasty tacos with spiced beef.',
      'image': 'assets/images/beef_tacos.jpg',
      'price': 9.50,
      'categories': ['Tacos', 'Beef', 'Weight Gain', 'Omnivore'],
    },
    {
      'title': 'Veggie Wrap',
      'description': 'Healthy wrap filled with fresh vegetables.',
      'image': 'assets/images/veggie_wrap.jpg',
      'price': 8.50,
      'categories': ['Wrap', 'Vegetarian', 'Weight Loss'],
    },
    {
      'title': 'Pasta Primavera',
      'description': 'Pasta tossed with seasonal vegetables.',
      'image': 'assets/images/pasta_primavera.jpg',
      'price': 11.00,
      'categories': ['Pasta', 'Vegetarian', 'More Energy'],
    },
    {
      'title': 'Caesar Salad',
      'description': 'Classic Caesar salad with fresh ingredients.',
      'image': 'assets/images/caesar_salad.jpg',
      'price': 10.00,
      'categories': ['Salad', 'Chicken', 'Weight Loss', 'Omnivore'],
    },
    {
      'title': 'Smoothie Bowl',
      'description': 'A nutritious smoothie bowl topped with fruits.',
      'image': 'assets/images/smoothie_bowl.jpg',
      'price': 6.50,
      'categories': ['Breakfast', 'Vegan', 'Gluten-Free', 'More Energy'],
    },
    {
      'title': 'Chicken Curry',
      'description': 'Spicy chicken curry served with rice.',
      'image': 'assets/images/chicken_curry.jpg',
      'price': 12.50,
      'categories': ['Curry', 'Chicken', 'Weight Gain', 'Omnivore'],
    },
    {
      'title': 'Avocado Toast',
      'description': 'Whole grain toast topped with smashed avocado.',
      'image': 'assets/images/avocado_toast.jpg',
      'price': 5.99,
      'categories': ['Snack', 'Vegan', 'Gluten-Free', 'More Energy'],
    },
    {
      'title': 'Stuffed Peppers',
      'description': 'Peppers stuffed with rice, beans, and spices.',
      'image': 'assets/images/stuffed_peppers.jpg',
      'price': 9.00,
      'categories': ['Baked', 'Vegetarian', 'Weight Loss', 'Gluten-Free'],
    },
    {
      'title': 'Shrimp Fried Rice',
      'description': 'Fried rice served with shrimp and vegetables.',
      'image': 'assets/images/shrimp_fried_rice.jpg',
      'price': 10.50,
      'categories': ['Rice', 'Shrimp', 'Weight Gain', 'Omnivore'],
    },
    {
      'title': 'Chickpea Salad',
      'description': 'Nutritious salad with chickpeas and vegetables.',
      'image': 'assets/images/chickpea_salad.jpg',
      'price': 7.50,
      'categories': ['Salad', 'Vegan', 'Gluten-Free', 'Muscle Gain'],
    },
    {
      'title': 'Pumpkin Soup',
      'description': 'Creamy pumpkin soup perfect for fall.',
      'image': 'assets/images/pumpkin_soup.jpg',
      'price': 6.50,
      'categories': ['Soup', 'Vegan', 'Gluten-Free', 'Weight Loss'],
    },
    {
      'title': 'Eggplant Parmesan',
      'description': 'Layers of eggplant with cheese and marinara sauce.',
      'image': 'assets/images/eggplant_parmesan.jpg',
      'price': 11.50,
      'categories': ['Baked', 'Vegetarian', 'Weight Gain'],
    },
    {
      'title': 'Couscous Bowl',
      'description': 'Couscous topped with seasonal vegetables.',
      'image': 'assets/images/couscous_bowl.jpg',
      'price': 9.50,
      'categories': ['Bowl', 'Vegetarian', 'More Energy'],
    },
    {
      'title': 'Turkey Burger',
      'description': 'Juicy turkey burger with all the fixings.',
      'image': 'assets/images/turkey_burger.jpg',
      'price': 10.50,
      'categories': ['Burger', 'Turkey', 'Weight Gain', 'Omnivore'],
    },
    {
      'title': 'Greek Yogurt Parfait',
      'description': 'Layers of yogurt, granola, and fresh berries.',
      'image': 'assets/images/greek_yogurt_parfait.jpg',
      'price': 6.00,
      'categories': ['Breakfast', 'Dairy', 'More Energy', 'Omnivore'],
    },
    {
      'title': 'Lentil Soup',
      'description': 'Hearty soup made with lentils and spices.',
      'image': 'assets/images/lentil_soup.jpg',
      'price': 7.00,
      'categories': ['Soup', 'Vegan', 'Gluten-Free', 'Weight Loss'],
    },
  ];

  late List<Map<String, dynamic>> _filteredMeals;

  @override
  void initState() {
    super.initState();
    _filteredMeals = List.from(_meals);
    _searchController.addListener(() {
      _filterMeals(_searchController.text);
    });
  }

  void _filterMeals(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        _applyFilters();
      } else {
        _filteredMeals = _meals.where((meal) {
          String title = meal['title'] as String;
          bool matchesTitle = title.toLowerCase().contains(query.toLowerCase());

          List<dynamic> categories = meal['categories'] as List<dynamic>;
          bool matchesCategory = categories.any((cat) {
            return (cat is String) &&
                cat.toLowerCase().contains(query.toLowerCase());
          });

          return matchesTitle || matchesCategory;
        }).toList();
      }
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredMeals = _meals.where((meal) {
        bool matchesCategory = selectedCategory == null ||
            meal['categories'].contains(selectedCategory!);
        return matchesCategory;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      selectedCategory = null;
      _filteredMeals = List.from(_meals);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filterMeals('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recommended Meals'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FavoritesScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShoppingCartScreen(),
                ),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          color: Colors.teal[100], // New background color for the drawer
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                    color: Colors.teal[600]), // Original header color
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Menu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Choose an option below:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(Icons.person, color: Colors.teal[800]),
                      title: Text('Profile',
                          style: TextStyle(color: Colors.black)),
                      onTap: () {
                        // Navigate to Profile
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.analytics, color: Colors.teal[800]),
                      title: Text('Analytics Dashboard',
                          style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => UserAnalyticsDashboard()),
                        );
                      },
                    ),
                    Divider(),
                    ListTile(
                      leading:
                          Icon(Icons.shopping_cart, color: Colors.teal[800]),
                      title: Text('Shopping Cart',
                          style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ShoppingCartScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                color: Colors.teal[100],
                height: 60,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    '',
                    style: TextStyle(
                      color: Colors.teal[800],
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 200.0,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.0),
                    child: Image.asset(
                      'assets/images/meals_slideshow.gif',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SizedBox(height: 20.0),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                    labelText: 'Search Meals',
                    labelStyle: TextStyle(color: Colors.black),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.teal),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black12),
                    ),
                    prefixIcon: Icon(Icons.search, color: Colors.teal),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.teal),
                      onPressed: _clearSearch,
                    ),
                  ),
                ),
                SizedBox(height: 10.0),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  collapsedBackgroundColor: Colors.white.withOpacity(0.8),
                  backgroundColor: Colors.teal.withOpacity(0.01),
                  title: Text('  Show Filters',
                      style: TextStyle(color: Colors.teal[700])),
                  children: [
                    _buildFilterOptions(),
                  ],
                ),
                SizedBox(height: 20.0),
                _buildMealGrid(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealGrid(BuildContext context) {
    return GridView.builder(
      physics: NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        childAspectRatio: 0.8,
      ),
      itemCount: _filteredMeals.length,
      itemBuilder: (context, index) {
        final meal = _filteredMeals[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MealDetailScreen(meal: meal),
              ),
            );
          },
          child: _buildMealCard(meal['title'], meal['image'], meal['price']),
        );
      },
    );
  }

  Widget _buildFilterOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filters',
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: _getUniqueCategories().map((category) {
            return ChoiceChip(
              label: Text(
                category,
                style: TextStyle(color: Colors.white),
              ),
              selected: selectedCategory == category,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    selectedCategory = category;
                  } else {
                    selectedCategory = null;
                  }
                  _applyFilters();
                });
              },
              backgroundColor: Colors.teal[800],
              selectedColor: Colors.orange,
              elevation: 2,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 20.0),
        ElevatedButton(
          onPressed: _clearFilters,
          child: Text('Clear Filters', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: EdgeInsets.symmetric(vertical: 9.0),
          ),
        ),
      ],
    );
  }

  List<String> _getUniqueCategories() {
    final Set<String> categories = {};
    for (var meal in _meals) {
      categories.addAll(meal['categories']);
    }
    return categories.toList();
  }

  Widget _buildMealCard(String title, String imagePath, double price) {
    return Card(
      elevation: 4,
      color: Colors.orangeAccent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                imagePath,
                width: double.infinity,
                fit: BoxFit.cover,
                color: Colors.white,
                colorBlendMode: BlendMode.dstATop,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4.0),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[900],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showCustomSnackBar(BuildContext context, String message) {
  final snackBar = SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0, bottom: 110.0),
    backgroundColor: Colors.teal[700],
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.0),
    ),
    content: Text(
      message,
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
    ),
  );

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(snackBar);
}

class MealDetailScreen extends StatelessWidget {
  final Map<String, dynamic> meal;

  MealDetailScreen({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(meal['title']),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal[800],
        elevation: 0,
        actions: [
          // Added actions section
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FavoritesScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 250,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.asset(
                      meal['image'],
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal['title'],
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800],
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        meal['description'],
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(
                        'Price:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '\$${meal['price'].toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[600],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 34),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meal type:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: meal['categories'].map<Widget>((category) {
                          return Chip(
                            label: Text(category),
                            backgroundColor: Colors.teal[50],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            labelStyle: TextStyle(
                              color: Colors.teal[800],
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 42),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.favorite,
                                size: 20,
                                color: Colors.teal,
                              ),
                              label: Text('Favorite'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                minimumSize: Size.fromHeight(50),
                              ),
                              onPressed: () {
                                Favorites.addItem(meal['title'], meal['price'],
                                    meal['image']);
                                showCustomSnackBar(context,
                                    '${meal['title']} added to favorites!');
                              },
                            ),
                          ),
                        ),
                        Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.shopping_cart,
                                size: 20,
                                color: Colors.teal,
                              ),
                              label: Text('Add to Cart'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                minimumSize: Size.fromHeight(50),
                              ),
                              onPressed: () {
                                ShoppingCart.addItem(
                                    meal['title'], meal['price']);
                                showCustomSnackBar(
                                    context, '${meal['title']} added to cart!');
                              },
                            ),
                          ),
                        ),
                        Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: ElevatedButton.icon(
                              icon: Icon(
                                Icons.credit_card,
                                size: 20,
                                color: Colors.teal,
                              ),
                              label: Text('Order Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                minimumSize: Size.fromHeight(50),
                              ),
                              onPressed: () {
                                ShoppingCart.addItem(
                                    meal['title'], meal['price']);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CheckoutScreen(
                                      cartItems: ShoppingCart.items,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
