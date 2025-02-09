import 'package:flutter/material.dart';
import 'package:zinzi2/actual.dart';
import 'package:zinzi2/checkout.dart'; // Import checkout if needed
import 'package:zinzi2/repeat.dart';
import 'cart.dart'; // Adjust this as needed for the correct path

class ChooseChef extends StatelessWidget {
  final List<Map<String, dynamic>> chefs = [
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

  ChooseChef({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Available Chefs'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context); // Go back without returning data
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'), // Background image
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(1.0),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: ListView.builder(
            itemCount: chefs.length,
            itemBuilder: (context, index) {
              final chef = chefs[index];
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: () {
                    // Add the selected chef to the shopping cart
                    ShoppingCart.addItem(
                      chef['name'],
                      (chef['price'] as num).toDouble(),
                      quantity: 1,
                      selectedChef: chef,
                    );
                    // Optionally provide feedback to the user
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${chef['name']}  Selected  !'),
                        duration: Duration(seconds: 2),
                      ),
                    );

                    // Go back to the previous screen after adding to cart
                    Navigator.push(
                        context, MaterialPageRoute(builder: (context) => RepeatCustomerSelectionPage())); // Pop if you want to return to the previous page
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (int i = 0; i < chef['rating']; i++)
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 18),
                                  for (int i = chef['rating']; i < 5; i++)
                                    const Icon(Icons.star_border,
                                        color: Colors.amber, size: 18),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.monetization_on,
                                      color: Colors.teal, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '\$${chef['price']}',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.location_on,
                                      color: Colors.teal, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    chef['location'],
                                    style: const TextStyle(fontSize: 16),
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
