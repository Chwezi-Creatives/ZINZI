import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinzi2/meal_detail.dart';
import 'package:zinzi2/profile.dart';
import 'package:zinzi2/useranalytics.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/blogview.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class Recommend_Meals_Screen extends StatefulWidget {
  @override
  _Recommend_Meals_ScreenState createState() => _Recommend_Meals_ScreenState();
}

class _Recommend_Meals_ScreenState extends State<Recommend_Meals_Screen> {
  TextEditingController _searchController = TextEditingController();
  bool isLoading = true;
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _filteredMeals = [];
  String? selectedCategory;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchMeals();
    _searchController.addListener(() => _filterMeals(_searchController.text));
  }

  Future<void> _fetchMeals() async {
    setState(() => isLoading = true);
    try {
      // Retrieve user_id from SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');

      // Check if user_id is present
      if (userId != null) {
        // Modify API call to include user_id
        final response = await http.get(Uri.parse('$apibaseurl/rr/recommend_meals?user_id=$userId'));

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          
          // Log the decoded response for debugging
          print('Decoded response: $decoded');

          // Check for key and type
          if (decoded is Map<String, dynamic> && decoded.containsKey('recommended_meals')) {
            final rawMeals = decoded['recommended_meals'];

            if (rawMeals is List<dynamic>) {
              final List<Map<String, dynamic>> mealsJson = rawMeals
                  .map<Map<String, dynamic>>((meal) => Map<String, dynamic>.from(meal))
                  .toList();

              // Process each meal
              for (var meal in mealsJson) {
                meal['Nutritional_Info'] = (meal['Nutritional_Info'] is Map)
                    ? Map<String, dynamic>.from(meal['Nutritional_Info'])
                    : {};

                // Ensure all keys in the nutritional info are handled properly
                var nutritionalInfo = meal['Nutritional_Info'] as Map<String, dynamic>;

                nutritionalInfo['calories'] = nutritionalInfo['calories']?.toString() ?? '0';
                nutritionalInfo['carbohydrates'] = nutritionalInfo['carbohydrates']?.toString() ?? '0';
                nutritionalInfo['cholesterol'] = nutritionalInfo['cholesterol']?.toString() ?? '0';
                nutritionalInfo['fats'] = nutritionalInfo['fats']?.toString() ?? '0';
                nutritionalInfo['fiber'] = nutritionalInfo['fiber']?.toString() ?? '0';
                nutritionalInfo['proteins'] = nutritionalInfo['proteins']?.toString() ?? '0';
                nutritionalInfo['sugars'] = nutritionalInfo['sugars']?.toString() ?? '0';
                nutritionalInfo['total_weight'] = nutritionalInfo['total_weight']?.toString() ?? '0';
              }

              setState(() {
                _meals = mealsJson;
                _filteredMeals = List.from(_meals);
                isLoading = false;
              });
            } else {
              throw Exception('Invalid data format: recommended_meals is not a List');
            }
          } else {
            throw Exception('Missing recommended_meals key in the response');
          }
        } else {
          throw Exception('Failed to load meals: ${response.statusCode}');
        }
      } else {
        throw Exception('User ID not found in Shared Preferences');
      }
    } catch (e) {
      print('Error fetching meals: $e');
      setState(() {
        _meals = [];
        _filteredMeals = [];
        isLoading = false;
      });
    }
  }

  void _filterMeals(String query) {
    final cleanQuery = query.toLowerCase().trim();
    setState(() {
      searchQuery = cleanQuery;
      _filteredMeals = _meals.where((meal) {
        final title = meal['Meal_name']?.toString().toLowerCase() ?? '';
        return title.contains(cleanQuery);
      }).toList();
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
        backgroundColor: Colors.teal[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ShoppingCartScreen()),
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Container(
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
                  padding: EdgeInsets.all(4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.5),
                            labelText: 'Search Meals',
                            labelStyle: TextStyle(color: Colors.teal[900]),
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
                      ),
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
        crossAxisSpacing: 6.0,
        mainAxisSpacing: 6.0,
        childAspectRatio: 0.9,
      ),
      itemCount: _filteredMeals.length,
      itemBuilder: (context, index) {
        final meal = _filteredMeals[index];
        String title = meal['Meal_name'] ?? 'Unknown Meal';
        String imagePath = meal['Image_link'] ?? 'assets/images/mealimageplaceholder.jpg';
        double price = double.tryParse(meal['Nutritional_Info']['calories'] ?? '0') ?? 5.0; // Default price if not provided

        if (imagePath.contains('drive.google.com')) {
          String fileId = imagePath.split('/d/')[1].split('/')[0];
          imagePath = 'https://drive.google.com/uc?export=view&id=$fileId';
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => MealDetailScreen(meal: meal)),
            );
          },
          child: _buildMealCard(title, imagePath, price),
        );
      },
    );
  }

  Widget _buildMealCard(String title, String imagePath, double price) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.teal[600]!,
              Colors.teal[800]!,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Expanded(
                child: CachedNetworkImage(
                  imageUrl: imagePath,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => CircularProgressIndicator(),
                  errorWidget: (context, url, error) => Image.asset(
                    'assets/images/mealimageplaceholder.jpg',
                    fit: BoxFit.cover,
                  ),
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
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'UGX ${price.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.teal[100],
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.teal[600]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: AssetImage('assets/images/proffr.png'),
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User Name',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'user@example.com',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    title: Text('Profile', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ProfilePage()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.analytics, color: Colors.teal[800]),
                    title: Text('Analytics Dashboard', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => UserAnalyticsDashboard()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.shopping_cart, color: Colors.teal[800]),
                    title: Text('Shopping Cart', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ShoppingCartScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.article, color: Colors.teal[800]),
                    title: Text('Blog', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => BlogScreen(url: 'https://artchwezi.blogspot.com/')),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.health_and_safety, color: Colors.teal[800]),
                    title: Text('Wellness Communities', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      // Navigate to Wellness Communities screen
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.help, color: Colors.teal[800]),
                    title: Text('Help', style: TextStyle(color: Colors.black)),
                    onTap: () {
                      // Navigate to Help screen
                    },
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
