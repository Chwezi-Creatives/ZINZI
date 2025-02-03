import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/useranalytics.dart';
import 'dart:math';
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

  @override
  void initState() {
    super.initState();
    isFavorite = Favorites.isFavorite(widget.meal['title']);
  }

  @override
  Widget build(BuildContext context) {
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
                            IconButton(
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Colors.teal,
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
                                      widget.meal['image'],
                                    );
                                    showCustomSnackBar(context,
                                        '${widget.meal['title']} added to favorites!');
                                    isFavorite = true;
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.shopping_cart,
                                color: Colors.orange,
                              ),
                              onPressed: () {
                                ShoppingCart.addItem(
                                    widget.meal['title'], widget.meal['price']);
                                showCustomSnackBar(context,
                                    '${widget.meal['title']} added to cart!');
                              },
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
                  SizedBox(height: 24),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Best Served With:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.meal['bestServedWith'].length,
                      itemBuilder: (context, index) {
                        final complementMeal =
                            widget.meal['bestServedWith'][index];
                        return Container(
                          width: 140,
                          margin: EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                spreadRadius: 2,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(12)),
                                child: Image.asset(
                                  complementMeal['image'],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: 95,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 1),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            complementMeal['title'],
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '\$${complementMeal['price'].toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 0),
                                    TextButton(
                                      onPressed: () {
                                        ShoppingCart.addItem(
                                          complementMeal['title'],
                                          complementMeal['price'],
                                        );
                                        showCustomSnackBar(
                                          context,
                                          '${complementMeal['title']} added to cart!',
                                        );
                                      },
                                      child: Text(
                                        'Add to Cart',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.orange,
                                        padding: EdgeInsets.symmetric(
                                            vertical: 4, horizontal: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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
                        onChanged: (bool value) {
                          setState(() {
                            cookForMyself = value;
                          });
                        },
                        activeColor: Colors.teal[900],
                        inactiveTrackColor: Colors.grey,
                      )
                    ],
                  ),
                  SizedBox(height: 20),
                  // CTA Buttons
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
                              child: ElevatedButton(
                                onPressed: () {
                                  ShoppingCart.addItem(
                                    widget.meal['title'],
                                    widget.meal['price'],
                                  );
                                  showCustomSnackBar(
                                    context,
                                    '${widget.meal['title']} added to cart!',
                                  );
                                },
                                child: Icon(Icons.shopping_cart,
                                    color: Colors.white),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: EdgeInsets.all(12),
                                  minimumSize: Size.fromHeight(50),
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: ElevatedButton(
                                onPressed: () {
                                  // Implement order functionality here
                                },
                                child:
                                    Icon(Icons.fastfood, color: Colors.white),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: EdgeInsets.all(12),
                                  minimumSize: Size.fromHeight(50),
                                ),
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
      ),
    );
  }
}
