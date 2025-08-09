//cspell:disable
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart'; // For custom fonts
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/onboard.dart';
import 'package:zinzi/signup_or_login.dart'; // Assuming this is your login/signup choice page
import 'package:zinzi/nutri_detail.dart' as nutrition_details;
import 'package:zinzi/chef_net.dart';
import 'package:zinzi/chef_dash8888.dart';
import 'package:zinzi/produ_dash22.dart';
import 'package:zinzi/transooter_dash_before_mapbox.dart';
import 'package:zinzi/stakeholderdash222.dart';
import 'package:zinzi/allmeals.dart';
import 'package:zinzi/features/payment/payment_plan_gate.dart';
import 'package:zinzi/meal_detail.dart';
import 'package:zinzi/orderhistory.dart'; // For preloading
import 'package:zinzi/nutrition+.dart'; // For preloading
import 'package:zinzi/services/location_service.dart'; // For location services

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
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isPreloading = false;
  late Widget _nextScreen; // Store the next screen for manual navigation
  bool _showBanner = false;
  bool _isTransitioning = false; // To prevent multiple transitions

  @override
  void initState() {
    super.initState();

    _nextScreen = SignUpOrLoginPage(); // Default fallback screen

    // Pre-cache the banner image
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/grodd2.jpg'), context);
    });

    // Initialize the main animation controller
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Define the fade animation for the background/logo
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuad,
      ),
    );

    // Define the slide animation for text and button (from bottom up)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start the main animation with a small delay to ensure frame is ready
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _controller.forward().then((_) {
          if (mounted) {
            setState(() {
              _showBanner = true;
            });
            // Start preload after banner is fully visible
            _preloadAndNavigate();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Custom method for navigation with scale and fade transition
  Future<void> _navigateWithScaleTransition(BuildContext context, Widget page) async {
    if (_isTransitioning || !mounted) return;
    _isTransitioning = true;

    await _controller.animateTo(1.0, duration: const Duration(milliseconds: 100));

    if (!mounted) {
      _isTransitioning = false;
      return;
    }

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutQuad,
              ),
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutQuad,
                ),
              ),
              child: child,
            ),
          );
        },
      ),
    );

    _isTransitioning = false;
  }

  // Decide where to go after splash based on login state and preloading
  Future<void> _preloadAndNavigate() async {
    if (mounted) setState(() => _isPreloading = true);
    final prefs = await SharedPreferences.getInstance();

    int? userId;
    final rawUserId = prefs.get('user_id');
    if (rawUserId is int) {
      userId = rawUserId;
    } else if (rawUserId is String) {
      userId = int.tryParse(rawUserId);
    }

    String? userType = prefs.getString('user_type');
    final normalizedUserType = userType?.trim().toLowerCase();

    debugPrint('[SPLASH] rawUserId: $rawUserId, userType: ${userType ?? 'null'}, normalizedUserType: ${normalizedUserType ?? 'null'}');

    Widget determinedNextScreen;
    if (userId != null && normalizedUserType != null && normalizedUserType.isNotEmpty) {
      switch (normalizedUserType) {
        case 'chef':
          determinedNextScreen = ChefDash88new();
          break;
        case 'producer':
          determinedNextScreen = ProducerDash22();
          break;
        case 'transporter':
          determinedNextScreen = TransporterDashNew(transporterId: userId.toString());
          break;
        case 'stakeholder':
          determinedNextScreen = stakeholderdas2222();
          break;
        case 'user':
          // Use createRoute for consistent transition
          Navigator.of(context).pushReplacement(LandingPage.createRoute());
          return; // Return early since we're handling navigation here
          break;
        default:
          // Wrap AllMealsScreen with PaymentPlanGate
          determinedNextScreen = PaymentPlanGate(
            child: AllMealsScreen(),
            requirePlan: true,
            onPlanVerified: () {
              // This will be called after successful plan verification
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => AllMealsScreen()),
                );
              }
            },
          );
          break;
      }
    } else {
      determinedNextScreen = SignUpOrLoginPage();
    }

    // **** START FIX: Provide null for location-aware cache methods ****
    // Parallelized preload/caching logic for fastest splash
    final preloadFutures = <Future>[
      OrderHistoryScreen.preloadCacheForSplash(),
      ProducerDash22.preloadCacheForSplash(),
      AllMealsScreen.preloadMealsIfNeeded().then((refreshed) {
        if (refreshed) {
          debugPrint('[SPLASH] Successfully refreshed meals cache');
        } else {
          debugPrint('[SPLASH] Using existing meals cache');
        }
      }).catchError((e) {
        debugPrint('[SPLASH] Error preloading meals: $e');
      }),
      // FIX: Provide null to location-aware caching methods
      MealDetailScreen.loadChefsCacheFromUserCache(null),
      MealDetailScreen.loadProducersCacheFromUserCache(null),
      // FIX: Provide null to location-aware caching method
      nutrition_details.Nutri_DetailPage.preloadProducersCacheForSplash(),
      ChooseChefNetwork.preloadCacheForSplash(),
      NutritionPage.preloadCachesForSplash().catchError((e) {
        debugPrint('[SPLASH] Error preloading Nutrition+ data: $e');
      }),
      LocationService.instance.fetchAndSetCurrentLocation().then((_) {
        debugPrint('[SPLASH] Initial location fetch attempt completed (non-blocking).');
        if (LocationService.instance.currentPosition != null) {
          debugPrint('[SPLASH] Location fetched: ${LocationService.instance.currentPosition}');
          if (LocationService.instance.currentAddress != null) {
            debugPrint('[SPLASH] Address fetched: ${LocationService.instance.currentAddress}');
          }
        } else {
          debugPrint('[SPLASH] Initial location fetch failed or permission denied.');
        }
      }).catchError((e) {
        debugPrint('[SPLASH] Error during initial location fetch: $e');
      }),
    ];
    // **** END FIX ****

    if (userType == 'transporter' && userId != null) {
      preloadFutures.add(TransporterDashNew.preloadCacheForSplash(userId.toString()));
    }
    
    // Await all futures but catch individual errors so one failure doesn't stop others
    await Future.wait(preloadFutures.map((f) => f.catchError((e) {
      debugPrint('A non-critical preload task failed: $e');
      return Future.value(); // Return a completed future to continue
    })));

    // A small delay to ensure UI updates smoothly
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      setState(() {
        _isPreloading = false;
        _nextScreen = determinedNextScreen;
      });
      // Automatically navigate after preloading is complete
      _navigateWithScaleTransition(context, _nextScreen);
    }
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
          AnimatedPositioned(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutQuart,
            top: _showBanner ? 0 : -100,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/grodd2.jpg',
              fit: BoxFit.cover,
              height: MediaQuery.of(context).size.height * 0.1,
              width: MediaQuery.of(context).size.width,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error loading grodd2.jpg: $error');
                return Container(
                  color: kColorPrimary.withOpacity(0.1),
                  height: MediaQuery.of(context).size.height * 0.1,
                  width: MediaQuery.of(context).size.width,
                  child: const Center(child: Icon(Icons.image_not_supported)),
                );
              },
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
                                : () => _navigateWithScaleTransition(context, _nextScreen),
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
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              child: Text(
                                _isPreloading ? "LOADING..." : "GET STARTED",
                                key: ValueKey<bool>(_isPreloading),
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
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