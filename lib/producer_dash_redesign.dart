import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class ProducerDashboardRedesign extends StatefulWidget {
  @override
  _ProducerDashboardRedesignState createState() =>
      _ProducerDashboardRedesignState();
}

class _ProducerDashboardRedesignState extends State<ProducerDashboardRedesign> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Producer Dashboard'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ProducerProfileOverview(),
          ProductManagement(),
          SupplyRequestList(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Products',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Orders',
          ),
        ],
        backgroundColor: Colors.teal,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
      ),
    );
  }
}

class ProducerProfileOverview extends StatefulWidget {
  @override
  _ProducerProfileOverviewState createState() =>
      _ProducerProfileOverviewState();
}

class _ProducerProfileOverviewState extends State<ProducerProfileOverview> {
  Map<String, dynamic>? producerProfile;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchProducerProfile();
  }

  Future<void> _fetchProducerProfile() async {
    try {
      final producerId = await getProducerId();
      if (producerId == null) {
        throw Exception('Producer ID not found in SharedPreferences');
      }
      final response = await http
          .get(Uri.parse('$apibaseurl/rr/rproducers?producer_id=$producerId'));
      if (response.statusCode == 200) {
        final profileData = json.decode(response.body);
        print(
            'DEBUG: Producer Profile Response -> $profileData'); // Debug print
        setState(() {
          if (profileData is Map && profileData.containsKey('data')) {
            final data = profileData['data'];
            if (data is List && data.isNotEmpty) {
              producerProfile = data.first; // Use the first producer profile
            } else {
              producerProfile = null;
            }
          } else {
            producerProfile = null;
          }
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load producer profile');
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
    return Scaffold(
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : errorMessage != null
                ? Text(errorMessage!, style: TextStyle(color: Colors.red))
                : producerProfile != null
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 70,
                              backgroundColor: Colors.transparent,
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: producerProfile!['Image'] ??
                                      'assets/images/producerHolder.png',
                                  fit: BoxFit.cover,
                                  width: 140,
                                  height: 140,
                                  errorWidget: (context, url, error) =>
                                      Image.asset(
                                          'assets/images/producerHolder.png'),
                                ),
                              ),
                            ),
                            SizedBox(height: 20),
                            Text(
                              producerProfile!['Name'] ?? 'Unknown Producer',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[900]),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (int i = 0;
                                    i <
                                        (double.tryParse(
                                                    producerProfile!['Rating']
                                                            ?.toString() ??
                                                        '0')
                                                ?.toInt() ??
                                            0);
                                    i++)
                                  Icon(Icons.star, color: Colors.teal),
                                for (int i = (double.tryParse(
                                                producerProfile!['Rating']
                                                        ?.toString() ??
                                                    '0')
                                            ?.toInt() ??
                                        0);
                                    i < 5;
                                    i++)
                                  Icon(Icons.star_border,
                                      color: Colors.teal[200]),
                              ],
                            ),
                            SizedBox(height: 16),
                            Text(
                              producerProfile!['Location']?.toString() ??
                                  'Unknown Location',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[700]),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 16),
                            Text(
                              producerProfile!['Description']?.toString() ??
                                  'No description available',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.grey[700]),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                // Navigate to edit profile
                              },
                              child: Text('Edit Profile',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal[800],
                                padding: EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 12),
                                textStyle: TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text('No profile data available'),
      ),
    );
  }
}

class ProductManagement extends StatefulWidget {
  @override
  _ProductManagementState createState() => _ProductManagementState();
}

class _ProductManagementState extends State<ProductManagement> {
  final List<Map<String, dynamic>> products = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    try {
      final producerId = await getProducerId();
      if (producerId == null) {
        throw Exception('Producer ID not found in SharedPreferences');
      }
      final response = await http
          .get(Uri.parse('$apibaseurl/rr/produce?producer_id=$producerId'));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('DEBUG: Products Response -> $responseData'); // Debug print
        setState(() {
          if (responseData is List) {
            products.addAll(responseData.cast<Map<String, dynamic>>());
          } else if (responseData is Map && responseData.containsKey('data')) {
            final data = responseData['data'];
            if (data is List) {
              products.addAll(data.cast<Map<String, dynamic>>());
            }
          }
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load products');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load products: $e';
      });
    }
  }

  void _addProduct(String name, double price) {
    setState(() {
      products.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': name,
        'price': price
      });
    });
  }

  void _editProduct(int index, String name, double price) {
    setState(() {
      products[index] = {
        'id': products[index]['id'],
        'name': name,
        'price': price
      };
    });
  }

  void _removeProduct(int index) {
    setState(() {
      products.removeAt(index);
    });
  }

  void _openAddProductDialog() {
    _openProductDialog(isEdit: false);
  }

  void _openEditProductDialog(int index) {
    _openProductDialog(isEdit: true, productIndex: index);
  }

  void _openProductDialog({bool isEdit = false, int? productIndex}) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    if (isEdit) {
      nameController.text = products[productIndex!]['name'];
      priceController.text = products[productIndex]['price'].toString();
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Product' : 'Add Product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Product Name'),
              ),
              TextField(
                controller: priceController,
                decoration: InputDecoration(labelText: 'Price'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text;
                final price = double.tryParse(priceController.text);
                if (name.isNotEmpty && price != null) {
                  if (isEdit) {
                    _editProduct(productIndex!, name, price);
                  } else {
                    _addProduct(name, price);
                  }
                  Navigator.of(context).pop();
                }
              },
              child: Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            'Manage Products',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal[900]),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _openAddProductDialog,
            child: Text('Add Product', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[800],
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              textStyle: TextStyle(fontSize: 18),
            ),
          ),
          SizedBox(height: 20),
          if (isLoading)
            Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Center(
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)))
          else
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                          product['name']?.toString() ?? 'Unnamed Product',
                          style: TextStyle(color: Colors.teal[800])),
                      subtitle: Text(
                          'ugx ${(product['price'] ?? 0.0).toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.grey[600])),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.teal[600]),
                            onPressed: () => _openEditProductDialog(index),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red[600]),
                            onPressed: () => _removeProduct(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class SupplyRequestList extends StatefulWidget {
  @override
  _SupplyRequestListState createState() => _SupplyRequestListState();
}

class _SupplyRequestListState extends State<SupplyRequestList> {
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    try {
      final producerId = await getProducerId();
      if (producerId == null) {
        throw Exception('Producer ID not found in SharedPreferences');
      }
      final uri = Uri.parse('$apibaseurl/rr/orders?producer_id=$producerId');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('DEBUG: Orders Response -> $responseData'); // Debug print
        setState(() {
          if (responseData is Map && responseData.containsKey('data')) {
            final data = responseData['data'];
            if (data is List) {
              orders.addAll(data.cast<Map<String, dynamic>>());
            }
          }
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
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal[900]),
          ),
          SizedBox(height: 20),
          if (isLoading)
            Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Center(
                child: Text(errorMessage!, style: TextStyle(color: Colors.red)))
          else
            Expanded(
              child: ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                          'Order #${order['order_id']?.toString() ?? 'Unknown'}',
                          style: TextStyle(color: Colors.teal[800])),
                      subtitle: Text(
                        'Product: ${order['meal_name']?.toString() ?? 'Unknown'}, Quantity: ${order['quantity']?.toString() ?? '0'}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      trailing: Text(
                          order['order_status']?.toString() ?? 'Pending',
                          style: TextStyle(color: Colors.teal[800])),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<int?> getProducerId() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getInt('producer_id');
}
