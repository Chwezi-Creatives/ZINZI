//cspell:disable
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WellnessCommunitiesScreen extends StatefulWidget {
  final String url;

  const WellnessCommunitiesScreen({Key? key, this.url = 'https://events.chwezicreatives.com'}) : super(key: key);

  @override
  _WellnessCommunitiesScreenState createState() => _WellnessCommunitiesScreenState();
}

class _WellnessCommunitiesScreenState extends State<WellnessCommunitiesScreen> {
  late WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onHttpError: (HttpResponseError error) {
            setState(() {
              _isLoading = false;
            });
            // Handle HTTP error event
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
            // Handle web resource error event
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow all navigation by default
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didUpdateWidget(WellnessCommunitiesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wellness Communities'),
        backgroundColor: Colors.teal[800],foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          WebViewWidget(
            controller: _controller,
          ),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : const SizedBox.shrink(),
        ],
      ),
    );
  }
}
