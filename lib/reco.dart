import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/useranalytics.dart';

class RecommendedMealsScreen extends StatefulWidget {
  @override
  _RecommendedMealsScreenState createState() => _RecommendedMealsScreenState();
}

class _RecommendedMealsScreenState extends State<RecommendedMealsScreen> {
  String? selectedDietaryPreference; // Track selected dietary preference
  String? selectedHealthGoal; // Track selected health goal
  String searchQuery = '';

  // Sample meal list
  List<Map<String, dynamic>> _meals = [
    {
      'title': 'Chicken Sandwich',
      'description': 'Chicken flesh, tomatoes, 380 cal, high protein',
      'image': 'assets/images/meal1.jpg',
      'price': 8.99,
      'dietary_preferences': ['Vegan'],
      'health_goals': ['Weight Loss'],
    },
    {
      'title': 'Meal 2',
      'description': 'Description for Meal 2',
      'image': 'assets/images/meal2.jpg',
      'price': 12.50,
      'dietary_preferences': ['Omnivore'],
      'health_goals': ['More Energy'],
    },
    {
      'title': 'Fried Cassava',
      'description':
          'Crispy fried cassava served with spicy dip, approximately 250 cal.',
      'image': 'assets/images/fried_cassava.jpg',
      'price': 5.99,
      'dietary_preferences': ['Gluten-free'],
      'health_goals': ['Weight Loss'],
    },
  ];

  late List<Map<String, dynamic>> _filteredMeals;

  @override
  void initState() {
    super.initState();
    _filteredMeals = List.from(_meals);
  }

  void _filterMeals(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        _applyFilters();
      } else {
        _filteredMeals = _meals
            .where((meal) =>
                meal['title'].toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredMeals = _meals.where((meal) {
        bool matchesDietary = selectedDietaryPreference == null ||
            meal['dietary_preferences'].contains(selectedDietaryPreference);
        bool matchesHealthGoals = selectedHealthGoal == null ||
            meal['health_goals'].contains(selectedHealthGoal);
        return matchesDietary && matchesHealthGoals;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      selectedDietaryPreference = null;
      selectedHealthGoal = null;
      _filteredMeals = List.from(_meals);
    });
  }

  void _clearSearch() {
    setState(() {
      searchQuery = '';
      _filterMeals('');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recommended Meals'),
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
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[300]),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.person),
              title: Text('Profile'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.analytics),
              title: Text('Analytics Dashboard'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => UserAnalyticsDashboard()),
                );
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
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
                controller: TextEditingController(text: searchQuery),
                onChanged: (query) {
                  _filterMeals(query);
                },
                decoration: InputDecoration(
                  labelText: 'Search Meals',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.clear),
                    onPressed: _clearSearch,
                  ),
                ),
              ),
              SizedBox(height: 20.0),
              ExpansionTile(
                title: Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dietary Preferences',
                          style: TextStyle(
                              fontSize: 16.0, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10.0),
                      _buildRadioTile('Vegan', selectedDietaryPreference),
                      _buildRadioTile('Gluten-free', selectedDietaryPreference),
                      _buildRadioTile('Omnivore', selectedDietaryPreference),
                      SizedBox(height: 20.0),
                      Text('Health Goals',
                          style: TextStyle(
                              fontSize: 16.0, fontWeight: FontWeight.bold)),
                      SizedBox(height: 10.0),
                      _buildRadioTile('Weight Loss', selectedHealthGoal),
                      _buildRadioTile('Weight Gain', selectedHealthGoal),
                      _buildRadioTile('More Energy', selectedHealthGoal),
                      SizedBox(height: 20.0),
                      ElevatedButton(
                        onPressed: _clearFilters,
                        child: Text('Clear Filters'),
                        style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 12.0)),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20.0),
              _buildAnimatedMealList(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedMealList(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _filteredMeals.length,
      itemBuilder: (context, index) {
        final meal = _filteredMeals[index];
        return AnimatedScale(
          duration: Duration(milliseconds: 300),
          scale: 1.0,
          child: GestureDetector(
            onTap: () {
              // Add transition or action here if needed
            },
            child: Column(
              children: [
                _buildMealCard(meal['title'], meal['description'],
                    meal['image'], meal['price']),
                SizedBox(height: 20.0),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRadioTile(String title, String? groupValue) {
    return RadioListTile<String>(
      title: Text(title),
      value: title,
      groupValue: groupValue,
      onChanged: (String? value) {
        setState(() {
          if (title == 'Vegan' ||
              title == 'Gluten-free' ||
              title == 'Omnivore') {
            selectedDietaryPreference =
                value; // Update selected dietary preference
          } else {
            selectedHealthGoal = value; // Update selected health goal
          }
          _applyFilters();
        });
      },
    );
  }

  Widget _buildMealCard(
      String title, String description, String imagePath, double price) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Image.asset(
              imagePath,
              width: 80.0,
              height: 80.0,
              fit: BoxFit.cover,
            ),
            SizedBox(width: 16.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style:
                        TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8.0),
                  Text(description),
                  SizedBox(height: 8.0),
                  Text('\$${price.toStringAsFixed(2)}'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.favorite_border),
                        onPressed: () {
                          Favorites.addItem(title, price);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('$title added to favorites!')));
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.add_shopping_cart),
                        onPressed: () {
                          ShoppingCart.addItem(title, price);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$title added to cart!')));
                        },
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
  }
}
