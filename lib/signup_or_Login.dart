import 'package:flutter/material.dart';
import 'Transporter_login.dart';
import 'transporter_signup.dart';
import 'package:zinzi2/chef_form_netwroked.dart';
import 'package:zinzi2/chef_login_modular.dart';
import 'package:zinzi2/chefsigup.dart';
import 'package:zinzi2/prodsignup.dart';
import 'package:zinzi2/producer_login_modular.dart';
import 'package:zinzi2/signup_page.dart';
import 'package:zinzi2/user_login_modular.dart';
import 'package:zinzi2/stakeholdersignup.dart';
import 'package:zinzi2/stk_login_modular.dart';

class SignUpOrLoginPage extends StatefulWidget {
  @override
  _SignUpOrLoginPageState createState() => _SignUpOrLoginPageState();
}

class _SignUpOrLoginPageState extends State<SignUpOrLoginPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  final List<String> roles = [
    "User",
    "Chef",
    "Producer",
    "Transporter / Rider",
    "Stakeholder"
  ];
  String? selectedRole;

  @override
  void initState() {
    super.initState();
    // Initialize the animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 1 second slide-in
    );
    // Define the slide animation (from top to center)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0), // Start from the top
      end: Offset.zero, // End at the center
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut, // Smooth slide-in curve
      ),
    );
    // Start the animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose the controller
    super.dispose();
  }

  void _navigateToPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0); // Slide from the right
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }

  void _handleLoginTap() {
    if (selectedRole == null) {
      selectedRole = 'User';
    }
    if (selectedRole == 'User') {
      _navigateToPage(context, UserLoginPageModular());
    } else if (selectedRole == 'Chef') {
      _navigateToPage(context, ChefLoginPageModular());
    } else if (selectedRole == 'Producer') {
      _navigateToPage(context, ProducerLoginPageModular());
    } else if (selectedRole == 'Transporter / Rider') {
      _navigateToPage(context, TransporterLoginPage());
    } else if (selectedRole == 'Stakeholder') {
      _navigateToPage(context, StakeholderLoginPageModular());
    }
  }

  void _handleSignUpTap() {
    if (selectedRole == null) {
      selectedRole = 'User';
    }
    if (selectedRole == 'User') {
      _navigateToPage(context, UserSignUpPage());
    } else if (selectedRole == 'Chef') {
      _navigateToPage(context, ChefDataFormNetwork());
    } else if (selectedRole == 'Producer') {
      _navigateToPage(context, ProducerSignUpPage());
    } else if (selectedRole == 'Transporter / Rider') {
      _navigateToPage(context, TransporterSignUpPage());
    } else if (selectedRole == 'Stakeholder') {
      _navigateToPage(context, StakeholderSignUpPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign up or Log in',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/soft.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.teal.withOpacity(0.2)),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Mascot Image
                          SizedBox(
                            width: 80, // Adjusted width for the mascot
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Image.asset(
                                'assets/images/Gru green.png',
                                height: 120, // Adjusted height for the mascot
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(
                              width: 16), // Spacing between mascot and card
                          // Content (Text and Dropdown)
                          Expanded(
                            child: Card(
                              margin: EdgeInsets.zero,
                              elevation: 1,
                              color: Colors.teal.shade100,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "WELCOME TO ZINZI !",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.teal[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.teal.shade100,
                                          width: 1.0,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: selectedRole,
                                          hint: const Text("SELECT YOUR ROLE"),
                                          items: roles.map((String role) {
                                            return DropdownMenuItem<String>(
                                              value: role,
                                              child: Text(
                                                role,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.teal.shade700,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (String? newValue) {
                                            setState(() {
                                              selectedRole = newValue;
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GestureDetector(
                      onTap: _handleLoginTap,
                      child: _buildButton("Log In", Colors.teal),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "or",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: GestureDetector(
                      onTap: _handleSignUpTap,
                      child: _buildButton("Sign Up", Colors.teal),
                    ),
                  ),
                ],
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
