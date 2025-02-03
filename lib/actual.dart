import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/meal_detail.dart';
import 'package:zinzi2/useranalytics.dart'; // Ensure the necessary imports
import 'dart:math';
import 'package:zinzi2/blogview.dart';

class ActualRecommendedMealsScreen extends StatefulWidget {
  final List<String>
      selectedCategories; // This will hold the selected categories

  ActualRecommendedMealsScreen({Key? key, required this.selectedCategories})
      : super(key: key);

  @override
  _ActualRecommendedMealsScreenState createState() =>
      _ActualRecommendedMealsScreenState();
}

class _ActualRecommendedMealsScreenState
    extends State<ActualRecommendedMealsScreen> {
  String searchQuery = '';
  TextEditingController _searchController = TextEditingController();
  final Random _random = Random();

  List<Map<String, dynamic>> _meals = [
    {
      'title': 'Chicken Sandwich',
      'description': 'Tender chicken with fresh vegetables.',
      'image': 'assets/images/meal1.jpg',
      'price': 8.99,
      'ingredients': ['Chicken', 'Bread', 'Lettuce', 'Tomato'],
      'categories': ['Sandwich', 'Chicken', 'Weight Loss', 'Omnivore'],
      'bestServedWith': [
        {'title': 'Fries', 'image': 'assets/images/fries.jpg', 'price': 2.99},
        {'title': 'Salad', 'image': 'assets/images/salad.jpg', 'price': 4.50},
        {'title': 'Chips', 'image': 'assets/images/chips.jpg', 'price': 1.50},
      ],
    },
    {
      'title': 'Grilled Salmon',
      'description': 'Grilled salmon with lemon butter sauce.',
      'image': 'assets/images/meal2.jpg',
      'price': 12.50,
      'ingredients': ['Salmon', 'Lemon', 'Butter'],
      'categories': ['Fish', 'Grilled', 'More Energy', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Steamed Vegetables',
          'image': 'assets/images/steamed_vegetables.jpg',
          'price': 3.75
        },
        {
          'title': 'Roasted Potatoes',
          'image': 'assets/images/roasted_potatoes.jpg',
          'price': 3.50
        },
        {
          'title': 'Garlic Bread',
          'image': 'assets/images/garlic_bread.jpg',
          'price': 2.25
        },
      ],
    },
    {
      'title': 'Fried Cassava',
      'description': 'Crispy fried cassava served with dip.',
      'image': 'assets/images/fried_cassava.jpg',
      'price': 7.99,
      'ingredients': ['Cassava'],
      'categories': ['Snack', 'Vegan', 'Gluten-Free', 'Weight Loss'],
      'bestServedWith': [
        {
          'title': 'Guacamole',
          'image': 'assets/images/guacamole.jpg',
          'price': 2.00
        },
        {'title': 'Salsa', 'image': 'assets/images/salsa.jpg', 'price': 1.75},
        {'title': 'Queso', 'image': 'assets/images/queso.jpg', 'price': 2.50},
      ],
    },
    {
      'title': 'Quinoa Salad',
      'description': 'A healthy salad with quinoa and vegetables.',
      'image': 'assets/images/quinoa_salad.jpg',
      'price': 10.50,
      'ingredients': ['Quinoa', 'Vegetables'],
      'categories': ['Bowl', 'Vegan', 'Gluten-Free', 'Muscle Gain'],
      'bestServedWith': [
        {'title': 'Hummus', 'image': 'assets/images/hummus.jpg', 'price': 3.00},
        {
          'title': 'Pita Bread',
          'image': 'assets/images/pita_bread.jpg',
          'price': 2.75
        },
        {
          'title': 'Fruit Bowl',
          'image': 'assets/images/fruit_bowl.jpg',
          'price': 5.00
        },
      ],
    },
    {
      'title': 'Beef Tacos',
      'description': 'Tasty tacos with spiced beef.',
      'image': 'assets/images/beef_tacos.jpg',
      'price': 9.50,
      'ingredients': ['Beef', 'Tortilla', 'Lettuce', 'Cheese'],
      'categories': ['Tacos', 'Beef', 'Weight Gain', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Mexican Rice',
          'image': 'assets/images/mexican_rice.jpg',
          'price': 3.50
        },
        {
          'title': 'Refried Beans',
          'image': 'assets/images/refried_beans.jpg',
          'price': 3.00
        },
        {
          'title': 'Sour Cream',
          'image': 'assets/images/sour_cream.jpg',
          'price': 1.00
        },
      ],
    },
    {
      'title': 'Veggie Wrap',
      'description': 'Healthy wrap filled with fresh vegetables.',
      'image': 'assets/images/veggie_wrap.jpg',
      'price': 8.50,
      'ingredients': ['Vegetables', 'Wrap'],
      'categories': ['Wrap', 'Vegetarian', 'Weight Loss'],
      'bestServedWith': [
        {
          'title': 'Sweet Potato Fries',
          'image': 'assets/images/sweet_potato_fries.jpg',
          'price': 3.50
        },
        {
          'title': 'Cucumber Salad',
          'image': 'assets/images/cucumber_salad.jpg',
          'price': 4.00
        },
        {
          'title': 'Kettle Chips',
          'image': 'assets/images/kettle_chips.jpg',
          'price': 1.25
        },
      ],
    },
    {
      'title': 'Pasta Primavera',
      'description': 'Pasta tossed with seasonal vegetables.',
      'image': 'assets/images/pasta_primavera.jpg',
      'price': 11.00,
      'ingredients': ['Pasta', 'Vegetables'],
      'categories': ['Pasta', 'Vegetarian', 'More Energy'],
      'bestServedWith': [
        {
          'title': 'Garlic Breadsticks',
          'image': 'assets/images/garlic_breadsticks.jpg',
          'price': 2.50
        },
        {
          'title': 'Caesar Salad',
          'image': 'assets/images/caesar_salad_small.jpg',
          'price': 4.50
        },
        {
          'title': 'Parmesan Cheese',
          'image': 'assets/images/parmesan_cheese.jpg',
          'price': 1.50
        },
      ],
    },
    {
      'title': 'Caesar Salad',
      'description': 'Classic Caesar salad with fresh ingredients.',
      'image': 'assets/images/caesar_salad.jpg',
      'price': 10.00,
      'ingredients': ['Lettuce', 'Croutons', 'Caesar Dressing'],
      'categories': ['Salad', 'Chicken', 'Weight Loss', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Grilled Chicken',
          'image': 'assets/images/grilled_chicken.jpg',
          'price': 5.00
        },
        {
          'title': 'Breadsticks',
          'image': 'assets/images/breadsticks.jpg',
          'price': 2.50
        },
        {'title': 'Olives', 'image': 'assets/images/olives.jpg', 'price': 1.00},
      ],
    },
    {
      'title': 'Smoothie Bowl',
      'description': 'A nutritious smoothie bowl topped with fruits.',
      'image': 'assets/images/smoothie_bowl.jpg',
      'price': 6.50,
      'ingredients': ['Fruits', 'Yogurt'],
      'categories': ['Breakfast', 'Vegan', 'Gluten-Free', 'More Energy'],
      'bestServedWith': [
        {
          'title': 'Granola',
          'image': 'assets/images/granola.jpg',
          'price': 1.75
        },
        {
          'title': 'Chia Seeds',
          'image': 'assets/images/chia_seeds.jpg',
          'price': 1.50
        },
        {'title': 'Honey', 'image': 'assets/images/honey.jpg', 'price': 1.00},
      ],
    },
    {
      'title': 'Chicken Curry',
      'description': 'Spicy chicken curry served with rice.',
      'image': 'assets/images/chicken_curry.jpg',
      'price': 12.50,
      'ingredients': ['Chicken', 'Curry Sauce'],
      'categories': ['Curry', 'Chicken', 'Weight Gain', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Naan Bread',
          'image': 'assets/images/naan_bread.jpg',
          'price': 2.50
        },
        {'title': 'Raita', 'image': 'assets/images/raita.jpg', 'price': 1.80},
        {
          'title': 'Poppadoms',
          'image': 'assets/images/poppadoms.jpg',
          'price': 1.00
        },
      ],
    },
    {
      'title': 'Avocado Toast',
      'description': 'Whole grain toast topped with smashed avocado.',
      'image': 'assets/images/avocado_toast.jpg',
      'price': 5.99,
      'ingredients': ['Avocado', 'Bread'],
      'categories': ['Snack', 'Vegan', 'Gluten-Free', 'More Energy'],
      'bestServedWith': [
        {'title': 'Eggs', 'image': 'assets/images/eggs.jpg', 'price': 2.50},
        {
          'title': 'Tomato Salsa',
          'image': 'assets/images/tomato_salsa.jpg',
          'price': 1.50
        },
        {
          'title': 'Balsamic Glaze',
          'image': 'assets/images/balsamic_glaze.jpg',
          'price': 0.75
        },
      ],
    },
    {
      'title': 'Stuffed Peppers',
      'description': 'Peppers stuffed with rice, beans, and spices.',
      'image': 'assets/images/stuffed_peppers.jpg',
      'price': 9.00,
      'ingredients': ['Peppers', 'Beans', 'Spices'],
      'categories': ['Baked', 'Vegetarian', 'Weight Loss', 'Gluten-Free'],
      'bestServedWith': [
        {'title': 'Quinoa', 'image': 'assets/images/quinoa.jpg', 'price': 2.50},
        {
          'title': 'Salsa Verde',
          'image': 'assets/images/salsa_verde.jpg',
          'price': 1.75
        },
        {
          'title': 'Guacamole',
          'image': 'assets/images/guacamole_small.jpg',
          'price': 2.00
        },
      ],
    },
    {
      'title': 'Shrimp Fried Rice',
      'description': 'Fried rice served with shrimp and vegetables.',
      'image': 'assets/images/shrimp_fried_rice.jpg',
      'price': 10.50,
      'ingredients': ['Shrimp', 'Vegetables'],
      'categories': ['Rice', 'Shrimp', 'Weight Gain', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Spring Rolls',
          'image': 'assets/images/spring_rolls.jpg',
          'price': 3.50
        },
        {
          'title': 'Soy Sauce',
          'image': 'assets/images/soy_sauce.jpg',
          'price': 0.50
        },
        {
          'title': 'Green Tea',
          'image': 'assets/images/green_tea.jpg',
          'price': 1.50
        },
      ],
    },
    {
      'title': 'Chickpea Salad',
      'description': 'Nutritious salad with chickpeas and vegetables.',
      'image': 'assets/images/chickpea_salad.jpg',
      'price': 7.50,
      'ingredients': ['Chickpeas', 'Vegetables'],
      'categories': ['Salad', 'Vegan', 'Gluten-Free', 'Muscle Gain'],
      'bestServedWith': [
        {
          'title': 'Whole Wheat Pita',
          'image': 'assets/images/whole_wheat_pita.jpg',
          'price': 1.75
        },
        {
          'title': 'Olive Oil Dressing',
          'image': 'assets/images/olive_oil_dressing.jpg',
          'price': 1.00
        },
        {
          'title': 'Feta Cheese',
          'image': 'assets/images/feta_cheese.jpg',
          'price': 1.50
        },
      ],
    },
    {
      'title': 'Pumpkin Soup',
      'description': 'Creamy pumpkin soup perfect for fall.',
      'image': 'assets/images/pumpkin_soup.jpg',
      'price': 6.50,
      'ingredients': ['Pumpkin', 'Cream', 'Spices'],
      'categories': ['Soup', 'Vegan', 'Gluten-Free', 'Weight Loss'],
      'bestServedWith': [
        {
          'title': 'Crusty Bread',
          'image': 'assets/images/crusty_bread.jpg',
          'price': 2.00
        },
        {
          'title': 'Pepitas',
          'image': 'assets/images/pepitas.jpg',
          'price': 1.50
        },
        {
          'title': 'Cinnamon Croutons',
          'image': 'assets/images/cinnamon_croutons.jpg',
          'price': 1.00
        },
      ],
    },
    {
      'title': 'Eggplant Parmesan',
      'description': 'Layers of eggplant with cheese and marinara sauce.',
      'image': 'assets/images/eggplant_parmesan.jpg',
      'price': 11.50,
      'ingredients': ['Eggplant', 'Cheese', 'Marinara Sauce'],
      'categories': ['Baked', 'Vegetarian', 'Weight Gain'],
      'bestServedWith': [
        {
          'title': 'Garlic Bread',
          'image': 'assets/images/garlic_bread_small.jpg',
          'price': 3.00
        },
        {
          'title': 'Mixed Greens Salad',
          'image': 'assets/images/mixed_greens_salad.jpg',
          'price': 4.00
        },
        {
          'title': 'Red Wine',
          'image': 'assets/images/red_wine.jpg',
          'price': 5.50
        },
      ],
    },
    {
      'title': 'Couscous Bowl',
      'description': 'Couscous topped with seasonal vegetables.',
      'image': 'assets/images/couscous_bowl.jpg',
      'price': 9.50,
      'ingredients': ['Couscous', 'Vegetables'],
      'categories': ['Bowl', 'Vegetarian', 'More Energy'],
      'bestServedWith': [
        {
          'title': 'Grilled Vegetables',
          'image': 'assets/images/grilled_vegetables.jpg',
          'price': 3.50
        },
        {
          'title': 'Lemon Vinaigrette',
          'image': 'assets/images/lemon_vinaigrette.jpg',
          'price': 1.50
        },
        {
          'title': 'Pine Nuts',
          'image': 'assets/images/pine_nuts.jpg',
          'price': 1.50
        },
      ],
    },
    {
      'title': 'Turkey Burger',
      'description': 'Juicy turkey burger with all the fixings.',
      'image': 'assets/images/turkey_burger.jpg',
      'price': 10.50,
      'ingredients': ['Turkey', 'Burger Bun', 'Lettuce', 'Tomato'],
      'categories': ['Burger', 'Turkey', 'Weight Gain', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Onion Rings',
          'image': 'assets/images/onion_rings.jpg',
          'price': 3.00
        },
        {
          'title': 'Coleslaw',
          'image': 'assets/images/coleslaw.jpg',
          'price': 2.50
        },
        {
          'title': 'Pickles',
          'image': 'assets/images/pickles.jpg',
          'price': 0.75
        },
      ],
    },
    {
      'title': 'Greek Yogurt Parfait',
      'description': 'Layers of yogurt, granola, and fresh berries.',
      'image': 'assets/images/greek_yogurt_parfait.jpg',
      'price': 6.00,
      'ingredients': ['Yogurt', 'Granola', 'Berries'],
      'categories': ['Breakfast', 'Dairy', 'More Energy', 'Omnivore'],
      'bestServedWith': [
        {
          'title': 'Honey Drizzle',
          'image': 'assets/images/honey_drizzle.jpg',
          'price': 0.50
        },
        {
          'title': 'Almonds',
          'image': 'assets/images/almonds.jpg',
          'price': 1.50
        },
        {
          'title': 'Fresh Mint',
          'image': 'assets/images/fresh_mint.jpg',
          'price': 0.75
        },
      ],
    },
    {
      'title': 'Lentil Soup',
      'description': 'Hearty soup made with lentils and spices.',
      'image': 'assets/images/lentil_soup.jpg',
      'price': 7.00,
      'ingredients': ['Lentils', 'Vegetables', 'Spices'],
      'categories': ['Soup', 'Vegan', 'Gluten-Free', 'Weight Loss'],
      'bestServedWith': [
        {
          'title': 'Crusty Bread',
          'image': 'assets/images/crusty_bread_small.jpg',
          'price': 2.00
        },
        {
          'title': 'Side Salad',
          'image': 'assets/images/side_salad.jpg',
          'price': 3.50
        },
        {
          'title': 'Chili Flakes',
          'image': 'assets/images/chili_flakes.jpg',
          'price': 0.50
        },
      ],
    },
  ];

  List<Map<String, dynamic>> _filteredMeals = [];

  @override
  void initState() {
    super.initState();
    _filteredMeals = List.from(_meals);
    _searchController.addListener(() {
      _filterMeals(_searchController.text);
    });
    _applyCategoryFilters();
  }

  void _filterMeals(String query) {
    setState(() {
      searchQuery = query;
      _filteredMeals = _meals.where((meal) {
        bool matchesTitle =
            meal['title'].toLowerCase().contains(query.toLowerCase());
        bool matchesCategory = meal['categories']
            .any((cat) => cat.toLowerCase().contains(query.toLowerCase()));

        return matchesTitle || matchesCategory;
      }).toList();
    });
  }

  void _applyCategoryFilters() {
    setState(() {
      if (widget.selectedCategories.isNotEmpty) {
        _filteredMeals = _meals.where((meal) {
          return meal['categories']
              .toSet()
              .intersection(widget.selectedCategories.toSet())
              .isNotEmpty;
        }).toList();
      }
    });
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
        title: Text('Actual Recommended Meals'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: Container(
          color: Colors.teal[100],
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Colors.teal[600]),
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
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.article, color: Colors.teal[800]),
                      title:
                          Text('Blog', style: TextStyle(color: Colors.black)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BlogScreen(
                                url: 'https://artchwezi.blogspot.com/'),
                          ),
                        );

                        ListTile(
                          leading: Icon(Icons.health_and_safety,
                              color: Colors.teal[800]),
                          title: Text('Wellness Communities',
                              style: TextStyle(color: Colors.black)),
                          onTap: () {
                            Navigator.pop(context);
                            // Navigate to Wellness Communities screen
                          },
                        );
                        ListTile(
                          leading: Icon(Icons.help, color: Colors.teal[800]),
                          title: Text('Help',
                              style: TextStyle(color: Colors.black)),
                          onTap: () {
                            Navigator.pop(context);
                            // Navigate to Help screen
                          },
                        );
                      },
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
            ],
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'), // Background image
            fit: BoxFit.cover,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                /*TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                    labelText: 'Search Meals',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search, color: Colors.teal),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.teal),
                      onPressed: () {
                        _searchController.clear();
                        _filterMeals('');
                      },
                    ),
                  ),
                ),*/
                SizedBox(height: 20.0),
                // Meal grid
                GridView.builder(
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
                      child: _buildMealCard(
                          meal['title'], meal['image'], meal['price']),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealCard(String title, String imagePath, double price) {
    return Card(
      elevation: 4,
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
              ),
            ),
            Padding(
              padding: EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.teal, fontSize: 14),
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
