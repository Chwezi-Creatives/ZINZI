import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/onboard.dart';
import 'dashboard_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'Profile.dart';
import 'notifications/fcm_service.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
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
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -1), end: const Offset(0, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

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
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/login_user'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': _identifier,
          'password': _password,
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        if (data.containsKey('user_id')) {
          int userId = data['user_id'];
          final String? phoneNumber = data['phone'] as String?;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', userId);
          await prefs.setString('user_type', data['user_type'] ?? '');
          await prefs.setString('user_email', data['email'] ?? '');
          await prefs.setBool('is_logged_in', true);
          
          // Save phone number if available in the response
          if (phoneNumber != null && phoneNumber.isNotEmpty) {
            await prefs.setString('user_phone', phoneNumber);
          }
          
          // Register FCM token with user info (async, do not await)
          FCMService.registerTokenWithUserInfo();

          // Navigate to the dashboard with a custom transition
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  LandingPage(),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                const curve = Curves.easeInOut;
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
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No user_id found in response.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('wrong password or username.')),
        );
      }
    } catch (error) {
      print('Login error: $error');
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
          child: const Text(
            'Login',
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Semi-transparent overlay
          Positioned.fill(
            child: Container(
              color: Colors.teal.withOpacity(0.2),
            ),
          ),
          // Animated form content
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Wrap both mascot and welcome text inside SlideTransition
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 170,
                              width: 170,
                              child: Image.asset('assets/images/acc.png'),
                            ),
                            const SizedBox(height: 1),
                            // Welcome text
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
                                    'Lets continue your health journey!',
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
                      const SizedBox(
                          height:
                              70), // Space between the intro text and the form

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Identifier Field
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
                            // Password Field
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
                            // Login Button
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: _controller,
                                curve: Curves.easeOut,
                              ),
                              child: ElevatedButton(
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
                                    : const Text(
                                        'LOG IN',
                                        style: TextStyle(
                                            fontSize: 16, color: Colors.white),
                                      ),
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
