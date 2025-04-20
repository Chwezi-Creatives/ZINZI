import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zinzi2/signup_or_login.dart'; // Assuming this is your login/signup choice page
import 'package:google_fonts/google_fonts.dart'; // For custom fonts
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/onboard.dart';
import 'package:zinzi2/chef_dash8888.dart';
import 'package:zinzi2/produ_dash22.dart';
import 'package:zinzi2/allmeals.dart';
import 'package:zinzi2/meal_detail.dart';

// --- Hardcoded Color Scheme (Shades of Teal and White/Off-White) ---
const Color kColorPrimaryDark = Color(0xFF004D40); // Darkest Teal
const Color kColorPrimary = Color(0xFF00796B); // Medium Teal
const Color kColorPrimaryLight = Color(0xFF4DB6AC); // Lighter Teal
const Color kColorPrimaryLightest = Color(0xFFE0F2F1); // Very Light Teal
const Color kColorBackground =
    Color(0xFFB2DFDB); // Updated teal background (lighter teal)
const Color kColorSurface = Colors.white; // White for elements on background
const Color kColorTextOnPrimary = Colors.white; // Text on dark teal buttons/bg
const Color kColorTextPrimary = kColorPrimaryDark; // Dark teal text on light bg
const Color kColorTextAccent = kColorPrimary; // Medium teal text for accents
const Color kColorTextSecondary =
    kColorPrimaryLight; // Light teal text for secondary elements
// --- End Color Scheme ---

class SplashScreen extends StatefulWidget {
  // Use const constructor
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation; // Changed to Fade Animation
  late Animation<Offset>
      _slideAnimation; // Added Slide Animation for Text/Button

  @override
  void initState() {
    super.initState();

    // Initialize the animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
          milliseconds: 1500), // Longer duration for fade + slide
    );

    // Define the fade animation for the background/logo
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        // Fade in during the first half of the animation
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    // Define the slide animation for text and button (from bottom up)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5), // Start slightly below center
      end: Offset.zero, // End at the center
    ).animate(
      CurvedAnimation(
        parent: _controller,
        // Slide in during the second half, after fade starts
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Start the animation
    _controller.forward();

    // Preload all meals cache and auto-navigate after loading
    _preloadAndNavigate();
  }

  // (Removed duplicate _preloadAndNavigate)

  @override
  void dispose() {
    _controller.dispose(); // Dispose the controller
    super.dispose();
  }

  // Custom method for navigation with slide transition (from right)
  void _navigateWithSlideTransition(BuildContext context, Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          final curve = Curves.easeInOutCubic;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  // Decide where to go after splash based on login state
  Future<void> _preloadAndNavigate() async {
    // Preload caches for meals, chefs, and producers (persistent)
    try {
      await AllMealsScreen.loadMealsCacheFromPrefs();
      // Load chef/producer caches using the public static methods
      await MealDetailScreen.loadChefsCacheFromUserCache();
      await MealDetailScreen.loadProducersCacheFromUserCache();
    } catch (e) {
      print("Error preloading cache in splash screen: $e");
      // Continue even if preloading fails
    }

    // Wait for animation to finish (at least 1.5s)
    await Future.delayed(const Duration(milliseconds: 3000));

    // Check login state
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final chefId = prefs.getString('chef_user_id');
    final producerId = prefs.getString('producer_id');

    Widget nextScreen;
    if (userId != null) {
      // User is logged in as a regular user
      nextScreen = LandingPage(); // Use LandingPage as the user dashboard/home
    } else if (chefId != null) {
      nextScreen = ChefDash88new(); // Replace with your chef dashboard
    } else if (producerId != null) {
      nextScreen = ProducerDash22(); // Replace with your producer dashboard
    } else {
      nextScreen = SignUpOrLoginPage();
    }

    if (mounted) {
      _navigateWithSlideTransition(context, nextScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar style for better appearance
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      // Or .light depending on your background
      statusBarColor: Colors.transparent, // Make status bar transparent
      statusBarIconBrightness:
          Brightness.dark, // Use dark icons on light background
    ));

    return Scaffold(
      backgroundColor: kColorBackground, // Updated teal background
      body: Stack(
        fit: StackFit.expand, // Make stack fill the screen
        children: [
          // Optional: Subtle background pattern or texture instead of image

          // Animated Content
          FadeTransition(
            opacity: _fadeAnimation, // Apply fade to logo
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Center vertically
              children: [
                // Logo
                const Spacer(flex: 2), // Push logo up slightly
                Container(
                  height: 146, // Slightly larger logo
                  width: 146,
                  padding: const EdgeInsets.all(8), // Padding around logo
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        Colors.transparent, // White background for logo circle
                    boxShadow: [
                      BoxShadow(
                        color: kColorPrimary.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    // Clip the image itself
                    child: Image.asset(
                      'assets/images/Logo (1).png',
                      fit: BoxFit.contain, // Contain to avoid distortion
                    ),
                  ),
                ),
                const Spacer(flex: 1), // Space between logo and text

                // Animated Text and Button (Slide + Fade)
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _controller.drive(CurveTween(
                        curve: const Interval(
                            0.5, 1.0))), // Fade text/button in later
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30.0),
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min, // Take minimum vertical space
                        children: [
                          Text(
                            "ZINZI",
                            style: GoogleFonts.poppins(
                              // Use Google Fonts
                              fontSize: 52, // Slightly reduced size
                              fontWeight: FontWeight.w800,
                              color: kColorPrimaryDark, // Dark Teal
                              letterSpacing: 3.0, // Adjust spacing
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            "Your Journey To A Healthier You!",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w500, // Medium weight
                              color: kColorPrimaryDark, // Secondary text color
                              letterSpacing: 0.5, // Reduced spacing
                            ),
                          ),
                          const SizedBox(
                              height: 50), // More space before button
                          // "Get Started" button
                          ElevatedButton(
                            onPressed: () {
                              _navigateWithSlideTransition(
                                  context, SignUpOrLoginPage());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  kColorPrimary, // Medium Teal button
                              foregroundColor:
                                  kColorTextOnPrimary, // White text
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 50,
                                  vertical: 16), // Adjusted padding
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    30), // Keep pill shape
                              ),
                              elevation: 3, // Subtle elevation
                              shadowColor: kColorPrimary.withOpacity(0.3),
                            ),
                            child: Text(
                              "Get Started",
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w600, // Semi-bold
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 2), // Space at the bottom
              ],
            ),
          ),
        ],
      ),
    );
  }
}
