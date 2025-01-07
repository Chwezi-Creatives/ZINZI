//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:zinzi2/dashboard_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class PaymentScreenstrp extends StatefulWidget {
  @override
  _PaymentScreenstrpState createState() => _PaymentScreenstrpState();
}

class _PaymentScreenstrpState extends State<PaymentScreenstrp> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Stripe.publishableKey =
        "pk_test_51QdZkrP0TRsYJeZc8aXUZ6J6fMhORZJoleJLSunhzlmkhR7f2XJhqnc9PfPuF0d08WaDp9gKxDL0dGSFNHWFycjT00VFBOgTTd";
  }

  Future<void> createPaymentIntent() async {
    if (_amountController.text.isEmpty) {
      _showError('Please enter a valid amount.');
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Create PaymentIntent on your backend
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/create_stripe_payment'),
        headers: {'Content-Type': 'application/json'},
        body:
            jsonEncode({'amount': double.parse(_amountController.text) * 100}),
      );

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        if (jsonResponse['status'] == 'success') {
          // Call method to display payment sheet now
          await _showPaymentSheet(jsonResponse['client_secret']);
        } else {
          _showError(jsonResponse['error']);
        }
      } else {
        _showError('Failed to create payment intent. Please try again.');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showPaymentSheet(String clientSecret) async {
    try {
      // Show the payment sheet to collect payment information
      await Stripe.instance.presentPaymentSheet();

      // Payment was successful
      _showSuccess('Payment successful! Redirecting...');
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              DashboardPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            final tween =
                Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            final offsetAnimation = animation.drive(tween);

            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          },
        ),
      );
    } catch (e) {
      _showError('Error during payment processing: ${e.toString()}');
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSuccess(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Success'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Screen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _amountController,
              decoration: InputDecoration(labelText: 'Amount (in USD)'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : createPaymentIntent,
              child: Text(_isLoading ? 'Processing...' : 'Pay with Stripe'),
            ),
          ],
        ),
      ),
    );
  }
}
