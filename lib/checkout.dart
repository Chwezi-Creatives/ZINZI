import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'orderstatus.dart'; // Import the modular OrderStatusScreen

final String apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  const CheckoutScreen({Key? key, required this.cartItems}) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late double _scaleFactor;
  late Timer _timer;
  String _selectedPaymentMethod = 'Momo';
  String _fullName = '';
  String _specialInstructions = '';
  String _orderType = 'Meal';
  String _location = '';
  bool _isLoading = false;
  bool _isOptionalInfoExpanded = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _scaleFactor = 1.0;
    _startAnimation();
    _getCurrentLocation(); // Fetch user's current location on startup
    print('DEBUG: Cart Items -> ${widget.cartItems}');
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _scaleFactor = _scaleFactor == 1.0 ? 0.95 : 1.0;
      });
    });
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      // Check if user_id is null
      if (userId == null) {
        _showSnackBar('User is not logged in.');
        setState(() => _isLoading = false);
        return;
      }

      final totalPrice = calculateTotal();

      // Prepare items for the API request
      List<Map<String, dynamic>> itemsForApi = widget.cartItems.map((item) {
         final selectedProducer = item['selectedproducer'];
         final selectedChef = item['selectedchef'];
 
         // Determine which ID to attach to the order
         String? chefId;
         String? producerId;
 
         if (selectedChef != null) {
           chefId = selectedChef['chefid']?.toString(); // Ensure it is a String
         }
         if (selectedProducer != null) {
           producerId = selectedProducer['producer_id']?.toString(); // Ensure it is a String
         }
 
         // Debugging information
         print('DEBUG: product_id=${item['meal']['meal_id']}, chef_id=$chefId, producer_id=$producerId');
 
         return {
           'product_id': item['meal']['meal_id'].toString(), // Ensure meal_id is a String
           'chef_id': chefId, // Attach chef ID or null
           'producer_id': producerId, // Attach producer ID or null
           'quantity': item['quantity'] ?? 1, // Default to 1 if quantity is null
           'price': item['price'] ?? 0, // Default to 0 if price is null
         };
       }).toList();

      final deliveryAddress = _location.isNotEmpty ? _location : 'Default location';

      final response = await http.post(
        Uri.parse('$apibaseurl/rr/Aorders'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId.toString(), // Convert userId to String
          'order_type': _orderType.toLowerCase(),
          'delivery_address': deliveryAddress,
          'total_price': totalPrice,
          'notes': _specialInstructions,
          'payment_mode': _selectedPaymentMethod.toLowerCase(),
          'items': itemsForApi,
        }),
      );

      // Debugging: Print the API response
      print('API Response Status Code: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      final responseData = json.decode(response.body);
      print('Parsed Response Data: $responseData');

      if (response.statusCode == 201) {
        final orderId = responseData['order_id'];
        if (orderId != null) {
          print('Extracted Order ID: $orderId');
          _showSnackBar('Order #$orderId placed successfully!');

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderStatusScreen(orderId: orderId, userId: userId),
            ),
          );
        } else {
          print('Error: order_id not found in API response');
          _showSnackBar('Error: order_id not found in API response');
        }
      } else {
        print('Error: ${responseData['error'] ?? response.reasonPhrase}');
        _showSnackBar('Error: ${responseData['error'] ?? response.reasonPhrase}');
      }
    } catch (error) {
      print('Error placing order: $error');
      _showSnackBar('Error: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Enable location services in settings');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permissions required');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Enable location in app settings');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _location = "${position.latitude}, ${position.longitude}, ${data['display_name']}";
        });
      } else {
        setState(() {
          _location = "${position.latitude}, ${position.longitude}";
        });
      }
    } catch (e) {
      _showSnackBar('Error getting location: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 4,
        title: const Text('Checkout'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildSectionTitle('A summary of your order'),
                        const SizedBox(height: 8.0),
                        _buildOrderSummary(),
                        const Divider(),
                        _buildPriceRow('Shipping/Tax', calculateShippingTax()),
                        const Divider(),
                        _buildPriceRow('Total', calculateTotal(), isTotal: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildSectionTitle('Please choose a payment method'),
                        const SizedBox(height: 8.0),
                        _buildPaymentMethods(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildSectionTitle('Delivery Location'),
                        const SizedBox(height: 8.0),
                        TextFormField(
                          controller: TextEditingController(text: _location),
                          decoration: InputDecoration(
                            labelText: 'Location',
                            labelStyle: TextStyle(color: Colors.teal[400]),
                            suffixIcon: _isLoading
                                ? const CircularProgressIndicator()
                                : IconButton(
                                    icon: const Icon(Icons.location_on),
                                    onPressed: _getCurrentLocation,
                                  ),
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Location is required' : null,
                          onChanged: (value) => _location = value,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                ExpansionTile(
                  title: Text(
                    'Optional Information',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                  ),
                  initiallyExpanded: _isOptionalInfoExpanded,
                  onExpansionChanged: (bool expanding) => setState(() => _isOptionalInfoExpanded = expanding),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              labelStyle: TextStyle(color: Colors.teal[400]),
                            ),
                            onChanged: (value) => _fullName = value,
                          ),
                          const SizedBox(height: 8.0),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'Special Instructions (optional)',
                              labelStyle: TextStyle(color: Colors.teal[400]),
                            ),
                            maxLines: 3,
                            onChanged: (value) => _specialInstructions = value,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    transform: Matrix4.identity()..scale(_scaleFactor),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _placeOrder,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Confirm Order Now!',
                                style: TextStyle(color: Colors.white),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal[800],
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                        ),
                      ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.teal[800]),
    );
  }

  Widget _buildPriceRow(String title, double value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Text(
            title,
            style: TextStyle(color: Colors.teal[700]),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            ' ',
            style: TextStyle(color: isTotal ? Colors.teal[900]! : Colors.teal[600]!),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            '\$${value.toStringAsFixed(2)}',
            style: isTotal
                ? TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[900])
                : TextStyle(color: Colors.teal[600]),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary() {
    return Column(
      children: widget.cartItems.map((item) {
        double itemTotal = item['price'] * item['quantity'];
        return _buildItemRow(item, itemTotal);
      }).toList(),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item, double itemTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Text(
            item['title'],
            style: TextStyle(color: Colors.teal[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            'x${item['quantity']}',
            style: TextStyle(color: Colors.teal[600]),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            '\$${itemTotal.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.teal[600]),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _buildPaymentMethodButton('Momo', 'assets/images/momo.png'),
          const SizedBox(width: 5.0),
          _buildPaymentMethodButton('Stripe', 'assets/images/stripe.png'),
          const SizedBox(width: 5.0),
          _buildPaymentMethodButton('PayPal', 'assets/images/paypal.png'),
          const SizedBox(width: 5.0),
          _buildPaymentMethodButton('Cash', Icons.account_balance_wallet),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodButton(String title, dynamic icon) {
    bool isSelected = _selectedPaymentMethod.toLowerCase() == title.toLowerCase();
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = title;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isSelected ? Colors.teal[800]! : Colors.teal[100]!),
          boxShadow: isSelected
              ? [
                  BoxShadow(color: Colors.teal[100]!, blurRadius: 5, spreadRadius: 1, offset: const Offset(1, 4))
                ]
              : [],
        ),
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.teal[900],
            backgroundColor: Colors.teal[50],
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icon is String
                  ? Image.asset(
                      icon,
                      height: 24.0,
                      width: 24.0,
                    )
                  : Icon(icon),
              const SizedBox(width: 4.0),
              Text(title, style: TextStyle(color: Colors.teal[800])),
            ],
          ),
        ),
      ),
    );
  }

  double calculateSubtotal() {
    return widget.cartItems.fold(0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  double calculateShippingTax() {
    return 0.5; // Placeholder for actual shipping logic
  }

  double calculateTotal() {
    return calculateSubtotal() + calculateShippingTax();
  }
}
