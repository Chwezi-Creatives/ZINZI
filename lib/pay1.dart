import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentScreen extends StatefulWidget {
  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final TextEditingController _amountController = TextEditingController();
  String _paymentUrl = "";

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initiatePayment() async {
    final amount = _amountController.text;
    if (amount.isEmpty) return;

    final response = await http.post(
      Uri.parse('http://localhost:5000/rr/pay'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      setState(() {
        _paymentUrl = responseBody['approval_url'];
      });
    } else {
      print('Failed to create payment: ${response.body}');
    }
  }

  void _pay() {
    if (_paymentUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WebViewPage(url: _paymentUrl),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PayPal Payment")),
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
              onPressed: _initiatePayment,
              child: Text("Initiate Payment"),
            ),
            SizedBox(height: 20),
            if (_paymentUrl.isNotEmpty)
              ElevatedButton(
                onPressed: _pay,
                child: Text("Proceed to PayPal"),
              ),
          ],
        ),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  final String url;

  const WebViewPage({Key? key, required this.url}) : super(key: key);

  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  //late WebViewController _webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("PayPal Payment Approval")),
      body: WebView(
        initialUrl: widget.url,
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (WebViewController webViewController) {
          //_webViewController = webViewController;
        },
        navigationDelegate: (NavigationRequest request) {
          if (request.url.contains('execute')) {
            print('Payment approved');
            // Here you would capture paymentId and PayerID and execute payment
            // Call /execute endpoint with the required parameters
          }
          return NavigationDecision.navigate;
        },
      ),
    );
  }
}
