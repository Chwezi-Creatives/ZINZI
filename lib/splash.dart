import 'package:flutter/material.dart';
import 'package:zinzi2/checkout.dart';
import 'package:zinzi2/reco.dart';
import 'signup_or_login.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoAnimation;
  late Animation<double>
      _logoSlideAnimation; // New slide animation for the logo
  late Animation<double> _textFadeAnimation;
  late Animation<double> _buttonFadeAnimation;
  late Animation<double> _buttonScaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _logoAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _logoSlideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );

    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.8, curve: Curves.easeInOut),
    );

    _buttonFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
    );

    _buttonScaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/soft.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Semi-transparent overlay
          Container(
            color: Colors.teal.withOpacity(0.2),
          ),
          // Centered content above overlay
          Center(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween, // Adjusts vertical spacing
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Centers content horizontally
              children: [
                // Logo animation (with slide effect from the bottom)
                Padding(
                  padding: const EdgeInsets.only(top: 90.0), // Adjusted padding
                  child: SlideTransition(
                    position:
                        Tween<Offset>(begin: Offset(0, 1), end: Offset(0, 0))
                            .animate(
                      CurvedAnimation(
                          parent: _controller, curve: Curves.easeOut),
                    ),
                    child: ScaleTransition(
                      scale: _logoAnimation,
                      child: Container(
                        height: 120,
                        width: 120,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: AssetImage('assets/images/picsay.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40), // Adjusted spacing after logo
                // Fade-in text (middle)
                FadeTransition(
                  opacity: _textFadeAnimation,
                  child: Column(
                    children: [
                      Text(
                        "Zinzi",
                        style: const TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.w800,
                          color: Colors.teal,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Your Journey To A Healthier You!",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                    height: 40), // Adjusted spacing before the button
                // "Get Started" button (bottommost)
                ScaleTransition(
                  scale: _buttonScaleAnimation,
                  child: FadeTransition(
                    opacity: _buttonFadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 50.0),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (context) => RecommendedMealsScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          "Get Started",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
