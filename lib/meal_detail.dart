import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/chef.dart';
import 'package:zinzi2/useranalytics.dart';
import 'reco.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  List<String> bestServedWithInCart = [];

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
      'name': 'Edgar',
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
    final mealTitle = widget.meal['meal_name'] ?? 'Unknown Meal';
    isFavorite = Favorites.isFavorite(mealTitle);
  }

  @override
  Widget build(BuildContext context) {
    final mealTitle = widget.meal['meal_name'] ?? 'Unknown Meal';
    final mealDescription =
        widget.meal['meal_description'] ?? 'No description available';
    final mealPrice = (widget.meal['price'] is num)
        ? (widget.meal['price'] as num).toDouble()
        : 5.0;
    final mealImage =
        widget.meal['image_link'] ?? 'assets/images/notfound.avif';
    final ingredients = (widget.meal['ingredients'] is List)
        ? List<String>.from(widget.meal['ingredients'])
        : (widget.meal['ingredients']?.toString().split(', ') ?? []);
    final complementaries = (widget.meal['complementary_names'] is List)
        ? List<String>.from(widget.meal['complementary_names'])
        : (widget.meal['complementary_names']?.toString().split(', ') ?? []);
    final complementaryImages = (widget.meal['complementary_images'] is List)
        ? List<String>.from(widget.meal['complementary_images'])
        : (widget.meal['complementary_images']?.toString().split(', ') ?? []);

    final String imageUrl = mealImage.contains('drive.google.com')
        ? 'https://drive.google.com/uc?export=view&id=${mealImage.split('/d/')[1].split('/')[0]}'
        : mealImage;

    final isInCart =
        ShoppingCart.items.any((item) => item['title'] == mealTitle);

    return Scaffold(
      appBar: AppBar(
        title: Text(mealTitle),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal[800],
        elevation: 4,
        actions: [
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => FavoritesScreen())),
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (context) => ShoppingCartScreen())),
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
                  Colors.white.withOpacity(0.95), BlendMode.dstATop),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(8),
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
                      child: mealImage.startsWith(
                              'http') // Check if it's a network image
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              placeholder: (context, url) =>
                                  Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) => Image.asset(
                                'assets/images/notfound.avif',
                                fit: BoxFit.cover,
                              ),
                              fit: BoxFit.cover,
                            )
                          : Image.asset(
                              mealImage,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  SizedBox(height: 10),
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
                                mealTitle,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[800],
                                ),
                              ),
                              SizedBox(height: 0),
                              Text(
                                mealDescription,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              icon: Icon(isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_outline),
                              color: isFavorite ? Colors.red : Colors.teal[900],
                              onPressed: () => _toggleFavorite(
                                  mealTitle, mealPrice, mealImage),
                            ),
                            IconButton(
                              icon: Icon(isInCart
                                  ? Icons.shopping_cart
                                  : Icons.add_shopping_cart),
                              color:
                                  isInCart ? Colors.orange : Colors.teal[900],
                              onPressed: () => _toggleCart(
                                  mealTitle, mealPrice, complementaries),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  _buildBestServedWith(complementaries, complementaryImages),
                  _buildIngredientsSection(ingredients),
                  _buildPropertiesSection(),
                  _buildSkillLevelAndPrepTimeCard(),
                  _buildChefSection(),
                  SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildProceedToCartButton(context),
    );
  }

  void _toggleFavorite(String title, double price, String image) {
    setState(() {
      if (isFavorite) {
        Favorites.removeItem(title);
      } else {
        // Use the actual image link from the meal being favorited
        String imagePath = widget.meal['image_link'] ?? 'assets/images/notfound.avif';
        Favorites.addItem(title, price, imagePath);
        showCustomSnackBar(context, '$title added to favorites!');
      }
      isFavorite = !isFavorite;
    });
  }

  void _toggleCart(String title, double price, List<String> complementaries) {
    setState(() {
      if (ShoppingCart.items.any((item) => item['title'] == title)) {
        ShoppingCart.removeItemFromCart(title);
        showCustomSnackBar(context, '$title removed from cart!');
      } else {
        ShoppingCart.addItem(
          title,
          price,
          bestServedWith:
              complementaries.map((item) => {'title': item}).toList(),
          selectedChef: selectedChef ?? {},
        );
        showCustomSnackBar(context, '$title added to cart!');
      }
    });
  }

  Widget _buildIngredientsSection(List<String> ingredients) {
    return Card(
      elevation: 0.3,
      margin: EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.teal[50],
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ingredients', style: _sectionTitleStyle),
            SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ingredients
                    .map((ingredient) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Chip(
                            label: Text(ingredient, style: _chipTextStyle),
                            backgroundColor: Colors.teal[100],
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesSection() {
    final healthGoal = widget.meal['goal'] ?? 'General Health';
    final allergens = (widget.meal['allergies'] is List)
        ? List<String>.from(widget.meal['allergies'])
        : [];
    final diseasesManaged = (widget.meal['disease_management'] is String)
        ? (widget.meal['disease_management'] as String).split(', ')
        : [];

    return Card(
      elevation: 0.5,
      margin: EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.teal[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Health info', style: _sectionTitleStyle),
            SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPropertyChipFromAsset(
                      'assets/images/goal-picsay.png', 'Health Goal', healthGoal),
                  _buildPropertyChipFromAsset(
                      'assets/images/allergy-picsay.png',
                      'Allergens',
                      allergens.isNotEmpty ? allergens.join(', ') : 'None'),
                  _buildPropertyChip(
                      Icons.health_and_safety,
                      'Diseases Managed',
                      diseasesManaged.isNotEmpty
                          ? diseasesManaged.join(', ')
                          : 'None'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillLevelAndPrepTimeCard() {
    final skillLevel = widget.meal['cooking_skill_level'] ?? 'Intermediate';
    final prepTime = widget.meal['prep_time']?.toString() ?? '30';

    return Card(
      elevation: 0.5,
      margin: EdgeInsets.symmetric(vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.teal[50],
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cooking Info', style: _sectionTitleStyle),
            SizedBox(height: 12),
            Text('Skill Level: $skillLevel', style: _subtitleStyle),
            LinearProgressIndicator(
              value: _getSkillLevelValue(skillLevel),
              color: Colors.green[600],
              backgroundColor: Colors.grey[300],
            ),
            SizedBox(height: 16),
            Text('Prep Time: ${prepTime} minutes', style: _subtitleStyle),
            LinearProgressIndicator(
              value: _getPrepTimeValue(prepTime),
              color: Colors.green[600],
              backgroundColor: Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChefSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              cookForMyself ? 'Cook for Myself' : 'Hire a Chef',
              style: TextStyle(fontSize: 16, color: Colors.teal[800]),
            ),
            Switch(
              value: cookForMyself,
              onChanged: _handleCookForMyselfChange,
              activeColor: Colors.teal[900],
              inactiveTrackColor: Colors.grey,
            ),
          ],
        ),
        if (selectedChef != null) _buildChefCard(selectedChef!),
      ],
    );
  }

  Future<void> _handleCookForMyselfChange(bool value) async {
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
        ShoppingCart.addItem(selectedChef['name'], selectedChef['price'],
            selectedChef: selectedChef);
        showCustomSnackBar(context, '${selectedChef['name']} added to cart!');
      }
    } else {
      setState(() {
        selectedChef = null;
      });
    }
  }

  Widget _buildChefCard(Map<String, dynamic> chef) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      color: Colors.teal[800],
                    ),
                  ),
                  Row(
                    children: [
                      _buildStarRating(chef['rating']),
                      SizedBox(width: 8),
                      Text('(${chef['location']})',
                          style:
                              TextStyle(fontSize: 14, color: Colors.teal[800])),
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
                color: Colors.teal[800],
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

  Widget _buildProceedToCartButton(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 0,
            offset: Offset(0, 0),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal[800],
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16.0),
          textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShoppingCartScreen(),
            ),
          );
        },
        child: Text('Proceed to Cart'),
      ),
    );
  }

  Widget _buildBestServedWith(
      List<String> complementaries, List<String> complementaryImages) {
    if (complementaries.isEmpty) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Best Served With:',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[900])),
          SizedBox(height: 10),
          SizedBox(
            height: 135,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: complementaries.length,
              itemBuilder: (context, index) {
                final item = complementaries[index];
                final complementaryImageUrl = complementaryImages[index];

                return GestureDetector(
                  onTap: () {
                    // Action when tapping the complementary item
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        margin: EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.teal[50],
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: Offset(0, 2))
                          ],
                        ),
                        child: Column(
                          children: [
                            complementaryImageUrl.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: complementaryImageUrl,
                                    width: 100,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Center(
                                        child: CircularProgressIndicator()),
                                    errorWidget: (context, url, error) =>
                                        Image.asset(
                                      'assets/images/notfound.avif',
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Image.asset(
                                    complementaryImageUrl,
                                    width: 100,
                                    height: 70,
                                    fit: BoxFit.cover,
                                  ),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(item,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal[800],
                                      fontSize: 12)),
                            ),
                            Text('\$5.00',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void showCustomSnackBar(BuildContext context, String message) {
    final snackBar = SnackBar(
      content: Text(message),
      duration: Duration(seconds: 2),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  double _getSkillLevelValue(String skillLevel) {
    switch (skillLevel.toLowerCase()) {
      case 'beginner':
        return 0.33;
      case 'intermediate':
        return 0.67;
      case 'advanced':
        return 1.0;
      default:
        return 0.67;
    }
  }

  double _getPrepTimeValue(String prepTime) {
    const maxPrepTime = 60;
    int prepMinutes = int.tryParse(prepTime) ?? 30;
    return (prepMinutes / maxPrepTime).clamp(0.0, 1.0);
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
        label: Text(
          label,
          style: TextStyle(color: Colors.teal[800]),
        ),
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
        label: Text(
          label,
          style: TextStyle(color: Colors.teal[800]),
        ),
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

  final TextStyle _sectionTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.teal[800],
  );

  final TextStyle _subtitleStyle = TextStyle(
    color: Colors.teal[800],
    fontSize: 16,
  );

  final TextStyle _chipTextStyle = TextStyle(
    color: Colors.teal[800],
    fontWeight: FontWeight.w500,
  );
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
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(1.0),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: ListView.builder(
            itemCount: chefs.length,
            itemBuilder: (context, index) {
              final chef = chefs[index];
              return Card(
                elevation: 0.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: EdgeInsets.symmetric(vertical: 1),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context, chef);
                  },
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
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
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chef['name'],
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal[900],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Icon(Icons.location_on,
                                            color: Colors.teal[600], size: 16),
                                        Text(
                                          ' ${chef['location']}',
                                          style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.teal[900]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        for (int i = 0; i < chef['rating']; i++)
                                          Icon(Icons.star,
                                              color: Colors.teal[600],
                                              size: 16),
                                        for (int i = chef['rating']; i < 5; i++)
                                          Icon(Icons.star_border,
                                              color: Colors.teal[600],
                                              size: 16),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.monetization_on,
                                            color: Colors.teal[600], size: 16),
                                        Text(
                                          ' \$${chef['price']}',
                                          style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.teal[900]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}