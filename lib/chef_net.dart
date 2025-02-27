import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:zinzi2/allmeals.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/reco.dart';
import 'package:zinzi2/repeat.dart';
import 'cart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class ChooseChefNetwork extends StatefulWidget {
  @override
  _ChooseChefNetworkState createState() => _ChooseChefNetworkState();
}

class _ChooseChefNetworkState extends State<ChooseChefNetwork> {
  List<dynamic> chefs = []; // Dynamic list to store chefs data
  bool isLoading = true; // Loading state

  @override
  void initState() {
    super.initState();
    fetchChefs(); // Fetch chefs data when the widget is initialized
  }

  Future<void> fetchChefs() async {
    final url = '$apibaseurl/rr/rchefs';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // If server returns an OK response, parse the JSON
        setState(() {
          chefs = json.decode(response.body); // Decode JSON response
          isLoading = false; // Update loading state
        });
      } else {
        // If the response is not OK, handle the error
        throw Exception('Failed to load chefs');
      }
    } catch (e) {
      print(e); // Optionally handle the error (e.g., show a snack bar)
      setState(() {
        isLoading = false; // Update loading state in case of error
      });
    }
  }

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
      body: isLoading
          ? Center(
              child: CircularProgressIndicator()) // Show loader while fetching
          : Container(
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
                                child: Image.network(
                                  chef[
                                      'image'], // Use Image.network for fetching from the API
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            children: [
                                              Icon(Icons.location_on,
                                                  color: Colors.teal[600],
                                                  size: 16),
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
                                              for (int i = 0;
                                                  i < chef['rating'];
                                                  i++)
                                                Icon(Icons.star,
                                                    color: Colors.teal[600],
                                                    size: 16),
                                              for (int i = chef['rating'];
                                                  i < 5;
                                                  i++)
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
                                                  color: Colors.teal[600],
                                                  size: 16),
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

  const ChefDetailScreen({Key? key, required this.chef}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chef['name']),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.teal[50],
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: NetworkImage(chef['image']),
                ),
              ),
              SizedBox(height: 15),
              _buildSectionHeader('Basic Information'),
              SizedBox(
                height: 160,
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2,
                  children: [
                    _buildDetailColumn(
                        'Experience', '${chef['experience']} years'),
                    _buildDetailColumn(
                        'Service Radius', '${chef['service_radius']} km'),
                    _buildDetailColumn('Response Time', chef['response_time']),
                    _buildDetailColumn(
                        'Minimum Notice', '${chef['min_notice']} hours'),
                  ],
                ),
              ),
              _buildSectionHeader('Specialties'),
              SizedBox(
                height: 110,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3,
                  ),
                  itemCount: chef['specialties'].length,
                  itemBuilder: (context, index) {
                    return _buildGridItem(chef['specialties'][index]);
                  },
                ),
              ),
              _buildSectionHeader('About'),
              Text(chef['bio'], style: TextStyle(fontSize: 16)),
              _buildSectionHeader('Certifications'),
              ...chef['certifications'].map((cert) => ListTile(
                    leading: Icon(Icons.verified, color: Colors.teal),
                    title: Text(cert),
                  )),
              _buildSectionHeader('Availability'),
              Text(chef['availability'].join(', '),
                  style: TextStyle(fontSize: 16)),
              _buildSectionHeader('Sample Menu'),
              SizedBox(
                height: 120,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3,
                  ),
                  itemCount: chef['sample_menu'].length,
                  itemBuilder: (context, index) {
                    return _buildGridItem(chef['sample_menu'][index]);
                  },
                ),
              ),
              _buildSectionHeader('Reviews'),
              Column(
                children: chef['reviews']
                    .map<Widget>((review) => Card(
                          margin: EdgeInsets.symmetric(vertical: 5),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(review['user'],
                                    style: TextStyle(
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
                        ))
                    .toList(),
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
                      selectedChef: chef,
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
        color: Colors.teal[100],
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
        color: Colors.teal[100],
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
