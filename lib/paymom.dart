//cspell:disable
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class MoMoPaymentPage extends StatefulWidget {
  @override
  _MoMoPaymentPageState createState() => _MoMoPaymentPageState();
}

class _MoMoPaymentPageState extends State<MoMoPaymentPage> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _payerNumberController = TextEditingController();
  String? _transactionRef;
  String? _paymentStatus;

  Future<void> _initiatePayment() async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        prefs.getString('user_id'); // Retrieve user_id from shared preferences

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User ID not found. Please log in again.')),
      );
      return;
    }

    final externalId = userId; // Use user_id as the external ID

    final response = await http.post(
      Uri.parse('$apibaseurl/rr/request_momo_payment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': _amountController.text,
        'currency': 'USD',
        'external_id': externalId,
        'payer_number': _payerNumberController.text,
        'payer_message': 'Payment for Zinzi Health Service',
        'payee_note': 'Thank you for your payment',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _transactionRef = data['transaction_ref'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment initiated successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initiate payment.')),
      );
    }
  }

  Future<void> _checkPaymentStatus() async {
    if (_transactionRef == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No transaction reference found.')),
      );
      return;
    }

    final response = await http.get(
      Uri.parse(
          '$apibaseurl/rr/check_momo_payment_status?transaction_ref=$_transactionRef'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _paymentStatus = data['payment_status'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment status retrieved successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retrieve payment status.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MoMo Payment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Amount'),
            ),
            TextField(
              controller: _payerNumberController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Payer Phone Number'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initiatePayment,
              child: Text('Initiate Payment'),
            ),
            ElevatedButton(
              onPressed: _checkPaymentStatus,
              child: Text('Check Payment Status'),
            ),
            if (_transactionRef != null)
              Text('Transaction Ref: $_transactionRef'),
            if (_paymentStatus != null) Text('Payment Status: $_paymentStatus'),
          ],
        ),
      ),
    );
  }
}
