import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class PaymentScreennowebview extends StatefulWidget {
  @override
  _PaymentScreennowebviewState createState() => _PaymentScreennowebviewState();
}

class _PaymentScreennowebviewState extends State<PaymentScreennowebview> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;

  Future<void> initiatePayment() async {
    final String amount = _amountController.text.trim();

    if (amount.isEmpty) {
      showError('Please enter the amount.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/create_stripe_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': double.parse(amount)}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['status'] == 'success') {
          final clientSecret = responseData['client_secret'];
          showSuccess('Payment initiated successfully.');
        } else {
          showError(responseData['error'] ?? 'Payment initiation failed.');
        }
      } else {
        showError('Error: ${response.body}');
      }
    } catch (e) {
      showError('Something went wrong: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Okay'),
          ),
        ],
      ),
    );
  }

  void showSuccess(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Okay'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stripe Payment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (USD)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 24),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: initiatePayment,
                    child: Text('Pay Now'),
                  ),
          ],
        ),
      ),
    );
  }
}
