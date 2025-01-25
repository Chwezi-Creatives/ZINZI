import 'package:flutter/material.dart';
import 'dart:async';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;

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
    _timer.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _scaleFactor = _scaleFactor == 1.0 ? 0.8 : 1.0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 4,
        title: Text('Checkout'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
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
        padding: EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Order Summary Card
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 1,
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle('Choose a payment method'),
                      SizedBox(height: 16.0),
                      _buildPaymentMethods(),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24.0),

              // Billing Information Card
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 1,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle('Billing Information'),
                      SizedBox(height: 16.0),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Column(
                            children: <Widget>[
                              _buildTextField('Full Name'),
                              Divider(),
                              _buildTextField('Email Address'),
                              Divider(),
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
                      'Confirm Order Now!',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[800],
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
          fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.teal[800]),
    );
  }

  Widget _buildPriceRow(String title, double value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(title, style: TextStyle(color: Colors.black)),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: isTotal
              ? TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800])
              : null,
        ),
      ],
    );
  }

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

  Widget _buildTextField(String label, {int maxLines = 1}) {
    return TextField(
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: InputBorder.none,
      ),
    );
  }

  double calculateSubtotal() {
    return widget.cartItems.fold(0, (sum, item) => sum + item['price']);
  }

  double calculateShippingTax() {
    return 0.5;
  }

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
                  icon,
                  height: 24.0,
                  width: 24.0,
                )
              : Icon(icon),
          SizedBox(width: 4.0),
          Text(title),
        ],
      ),
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal[100], foregroundColor: Colors.black),
    );
  }
}
