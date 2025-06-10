//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class StripePaymentScreen extends StatefulWidget {
  @override
  _StripePaymentScreenState createState() => _StripePaymentScreenState();
}

class _StripePaymentScreenState extends State<StripePaymentScreen> {
  final TextEditingController _amountController = TextEditingController();

  Future<void> _initiateAndPay() async {
    final amount = _amountController.text;
    if (amount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Please enter a valid amount."),
      ));
      return;
    }

    try {
      // Initiate payment request
      final response = await http.post(
        Uri.parse('https://24.ip.gl.ply.gg:18851/rr/create_stripe_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount}),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final paymentUrl = responseBody['payment_url'];

        if (paymentUrl != null && paymentUrl.isNotEmpty) {
          // Navigate to WebView for payment
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => StripeWebViewScreen(paymentUrl)),
          );
        } else {
          throw Exception("Invalid payment URL received.");
        }
      } else {
        throw Exception('Failed to create payment: ${response.body}');
      }
    } catch (e) {
      print('Error initiating payment: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error initiating payment. Please try again."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Stripe Payment")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              decoration: InputDecoration(labelText: 'Enter amount'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initiateAndPay,
              child: Text("Proceed to Stripe"),
            ),
          ],
        ),
      ),
    );
  }
}

class StripeWebViewScreen extends StatefulWidget {
  final String url;

  StripeWebViewScreen(this.url);

  @override
  _StripeWebViewScreenState createState() => _StripeWebViewScreenState();
}

class _StripeWebViewScreenState extends State<StripeWebViewScreen> {
  late WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) =>
              debugPrint('WebView is loading (progress : $progress)'),
          onPageStarted: (url) => debugPrint('WebView onPageStarted: $url'),
          onPageFinished: (url) => debugPrint('WebView onPageFinished: $url'),
          onWebResourceError: (error) =>
              debugPrint('WebView onWebResourceError: $error'),
          onNavigationRequest: (request) {
            if (request.url.contains("success")) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Payment successful!"),
              ));
              Navigator.pop(context);
              return NavigationDecision.prevent;
            } else if (request.url.contains("cancel")) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Payment was cancelled."),
              ));
              Navigator.pop(context);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Stripe Payment")),
      body: WebViewWidget(
        controller: _webViewController,
      ),
    );
  }
}
