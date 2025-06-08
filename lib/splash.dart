import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zinzi/onboard.dart';
import 'package:zinzi/signup_or_login.dart'; // Assuming this is your login/signup choice page
import 'package:google_fonts/google_fonts.dart'; // For custom fonts
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/nutri_detail.dart' as nutrition_details;
import 'package:zinzi/chef_net.dart';

import 'package:zinzi/chef_dash8888.dart';
import 'package:zinzi/produ_dash22.dart';
import 'package:zinzi/transooter_dash_before_mapbox.dart';
import 'package:zinzi/stakeholderdash222.dart';
import 'package:zinzi/allmeals.dart';
import 'package:zinzi/meal_detail.dart';
import 'package:zinzi/cache_config.dart'; // Import CacheConfig
import 'package:zinzi/user_cache.dart'; // Import UserCache
import 'package:zinzi/orderhistory.dart'; // Import OrderHistoryScreen for preloading
import 'package:zinzi/nutrition+.dart'; // Import NutritionPage for preloading
import 'package:zinzi/services/location_service.dart'; // Import LocationService

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
  const SplashScreen({super.key});

  @override
  @override
  _SplashScreenState createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isPreloading = false;
  late Widget _nextScreen; // Store the next screen for manual navigation

  @override
  void initState() {
    super.initState();

    // Initialize the animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Define the fade animation for the background/logo
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    // Define the slide animation for text and button (from bottom up)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Start the animation
    _controller.forward();

    // Start preloading and navigation logic
    _preloadAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
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
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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

  // Decide where to go after splash based on login state and preloading
  Future<void> _preloadAndNavigate() async {
    if (mounted) setState(() => _isPreloading = true);
    final prefs = await SharedPreferences.getInstance();

    // Efficiently fetch user_id (int or String)
    int? userId;
    final rawUserId = prefs.get('user_id');
    if (rawUserId is int) {
      userId = rawUserId;
    } else if (rawUserId is String) {
      userId = int.tryParse(rawUserId);
    }

    // Efficiently fetch user_type
    String? userType = prefs.getString('user_type');
    // Normalize userType for case and whitespace
    final normalizedUserType = userType?.trim().toLowerCase();

    // Debug log for splash extraction
    debugPrint('[SPLASH] rawUserId: '
        '[36m'
        '[1m'
        '[0m' + rawUserId.toString() +
        ', userType: ' + (userType ?? 'null') +
        ', normalizedUserType: ' + (normalizedUserType ?? 'null'));

    // Decide next screen based on login state and user type
    Widget nextScreen;
    if (userId != null && normalizedUserType != null && normalizedUserType.isNotEmpty) {
      switch (normalizedUserType) {
        case 'chef':
          nextScreen = ChefDash88new();
          break;
        case 'producer':
          nextScreen = ProducerDash22();
          break;
        case 'transporter':
          nextScreen = TransporterDashNew(transporterId: userId.toString());
          break;
        case 'stakeholder':
          nextScreen = stakeholderdas2222();
          break;
        case 'user':
          nextScreen = LandingPage();
          break;
        default:
          nextScreen = AllMealsScreen();
          break;
      }
    } else {
      nextScreen = SignUpOrLoginPage();
    }

      // Parallelized preload/caching logic for fastest splash
    final preloadFutures = <Future>[
      OrderHistoryScreen.preloadCacheForSplash(),
      ProducerDash22.preloadCacheForSplash(),
      // Preload meals data if cache is invalid
      AllMealsScreen.preloadMealsIfNeeded().then((refreshed) {
        if (refreshed) {
          debugPrint('[SPLASH] Successfully refreshed meals cache');
        } else {
          debugPrint('[SPLASH] Using existing meals cache');
        }
      }).catchError((e) {
        debugPrint('[SPLASH] Error preloading meals: $e');
      }),
      MealDetailScreen.loadChefsCacheFromUserCache(),
      MealDetailScreen.loadProducersCacheFromUserCache(),
      nutrition_details.Nutri_DetailPage.preloadProducersCacheForSplash(),
      ChooseChefNetwork.preloadCacheForSplash(),
      NutritionPage.preloadCachesForSplash().catchError((e) {
        debugPrint('[SPLASH] Error preloading Nutrition+ data: $e');
      }),
      // Add non-blocking location fetching
      LocationService.instance.fetchAndSetCurrentLocation().then((_) {
        debugPrint('[SPLASH] Initial location fetch attempt completed (non-blocking).');
        if (LocationService.instance.currentPosition != null) {
          debugPrint('[SPLASH] Location fetched: ${LocationService.instance.currentPosition}');
          if (LocationService.instance.currentAddress != null) {
            debugPrint('[SPLASH] Address fetched: ${LocationService.instance.currentAddress}');
          } else {
            debugPrint('[SPLASH] Address not fetched or geocoding failed for initial fetch.');
          }
        } else {
          debugPrint('[SPLASH] Initial location fetch failed or permission denied. Error: ${LocationService.instance.error}');
        }
      }).catchError((e) {
        debugPrint('[SPLASH] Error during initial location fetch: $e');
      }),
    ];
    
    // Add transporter-specific preloading if needed
    if (userType == 'transporter' && userId != null) {
      preloadFutures.add(TransporterDashNew.preloadCacheForSplash(userId.toString()));
    }
    await Future.wait(preloadFutures.map((f) => f.catchError((e) {
      debugPrint('Preload error: \$e');
    })));
    await Future.delayed(const Duration(milliseconds: 0));

    if (mounted) {
      setState(() {
        _isPreloading = false;
        _nextScreen = nextScreen; // Store the next screen for manual navigation
      });
      // Auto-navigation is disabled for banner testing
      // Uncomment the line below to restore auto-navigation
      // _navigateWithSlideTransition(context, nextScreen);
    }
    return;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: kColorBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Banner Image at the top
          Positioned(
            top: 0, // or 340, // or 170.0, // Added 170 pixels of space from the top
            left: 0,
            right: 0,
            child: Opacity(
            opacity: 0.08, //or 0.02, // or 1.0, // 100% opacity
            child: Image.asset(
              'assets/images/sp.jpg',
              fit: BoxFit.cover,
              height: MediaQuery.of(context).size.height * 1.0, //orMediaQuery.of(context).size.height * 0.2,  // or just plain pixels figure of 500, // Reduced height from 150px to 80px
              width: MediaQuery.of(context).size.width,
            ),
          ),
          ),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Container(
                  height: 146,
                  width: 146,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    boxShadow: [
                      BoxShadow(
                        color: kColorPrimary.withOpacity(0.15),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/Logo (1).png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const Spacer(flex: 1),
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _controller
                        .drive(CurveTween(curve: const Interval(0.5, 1.0))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "ZINZI",
                            style: GoogleFonts.poppins(
                              fontSize: 52,
                              fontWeight: FontWeight.w800,
                              color: kColorPrimaryDark,
                              letterSpacing: 3.0,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            "Your Journey To A Healthier You!",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: kColorPrimaryDark,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 50),
                          ElevatedButton(
                            onPressed: _isPreloading 
                                ? null 
                                : () => _navigateWithSlideTransition(context, _nextScreen),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kColorPrimary,
                              foregroundColor: kColorTextOnPrimary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 50, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 3,
                              shadowColor: kColorPrimary.withOpacity(0.3),
                            ),
                            child: Text(
                              _isPreloading ? "Loading..." : "Get Started",
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
          if (_isPreloading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                color: kColorPrimary,
                backgroundColor: kColorPrimary.withOpacity(0.2),
              ),
            ),
        ],
      ),
    );
  }
}
