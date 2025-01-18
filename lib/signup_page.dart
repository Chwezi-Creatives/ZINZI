import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zinzi2/verification.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false; // Flag to control the loading state

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _buttonFadeAnimation;
  late Animation<double> _buttonScaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // Mascot fades in first
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    // Slide animation for form content (text, input fields, and buttons)
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Buttons fade in after text
    _buttonFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
    );

    // Scale animation for the CTA button
    _buttonScaleAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/signup_user'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final int userId = responseData['user_id'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', userId);

        Navigator.push(
          context,
          _createSlideFadeTransition(const EmailVerificationPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Signup failed. Try again!'),
        ));
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An error occurred. Please try again later.'),
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
      appBar: AppBar(
        title: Text(
          'Sign Up',
          style: const TextStyle(color: Colors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
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
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mascot fades in from top
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/Gru green.png',
                              height: 170,
                              width: 170,
                            ),
                            const SizedBox(height: 01),
                            Card(
                              elevation: 3,
                              color: Colors.white.withOpacity(0.8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Text(
                                      "Create an Account",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Join us to Personalize, track and Achieve your health goals and more !",
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.black.withOpacity(0.9),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 70),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Name Field
                            _buildTextField(
                              controller: _nameController,
                              label: "Name",
                              icon: Icons.person,
                              validator: (value) => value?.isEmpty ?? true
                                  ? "Enter your name"
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            // Email Field
                            _buildTextField(
                              controller: _emailController,
                              label: "Email",
                              icon: Icons.email,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return "Enter your email";
                                }
                                final emailRegex = RegExp(
                                    r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                                if (!emailRegex.hasMatch(value)) {
                                  return "Enter a valid email address";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            // Password Field
                            _buildTextField(
                              controller: _passwordController,
                              label: "Password",
                              icon: Icons.lock,
                              obscureText: true,
                              validator: (value) => value?.isEmpty ?? true
                                  ? "Enter your password"
                                  : null,
                            ),
                            const SizedBox(height: 70),
                            // Signup Button with fade and scale animation
                            FadeTransition(
                              opacity: _buttonFadeAnimation,
                              child: ScaleTransition(
                                scale: _buttonScaleAnimation,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _signUp,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    backgroundColor: Colors.teal,
                                  ),
                                  child: _isLoading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white)
                                      : const Text(
                                          "Sign Up",
                                          style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.white),
                                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.teal.shade700),
        filled: true,
        fillColor: Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        prefixIcon: Icon(icon, color: Colors.teal),
      ),
      obscureText: obscureText,
      style: const TextStyle(color: Colors.teal),
      validator: validator,
    );
  }

  // Slide and fade transition for page navigation
  PageRouteBuilder _createSlideFadeTransition(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);
        var fadeAnimation = animation.drive(CurveTween(curve: curve));

        return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(opacity: fadeAnimation, child: child));
      },
    );
  }
}
