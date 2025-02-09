import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/chef.dart';
import 'package:zinzi2/useranalytics.dart';
import 'reco.dart';

class MealDetailScreen extends StatefulWidget {
  final Map<String, dynamic> meal;

  MealDetailScreen({required this.meal});

  @override
  _MealDetailScreenState createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  bool isFavorite = false;
  bool cookForMyself = true;
  Map<String, dynamic>? selectedChef;

  List<Map<String, dynamic>> chefs = [
    {
      'image': 'assets/images/kharol.jpg',
      'name': 'Kharol',
      'price': 7,
      'rating': 3,
      'location': 'KATWE',
    },
    {
      'image': 'assets/images/dani3.jpg',
      'name': 'Dani',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/abdul.jpg',
      'name': 'Abdul',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/zay.jpg',
      'name': 'Nick',
      'price': 45,
      'rating': 5,
      'location': 'NEW YORK',
    },
    {
      'image': 'assets/images/victor.jpg',
      'name': 'Victor',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/dante.jpg',
      'name': 'Dante',
      'price': 4,
      'rating': 2,
      'location': 'MAWANDA Rd',
    },
  ];

  @override
  void initState() {
    super.initState();
    isFavorite = Favorites.isFavorite(widget.meal['title']);
  }

  @override
  Widget build(BuildContext context) {
    final isInCart =
        ShoppingCart.items.any((item) => item['title'] == widget.meal['title']);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.meal['title']),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal[800],
        elevation: 4,
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
      body: SizedBox.expand(
        child: Container(
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
                  // Meal Image
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
                        widget.meal['image'],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Meal Title with Buttons
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.meal['title'],
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[800],
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                widget.meal['description'],
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Add to Favorites and Cart Buttons
                        Column(
                          children: [
                            IconButton(
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_outline,
                                color: isFavorite ? Colors.red : null,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isFavorite) {
                                    Favorites.removeItem(widget.meal['title']);
                                    isFavorite = false;
                                  } else {
                                    Favorites.addItem(
                                        widget.meal['title'],
                                        widget.meal['price'],
                                        widget.meal['image']);
                                    showCustomSnackBar(context,
                                        '${widget.meal['title']} added to favorites!');
                                    isFavorite = true;
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                isInCart
                                    ? Icons.shopping_cart
                                    : Icons.add_shopping_cart,
                                color: isInCart ? Colors.orange : null,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isInCart) {
                                    ShoppingCart.removeItemFromCart(
                                        widget.meal['title']);
                                    showCustomSnackBar(context,
                                        '${widget.meal['title']} removed from cart!');
                                  } else {
                                    ShoppingCart.addItem(
                                      widget.meal['title'],
                                      widget.meal['price'],
                                      bestServedWith:
                                          widget.meal['bestServedWith'],
                                      selectedChef: selectedChef,
                                    );
                                    showCustomSnackBar(context,
                                        '${widget.meal['title']} added to cart!');
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),

                  // Ingredients Section
                  Row(
                    children: [
                      Expanded(
                        child: _buildIngredientsSection(),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Properties Section
                  Row(
                    children: [
                      Expanded(
                        child: _buildPropertiesSection(),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Skill Level and Prep Time Card
                  _buildSkillLevelAndPrepTimeCard(),

                  SizedBox(height: 20),

                  // Cook for Myself Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cookForMyself ? 'Cook for Myself' : 'Hire a Chef',
                        style: TextStyle(fontSize: 16),
                      ),
                      Switch(
                        value: cookForMyself,
                        onChanged: (bool value) async {
                          setState(() {
                            cookForMyself = value;
                          });
                          if (!cookForMyself) {
                            final selectedChef = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChooseChef(chefs: chefs),
                              ),
                            );

                            if (selectedChef != null) {
                              setState(() {
                                this.selectedChef = selectedChef;
                              });
                              ShoppingCart.addItem(
                                  selectedChef['name'], selectedChef['price'],
                                  selectedChef: selectedChef);
                              showCustomSnackBar(context,
                                  '${selectedChef['name']} added to cart!');
                            }
                          } else {
                            setState(() {
                              selectedChef = null;
                            });
                          }
                        },
                        activeColor: Colors.teal[900],
                        inactiveTrackColor: Colors.grey,
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // Display selected chef information if available
                  if (selectedChef != null) _buildChefCard(selectedChef!),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIngredientsSection() {
    return Card(
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingredients',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.meal['ingredients'].map<Widget>((ingredient) {
                return Chip(
                  label: Text(
                    ingredient,
                    style: TextStyle(
                      color: Colors.teal[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesSection() {
    return Card(
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Health info',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildPropertyChipFromAsset('assets/images/goal.png',
                    'Health Goal', widget.meal['healthGoal']),
                _buildPropertyChipFromAsset('assets/images/dairy_free2.png',
                    'Allergens', widget.meal['allergens'].join(', ') ?? 'None'),

                _buildPropertyChip(Icons.health_and_safety, 'Diseases Managed',
                    widget.meal['diseasesManaged'].join(', ') ?? 'None'),
                // Using Image.asset instead of Icon for Health Goal

                _buildPropertyChipFromAsset('assets/images/recipe1.png',
                    'Recipe', widget.meal['recipe']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyChip(IconData icon, String label, String data) {
    return InkWell(
      onTap: () {
        _showPopup(context, label, data);
      },
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: Colors.teal[50],
          child: Icon(icon, color: Colors.teal[800]),
        ),
        label: Text(label),
        backgroundColor: Colors.teal[50],
      ),
    );
  }

  Widget _buildPropertyChipFromAsset(
      String assetPath, String label, String data) {
    return InkWell(
      onTap: () {
        _showPopup(context, label, data);
      },
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: Colors.teal[50],
          child: Image.asset(assetPath, width: 24, height: 24),
        ),
        label: Text(label),
        backgroundColor: Colors.teal[50],
      ),
    );
  }

  void _showPopup(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkillLevelAndPrepTimeCard() {
    double skillLevelValue =
        getSkillLevelValue(widget.meal['cookingSkillLevel']);
    double prepTimeValue = getPrepTimeValue(widget.meal['prepTime']);

    return Card(
      elevation: 1,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cooking time and skill',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            SizedBox(height: 12),
            Text('Skill Level:  ${widget.meal['cookingSkillLevel']}'),
            LinearProgressIndicator(
              value: skillLevelValue,
              color: Colors.teal[600],
              backgroundColor: Colors.grey[300],
            ),
            SizedBox(height: 16),
            Text('Prep Time: ${widget.meal['prepTime']} minutes'),
            LinearProgressIndicator(
              value: prepTimeValue,
              color: Colors.teal[600],
              backgroundColor: Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }

  double getSkillLevelValue(String skillLevel) {
    switch (skillLevel.toLowerCase()) {
      case 'beginner':
        return 0.33;
      case 'intermediate':
        return 0.67;
      case 'advanced':
        return 1.0;
      default:
        return 0.0;
    }
  }

  double getPrepTimeValue(String prepTime) {
    const maxPrepTime = 60;
    int prepMinutes = int.parse(prepTime);
    return (prepMinutes / maxPrepTime).clamp(0.0, 1.0);
  }

  Widget _buildChefCard(Map<String, dynamic> chef) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Row(
          children: [
            ClipOval(
              child: Image.asset(
                chef['image'],
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chef['name'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      _buildStarRating(chef['rating']),
                      SizedBox(width: 8),
                      Text('(${chef['location']})',
                          style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              '\$${chef['price']}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating(int rating) {
    List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      stars.add(Icon(i < rating ? Icons.star : Icons.star_border,
          color: Colors.amber, size: 16));
    }
    return Row(children: stars);
  }

  void showCustomSnackBar(BuildContext context, String message) {
    final snackBar = SnackBar(
      content: Text(message),
      duration: Duration(seconds: 2),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}

class ChooseChef extends StatelessWidget {
  final List<Map<String, dynamic>> chefs;

  const ChooseChef({Key? key, required this.chefs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Available Chefs'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: chefs.length,
        itemBuilder: (context, index) {
          final chef = chefs[index];
          return Card(
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: InkWell(
              onTap: () {
                Navigator.pop(context, chef); // Pass the selected chef back
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        chef['image'],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chef['name'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              _buildStarRating(chef['rating']),
                              SizedBox(width: 8),
                              Text('(${chef['location']})',
                                  style: TextStyle(fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text('\$${chef['price']}', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStarRating(int rating) {
    List<Widget> stars = [];
    for (int i = 0; i < 5; i++) {
      stars.add(Icon(i < rating ? Icons.star : Icons.star_border,
          color: Colors.amber, size: 16));
    }
    return Row(children: stars);
  }
}