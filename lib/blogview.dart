import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BlogScreen extends StatefulWidget {
  final String url;

  const BlogScreen({Key? key, required this.url}) : super(key: key);

  @override
  _BlogScreenState createState() => _BlogScreenState();
}

class _BlogScreenState extends State<BlogScreen> {
  late WebViewController _controller;
  bool _isLoading = true; // Add a loading indicator

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
            // Update loading indicator if needed
            setState(() {
              _isLoading = true; // Show loading while in progress
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true; // Show loading when page starts
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false; // Hide loading when page finishes
            });
          },
          onHttpError: (HttpResponseError error) {
            setState(() {
              _isLoading = false; // Hide loading on error
            });
            // Handle HTTP error event
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false; // Hide loading on error
            });
            // Handle web resource error event
          },
          onNavigationRequest: (NavigationRequest request) {
            // Optionally prevent navigation to certain URLs
            return NavigationDecision.navigate; // Allow navigation by default
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url)); // Load the URL
  }

  @override
  void didUpdateWidget(BlogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blog'),
        backgroundColor: Colors.teal[800],
      ),
      body: Stack( // Use a Stack to overlay the loading indicator
        children: [
          WebViewWidget(
            controller: _controller,
          ),
          _isLoading // Show loading indicator only when _isLoading is true
              ? const Center(child: CircularProgressIndicator())
              : const SizedBox.shrink(), // Empty widget when not loading
        ],
      ),
    );
  }
}
