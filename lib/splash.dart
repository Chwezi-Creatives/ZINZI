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
import 'package:zinzi2/cache_config.dart'; // Import CacheConfig
import 'package:zinzi2/user_cache.dart'; // Import UserCache

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
    if (mounted) {
      setState(() {
        _isPreloading = true;
      });
    }

    // Start the animation delay and the data preloading concurrently
    final animationDelay = Future.delayed(const Duration(milliseconds: 3000));
    final preloadTasks = <Future>[];
    preloadTasks.add(AllMealsScreen.loadMealsCacheFromPrefs());
    preloadTasks.add(MealDetailScreen.loadChefsCacheFromUserCache());
    preloadTasks.add(MealDetailScreen.loadProducersCacheFromUserCache());

    // Add fetching and saving logic if cache is invalid
    final now = DateTime.now();

    // Check and fetch/save Chefs if cache is invalid
    final dynamic chefsTimestampData =
        await UserCache.getData('chefs_list_cache_timestamp');
    DateTime? chefsCacheTimestamp;
    if (chefsTimestampData is String) {
      try {
        chefsCacheTimestamp = DateTime.parse(chefsTimestampData);
      } catch (_) {}
    }
    final bool chefsCacheValid = chefsCacheTimestamp != null &&
        now.difference(chefsCacheTimestamp) <
            CacheConfig.chefProducerDetailCacheDuration;

    if (!chefsCacheValid) {
      print("Splash: Chef cache invalid, fetching...");
      preloadTasks.add(ApiService.fetchChefsStatic().then((fetchedChefs) async {
        if (fetchedChefs != null) {
          await MealDetailScreen.saveChefsCacheToUserCache(fetchedChefs);
          print("Splash: Fetched and saved new chef cache.");
        } else {
          print("Splash: Failed to fetch new chef cache.");
        }
      }).catchError((e) {
        print("Splash: Error fetching chefs: $e");
      }));
    } else {
      print("Splash: Chef cache is valid.");
    }

    // Check and fetch/save Producers if cache is invalid
    final dynamic producersTimestampData =
        await UserCache.getData('producers_list_cache_timestamp');
    DateTime? producersCacheTimestamp;
    if (producersTimestampData is String) {
      try {
        producersCacheTimestamp = DateTime.parse(producersTimestampData);
      } catch (_) {}
    }
    final bool producersCacheValid = producersCacheTimestamp != null &&
        now.difference(producersCacheTimestamp) <
            CacheConfig.chefProducerDetailCacheDuration;

    if (!producersCacheValid) {
      print("Splash: Producer cache invalid, fetching...");
      preloadTasks
          .add(ApiService.fetchProducersStatic().then((fetchedProducers) async {
        if (fetchedProducers != null) {
          await MealDetailScreen.saveProducersCacheToUserCache(
              fetchedProducers);
          print("Splash: Fetched and saved new producer cache.");
        } else {
          print("Splash: Failed to fetch new producer cache.");
        }
      }).catchError((e) {
        print("Splash: Error fetching producers: $e");
      }));
    } else {
      print("Splash: Producer cache is valid.");
    }

    // Wait for both the animation delay and all preload tasks to complete
    await Future.wait([animationDelay, ...preloadTasks]);

    if (mounted) {
      setState(() {
        _isPreloading = false;
      });
    }

    // Add a small delay to allow UI to update
    await Future.delayed(const Duration(milliseconds: 200));

    // Check login state
    final prefs = await SharedPreferences.getInstance();
    // Try to get user_id as string first, fall back to int for backward compatibility
    final userId = prefs.getString('user_id') ?? 
                 prefs.getInt('user_id')?.toString();
    final chefId = prefs.getString('chef_user_id');
    final producerId = prefs.getString('producer_id');

    await Future.delayed(const Duration(milliseconds: 300));

    Widget nextScreen;
    if (userId != null) {
      nextScreen = LandingPage(); // Assumed to be defined elsewhere
    } else if (chefId != null) {
      nextScreen = ChefDash88new(); // Assumed to be defined elsewhere
    } else if (producerId != null) {
      nextScreen = ProducerDash22();
    } else {
      nextScreen = SignUpOrLoginPage();
    }

    if (mounted) {
      _navigateWithSlideTransition(context, nextScreen);
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
                                : () {
                                    _navigateWithSlideTransition(
                                        context, SignUpOrLoginPage());
                                  },
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
                              "Get Started",
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
