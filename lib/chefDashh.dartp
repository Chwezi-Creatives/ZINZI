import 'package:flutter/material.dart';
import 'chefdash_redesign.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChefDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChefDashboardRedesign();
  }
}

class ChefProfileOverview extends StatefulWidget {
  @override
  _ChefProfileOverviewState createState() => _ChefProfileOverviewState();
}

class _ChefProfileOverviewState extends State<ChefProfileOverview> {
  dynamic chefProfile; // Holds the list of profiles
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchChefProfile();
  }

  Future<void> _fetchChefProfile() async {
    try {
      final chefId = await getChefId();
      if (chefId == null) {
        throw Exception('Chef ID not found in SharedPreferences');
      }
      final response =
          await http.get(Uri.parse('$apibaseurl/rr/rchefs?chef_id=$chefId'));
      if (response.statusCode == 200) {
        final profileData = json.decode(response.body);
        print('DEBUG: Chef Profile Response -> $profileData'); // Debug print
        setState(() {
          chefProfile =
              handleApiResponse(profileData); // Handle dynamic response
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load chef profile');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Center(
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)))
          else if (chefProfile != null &&
              chefProfile is List &&
              chefProfile.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Access the first chef profile in the list
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.transparent,
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: (chefProfile[0]['image'] ?? '').toString(),
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) {
                        return Image.asset(
                          'assets/images/producerHolder.png',
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  (chefProfile[0]['name'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[900],
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < _getRating(chefProfile[0]); i++)
                      Icon(Icons.star, color: Colors.teal),
                    for (int i = _getRating(chefProfile[0]); i < 5; i++)
                      Icon(Icons.star_border, color: Colors.teal[200]),
                  ],
                ),
                SizedBox(height: 16),
                Text(
                  (chefProfile[0]['bio'] ?? '').toString(),
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to edit profile
                  },
                  child: Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[200],
                    foregroundColor: Colors.teal[900],
                  ),
                ),
              ],
            )
          else
            Center(child: Text('No profile data available')),
        ],
      ),
    );
  }

  // Helper function to safely parse the Rating field
  int _getRating(dynamic profile) {
    try {
      final ratingValue = double.tryParse((profile['Rating'] ?? '').toString());
      return ratingValue?.toInt() ?? 0; // Default to 0 if parsing fails
    } catch (e) {
      return 0; // Return 0 in case of any exception
    }
  }
}

class MenuManagement extends StatefulWidget {
  @override
  _MenuManagementState createState() => _MenuManagementState();
}

class _MenuManagementState extends State<MenuManagement> {
  dynamic menuItems;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMenuItems();
  }

  Future<void> _fetchMenuItems() async {
    try {
      final chefId = await getChefId();
      if (chefId == null) {
        throw Exception('Chef ID not found in SharedPreferences');
      }
      final response =
          await http.get(Uri.parse('$apibaseurl/rr/menu?chef_id=$chefId'));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('DEBUG: Menu Items Response -> $responseData'); // Debug print
        setState(() {
          menuItems =
              handleApiResponse(responseData); // Handle dynamic response
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load menu items');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load menu items: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            'Manage Menu',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          if (isLoading)
            Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Center(
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)))
          else if (menuItems != null && menuItems is List)
            Expanded(
              child: ListView.builder(
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final menuItem = menuItems[index];
                  return ListTile(
                    title: Text(menuItem['name'].toString()),
                    subtitle: Text('ugx ${_parsePrice(menuItem['price'])}'),
                  );
                },
              ),
            )
          else if (menuItems != null && menuItems is Map)
            Expanded(
              child: ListView.builder(
                itemCount: (menuItems['data'] as List).length,
                itemBuilder: (context, index) {
                  final menuItem = menuItems['data'][index];
                  return ListTile(
                    title: Text(menuItem['name'].toString()),
                    subtitle: Text('ugx ${_parsePrice(menuItem['price'])}'),
                  );
                },
              ),
            )
          else
            Expanded(child: Center(child: Text('No menu data available'))),
        ],
      ),
    );
  }

  // Helper function to safely parse the price field
  int _parsePrice(dynamic price) {
    try {
      return double.tryParse(price.toString())?.toInt() ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

class OrdersList extends StatefulWidget {
  @override
  _OrdersListState createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  dynamic orders;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    try {
      final chefId = await getChefId();
      if (chefId == null) {
        throw Exception('Chef ID not found in SharedPreferences');
      }
      final response =
          await http.get(Uri.parse('$apibaseurl/rr/orders?chef_id=$chefId'));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('DEBUG: Orders Response -> $responseData'); // Debug print
        setState(() {
          orders = handleApiResponse(responseData); // Handle dynamic response
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load orders');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load orders: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            'Orders',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (isLoading)
            Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Center(
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)))
          else if (orders != null && orders is List)
            Expanded(
              child: ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return ListTile(
                    title: Text('Order #${_parseId(order['id'])}'),
                    subtitle: Text(
                      'Item: ${order['item_name']}, Quantity: ${_parseQuantity(order['quantity'])}',
                    ),
                    trailing: Text(order['status'].toString()),
                  );
                },
              ),
            )
          else if (orders != null && orders is Map)
            Expanded(
              child: ListView.builder(
                itemCount: (orders['data'] as List).length,
                itemBuilder: (context, index) {
                  final order = orders['data'][index];
                  return ListTile(
                    title: Text('Order #${_parseId(order['id'])}'),
                    subtitle: Text(
                      'Item: ${order['item_name']}, Quantity: ${_parseQuantity(order['quantity'])}',
                    ),
                    trailing: Text(order['status'].toString()),
                  );
                },
              ),
            )
          else
            Expanded(child: Center(child: Text('No orders available'))),
        ],
      ),
    );
  }

  // Helper function to safely parse the id field
  int _parseId(dynamic id) {
    try {
      return int.tryParse(id.toString()) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // Helper function to safely parse the quantity field
  int _parseQuantity(dynamic quantity) {
    try {
      return int.tryParse(quantity.toString()) ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

// Helper function to handle dynamic API responses
dynamic handleApiResponse(dynamic responseData) {
  if (responseData is List) {
    return responseData; // Directly assign if it's a list
  } else if (responseData is Map && responseData.containsKey('data')) {
    return responseData['data']; // Use 'data' key if it's a map
  }
  return null; // Return null if neither condition is met
}

Future<String?> getChefId() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('chef_user_id');
}
