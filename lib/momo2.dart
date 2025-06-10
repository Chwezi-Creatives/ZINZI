//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class Momo2screen extends StatefulWidget {
  const Momo2screen({Key? key}) : super(key: key);

  @override
  _Momo2screenState createState() => _Momo2screenState();
}

class _Momo2screenState extends State<Momo2screen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _phoneNumberController =
      TextEditingController(); // Controller for phone number
  String _transactionId = ''; // Variable to hold the transaction ID

  Future<void> _makePayment() async {
    if (_formKey.currentState?.validate() ?? false) {
      final amount = _amountController.text;
      final phoneNumber = _phoneNumberController.text;

      // Debug: Check the values before sending the request
      print("Making payment with amount: $amount, phoneNumber: $phoneNumber");

      // Assuming your Flask API endpoint is '/rr/request_momo_payment'
      final url = Uri.parse('$apibaseurl/rr/request_momo_payment');

      final headers = {
        "Content-Type": "application/json",
        // Add any other required headers like authorization or session tokens
      };

      final body = jsonEncode({
        'amount':
            int.parse(amount) , // Convert to minor units (e.g., cents)
        'currency': '', // Currency can be set as needed
        'externalId': '', // External reference ID
        'payerMessage': '',
        'payeeMessage': '',
        'phoneNumber': phoneNumber, // Add phone number to the body
      });

      try {
        final response = await http.post(url, headers: headers, body: body);

        // Debug: Log the response status and body
        print("Response status: ${response.statusCode}");
        print("Response body: ${response.body}");

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          setState(() {
            // Store the transaction ID from the response
            _transactionId = responseData['transaction_id'];
          });

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment request sent successfully!')),
          );
        } else {
          // Handle failure
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send payment request.')),
          );
        }
      } catch (e) {
        // Handle error
        print("Error: $e"); // Debug: Log the error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
      }
    }
  }

  Future<void> _checkTransactionStatus() async {
    if (_transactionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No transaction ID available. Please make a payment first.')),
      );
      return;
    }

    final url = Uri.parse('$apibaseurl/rr/check_momo_payment_status');

    final headers = {
      "Content-Type": "application/json",
      // Add any other required headers like authorization or session tokens
    };

    final body = jsonEncode({
      'transaction_id': _transactionId,
    });

    try {
      final response = await http.post(url, headers: headers, body: body);

      // Debug: Log the response status and body for transaction status check
      print("Transaction status response status: ${response.statusCode}");
      print("Transaction status response body: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final status = responseData[
            'status']; // Assuming the status is returned in 'status' field
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaction Status: $status')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to retrieve transaction status')),
        );
      }
    } catch (e) {
      print("Error checking transaction status: $e"); // Debug: Log the error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoMo Payment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Amount Input Field
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Enter Amount',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Phone Number Input Field
              TextFormField(
                controller: _phoneNumberController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Enter Your Phone Number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Pay with MoMo Button
              ElevatedButton(
                onPressed: _makePayment,
                child: const Text('Pay with MoMo'),
              ),
              const SizedBox(height: 20),
              if (_transactionId.isNotEmpty)
                Text('Transaction ID: $_transactionId'),
              const SizedBox(height: 20),

              // Check Transaction Status Button
              ElevatedButton(
                onPressed: _checkTransactionStatus,
                child: const Text('Check Transaction Status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
