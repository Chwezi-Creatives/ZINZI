import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';

// Import necessary pages for navigation
import '../allmeals.dart';
import '../blogview.dart';
import '../cart.dart' as cart;
import '../profile.dart';
import '../signup_or_Login.dart';
import '../useranalytics.dart';
import '../social.dart';
import '../chef_net.dart';
import '../producer_network_testing.dart';
import '../onboard.dart';
import '../Nutri+.dart';

// --- Color Constants (Should be moved to a shared file ideally) ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Clean background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
// --- End Color Constants ---

// Use environment variable for API base URL
final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  // Static cache for user details
  static Map<String, dynamic>? _cachedUserDetails;
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheDuration = Duration(hours: 24);

  // Static method to refresh user details
  static Future<void> refreshUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) {
      _cachedUserDetails = null;
      _lastCacheUpdate = null;
      return;
    }

    final url = '$apiBaseUrl/rr/rusers/$userId';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          // Store both the full response and basic profile data
          _cachedUserDetails = responseData;
          _lastCacheUpdate = DateTime.now();

          // Also update SharedPreferences with basic profile data
          await prefs.setString(
              'user_name', responseData['name'] ?? 'User Name');
          await prefs.setString('user_email', responseData['email'] ?? '');
          await prefs.setString(
              'profile_image_url', responseData['profile_image_url'] ?? '');
        }
      }
    } catch (e) {
      print("Error refreshing user details: $e");
    }
  }

  // Static method to clear cache (call this on logout)
  static void clearCache() async {
    _cachedUserDetails = null;
    _lastCacheUpdate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('profile_image_url');
  }

  // Static method to initialize user data (call this at app start)
  static Future<void> initializeUserData() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if we have basic profile data in SharedPreferences
    final userName = prefs.getString('user_name');
    final userEmail = prefs.getString('user_email');
    final profileImageUrl = prefs.getString('profile_image_url');

    if (userName != null && userEmail != null && profileImageUrl != null) {
      // We have basic profile data, no need to fetch immediately
      return;
    }

    // If we don't have basic profile data, fetch it
    await refreshUserDetails();
  }

  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _userName = "User Name";
  String _userEmail = "";
  String? _profileImageUrl;
  String? _profileImagePath;
  bool _isLoading = true;
  int? _userId;
  String? _userType;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // First try to get basic profile data from SharedPreferences
    _userName = prefs.getString('user_name') ?? "User Name";
    _userEmail = prefs.getString('user_email') ?? "";
    _profileImageUrl = prefs.getString('profile_image_url');
    _profileImagePath = prefs.getString('profile_image_path');
    _userId = prefs.getInt('user_id');
    _userType = prefs.getString('user_type');

    // If we have basic profile data, we can show it immediately
    if (_userName != "User Name" && _profileImageUrl != null) {
      setState(() => _isLoading = false);
    }

    // Then try to get full user data from cache or API
    if (_userId != null) {
      if (AppDrawer._cachedUserDetails != null) {
        _updateFromCache();
      } else {
        await _fetchUserDetails();
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _updateFromCache() {
    if (AppDrawer._cachedUserDetails == null) return;

    final userData = AppDrawer._cachedUserDetails!;
    setState(() {
      _userName = userData['name'] ?? _userName;
      _userEmail = userData['email'] ?? _userEmail;
      _profileImageUrl = userData['profile_image_url'] ?? _profileImageUrl;
      _isLoading = false;
    });
  }

  Future<void> _fetchUserDetails() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final url = '$apiBaseUrl/rr/rusers/$_userId';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          // Update cache
          AppDrawer._cachedUserDetails = responseData;
          AppDrawer._lastCacheUpdate = DateTime.now();

          // Update SharedPreferences with basic profile data
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_name', responseData['name'] ?? _userName);
          await prefs.setString(
              'user_email', responseData['email'] ?? _userEmail);
          await prefs.setString('profile_image_url',
              responseData['profile_image_url'] ?? _profileImageUrl ?? '');

          if (mounted) {
            setState(() {
              _userName = responseData['name'] ?? _userName;
              _userEmail = responseData['email'] ?? _userEmail;
              _profileImageUrl =
                  responseData['profile_image_url'] ?? _profileImageUrl;
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print("Error fetching user details: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear user session data
    if (mounted) {
      // Check if widget is still mounted before navigating
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (context) =>
                SignUpOrLoginPage()), // Navigate to Landing/Login
        (Route<dynamic> route) => false, // Remove all routes behind it
      );
    }
  }

  // Helper for list tiles
  Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon,
          color: color ?? kColorPrimary), // Use primary color by default
      title: Text(title,
          style: GoogleFonts.poppins(
              color: color ?? kColorTextPrimary, fontSize: 15)), // Use Poppins
      onTap: onTap,
      dense: true, // Make tiles slightly more compact
    );
  }

  List<Widget> _buildUserTypeSpecificTiles() {
    List<Widget> tiles = [];

    // Common tiles for all user types
    tiles.addAll([
      _buildDrawerTile(Icons.home_outlined, 'Home', () {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LandingPage()),
          (Route<dynamic> route) => false,
        );
      }),
      _buildDrawerTile(Icons.restaurant_menu_outlined, 'Meals', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AllMealsScreen(),
            settings: RouteSettings(name: '/meals'),
          ),
        );
      }),
      _buildDrawerTile(Icons.shopping_cart_outlined, 'Shopping Cart', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => cart.ShoppingCartScreen(),
            settings: RouteSettings(name: '/cart'),
          ),
        );
      }),
      _buildDrawerTile(Icons.person_outline, 'Profile', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfilePage(),
            settings: RouteSettings(name: '/profile'),
          ),
        );
      }),
      _buildDrawerTile(Icons.analytics_outlined, 'Analytics Dashboard', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const UserAnalyticsDashboard(),
            settings: RouteSettings(name: '/analytics'),
          ),
        );
      }),
      _buildDrawerTile(Icons.people_outline, 'Hire a Chef', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ChooseChefNetwork(),
            settings: RouteSettings(name: '/chef_network'),
          ),
        );
      }),
      _buildDrawerTile(Icons.eco_outlined, 'Nutrition+', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const NutritionPage(),
            settings: RouteSettings(name: '/nutrition'),
          ),
        );
      }),
      _buildDrawerTile(Icons.groups_outlined, 'Wellness Communities', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SocialMediaScreen(),
            settings: RouteSettings(name: '/social'),
          ),
        );
      }),
      _buildDrawerTile(Icons.article_outlined, 'Blog', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const BlogScreen(url: 'https://artchwezi.blogspot.com/'),
          ),
        );
      }),
    ]);

    // Common tiles for all user types
    tiles.addAll([
      const Divider(height: 1, color: kColorDivider),
      _buildDrawerTile(Icons.help_outline, 'Help', () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Help Section Coming Soon!')),
        );
      }),
      _buildDrawerTile(Icons.logout, 'Logout', _logout,
          color: Colors.red.shade700),
      _buildDrawerTile(Icons.close, 'Close App', () {
        Navigator.pop(context);
        // Close the app without clearing data
        SystemNavigator.pop();
      }, color: Colors.red.shade700),
    ]);

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    // Determine the image provider based on fetched URL and local path
    ImageProvider<Object> avatarImage;
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      avatarImage = CachedNetworkImageProvider(_profileImageUrl!);
    } else if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        avatarImage = FileImage(file);
      } else {
        avatarImage = const AssetImage(
            'assets/images/proffr.png'); // Default if local file missing
      }
    } else {
      avatarImage =
          const AssetImage('assets/images/proffr.png'); // Default asset image
    }

    return Drawer(
      child: Container(
        color: kColorSurface, // Use surface color for drawer background
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                _isLoading ? "Loading..." : _userName,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: kColorTextOnPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              accountEmail: _isLoading || _userEmail.isEmpty
                  ? null
                  : Text(
                      _userEmail,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: kColorTextOnPrimary.withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              currentAccountPicture: CircleAvatar(
                radius: 35,
                backgroundColor: kColorSurface.withOpacity(0.8),
                backgroundImage: avatarImage,
                onBackgroundImageError: (_, __) {
                  print("Error loading profile picture in drawer.");
                  // Optionally handle error, maybe show initials?
                },
                child: _isLoading &&
                        _profileImageUrl == null &&
                        _profileImagePath == null
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(kColorPrimary)))
                    : null,
              ),
              decoration: const BoxDecoration(
                color: kColorPrimaryDark,
              ), // Dark teal header
              margin: EdgeInsets.zero,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _buildUserTypeSpecificTiles(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
