import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zinzi2/orderstatus polls.dart'
    as order_status; // Import with prefix
import 'cart.dart' as cart; // Import cart library with prefix
import 'package:zinzi2/widgets/app_drawer.dart'; // Import the AppDrawer
import 'package:google_fonts/google_fonts.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/order_status.dart';

final String apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

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

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) {
        _showSnackBar('User is not logged in.');
        setState(() => _isLoading = false);
        return;
      }

      final orderPayload = {
        'order_type': 'meal',
        'user_id': userId.toString(),
        'items': widget.items
            .map((item) {
              if (item['type'] == 'gig') {
                final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
                return {
                  'product_id': null, // Gigs don't have a product_id like meals
                  'quantity': null, // Gigs don't have a quantity in the same way as meals
                  'price': (gigDetails['price'] as num?)?.toDouble(),
                  'chef_id': gigDetails['chef_id']?.toString(),
                  'producer_id': gigDetails['producer_id']?.toString(),
                };
              } else { // Assume 'meal' type or handle other types if necessary
                return {
  'product_id': item['meal']?['Meal_id']?.toString(),
  'quantity': (item['quantity'] as num?)?.toInt(),
  'price': (item['price'] as num?)?.toDouble(),
  'chef_id': item['selectedchef']?['chefid']?.toString(),
  'producer_id': item['selectedproducer']?['producer_id']?.toString(),
  // Pass selected complementary meals (bestservedwith) if present
  'bestservedwith': item['bestservedwith'] ?? [],
};
              }
            }).toList(),
        'delivery_address':
            _location.isNotEmpty ? _location : _addressController.text,
        'notes': _notesController.text,
        'payment_mode': _selectedPaymentMethod.toLowerCase(),
        'total_price': widget.totalPrice,
        'chef_id': widget.items.first['selectedchef']?['chefid']?.toString(),
        'producer_id':
            widget.items.first['selectedproducer']?['producer_id']?.toString(),
      };

      print('Order Payload: ' + orderPayload.toString());

      final response = await http.post(
        Uri.parse('$apibaseurl/rr/Aorders'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(orderPayload),
      );

      print('API Response Status: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final orderId = responseData['order_id'];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => order_status.OrderStatusScreen(
              userId: userId,
              orderIdList: [orderId],
              orderId: orderId,
            ),
          ),
        );
      } else {
        throw Exception('Failed to place order: ${response.statusCode}');
      }
    } catch (e, stack) {
      print('Order submission error: $e');
      print('Stack trace: $stack');
      _showSnackBar('Failed to place order. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Debug log: print what checkout receives as cartItems

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
                        ...widget.items.map((item) => Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${item['title']} x${item['quantity']}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.teal[700],
                                    ),
                                  ),
                                  Text(
                                    '\$${((item['price'] ?? 0.0) * (item['quantity'] ?? 0)).toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.teal[700],
                                    ),
                                  ),
                                ],
                              ),
                            )),
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
                              '\$${widget.totalPrice.toStringAsFixed(2)}',
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

                // Payment Method Card
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
                          'Payment Method',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        RadioListTile<String>(
                          title: Text('Momo', style: GoogleFonts.poppins()),
                          value: 'Momo',
                          groupValue: _selectedPaymentMethod,
                          onChanged: (value) {
                            setState(() => _selectedPaymentMethod = value!);
                          },
                          activeColor: Colors.teal[800],
                        ),
                        RadioListTile<String>(
                          title: Text('Card', style: GoogleFonts.poppins()),
                          value: 'Card',
                          groupValue: _selectedPaymentMethod,
                          onChanged: (value) {
                            setState(() => _selectedPaymentMethod = value!);
                          },
                          activeColor: Colors.teal[800],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Location Card
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
                            labelStyle:
                                GoogleFonts.poppins(color: Colors.teal[400]),
                            suffixIcon: _isLocationLoading
                                ? SizedBox(
                                    width: 24.0,
                                    height: 24.0,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.0),
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 50, vertical: 15),
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
