import 'dart:async';
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'orderstatus polls.dart' as order_status;
import 'package:zinzi2/cart.dart'; // Import ShoppingCart

final String apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double totalPrice;

  const CheckoutScreen({
    Key? key,
    required this.items,
    required this.totalPrice,
  }) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedPaymentMethod = 'Momo';
  bool _isLoading = false;
  bool _isLocationLoading = false;
  bool _isOptionalInfoExpanded = false;
  String _location = '';
  late double _scaleFactor;
  late Timer _timer;

  String _extractGuests(dynamic numberOfPeople) {
    if (numberOfPeople == null) return 'ugx';
    final str = numberOfPeople.toString();
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? match.group(0)! : 'ugx';
  }

  @override
  void initState() {
    super.initState();
    print('cartItems: ' + widget.items.toString());
    _scaleFactor = 1.0;
    _startAnimation();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _timer.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _scaleFactor = _scaleFactor == 1.0 ? 0.95 : 1.0;
      });
    });
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLocationLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showSnackBar('Location services are disabled. Please enable them.');
          setState(() => _isLocationLoading = false);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showSnackBar('Location permission denied. Cannot get location.');
            setState(() => _isLocationLoading = false);
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showSnackBar(
              'Location permission permanently denied. Please enable from app settings.');
          setState(() => _isLocationLoading = false);
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      String apiUrl =
          'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
      final response = await http.get(Uri.parse(apiUrl));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _location =
              "${position.latitude}, ${position.longitude}, ${data['display_name']}";
        });
      } else {
        setState(() {
          _location = "${position.latitude}, ${position.longitude}";
        });
        _showSnackBar('Could not get detailed address, using coordinates.');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error getting location: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLocationLoading = false);
      }
    }
  }

  void _showSnackBar(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.teal[800],
      ),
    );
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    if (_location.trim().isEmpty) {
      _showSnackBar('Please acquire your delivery location before placing the order.');
      return;
    }

    setState(() => _isLoading = true);

    int? userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('user_id');

      if (userId == null) {
        _showSnackBar('User is not logged in.');
        setState(() => _isLoading = false);
        return;
      }
    } catch (e) {
      print('Error getting user ID: $e');
      _showSnackBar('Failed to get user information. Please try again.');
      setState(() => _isLoading = false);
      return;
    }

    // Process each item as a separate order
    List<String> orderIds = [];
    double totalProcessedPrice = 0.0;

    for (final item in widget.items) {
      // Determine order_type for this item
      String orderType = 'meal';
      if (item.containsKey('meal') && item['meal'] is Map && item['meal']['order_type'] != null) {
        orderType = item['meal']['order_type'].toString();
      } else if (item['type'] != null) {
        orderType = item['type'].toString();
      }

      // Prepare order payload for this single item
      Map<String, dynamic> itemPayload;
      if (item['type'] == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        itemPayload = {
          'user_id': userId.toString(),
          'chef_id': gigDetails['chef_id'],
          'producer_id': gigDetails['producer_id'],
          'gig_details': {
            'gig_type': gigDetails['gig_type'],
            'location': gigDetails['location'],
            'scheduled_date': gigDetails['scheduled_date'],
            'time': gigDetails['time'],
            'estimated_duration': gigDetails['estimated_duration'],
            'number_of_people': gigDetails['number_of_people'],
            'price': gigDetails['price'],
            'detailed_description': gigDetails['detailed_description'],
          }
        };
      } else {
        // Assume meal type
        final meal = item['meal'] as Map<String, dynamic>? ?? {};
        final productIdEntry = meal.entries.firstWhere(
          (e) => e.key.endsWith('_id') && e.key != 'chef_id' && e.key != 'producer_id',
          orElse: () => const MapEntry('product_id', null),
        );
        itemPayload = {
          'order_type': orderType,
          'type': orderType,
          productIdEntry.key: productIdEntry.value?.toString(),
          'product_id': productIdEntry.value?.toString(),
          'quantity': (item['quantity'] as num?)?.toInt(),
          'price': (item['price'] as num?)?.toDouble(),
          'chef_id': item['selectedchef']?['chefid']?.toString(),
          'producer_id': item['selectedproducer']?['producer_id']?.toString(),
          'bestservedwith': item['bestservedwith'] ?? [],
        };
      }

      // Create order payload for this single item
      Map<String, dynamic> orderPayload = {
        'order_type': orderType,
        'user_id': userId.toString(),
        'items': [itemPayload], // Only one item per order
        'delivery_address': _location.isNotEmpty ? _location : _addressController.text,
        'notes': _notesController.text,
        'payment_mode': _selectedPaymentMethod.toLowerCase(),
        'total_price': (item['price'] as num?)?.toDouble() ?? 0.0,
        'chef_id': item['selectedchef']?['chefid']?.toString(),
        'producer_id': item['selectedproducer']?['producer_id']?.toString(),
      };

      print('Submitting order for item: ' + item.toString());
      print('Order Payload: ' + orderPayload.toString());

      // Submit the order
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/Aorders'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(orderPayload),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final orderId = responseData['order_id'];
        orderIds.add(orderId.toString());
        totalProcessedPrice += (item['price'] as num?)?.toDouble() ?? 0.0;
        print('Successfully submitted order $orderId for item: ' + item.toString());
        // Remove the successfully ordered item from the cart
        ShoppingCart.removeItems([item]);
      } else {
        throw Exception('Failed to place order for item: ${item.toString()}. Response: ${response.statusCode}');
      }
    }

    // After all orders are processed
    if (orderIds.isNotEmpty) {
      // Navigate to order status screen with all order IDs
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => order_status.OrderStatusScreen(
            userId: userId!,
            orderIdList: orderIds.map(int.parse).toList(),
            orderId: int.parse(orderIds.first), // Show first order ID by default
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 4,
        title: Text('Checkout', style: GoogleFonts.poppins()),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: Container(
          height: MediaQuery.of(context).size.height,
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
          padding: EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Summary Card
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Summary',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        ...List.generate(widget.items.length, (i) {
                          final item = widget.items[i];
                          final bestServedWith = (item['bestservedwith'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final chef = item['selectedchef'] as Map<String, dynamic>?;
                          final chefHasPrice = chef != null && chef['price'] != null && chef['price'] is num;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (i != 0) Divider(height: 18, color: Colors.teal[100]),
                              if ((item['type'] ?? 'meal') == 'gig') ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item['gigDetails']?['gig_type'] ?? 'Gig'}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.teal[700],
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Guests (${_extractGuests(item['gigDetails']?['number_of_people'])})',
                                          style: GoogleFonts.poppins(
                                            color: Colors.teal[700],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      () {
                                        final gigPrice = (item['gigDetails']?['price'] is num)
                                            ? (item['gigDetails']['price'] as num)
                                            : (item['price'] ?? 0.0);
                                        return 'ugx ${gigPrice.toStringAsFixed(2)}';
                                      }(),
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal[700],
                                      ),
                                    ),
                                  ],
                                ),
                                if (item['gigDetails'] != null && item['gigDetails']['chef_name'] != null && item['gigDetails']['chef_name'].toString().isNotEmpty)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Chef: ${item['gigDetails']['chef_name']}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.teal[800])),
                                    ],
                                  ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${item['title']} x${item['quantity']}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal[700],
                                      ),
                                    ),
                                    Text(
                                      'ugx ${((item['price'] ?? 0.0) * (item['quantity'] ?? 0)).toStringAsFixed(2)}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal[700],
                                      ),
                                    ),
                                  ],
                                ),
                                if (chef != null && chef['name'] != null && chef['name'].toString().isNotEmpty)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Chef: ${chef['name']}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.teal[800])),
                                    ],
                                  ),
                                if (bestServedWith.isNotEmpty)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Best Served With:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
                                      ...bestServedWith.map((comp) {
                                        final compName = comp['name']?.toString() ?? comp['title']?.toString() ?? '';
                                        final compPrice = (comp['price'] is num) ? (comp['price'] as num).toDouble() : 5.0;
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(compName, style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800])),
                                            Text('ugx ${compPrice.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800])),
                                          ],
                                        );
                                      }).toList(),
                                    ],
                                  ),
                              ],
                            ],
                          );
                        }).toList(),
                        Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.teal[900],
                              ),
                            ),
                            Text(
                              'ugx ${widget.totalPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.teal[900],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Delivery Location
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Location',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: TextEditingController(text: _location),
                          decoration: InputDecoration(
                            labelText: 'Location',
                            labelStyle: GoogleFonts.poppins(color: Colors.teal[400]),
                            suffixIcon: _isLocationLoading
                                ? SizedBox(
                                    width: 24.0,
                                    height: 24.0,
                                    child: CircularProgressIndicator(strokeWidth: 2.0),
                                  )
                                : IconButton(
                                    icon: Icon(Icons.location_on),
                                    onPressed: _getCurrentLocation,
                                  ),
                          ),
                          validator: (value) => value?.isEmpty ?? true
                              ? 'Location is required'
                              : null,
                          onChanged: (value) => _location = value,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Optional Information
                ExpansionTile(
                  title: Text(
                    'Optional Information',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[800],
                    ),
                  ),
                  initiallyExpanded: _isOptionalInfoExpanded,
                  onExpansionChanged: (bool expanding) =>
                      setState(() => _isOptionalInfoExpanded = expanding),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            style: GoogleFonts.poppins(),
                          ),
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'Special Instructions',
                              prefixIcon: Icon(Icons.notes),
                            ),
                            maxLines: 3,
                            style: GoogleFonts.poppins(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),

                // Place Order Button
                Center(
                  child: AnimatedScale(
                    scale: _scaleFactor,
                    duration: Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                        textStyle: GoogleFonts.poppins(fontSize: 18),
                      ),
                      child: _isLoading
                          ? CircularProgressIndicator(color: Colors.white)
                          : Text('Place Order', style: GoogleFonts.poppins()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}