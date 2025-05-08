import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_metrics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url'; // Ensure API base URL is available

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  _EmailVerificationPageState createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _userId; // Initialize userId as nullable string
  bool _isUserIdLoaded = false; // Track whether the user ID has been loaded

  @override
  void initState() {
    super.initState();
    _loadUserId(); // Load user ID on initialization
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to get user_id as string first, fall back to int for backward compatibility
    final loadedUserId = prefs.getString('user_id') ?? 
                       prefs.getInt('user_id')?.toString();

    setState(() {
      _userId = loadedUserId; // Set the loaded user ID
      _isUserIdLoaded = true; // Mark that the user ID has been loaded
    });
  }

  Future<void> _verifyEmail() async {
    // Ensure both userId and form state are valid before proceeding
    if (!_isUserIdLoaded ||
        _userId == null ||
        !_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please make sure you have entered the code and the user ID is available.'),
      ));
      return;
    }

    setState(() {
      _isLoading = true; // Set loading state
    });

    try {
      // Convert user ID to int for the API if needed
      final userIdInt = int.tryParse(_userId ?? '');
      
      if (userIdInt == null) {
        throw Exception('Invalid user ID format');
      }

      final response = await http.post(
        Uri.parse('$apibaseurl/rr/verify_user'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userIdInt,
          'verification_code': _codeController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserMetricsPage()),
        );
      } else {
        final responseData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(responseData['message'] ?? 'Verification failed'),
        ));
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An error occurred. Please try again later.'),
      ));
    } finally {
      setState(() {
        _isLoading = false; // Reset loading state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Display loading dialog until user ID is loaded
    if (!_isUserIdLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Email Verification'),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Verification'),
        backgroundColor: Colors.teal,
      ),
      body: Stack(
        children: [
          // Background image within a container
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/soft.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Overlaying content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Verification image
                  Container(
                    height: 100,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/verification.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                  const Text(
                    'Enter your verification code:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: 'Verification Code',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyEmail,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 32),
                      backgroundColor: Colors.teal,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('VERIFY',
                            style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Didn't receive a code? Check your email or request a new one.",
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
