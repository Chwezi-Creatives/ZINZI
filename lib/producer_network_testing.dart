import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:zinzi2/allmeals.dart';
import 'package:zinzi2/checkout.dart';
import 'cart.dart'; // Make sure the cart.dart file is correctly imported
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Import for cached network images

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class ChooseProducerNetwork extends StatefulWidget {
  @override
  _ChooseProducerNetworkState createState() => _ChooseProducerNetworkState();
}

class _ChooseProducerNetworkState extends State<ChooseProducerNetwork> {
  List<dynamic> producers = []; // Dynamic list to store producers data
  bool isLoading = true; // Loading state

  @override
  void initState() {
    super.initState();
    fetchProducers(); // Fetch producers data when the widget is initialized
  }

  Future<void> fetchProducers() async {
    final url = '$apibaseurl/rr/rproducers';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        // Decode the response body
        final Map<String, dynamic> responseData = json.decode(response.body);

        // Extract the list of producers
        List<dynamic> producers = [];

        // Check if the response is a map and contains the 'data' key
        if (responseData.containsKey('data')) {
          producers = responseData['data']; // Assign the list under 'data'
        } else {
          // If the response is not a map with 'data', assign the first key that isn't 'message'
          producers = responseData.entries
              .where((entry) => entry.key != 'message')
              .first
              .value;
        }

        setState(() {
          this.producers = producers;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        throw Exception('Failed to load producers');
      }
    } catch (e) {
      // Handle errors
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Available Producers'),
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
                child: (producers.isEmpty)
                    ? Center(
                        child: Text('No producers available',
                            style: TextStyle(fontSize: 20)))
                    : ListView.builder(
                        itemCount: producers.length,
                        itemBuilder: (context, index) {
                          final producer = producers[index];

                          // Handle potential null values to avoid errors
                          final producerName =
                              producer['Name'] ?? 'No Name Available';
                          final producerImage = producer['Image'] ?? '';
                          final producerLocation = producer['Location'] ?? 'NA';
                          final producerType =
                              producer['Producer_Type'] ?? 'Unknown';
                          final producerRating =
                              double.tryParse(producer['Rating'] ?? '0')
                                      ?.toInt() ??
                                  0;

                          // Check if the image URL is valid (starts with http or https)
                          final bool isValidImageUrl =
                              producerImage.isNotEmpty &&
                                  producerImage.startsWith('http');

                          return Card(
                            elevation: 0.0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            child: InkWell(
                              onTap: () async {
                                // Pre-cache the image before navigating
                                if (isValidImageUrl) {
                                  await precacheImage(
                                    NetworkImage(producerImage),
                                    context,
                                  );
                                }

                                // Navigate to the detailed view
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProducerDetailScreen(
                                        producer: producer),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Hero(
                                      tag:
                                          'producer-image-${producer['Producer_Id']}',
                                      child: ClipOval(
                                        child: isValidImageUrl
                                            ? CachedNetworkImage(
                                                imageUrl: producerImage,
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    Container(
                                                  width: 50,
                                                  height: 50,
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        Image.asset(
                                                  'assets/images/producerHolder.png',
                                                  width: 50,
                                                  height: 50,
                                                  fit: BoxFit.cover,
                                                ),
                                              )
                                            : Image.asset(
                                                'assets/images/producerHolder.png',
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  producerName,
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
                                                    Expanded(
                                                      child:
                                                          SingleChildScrollView(
                                                        scrollDirection:
                                                            Axis.horizontal,
                                                        child: Text(
                                                          producerLocation,
                                                          style: TextStyle(
                                                              fontSize: 16,
                                                              color: Colors
                                                                  .teal[900]),
                                                          overflow: TextOverflow
                                                              .visible,
                                                        ),
                                                      ),
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
                                                        i < producerRating;
                                                        i++)
                                                      Icon(Icons.star,
                                                          color:
                                                              Colors.teal[600],
                                                          size: 16),
                                                    for (int i = producerRating;
                                                        i < 5;
                                                        i++)
                                                      Icon(Icons.star_border,
                                                          color:
                                                              Colors.teal[600],
                                                          size: 16),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.category,
                                                        color: Colors.teal[600],
                                                        size: 16),
                                                    Text(
                                                      ' $producerType',
                                                      style: TextStyle(
                                                          fontSize: 16,
                                                          color:
                                                              Colors.teal[900]),
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

class ProducerDetailScreen extends StatelessWidget {
  final Map<String, dynamic> producer;

  const ProducerDetailScreen({Key? key, required this.producer})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Handle Reviews (it could be a string or a list)
    final reviews = producer['Reviews'];
    final reviewsList = reviews is List
        ? reviews // If it's a list, use it directly
        : reviews?.toString().split(', ') ??
            []; // If it's a string, split it into a list

    // Check if the image URL is valid (starts with http or https)
    final bool isValidImageUrl = producer['Image'] != null &&
        producer['Image'].isNotEmpty &&
        producer['Image'].startsWith('http');

    return Scaffold(
      appBar: AppBar(
        title: Text(producer['Name'] ?? 'Unknown Producer'),
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
                child: Hero(
                  tag: 'producer-image-${producer['Producer_Id']}',
                  child: CircleAvatar(
                    radius: 80,
                    backgroundImage: isValidImageUrl
                        ? NetworkImage(producer['Image'] ?? '')
                        : AssetImage('assets/images/producerHolder.png')
                            as ImageProvider,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Text(
                      producer['Name'] ?? 'Unknown Producer',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[900],
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0;
                            i <
                                (double.tryParse(producer['Rating'] ?? '0')
                                        ?.toInt() ??
                                    0);
                            i++)
                          Icon(Icons.star, color: Colors.amber, size: 20),
                        for (int i = (double.tryParse(producer['Rating'] ?? '0')
                                    ?.toInt() ??
                                0);
                            i < 5;
                            i++)
                          Icon(Icons.star_border, color: Colors.grey, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              _buildSectionHeader('Basic Information'),
              SizedBox(
                height: 140,
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  childAspectRatio: 2.5,
                  children: [
                    _buildDetailColumn(
                        'Type', producer['Producer_Type'] ?? 'N/A'),
                    _buildDetailColumn(
                        'Location', producer['Location'] ?? 'N/A'),
                    _buildDetailColumn('Email', producer['Email'] ?? 'N/A'),
                    _buildDetailColumn(
                        'Phone', producer['Phone_Number'] ?? 'N/A'),
                  ],
                ),
              ),
              SizedBox(height: 20),
              _buildSectionHeader('About'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  producer['Bio'] ?? 'No bio available',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.teal[700],
                  ),
                ),
              ),
              SizedBox(height: 20),
              _buildSectionHeader('Reviews'),
              if (reviewsList.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'No reviews available',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.teal[700],
                    ),
                  ),
                ),
              if (reviewsList.isNotEmpty)
                Column(
                  children: reviewsList
                      .map<Widget>((review) => Card(
                            margin: EdgeInsets.symmetric(vertical: 5),
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    review ?? 'No review available',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.teal[900],
                                    ),
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
                  label: Text('Choose Producer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[800],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    // Ensure meal is defined according to your application logic
                    ShoppingCart.addItem(
                      producer['Name'] ?? 'Unknown Producer',
                      (producer['Price'] ?? 0).toDouble(),
                      quantity: 1,
                      selectedproducer: producer,
                      meal: {},
                      bestservedwith: [], // Include a valid meal object if applicable
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${producer['Name'] ?? 'Unknown Producer'} Selected!'),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal, // Enable horizontal scrolling
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: Colors.teal[700]),
              overflow: TextOverflow.visible, // Show full text
            ),
          ),
        ],
      ),
    );
  }
}
