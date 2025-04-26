import 'package:flutter/material.dart';
import 'nutrition+.dart'; // Ensure this file contains your NutritionItem model definition
import 'cart.dart' as cart;
import 'package:cached_network_image/cached_network_image.dart';

class Nutri_DetailPage extends StatefulWidget {
  final NutritionItem item;

  Nutri_DetailPage({required this.item});

  @override
  _Nutri_DetailPageState createState() => _Nutri_DetailPageState();
}

class _Nutri_DetailPageState extends State<Nutri_DetailPage> {
  Map<String, dynamic>? selectedChef;
  bool isFavorite = false;
  bool isInCart = false;

  @override
  void initState() {
    super.initState();
    // Use prefix for classes from cart.dart
    isFavorite = cart.Favorites.isFavorite(widget.item.name);
    isInCart = cart.ShoppingCart.getItems()
        .any((item) => item['title'] == widget.item.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Use actual constants from nutri+.dart or material.dart
        title: Text(widget.item.name, style: TextStyle(color: Colors.white)),
        backgroundColor: primaryTeal, // Defined in nutri+.dart
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.favorite),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => cart.FavoritesScreen()), // Use prefix
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        cart.ShoppingCartScreen()), // Use prefix
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/soft.jpg', fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item Image wrapped in Hero
                  Hero(
                    tag: widget.item.heroTag, // Use the same tag as in the grid
                    child: Container(
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
                        child: (widget.item.imagePath?.startsWith('http') ??
                                false)
                            ? CachedNetworkImage(
                                imageUrl: widget.item.imagePath ?? '',
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) {
                                  print(
                                      "Error loading network image: $url, $error"); // Add logging
                                  return Image.asset(
                                    // Use default image on error
                                    'assets/images/DrugRG.png',
                                    fit: BoxFit.cover,
                                    // Optional: Error builder for the default image itself
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                            child: Icon(Icons.error_outline,
                                                color: errorIconColor,
                                                size: 60)),
                                  );
                                },
                              )
                            : Image.asset(
                                widget.item.imagePath ?? '',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  print(
                                      "Error loading asset image: ${widget.item.imagePath}, $error"); // Add logging
                                  return Image.asset(
                                    // Use default image on error
                                    'assets/images/DrugRG.png',
                                    fit: BoxFit.cover,
                                    // Optional: Error builder for the default image itself
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                            child: Icon(Icons.error_outline,
                                                color: errorIconColor,
                                                size: 60)),
                                  );
                                },
                              ),
                      ),
                    ), // End Container
                  ), // End Hero
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.name,
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      primaryTextColor), // Use defined constant
                            ),
                            Text(
                              '\$${widget.item.price != null ? widget.item.price!.toStringAsFixed(2) : '0.00'}',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: priceColor), // Use defined constant
                            ),
                          ],
                        ),
                      ),
                      _buildFavoriteButton(),
                      _buildCartButton(),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    widget.item.description ?? '',
                    style: TextStyle(
                        fontSize: 16,
                        color: secondaryTextColor ??
                            Colors.grey), // Use defined constant
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Producers:',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor), // Use defined constant
                  ),
                  _buildProducersSection(),
                  SizedBox(height: 30),
                ],
              ),
            ),
          ),
          _buildProceedToCartButton(),
        ],
      ),
    );
  }

  Widget _buildFavoriteButton() {
    return Tooltip(
      message: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
      child: IconButton(
        icon: Icon(
          isFavorite
              ? Icons.favorite
              : Icons.favorite_outline, // Icon logic is fine
          color: isFavorite
              ? primaryTeal
              : primaryTextColor, // Use defined constants
        ),
        onPressed: () {
          setState(() {
            if (isFavorite) {
              cart.Favorites.removeItem(widget.item.name);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${widget.item.name} removed from favorites!'),
              ));
            } else {
              cart.Favorites.addItem(widget.item.name ?? '',
                  widget.item.price ?? 0.0, widget.item.imagePath ?? '');
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${widget.item.name} added to favorites!'),
              ));
            }
            isFavorite = !isFavorite;
          });
        },
      ),
    );
  }

  Widget _buildCartButton() {
    return Tooltip(
      message: isInCart ? 'Already in Cart' : 'Add to Cart',
      child: IconButton(
        icon: Icon(
          isInCart
              ? Icons.shopping_cart
              : Icons.shopping_cart_outlined, // Icon logic is fine
          color: isInCart
              ? primaryTeal
              : primaryTextColor, // Use defined constants
        ),
        onPressed: () {
          if (selectedChef != null) {
            setState(() {
              if (!isInCart) {
                // Use prefix for ShoppingCart and pass meal object correctly
                cart.ShoppingCart.addItem(
                  widget.item.name,
                  widget.item.price ?? 0.0,
                  quantity: 1,
                  selectedchef: selectedChef!,
                  // Pass the actual item object or relevant fields if needed by cart logic
                  meal: {
                    'name': widget.item.name,
                    'image_link': widget.item.imagePath,
                    'description': widget.item.description,
                    'price': widget.item.price
                  },
                  bestservedwith: [], // Assuming this is still required by addItem signature
                );
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${widget.item.name} added to cart!')));
                isInCart = true;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text('${widget.item.name} is already in your cart!')));
              }
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Please select a producer first!')));
          }
        },
      ),
    );
  }

  Widget _buildProducersSection() {
    final List<Map<String, dynamic>> producers = [
      {
        'image': 'assets/images/producerHolder.png',
        'name': 'Msafiri Poa',
        'location': 'KAMPALA',
        'type': 'Individual',
        'isVerified': true,
      },
      {
        'image': 'assets/images/producerHolder.png',
        'name': 'Organic Farms Inc.',
        'location': 'KATWE',
        'type': 'Company',
        'isVerified': false,
      },
      {
        'image': 'assets/images/producerHolder.png',
        'name': 'Fresh Produce Co.',
        'location': 'KAMPALA',
        'type': 'Company',
        'isVerified': true,
      },
      {
        'image': 'assets/images/producerHolder.png',
        'name': "Nature's Bounty",
        'location': 'KAMPALA',
        'type': 'Individual',
        'isVerified': true,
      },
      {
        'image': 'assets/images/producerHolder.png',
        'name': 'Super Chef Nick',
        'location': 'MUYENGA',
        'type': 'Individual',
        'isVerified': false,
      },
    ];

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: producers.length,
      itemBuilder: (context, index) {
        final producer = producers[index];
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedChef = producer;
            });
          },
          child: Card(
            margin: EdgeInsets.only(bottom: 4), // Reduced space between cards
            color: selectedChef != null &&
                    selectedChef!['name'] == producer['name']
                ? lightTeal // Use defined constant
                : Colors.teal[50], // Revert lighterTeal to original color
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  ClipOval(
                    child: Image.asset(
                      producer['image'],
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                producer['name'],
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        primaryTextColor), // Use defined constant
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                producer['isVerified']
                                    ? Icons.check_circle
                                    : Icons
                                        .check_circle_outline, // Icon logic fine
                                color: producer['isVerified']
                                    ? primaryTextColor
                                    : Colors.grey, // Use defined constant
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color:
                                      primaryTextColor, // Use defined constant
                                ),
                                SizedBox(width: 4),
                                Text(
                                  producer['location'],
                                  style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          primaryTextColor), // Use defined constant
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(
                                  producer['type'] == 'Company'
                                      ? Icons.business
                                      : Icons.person,
                                  size: 16,
                                  color:
                                      primaryTextColor, // Use defined constant
                                ),
                                SizedBox(width: 4),
                                Text(
                                  producer['type'],
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      color:
                                          primaryTeal), // Use defined constant
                                ),
                              ],
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
    );
  }

  Widget _buildProceedToCartButton() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Visibility(
        visible: selectedChef != null,
        child: ElevatedButton(
          onPressed: () {
            if (selectedChef != null) {
              if (!isInCart) {
                // Use prefix for ShoppingCart
                cart.ShoppingCart.addItem(
                  widget.item.name,
                  widget.item.price ?? 0.0,
                  quantity: 1,
                  selectedchef: selectedChef!,
                  meal: {
                    'name': widget.item.name,
                    'image_link':
                        widget.item.imagePath, // Match key used elsewhere
                    'description': widget.item.description,
                    'price': widget.item.price
                  },
                  bestservedwith: [], // Assuming this is still required by addItem signature
                );
                setState(() {
                  isInCart = true;
                });
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        cart.ShoppingCartScreen()), // Use prefix
              );
            }
          },
          child: Text('Proceed to Cart'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                accentTeal, // Use defined constant from nutri+.dart
            foregroundColor: Colors.white, // Standard white is fine here
            padding: EdgeInsets.symmetric(vertical: 16),
            textStyle: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
