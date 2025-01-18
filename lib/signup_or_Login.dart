import 'package:flutter/material.dart';
import 'package:zinzi2/login_page.dart';
import 'package:zinzi2/signup_page.dart';

class SignUpOrLoginPage extends StatefulWidget {
  @override
  _SignUpOrLoginPageState createState() => _SignUpOrLoginPageState();
}

class _SignUpOrLoginPageState extends State<SignUpOrLoginPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _welcomeSlideAnimation;
  late Animation<double> _welcomeTextFadeAnimation;
  late Animation<double> _signupButtonFadeAnimation;
  late Animation<double> _loginButtonFadeAnimation;

  //bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Mascot and Welcome Text slide from top
    _welcomeSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -1), // Start from the top
      end: Offset.zero, // End at the center
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    ));

    // Welcome Text fade-in
    _welcomeTextFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.5, curve: Curves.easeIn),
    );

    // Signup button fades in
    _signupButtonFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.75, curve: Curves.easeIn),
    );

    // Login button fades in
    _loginButtonFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateToPage(BuildContext context, Widget page) async {
    setState(() {
      //_isLoading = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Scale transition
          const begin = 0.0;
          const end = 1.0;
          final curve = Curves.easeInOut;

          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var scaleAnimation = animation.drive(tween);

          return ScaleTransition(scale: scaleAnimation, child: child);
        },
      ),
    );

    setState(() {
      //_isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sign Up or Log In',
          style: TextStyle(color: Colors.black),
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
          // Main content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Mascot and Welcome text slide in from top
                    SlideTransition(
                      position: _welcomeSlideAnimation,
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/Gru green.png',
                            height: 170,
                            width: 170,
                          ),
                          const SizedBox(height: 01),
                          // Welcome Text fades in
                          FadeTransition(
                            opacity: _welcomeTextFadeAnimation,
                            child: Card(
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
                                      "Welcome to ZINZI !",
                                      style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade800,
                                        letterSpacing: 1.0,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Choose an option to continue.",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black.withOpacity(0.8),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 95),
                    // Signup button fades in
                    FadeTransition(
                      opacity: _signupButtonFadeAnimation,
                      child: GestureDetector(
                        onTap: () => _navigateToPage(context, SignUpPage()),
                        child: _buildButton("Sign Up", Colors.teal),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "or",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    // Login button fades in
                    FadeTransition(
                      opacity: _loginButtonFadeAnimation,
                      child: GestureDetector(
                        onTap: () => _navigateToPage(context, LoginPage()),
                        child: _buildButton("Log In", Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
