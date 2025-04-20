import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'orderstatus polls.dart'; // Import the modular OrderStatusScreen
import 'cart.dart' as cart; // Import cart library with prefix
import 'package:zinzi2/widgets/app_drawer.dart'; // Import the AppDrawer

final String apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

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
  String _location = '';
  bool _isLoading = false; // For order placement loading state
  bool _isLocationLoading = false; // For location fetching loading state
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

  void _displaySnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.teal[800],
      ),
    );
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _scaleFactor = _scaleFactor == 1.0 ? 0.95 : 1.0;
      });
    });
  }

  List<Map<String, dynamic>> _groupCartItemsForOrderPlacement(
      List<Map<String, dynamic>> cartItems) {
    final List<Map<String, dynamic>> orderGroups =
        []; // Stores the final order payloads

    for (var item in cartItems) {
      final itemType = item['type'] ?? 'meal';

      if (itemType == 'gig') {
        // Construct payload for gig orders
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        final gigOrderPayload = {
          'order_type': 'gig',
          'items': [
            {
              'user_id': item['user_id'],
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
            }
          ],
          'total_price': (gigDetails['price'] as num?)?.toDouble() ?? 0.0,
          'chef_id': gigDetails['chef_id']?.toString(),
          'user_id': item['user_id'], // Assuming user ID is within item
        };
        orderGroups.add({
          'payload': gigOrderPayload,
          'original_items': [item],
        });
      } else {
        // Process meal items
        final selectedChef = item['selectedchef'];
        final selectedProducer = item['selectedproducer'];

        final formattedApiItems = [
          {
            'product_id': item['meal']?['Meal_id']?.toString(),
            'quantity': item['quantity'],
            'price': item['price'],
            'chef_id': selectedChef?['chefid']?.toString(),
            'producer_id': selectedProducer?['producer_id']?.toString(),
          }
        ];

        final mealOrderPayload = {
          'order_type': 'meal',
          'chef_id': selectedChef?['chefid']?.toString(),
          'producer_id': selectedProducer?['producer_id']?.toString(),
          'items': formattedApiItems,
          'total_price': (item['quantity'] * item['price']),
        };

        orderGroups.add({
          'payload': mealOrderPayload,
          'original_items': [item],
        });
      }
    }
    return orderGroups;
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // Store results associated with original items
    List<Map<String, dynamic>> successfulCartItems = [];
    List<Map<String, dynamic>> failedCartItems = [];
    List<Map<String, dynamic>> successDetails = [];
    List<Map<String, dynamic>> failureDetails = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) {
        _displaySnackBar('User is not logged in.');
        setState(() => _isLoading = false);
        return;
      }

      // Group items, getting payload + original items for each potential order
      final List<Map<String, dynamic>> orderGroupsToPlace =
          _groupCartItemsForOrderPlacement(widget.cartItems);

      if (orderGroupsToPlace.isEmpty) {
        _showSnackBar('Your cart is empty.');
        setState(() => _isLoading = false);
        return;
      }

      final deliveryAddress =
          _location.isNotEmpty ? _location : 'Default location';

      // Place each order group separately
      for (var orderGroup in orderGroupsToPlace) {
        final orderPayload = orderGroup['payload'] as Map<String, dynamic>;
        orderPayload['user_id'] = userId.toString();
        orderPayload['delivery_address'] = deliveryAddress;
        orderPayload['notes'] = _specialInstructions;
        orderPayload['payment_mode'] = _selectedPaymentMethod.toLowerCase();

        print('--- Placing Order Group ---');
        print('Payload: ${json.encode(orderPayload)}');

        String? currentOrderId;
        String? currentError;

        try {
          final response = await http.post(
            Uri.parse('$apibaseurl/rr/Aorders'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(orderPayload),
          );

          print('API Response Status Code: ${response.statusCode}');
          print('API Response Body: ${response.body}');

          if (response.statusCode == 201) {
            final responseData = json.decode(response.body);
            final orderId = responseData['order_id'];
            currentOrderId = orderId.toString();
            print('Successfully placed order: $currentOrderId');
          } else {
            final responseData = json.decode(response.body);
            currentError = responseData['error'] ??
                response.reasonPhrase ??
                'Unknown error';
            print('Failed to place order. Error: $currentError');
          }
        } catch (e) {
          currentError = 'Exception: $e';
          print('Exception placing order. Error: $currentError');
        }

        // Associate result with original items
        if (currentOrderId != null) {
          successfulCartItems.addAll(orderGroup['original_items']);
          successDetails.add({
            'orderId': currentOrderId,
            'items': orderGroup['original_items']
          });
        } else {
          failedCartItems.addAll(orderGroup['original_items']);
          failureDetails.add({
            'error': currentError ?? 'Unknown Failure',
            'items': orderGroup['original_items']
          });
        }
        print('---------------------');
      }

      await _showOrderSummaryDialog(
          successDetails, failureDetails, successfulCartItems, userId);
    } catch (error) {
      print('General error during order placement process: $error');
      _displaySnackBar('An unexpected error occurred: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- NEW: Dialog to show order summary ---
  Future<void> _showOrderSummaryDialog(
      List<Map<String, dynamic>> successDetails,
      List<Map<String, dynamic>> failureDetails,
      List<Map<String, dynamic>> successfulCartItems,
      int? userId) async {
    String successContent = successDetails.isEmpty
        ? "No orders were placed successfully."
        : successDetails.map((s) {
            final itemsDesc = (s['items'] as List<Map<String, dynamic>>)
                .map((i) => i['type'] == 'meal'
                    ? i['title']
                    : i['gigDetails']?['gig_type'])
                .where((name) => name != null)
                .join(', ');
            return "Order ID ${s['orderId']}: $itemsDesc";
          }).join('\n');

    String failureContent = failureDetails.isEmpty
        ? "No orders failed."
        : failureDetails.map((f) {
            final itemsDesc = (f['items'] as List<Map<String, dynamic>>)
                .map((i) => i['type'] == 'meal'
                    ? i['title']
                    : i['gigDetails']?['gig_type'])
                .where((name) => name != null)
                .join(', ');
            return "Failed Items ($itemsDesc): ${f['error']}";
          }).join('\n');

    await showDialog(
      context: context,
      barrierDismissible: false, // User must tap button
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Order Placement Summary'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                if (successDetails.isNotEmpty) ...[
                  Text('Successful Orders:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text(successContent),
                  SizedBox(height: 15),
                ],
                if (failureDetails.isNotEmpty) ...[
                  Text('Failed Orders:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  SizedBox(height: 5),
                  Text(failureContent),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog

                // Remove only successful items from cart
                if (successfulCartItems.isNotEmpty) {
                  print(
                      "DEBUG: Removing ${successfulCartItems.length} successful items from cart.");
                  cart.ShoppingCart.removeItems(successfulCartItems);
                }

                // Navigate - e.g., to first successful order or back to cart/menu
                if (successDetails.isNotEmpty && userId != null) {
                  final List<int> successfulIds = successDetails
                      .map((s) => int.tryParse(s['orderId']?.toString() ?? ''))
                      .where((id) => id != null)
                      .map((id) => id!)
                      .toList();

                  if (successfulIds.isNotEmpty) {
                    print(
                        "DEBUG: Navigating to OrderStatusScreen for order IDs $successfulIds");
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => OrderStatusScreen(
                                  userId: userId,
                                  orderIdList: successfulIds,
                                  orderId: successfulIds.first,
                                  //orderIds: [],
                                )));
                  } else {
                    print(
                        "DEBUG: Could not parse first successful order ID. Popping checkout screen.");
                    Navigator.of(context)
                        .pop(); // Pop checkout if ID parsing fails
                  }
                } else {
                  print(
                      "DEBUG: No successful orders or user ID missing. Popping checkout screen.");
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLocationLoading = true); // Use location loading flag
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _displaySnackBar('Location services are disabled. Please enable them.');
          setState(() => _isLocationLoading = false); // Use location loading flag
        }
        return;
      }

      // Check for location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Request permission if denied
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permission still denied after requesting
          if (mounted) {
            _displaySnackBar('Location permission denied. Cannot get location.');
            setState(() => _isLocationLoading = false); // Use location loading flag
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permission permanently denied
        if (mounted) {
          _displaySnackBar('Location permission permanently denied. Please enable from app settings.');
          setState(() => _isLocationLoading = false); // Use location loading flag
        }
        return;
      }

      // Permission granted, get the current position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Use geocoding API to get human-readable address
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
        // Fallback to just coordinates if geocoding fails
        setState(() {
          _location = "${position.latitude}, ${position.longitude}";
        });
        _displaySnackBar('Could not get detailed address, using coordinates.');
      }
    } catch (e) {
      if (mounted) {
        _displaySnackBar('Error getting location: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLocationLoading = false); // Use location loading flag
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(), // Add the drawer here
      appBar: AppBar(
        elevation: 4,
        title: const Text('Checkout'),
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
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                        _buildPriceRow('Total', calculateTotal(),
                            isTotal: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                            suffixIcon: _isLocationLoading // Use location loading flag
                                ? const SizedBox( // Use SizedBox to maintain layout space
                                    width: 24.0, // Match icon button width
                                    height: 24.0, // Match icon button height
                                    child: CircularProgressIndicator(strokeWidth: 2.0),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.location_on),
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
                const SizedBox(height: 8.0),
                ExpansionTile(
                  title: Text(
                    'Optional Information',
                    style: TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[800]),
                  ),
                  initiallyExpanded: _isOptionalInfoExpanded,
                  onExpansionChanged: (bool expanding) =>
                      setState(() => _isOptionalInfoExpanded = expanding),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          TextFormField(
                            decoration: const InputDecoration(
                                labelText: 'Full Name',
                                prefixIcon: Icon(Icons.person)),
                            onChanged: (value) => _fullName = value,
                          ),
                          const SizedBox(height: 16.0),
                          TextFormField(
                            decoration: const InputDecoration(
                                labelText: 'Special Instructions',
                                prefixIcon: Icon(Icons.notes)),
                            maxLines: 3,
                            onChanged: (value) => _specialInstructions = value,
                          ),
                          const SizedBox(height: 16.0),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Center(
                  child: AnimatedScale(
                    scale: _scaleFactor,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _placeOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 50, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Place Order'),
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
      style: TextStyle(
          fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.teal[800]),
    );
  }

  Widget _buildOrderSummary() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.cartItems.length,
      itemBuilder: (context, index) {
        final item = widget.cartItems[index];
        final itemType = item['type'] ?? 'meal';
        String title = '';
        double price = 0.0;
        int quantity = 1; // Default quantity for gigs

        if (itemType == 'gig') {
          final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
          title = gigDetails['gig_type'] ?? 'Custom Gig';
          price = (gigDetails['price'] as num?)?.toDouble() ?? 0.0;
          // Quantity is always 1 for a gig booking
        } else {
          // Meal item
          title = item['title'] ?? 'Unknown Item';
          price = (item['price'] as num?)?.toDouble() ?? 0.0;
          quantity = (item['quantity'] as int?) ?? 1;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$title ${itemType == 'meal' ? 'x$quantity' : ''}',
                  style: TextStyle(fontSize: 16.0, color: Colors.teal[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '\$${(price * quantity).toStringAsFixed(2)}',
                style: TextStyle(fontSize: 16.0, color: Colors.teal[700]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPriceRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18.0 : 16.0,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.teal[900] : Colors.teal[700],
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 18.0 : 16.0,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.teal[900] : Colors.teal[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      children: [
        RadioListTile<String>(
          title: const Text('Momo'),
          value: 'Momo',
          groupValue: _selectedPaymentMethod,
          onChanged: (value) {
            setState(() {
              _selectedPaymentMethod = value!;
            });
          },
          activeColor: Colors.teal[800],
        ),
        RadioListTile<String>(
          title: const Text('Card'),
          value: 'Card',
          groupValue: _selectedPaymentMethod,
          onChanged: (value) {
            setState(() {
              _selectedPaymentMethod = value!;
            });
          },
          activeColor: Colors.teal[800],
        ),
      ],
    );
  }

  double calculateSubtotal() {
    return widget.cartItems.fold(0.0, (sum, item) {
      final itemType = item['type'] ?? 'meal';
      if (itemType == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        return sum + ((gigDetails['price'] as num?)?.toDouble() ?? 0.0);
      } else {
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = (item['quantity'] as int?) ?? 1;
        return sum + (price * quantity);
      }
    });
  }

  double calculateShippingTax() {
    // Placeholder for shipping and tax calculation
    return calculateSubtotal() * 0.1; // Example: 10% of subtotal
  }

  double calculateTotal() {
    return calculateSubtotal() + calculateShippingTax();
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _placeOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal[800],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
          textStyle: const TextStyle(fontSize: 18),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Place Order'),
      ),
    );
  }
}
