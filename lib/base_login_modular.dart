//cspell:disable
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zinzi/screens/password_recovery_screen.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'];

class LoginPageModular extends StatefulWidget {
  final String apiUrl;
  final String pageTitle;
  final String buttonText;
  final String idKey;
  final String expectedUserType;
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
  bool _isLoading = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/${widget.apiUrl}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': _identifier,
          'password': _password,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        var responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic> && responseData.containsKey('data')) {
          final data = responseData['data'] as Map<String, dynamic>;
          final String userId = data[widget.idKey].toString(); // Extract user ID and convert to String
          final String userType = widget.expectedUserType; // Use expected user type
          final bool verified = data['verified'] as bool? ?? false; // Extract verified status, default to false if null
          final String? phone = data['phone'] as String?; // Extract phone number if available

          // Pass extracted data to the success callback
          if (mounted) {
            widget.onLoginSuccess({
              'userId': userId,
              'userType': userType,
              'verified': verified,
              'phone': phone, // Include phone number in the response
            });
          }
        } else {
          _showError('Invalid data structure in response.');
        }
      } else {
        _showError('Login failed. wrong password or name.');
      }
    } catch (e) {
      _showError('An error occurred. Please try again later.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: SlideTransition(
              position: _slideAnimation,
              child: Text(widget.pageTitle,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 24)),
            ),
            foregroundColor: Colors.white,
            backgroundColor: Colors.teal.shade700,
            elevation: 1,
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color.fromARGB(255, 203, 243, 248),Color(0xFFe0f7fa)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/acc.png',
                              height: 130,
                              width: 130,
                            ),
                            const SizedBox(height: 20),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: Column(
                                    children: [
                                      Text('WELCOME BACK,',
                                          style: GoogleFonts.poppins(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal.shade900,
                                            letterSpacing: 1.2,
                                          )),
                                      const SizedBox(height: 6),
                                      Text('Let\'s continue your health journey!',
                                          style: GoogleFonts.poppins(
                                              color: Colors.teal.shade800,
                                              fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 60),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              decoration: _inputDecoration(
                                  label: 'Email or Username',
                                  icon: Icons.person),
                              onChanged: (value) => _identifier = value,
                              validator: (value) => value!.isEmpty
                                  ? 'Please enter your email or username'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              obscureText: true,
                              decoration: _inputDecoration(
                                  label: 'Password', icon: Icons.lock),
                              onChanged: (value) => _password = value,
                              validator: (value) => value!.isEmpty
                                  ? 'Please enter your password'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Opacity(
                              opacity: 1.0, // Make the Forgot Password link visible
                              child: TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PasswordRecoveryScreen(
                                        userType: widget.expectedUserType,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: Colors.teal[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            AnimatedContainer(
                              duration: const Duration(seconds: 2),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                boxShadow: _isLoading
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.tealAccent
                                              .withOpacity(0.6),
                                          blurRadius: 15,
                                          spreadRadius: 1,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
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
                                  backgroundColor: Colors.teal,
                                  minimumSize: const Size(double.infinity, 60),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(widget.buttonText,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Colors.white,
                                    )),
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
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
      ],
    );
  }

  InputDecoration _inputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: Colors.teal),
      filled: true,
      fillColor: Colors.white.withOpacity(0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      prefixIcon: Icon(icon, color: Colors.teal),
    );
  }
}
