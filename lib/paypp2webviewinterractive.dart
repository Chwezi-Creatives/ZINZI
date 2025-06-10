//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentScreen222 extends StatefulWidget {
  @override
  _PaymentScreen222State createState() => _PaymentScreen222State();
}

class _PaymentScreen222State extends State<PaymentScreen222> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false; // For progress indication

  Future<void> _initiateAndPay() async {
    final amount = _amountController.text.trim();
    if (amount.isEmpty ||
        double.tryParse(amount) == null ||
        double.parse(amount) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Please enter a valid amount."),
      ));
      return;
    }

    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      final response = await http.post(
        Uri.parse('https://24.ip.gl.ply.gg:18851/rr/pay'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': amount}),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final paymentUrl = responseBody['approval_url'];

        if (paymentUrl != null && paymentUrl.isNotEmpty) {
          // Navigate to WebView for payment
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => WebViewScreen(paymentUrl)),
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
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PayPal Payment")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Secure Payment",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              "Enter the amount you'd like to pay:",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: "Payment Amount",
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
                errorText: _amountController.text.isNotEmpty &&
                        (double.tryParse(_amountController.text) == null ||
                            double.parse(_amountController.text) <= 0)
                    ? "Enter a valid amount"
                    : null,
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            _isLoading
                ? Center(
                    child: CircularProgressIndicator()) // Progress indicator
                : ElevatedButton(
                    onPressed: _initiateAndPay,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text("Proceed to PayPal"),
                  ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, color: Colors.green),
                SizedBox(width: 5),
                Text(
                  "Secure Payment via PayPal",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  final String url;

  WebViewScreen(this.url);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
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
            if (request.url.contains("paymentId") &&
                request.url.contains("PayerID")) {
              final uri = Uri.parse(request.url);
              final paymentId = uri.queryParameters['paymentId'];
              final payerId = uri.queryParameters['PayerID'];

              executePayment(paymentId!, payerId!);
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

  Future<void> executePayment(String paymentId, String payerId) async {
    try {
      final response = await http.get(Uri.parse(
          'https://24.ip.gl.ply.gg:18851/rr/execute?paymentId=$paymentId&PayerID=$payerId'));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Payment successful!"),
        ));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Payment execution failed."),
        ));
      }
    } catch (e) {
      print('Error executing payment: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error completing payment. Please try again."),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PayPal Payment")),
      body: WebViewWidget(
        controller: _webViewController,
      ),
    );
  }
}
