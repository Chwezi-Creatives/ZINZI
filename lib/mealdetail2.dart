import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/chef.dart';
import 'package:zinzi2/useranalytics.dart';
import 'reco.dart';

class MealDetailScreen2 extends StatefulWidget {
  final Map<String, dynamic> meal;

  MealDetailScreen2({required this.meal});

  @override
  _MealDetailScreen2State createState() => _MealDetailScreen2State();
}

class _MealDetailScreen2State extends State<MealDetailScreen2> {
  bool isFavorite = false;
  bool cookForMyself = true;
  Map<String, dynamic>? selectedChef; // Store the selected chef data
  // Track the state of the expansion
  Map<String, bool> isExpanded = {
    'allergens': false,
    'diseasesManaged': false,
    'healthGoal': false,
    'prepTime': false,
    'skillLevel': false,
  };

  final List<Map<String, dynamic>> chefs = [
    {
      'image': 'assets/images/kharol.jpg',
      'name': 'Chef Kharol',
      'price': 7,
      'rating': 3,
      'location': 'KATWE',
    },
    {
      'image': 'assets/images/dani3.jpg',
      'name': 'Chef Dani',
      'price': 5,
      'rating': 4,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/abdul.jpg',
      'name': 'Chef Abdul',
      'price': 5,
      'rating': 2,
      'location': 'KAMPALA',
    },
    {
      'image': 'assets/images/zay.jpg',
      'name': 'Nicks Pizza',
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
      'name': 'Chef Dante',
      'price': 4,
      'rating': 2,
      'location': 'MAWANDA Rd',
    }
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
        elevation: 0,
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
                  // Meal Title and Description
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.meal['title'],
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[800],
                              ),
                            ),
                            Spacer(),
                            // Favorite Icon Container
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isFavorite ? Colors.red : Colors.teal[100],
                              ),
                              child: IconButton(
                                icon: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color:
                                      isFavorite ? Colors.white : Colors.teal,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (isFavorite) {
                                      Favorites.removeItem(
                                          widget.meal['title']);
                                      isFavorite = false;
                                    } else {
                                      Favorites.addItem(
                                        widget.meal['title'],
                                        widget.meal['price'],
                                        widget.meal['image'],
                                      );
                                      showCustomSnackBar(context,
                                          '${widget.meal['title']} added to favorites!');
                                      isFavorite = true;
                                    }
                                  });
                                },
                              ),
                            ),
                            SizedBox(width: 16),
                            // Cart Icon Container
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isInCart ? Colors.orange : Colors.teal[100],
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.add_shopping_cart,
                                  color:
                                      isFavorite ? Colors.white : Colors.teal,
                                ),
                                onPressed: () {
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
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
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
                  SizedBox(height: 24),
                  // Ingredients section
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ingredients:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.meal['ingredients']
                              .map<Widget>((ingredient) {
                            return Chip(
                              label: Text(ingredient),
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
                  SizedBox(height: 20),
                  // Expandable sections for new properties
                  _buildExpandableSection(
                    title: 'Allergens',
                    content: widget.meal['allergens'].join(', ') ?? 'None',
                    isExpanded: isExpanded['allergens']!,
                    onTap: () {
                      setState(() {
                        isExpanded['allergens'] = !isExpanded['allergens']!;
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  _buildExpandableSection(
                    title: 'Diseases Managed',
                    content:
                        widget.meal['diseasesManaged'].join(', ') ?? 'None',
                    isExpanded: isExpanded['diseasesManaged']!,
                    onTap: () {
                      setState(() {
                        isExpanded['diseasesManaged'] =
                            !isExpanded['diseasesManaged']!;
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  _buildExpandableSection(
                    title: 'Health Goal',
                    content: widget.meal['healthGoal'],
                    isExpanded: isExpanded['healthGoal']!,
                    onTap: () {
                      setState(() {
                        isExpanded['healthGoal'] = !isExpanded['healthGoal']!;
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  _buildExpandableSection(
                    title: 'Prep Time',
                    content: widget.meal['prepTime'],
                    isExpanded: isExpanded['prepTime']!,
                    onTap: () {
                      setState(() {
                        isExpanded['prepTime'] = !isExpanded['prepTime']!;
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  _buildExpandableSection(
                    title: 'Skill Level',
                    content: widget.meal['cookingSkillLevel'],
                    isExpanded: isExpanded['skillLevel']!,
                    onTap: () {
                      setState(() {
                        isExpanded['skillLevel'] = !isExpanded['skillLevel']!;
                      });
                    },
                  ),
                  SizedBox(height: 20),
                  // Cook for Myself Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cookForMyself ? 'Cook for Myself' : 'Pick a Chef',
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
                                builder: (context) => ChooseChef(
                                  chefs: chefs, // Pass the chefs list
                                ),
                              ),
                            );

                            if (selectedChef != null) {
                              setState(() {
                                this.selectedChef =
                                    selectedChef; // Store selected chef
                              });
                              // Add the chef's fee to the cart
                              ShoppingCart.addItem(
                                  selectedChef['name'], selectedChef['price'], selectedChef: null);
                              showCustomSnackBar(context,
                                  '${selectedChef['name']} added to cart!');
                            }
                          } else {
                            setState(() {
                              selectedChef =
                                  null; // Clear selected chef if cooking for myself
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

  // Function to build an expandable section
  Widget _buildExpandableSection({
    required String title,
    required String content,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.teal[400]!),
          borderRadius: BorderRadius.circular(8),
          color: Colors.teal[50],
        ),
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            SizedBox(height: 8),
            if (isExpanded)
              Text(
                content,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChefCard(Map<String, dynamic> chef) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 12),
      elevation: 3,
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
