/*import 'package:flutter/material.dart';
import 'package:zinzi2/allmeals.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/reco.dartp';
import 'package:zinzi2/repeat.dartp';
import 'cart.dart';

class ChooseChef extends StatelessWidget {
  final List<Map<String, dynamic>> chefs = [
    {
      'image': 'assets/images/kharol.jpg',
      'name': 'Kharol',
      'price': 7,
      'rating': 3,
      'location': 'KATWE',
      'experience': 5,
      'specialties': ['Ugandan', 'Vegetarian', 'Traditional Stews'],
      'certifications': ['Food Safety Handler', 'UG Culinary Certificate'],
      'bio': 'Passionate about preserving traditional Ugandan cooking methods. Specializes in authentic local dishes with a healthy twist.',
      'languages': ['English', 'Luganda'],
      'service_radius': 15,
      'sample_menu': ['Luwombo', 'Matooke', 'Malakwang'],
      'reviews': [
        {'user': 'Sarah', 'comment': 'Kharol\'s peanut sauce is incredible!', 'rating': 4},
        {'user': 'James', 'comment': 'Authentic Katwe flavors', 'rating': 3},
      ],
      'availability': ['Mon', 'Wed', 'Fri'],
      'min_notice': 6,
      'response_time': '1 hour',
      'punctuality': 4.2,
      'team_size': 1,
      'equipment': 'Bring own utensils',
    },
    {
      'image': 'assets/images/dani3.jpg',
      'name': 'Edgar',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
      'experience': 3,
      'specialties': ['Continental', 'Baking', 'Quick Meals'],
      'certifications': ['Culinary Arts Diploma', 'Food Handling'],
      'bio': 'Fast-paced chef specializing in office lunch solutions and baked goods. Perfect for busy professionals.',
      'languages': ['English', 'Swahili'],
      'service_radius': 10,
      'sample_menu': ['Chicken Parmesan', 'Vegetable Stir-Fry', 'Pancakes'],
      'reviews': [
        {'user': 'Mary', 'comment': 'Great meal prep solutions', 'rating': 3},
        {'user': 'John', 'comment': 'Reliable weekly service', 'rating': 3},
      ],
      'availability': ['Tue', 'Thu', 'Sat'],
      'min_notice': 12,
      'response_time': '2 hours',
      'punctuality': 3.8,
      'team_size': 2,
      'equipment': 'Full kitchen setup',
    },
    {
      'image': 'assets/images/abdul.jpg',
      'name': 'Abdul',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
      'experience': 4,
      'specialties': ['BBQ', 'Meat Dishes', 'Street Food'],
      'certifications': ['Food Safety Level 2', 'Butchery Certificate'],
      'bio': 'Master of grilled meats and outdoor cooking. Perfect for events and gatherings.',
      'languages': ['English', 'Luganda'],
      'service_radius': 20,
      'sample_menu': ['Nyama Choma', 'Pilau', 'Roasted Chicken'],
      'reviews': [
        {'user': 'Ali', 'comment': 'Best BBQ in Kampala!', 'rating': 4},
        {'user': 'Grace', 'comment': 'Great for parties', 'rating': 4},
      ],
      'availability': ['Mon-Fri'],
      'min_notice': 8,
      'response_time': '45 mins',
      'punctuality': 4.5,
      'team_size': 3,
      'equipment': 'Portable grill included',
    },
    {
      'image': 'assets/images/zay.jpg',
      'name': 'Nick',
      'price': 45,
      'rating': 5,
      'location': 'MUYENGA',
      'experience': 8,
      'specialties': ['Italian', 'Vegan', 'Fine Dining'],
      'certifications': ['Cordon Bleu Graduate', 'Nutrition Specialist'],
      'bio': 'Internationally trained chef offering premium dining experiences at home.',
      'languages': ['English', 'Italian'],
      'service_radius': 25,
      'sample_menu': ['Truffle Risotto', 'Vegetarian Lasagna', 'Tiramisu'],
      'reviews': [
        {'user': 'Emma', 'comment': 'Worth every shilling!', 'rating': 5},
        {'user': 'David', 'comment': 'Michelin-star quality', 'rating': 5},
      ],
      'availability': ['All Days'],
      'min_notice': 24,
      'response_time': '30 mins',
      'punctuality': 4.9,
      'team_size': 1,
      'equipment': 'Professional kitchen kit',
    },
    {
      'image': 'assets/images/victor.jpg',
      'name': 'Victor',
      'price': 5,
      'rating': 3,
      'location': 'KAMPALA',
      'experience': 2,
      'specialties': ['Local Cuisine', 'Street Food', 'Quick Meals'],
      'certifications': ['Basic Food Handling'],
      'bio': 'Affordable daily meal solutions with authentic local taste.',
      'languages': ['English', 'Luganda'],
      'service_radius': 8,
      'sample_menu': ['Rolex', 'Katogo', 'Beans & Chapati'],
      'reviews': [
        {'user': 'Peter', 'comment': 'Great value for money', 'rating': 3},
        {'user': 'Jane', 'comment': 'Consistent quality', 'rating': 3},
      ],
      'availability': ['Weekends'],
      'min_notice': 24,
      'response_time': '1.5 hours',
      'punctuality': 3.5,
      'team_size': 1,
      'equipment': 'Basic utensils only',
    },
    {
      'image': 'assets/images/dante.jpg',
      'name': 'Dante',
      'price': 4,
      'rating': 2,
      'location': 'MULAGO',
      'experience': 1,
      'specialties': ['Student Meals', 'Baking', 'Quick Snacks'],
      'certifications': ['Food Safety Basics'],
      'bio': 'Upcoming chef specializing in budget-friendly student meals and baked goods.',
      'languages': ['English'],
      'service_radius': 5,
      'sample_menu': ['Pancakes', 'Spaghetti', 'Cakes'],
      'reviews': [
        {'user': 'Student', 'comment': 'Good for small budget', 'rating': 2},
        {'user': 'Mama', 'comment': 'Trying hard', 'rating': 2},
      ],
      'availability': ['Evenings'],
      'min_notice': 4,
      'response_time': '2 hours',
      'punctuality': 3.0,
      'team_size': 1,
      'equipment': 'Limited tools',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Available Chefs'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
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
                margin: const EdgeInsets.symmetric(vertical: 1),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChefDetailScreen(chef: chef),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
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
                        const SizedBox(width: 16),
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
                                      mainAxisAlignment: MainAxisAlignment.start,
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
                                              color: Colors.teal[600], size: 16),
                                        for (int i = chef['rating']; i < 5; i++)
                                          Icon(Icons.star_border,
                                              color: Colors.teal[600], size: 16),
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

class ChefDetailScreen extends StatelessWidget {
  final Map<String, dynamic> chef;

  const ChefDetailScreen({super.key, required this.chef});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chef['name']),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.teal[50], // Change background color to teal
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: AssetImage(chef['image']),
                ),
              ),
              SizedBox(height: 15),
              _buildSectionHeader('Basic Information'),
              SizedBox(
                height: 160, // Set a fixed height for the grid
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2, // Adjust aspect ratio for better spacing
                  children: [
                    _buildDetailColumn('Experience', '${chef['experience']} years'),
                    _buildDetailColumn('Service Radius', '${chef['service_radius']} km'),
                    _buildDetailColumn('Response Time', chef['response_time']),
                    _buildDetailColumn('Minimum Notice', '${chef['min_notice']} hours'),
                  ],
                ),
              ),
              
              // Specialties Section
              _buildSectionHeader('Specialties'),
              SizedBox(
                height: 110, // Set a fixed height for the grid
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3, // Adjust aspect ratio for better spacing
                  ),
                  itemCount: chef['specialties'].length,
                  itemBuilder: (context, index) {
                    return _buildGridItem(chef['specialties'][index]);
                  },
                ),
              ),

              // About Section
              _buildSectionHeader('About'),
              Text(chef['bio'], style: TextStyle(fontSize: 16)),
              
              // Certifications Section
              _buildSectionHeader('Certifications'),
              ...chef['certifications'].map((cert) => 
                ListTile(
                  leading: Icon(Icons.verified, color: Colors.teal),
                  title: Text(cert),
                )),
              
              // Availability Section
              _buildSectionHeader('Availability'),
              Text(chef['availability'].join(', '), style: TextStyle(fontSize: 16)),
              
              // Sample Menu Section
              _buildSectionHeader('Sample Menu'),
              SizedBox(
                height: 120, // Set a fixed height for the grid
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3, // Adjust aspect ratio for better spacing
                  ),
                  itemCount: chef['sample_menu'].length,
                  itemBuilder: (context, index) {
                    return _buildGridItem(chef['sample_menu'][index]);
                  },
                ),
              ),
              
              // Reviews Section
              _buildSectionHeader('Reviews'),
              Column(
                children: chef['reviews'].map<Widget>((review) => Card(
                  margin: EdgeInsets.symmetric(vertical: 5),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(review['user'], style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[900])),
                        SizedBox(height: 5),
                        Text(review['comment']),
                        Row(
                          children: [
                            Text('Rating: '),
                            _buildRatingStars(review['rating']),
                          ],
                        ),
                      ],
                    ),
                  ),
                )).toList(),
              ),
              
              SizedBox(height: 20),
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.people_alt),
                  label: Text('Choose Chef (\$${chef['price']})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[800],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                  onPressed: () {
                    ShoppingCart.addItem(
                      chef['name'],
                      (chef['price'] as num).toDouble(),
                      quantity: 1,
                      selectedchef: chef,
                      meal: {}, bestservedwith: [],
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${chef['name']} Selected!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    Navigator.push( 
                      context,
                      MaterialPageRoute(
                        builder: (context) => AllMealsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 15),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.teal[800],
        ),
      ),
    );
  }

  Widget _buildDetailColumn(String label, String value) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.teal[100], // Background color for the info box
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildGridItem(String label) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.teal[100], // Background color for the grid item
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildRatingStars(int rating) {
    return Row(
      children: [
        for (int i = 0; i < rating; i++)
          Icon(Icons.star, color: Colors.amber, size: 18),
        for (int i = rating; i < 5; i++)
          Icon(Icons.star_border, color: Colors.grey, size: 18),
      ],
    );
  }
}
*/