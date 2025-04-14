import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'];

class LoginPageModular extends StatefulWidget {
  final String apiUrl;
  final String pageTitle;
  final String buttonText;
  final String idKey; // Key for the unique ID in the API response
  final String expectedUserType; // Expected user type for this role
  final Widget Function(Map<String, dynamic> response) onLoginSuccess;

  const LoginPageModular({
    Key? key,
    required this.apiUrl,
    required this.pageTitle,
    required this.buttonText,
    required this.idKey,
    required this.expectedUserType,
    required this.onLoginSuccess,
  }) : super(key: key);

  @override
  _LoginPageModularState createState() => _LoginPageModularState();
}

class _LoginPageModularState extends State<LoginPageModular>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _identifier = '';
  String _password = '';
  bool _isLoading = false; // Flag to control loading indicator

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Reduced duration for faster animations
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut, // Smoother curve
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5), // Start slightly above the center
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut, // Smoother curve
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true; // Show loading indicator when login starts
    });

    try {
      print('Attempting login with identifier: $_identifier'); // Debugging output
      final response = await http.post(
        Uri.parse('$apibaseurl/${widget.apiUrl}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': _identifier,
          'password': _password,
        }),
      );

      print('Response status: ${response.statusCode}'); // Log response status code
      print('Response body: ${response.body}'); // Log the response body

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        print('Decoded response data: $data'); // Log decoded response data

        // Check for valid data structure in the response
        if (data.containsKey('data') && data['data'] is Map<String, dynamic>) {
          var userData = data['data'];

          // Check if the response contains the expected ID key and user type (case-insensitive)
          if (userData.containsKey(widget.idKey) &&
              userData['user_type'].toLowerCase() == widget.expectedUserType.toLowerCase()) {
            int userId = userData[widget.idKey];
            String userType = userData['user_type'];

            print('User ID: $userId'); // Log user ID
            print('User Type: $userType'); // Log user type

            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('user_id', userId); // Store user ID
            await prefs.setString('user_type', userType); // Store user type

            // Navigate to the appropriate page with the response data
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    widget.onLoginSuccess(data), // Pass the complete response
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  const curve = Curves.easeOut; // Smoother curve
                  final tween = Tween<Offset>(
                    begin: const Offset(1.0, 0.0), // Start from the right
                    end: Offset.zero,
                  ).chain(CurveTween(curve: curve));

                  final opacityTween = Tween<double>(begin: 0.0, end: 1.0)
                      .chain(CurveTween(curve: curve));

                  return FadeTransition(
                    opacity: animation.drive(opacityTween),
                    child: SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    ),
                  );
                },
                transitionDuration: const Duration(milliseconds: 500), // Faster transition
              ),
            );
          } else {
            print('No valid user data found in response: $data'); // Debug statement for invalid data
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No valid user data found in response.')),
            );
          }
        } else {
          print('Invalid data structure in response: $data'); // Debug statement for invalid data
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid data structure in response.')),
          );
        }
      } else {
        print('Login failed with status code: ${response.statusCode}'); // Log the error status code
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Invalid credentials.')),
        );
      }
    } catch (error) {
      print('Login error: $error'); // Log any errors that occurred during the request
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('An error occurred. Please try again later.')),
      );
    } finally {
      setState(() {
        _isLoading = false; // Hide loading indicator after login attempt
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SlideTransition(
          position: _slideAnimation,
          child: Text(
            widget.pageTitle,
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.teal.withOpacity(0.2),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 170,
                              width: 170,
                              child: Image.asset('assets/images/Gru green.png'),
                            ),
                            const SizedBox(height: 1),
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'WELCOME BACK,',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Let\'s continue your health journey!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.teal.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 70),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Email or Username',
                                labelStyle: TextStyle(color: Colors.teal),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon:
                                    Icon(Icons.person, color: Colors.teal),
                              ),
                              onChanged: (value) => _identifier = value,
                              validator: (value) => value!.isEmpty
                                  ? 'Please enter your email or username'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: TextStyle(color: Colors.teal),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon:
                                    Icon(Icons.lock, color: Colors.teal),
                              ),
                              obscureText: true,
                              onChanged: (value) => _password = value,
                              validator: (value) => value!.isEmpty
                                  ? 'Please enter your password'
                                  : null,
                            ),
                            const SizedBox(height: 50),
                            ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      if (_formKey.currentState!.validate()) {
                                        _login();
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                backgroundColor: Colors.teal,
                                elevation: 3,
                                minimumSize: const Size(double.infinity, 60),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : Text(
                                      widget.buttonText,
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
