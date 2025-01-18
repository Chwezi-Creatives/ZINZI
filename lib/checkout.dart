import 'package:flutter/material.dart';
import 'dart:async';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems; // Receiver for cart items

  // Constructor to receive cart items
  CheckoutScreen({required this.cartItems});

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late double _scaleFactor;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _scaleFactor = 1.0;
    _startAnimation();
  }

  @override
  void dispose() {
    _timer.cancel(); // Clean up the timer when the screen is disposed
    super.dispose();
  }

  void _startAnimation() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        // Alternate the scale factor between 1.0 and 1.2 to create the "pulsing" effect
        _scaleFactor = _scaleFactor == 1.0 ? 0.8 : 1.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 3.0,
        title: Text('Checkout'),
        backgroundColor: Colors.teal[400], // Set AppBar color to teal
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Order Summary Card
              Card(
                //elevation: 2.0,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle('Order Summary'),
                      SizedBox(height: 8.0),
                      _buildPriceRow('Subtotal', calculateSubtotal()),
                      _buildPriceRow('Shipping/Tax', calculateShippingTax()),
                      Divider(),
                      _buildPriceRow('Total', calculateTotal(), isTotal: true),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24.0),

              // Payment Method Card
              Card(
                //elevation: 2.0,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle('Payment Method'),
                      SizedBox(height: 16.0),
                      _buildPaymentMethods(),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24.0),

              // Billing Information Card
              Card(
                //elevation: 2.0,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle('Billing Information'),
                      SizedBox(height: 16.0),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors
                                  .grey), // Outer border around the fields
                          borderRadius: BorderRadius.circular(
                              8.0), // Optional rounded corners
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(
                              8.0), // Padding inside the container
                          child: Column(
                            children: <Widget>[
                              _buildTextField('Full Name'),
                              Divider(), // Divider between input fields
                              _buildTextField('Email Address'),
                              Divider(), // Divider between input fields
                              _buildTextField('Special Instructions',
                                  maxLines: 3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24.0),

              // Animated Place Order button
              Center(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  transform: Matrix4.identity()..scale(_scaleFactor),
                  child: ElevatedButton(
                    onPressed: () {
                      // Handle "Place Order" button press
                    },
                    child: Text(
                      'Comfirm Order Now!',
                      style: TextStyle(color: Colors.white), // White text
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[400], // teal[400] background
                      padding: EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 24.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build a section title
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // Build a price row
  Widget _buildPriceRow(String title, double value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(title),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: isTotal ? TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      ],
    );
  }

  // Build horizontal payment methods
  Widget _buildPaymentMethods() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _buildPaymentMethodButton('Paypal', 'assets/images/paypal.png'),
          SizedBox(width: 8.0),
          _buildPaymentMethodButton('Stripe', 'assets/images/stripe.png'),
          SizedBox(width: 8.0),
          _buildPaymentMethodButton('Momo', 'assets/images/momo.png'),
          SizedBox(width: 8.0),
          _buildPaymentMethodButton('Google Pay', Icons.account_balance_wallet),
        ],
      ),
    );
  }

  // Build a text input field without border
  Widget _buildTextField(String label, {int maxLines = 1}) {
    return TextField(
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: InputBorder.none, // Remove the individual borders
      ),
    );
  }

  // Calculate subtotal
  double calculateSubtotal() {
    return widget.cartItems.fold(0, (sum, item) => sum + item['price']);
  }

  // Simulating shipping/tax calculation
  double calculateShippingTax() {
    return 5.0; // Fixed shipping/tax amount for simplicity
  }

  // Calculate total
  double calculateTotal() {
    return calculateSubtotal() + calculateShippingTax();
  }

  Widget _buildPaymentMethodButton(String title, dynamic icon) {
    return ElevatedButton(
      onPressed: () {
        // Handle payment method selection
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          icon is String
              ? Image.asset(
                  icon, // Using custom icon from assets
                  height: 24.0,
                  width: 24.0,
                )
              : Icon(icon), // For Google Pay or other icons
          SizedBox(width: 8.0),
          Text(title),
        ],
      ),
    );
  }
}
