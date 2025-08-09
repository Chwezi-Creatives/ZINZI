//cspell:disable
/*import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zinzi/dashboard_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class PaymentScreenpp extends StatefulWidget {
  @override
  _PaymentScreenppState createState() => _PaymentScreenppState();
}

class _PaymentScreenppState extends State<PaymentScreenpp> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;

  Future<void> _initiateAndPay() async {
    setState(() {
      _isLoading = true;
    });

    final amount = _amountController.text;
    if (amount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Please enter a valid amount."),
      ));
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Initiate payment request
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/pay'),
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
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  WebViewScreen(paymentUrl),
              transitionDuration: Duration(milliseconds: 500),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const begin = Offset(1.0, 0.0);
                const end = Offset.zero;
                const curve = Curves.easeInOut;

                final tween = Tween(begin: begin, end: end)
                    .chain(CurveTween(curve: curve));
                final offsetAnimation = animation.drive(tween);

                return SlideTransition(
                  position: offsetAnimation,
                  child: child,
                );
              },
            ),
          );
        } else {
          throw Exception("Invalid payment URL received.");
        }
      } else {
        throw Exception('Failed to create payment: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error initiating payment: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error initiating payment. Please try again."),
      ));
    } finally {
      setState(() {
        _isLoading = false;
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
          children: [
            TextField(
              controller: _amountController,
              decoration: InputDecoration(labelText: 'Enter amount'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _initiateAndPay,
                    child: Text("Proceed to PayPal"),
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
          '$apibaseurl/rr/execute?paymentId=$paymentId&PayerID=$payerId'));

      if (response.statusCode == 200) {
        // Display success dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Payment Successful'),
            content: Text('Your payment has been successfully processed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Okay'),
              ),
            ],
          ),
        ).then((_) {
          // Navigate back to dashboard with slide transition
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  dashboard(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const begin = Offset(1.0, 0.0);
                const end = Offset.zero;
                const curve = Curves.easeInOut;

                final tween = Tween(begin: begin, end: end)
                    .chain(CurveTween(curve: curve));
                final offsetAnimation = animation.drive(tween);

                return SlideTransition(
                  position: offsetAnimation,
                  child: child,
                );
              },
            ),
          );
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Payment execution failed."),
        ));
      }
    } catch (e) {
      debugPrint('Error executing payment: $e');
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
*/