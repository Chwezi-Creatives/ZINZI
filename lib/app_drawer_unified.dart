import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:zinzi/blogview.dart';
import 'package:zinzi/wellness_communities_screen.dart';
import 'package:zinzi/cart.dart' as cart;
import 'package:zinzi/profile.dart';
import 'package:zinzi/chef_dash8888.dart';
import 'package:zinzi/produ_dash22.dart';
import 'package:zinzi/chef_profile.dart' show ChefProfileApp;
import 'package:zinzi/producer_profile.dart' show ProducerProfileApp;
import 'package:zinzi/profile.dart' show ProfilePage;
import 'package:zinzi/signup_or_Login.dart';
import 'package:zinzi/useranalytics.dart';
import 'package:zinzi/orderhistory.dart';
import 'package:zinzi/onboard.dart';

// --- Color Constants ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8);
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
// --- End Color Constants ---

final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url';

class UserDataCache {
  final String userId;
  final String userType;
  final Map<String, dynamic> data;
  final DateTime lastUpdated;

  UserDataCache({
    required this.userId,
    required this.userType,
    required this.data,
    required this.lastUpdated,
  });

  bool get isValid => lastUpdated.add(const Duration(hours: 36)).isAfter(DateTime.now());
}

class AppDrawer extends StatefulWidget {
  final String? invokedBy;
  const AppDrawer({Key? key, this.invokedBy}) : super(key: key);

  // Static cache for user details with user context
  static final Map<String, UserDataCache> _userCaches = {};
  
  // Static method to refresh user details
  static Future<void> refreshUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    final userType = (prefs.getString('user_type') ?? 'user').toLowerCase();
    
    if (userId.isEmpty) {
      _userCaches.remove(_getCacheKey(userId, userType));
      return;
    }
    
    String endpoint;
    Map<String, String> fieldMapping;

    switch (userType) {
      case 'chef':
        endpoint = '$apiBaseUrl/rr/rchefs/$userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
        break;
      case 'producer':
        endpoint = '$apiBaseUrl/rr/rproducers/$userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
        break;
      case 'transporter':
        endpoint = '$apiBaseUrl/rr/transporters/$userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'profile_image_url',
        };
        break;
      case 'user':
      default:
        endpoint = '$apiBaseUrl/rr/rusers/$userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
    }

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic> && responseData['data'] != null) {
          final userData = _createCaseInsensitiveMap(responseData['data'] as Map<String, dynamic>);
          
          final name = _getCaseInsensitive(userData, fieldMapping['name']!)?.toString() ?? 'User Name';
          final email = _getCaseInsensitive(userData, fieldMapping['email']!)?.toString() ?? '';
          final image = _getCaseInsensitive(userData, fieldMapping['image']!)?.toString() ?? '';

          // Update cache
          _userCaches[_getCacheKey(userId, userType)] = UserDataCache(
            userId: userId,
            userType: userType,
            data: {
              'name': name,
              'email': email,
              'image': image,
              'user_type': userType,
            },
            lastUpdated: DateTime.now(),
          );

          // Update SharedPreferences with user-specific keys
          await prefs.setString('${userType}_${userId}_user_name', name);
          await prefs.setString('${userType}_${userId}_user_email', email);
          await prefs.setString('${userType}_${userId}_profile_image_url', image);
        }
      }
    } catch (e) {
      print("Error refreshing $userType details: $e");
    }
  }

  // Static method to clear cache for specific user
  static Future<void> clearUserCache(String userId, String userType) async {
    _userCaches.remove(_getCacheKey(userId, userType));
    final prefs = await SharedPreferences.getInstance();
    
    // Remove all user-specific preferences
    final prefix = '${userType}_${userId}_';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // Static method to get current user cache
  static UserDataCache? getCurrentUserCache(String userId, String userType) {
    return _userCaches[_getCacheKey(userId, userType)];
  }

  // Helper to create cache key
  static String _getCacheKey(String userId, String userType) {
    return '${userType.toLowerCase()}_${userId.toLowerCase()}';
  }

  // Helper method to create a case-insensitive copy of a map
  static Map<String, dynamic> _createCaseInsensitiveMap(Map<String, dynamic> original) {
    return original.map((key, value) => 
      MapEntry(key.toLowerCase(), value is Map<String, dynamic> ? _createCaseInsensitiveMap(value) : value)
    );
  }

  // Helper for case-insensitive map access
  static dynamic _getCaseInsensitive(Map<String, dynamic> map, String key) {
    return map[key.toLowerCase()];
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
  String? _userId;
  String? _userType;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // Get current user context
    _userId = prefs.getString('user_id');
    _userType = prefs.getString('user_type')?.toLowerCase();

    if (_userId == null || _userType == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Check cache first
    final userCache = AppDrawer.getCurrentUserCache(_userId!, _userType!);
    if (userCache != null && userCache.isValid) {
      _updateFromCache(userCache);
      return;
    }

    // If no valid cache, fetch from API
    await _fetchUserDetails();
  }

  void _updateFromCache(UserDataCache cache) {
    setState(() {
      _userName = cache.data['name'] ?? _userName;
      _userEmail = cache.data['email'] ?? _userEmail;
      _profileImageUrl = cache.data['image'] ?? _profileImageUrl;
      _isLoading = false;
    });
  }

  Future<void> _fetchUserDetails() async {
    if (_userId == null || _userType == null) {
      setState(() => _isLoading = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    String endpoint;
    Map<String, String> fieldMapping;

    switch (_userType!) {
      case 'chef':
        endpoint = '$apiBaseUrl/rr/rchefs/$_userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
        break;
      case 'producer':
        endpoint = '$apiBaseUrl/rr/rproducers/$_userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
        break;
      case 'transporter':
        endpoint = '$apiBaseUrl/rr/transporters/$_userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'profile_image_url',
        };
        break;
      case 'user':
      default:
        endpoint = '$apiBaseUrl/rr/rusers/$_userId';
        fieldMapping = {
          'name': 'name',
          'email': 'email',
          'image': 'image',
        };
    }

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic> && responseData['data'] != null) {
          final userData = AppDrawer._createCaseInsensitiveMap(responseData['data'] as Map<String, dynamic>);
          
          final name = AppDrawer._getCaseInsensitive(userData, fieldMapping['name']!)?.toString() ?? _userName;
          final email = AppDrawer._getCaseInsensitive(userData, fieldMapping['email']!)?.toString() ?? _userEmail;
          final image = AppDrawer._getCaseInsensitive(userData, fieldMapping['image']!)?.toString() ?? _profileImageUrl ?? '';

          // Update cache
          AppDrawer._userCaches[AppDrawer._getCacheKey(_userId!, _userType!)] = UserDataCache(
            userId: _userId!,
            userType: _userType!,
            data: {
              'name': name,
              'email': email,
              'image': image,
              'user_type': _userType!,
            },
            lastUpdated: DateTime.now(),
          );

          // Update SharedPreferences with user-specific keys
          await prefs.setString('${_userType}_${_userId}_user_name', name);
          await prefs.setString('${_userType}_${_userId}_user_email', email);
          await prefs.setString('${_userType}_${_userId}_profile_image_url', image);

          if (mounted) {
            setState(() {
              _userName = name;
              _userEmail = email;
              _profileImageUrl = image;
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error fetching $_userType details: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToProfile() async {
    if (_userType == null) return;
    
    Navigator.pop(context); // Close the drawer
    
    // Navigate based on user type
    switch (_userType!.toLowerCase()) {
      case 'chef':
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChefProfileApp(),
              settings: RouteSettings(name: '/chef_profile'),
            ),
          );
        }
        break;
      case 'producer':
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProducerProfileApp(),
              settings: RouteSettings(name: '/producer_profile'),
            ),
          );
        }
        break;
      case 'user':
      default:
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfilePage(),
              settings: RouteSettings(name: '/profile'),
            ),
          );
        }
        break;
    }
  }

  Future<void> _logout() async {
    try {
      // Clear user cache if user info is available
      if (_userId != null && _userType != null) {
        await AppDrawer.clearUserCache(_userId!, _userType!);
      }
      
      // Clear all user-related data from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await prefs.remove('user_type');
      
      // Clear any other user-specific preferences if needed
      await prefs.remove('fcm_token');
      await prefs.remove('first_login');
      await prefs.remove('user_phone');  // Clear user phone number
      
      // Clear the cart when logging out
      cart.ShoppingCart.clearCart();
      
      if (mounted) {
        // Navigate to login screen and remove all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const SignUpOrLoginPage()),
          (Route<dynamic> route) => false,
        );
      }
      
      print('User logged out successfully');
    } catch (e) {
      print('Error during logout: $e');
      // Even if there's an error, we should still try to navigate to login
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const SignUpOrLoginPage()),
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  Widget _buildDrawerTile(IconData icon, String title, VoidCallback? onTap,
      {Color? color, bool enabled = true}) {
    final Color effectiveColor =
        enabled ? (color ?? kColorPrimary) : Colors.grey;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: enabled ? (color ?? kColorTextPrimary) : Colors.grey,
              fontSize: 15)),
      onTap: enabled && onTap != null ? onTap : null,
      enabled: enabled,
    );
  }

  List<Widget> _buildUserTypeSpecificTiles() {
    List<Widget> tiles = [];

    tiles.addAll([
      _buildDrawerTile(Icons.home_outlined, 'Home', () {
        Navigator.pop(context);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LandingPage()),
          (Route<dynamic> route) => false,
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
      _buildDrawerTile(
        Icons.history,
        'Order History',
        widget.invokedBy == 'chef_dashboard' ||
                widget.invokedBy == 'producer_dashboard'
            ? null
            : () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrderHistoryScreen(),
                    settings: RouteSettings(name: '/order_history'),
                  ),
                );
              },
        enabled: !(widget.invokedBy == 'chef_dashboard' ||
            widget.invokedBy == 'producer_dashboard'),
      ),
      _buildDrawerTile(Icons.analytics_outlined, 'Analytics Dashboard', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserAnalyticsDashboard(),
            settings: RouteSettings(name: '/analytics'),
          ),
        );
      }),
      _buildDrawerTile(Icons.groups_outlined, 'Wellness Communities', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const WellnessCommunitiesScreen(),
            settings: const RouteSettings(name: '/wellness_communities'),
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
            settings: const RouteSettings(name: '/blog'),
          ),
        );
      }),
    ]);

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
        SystemNavigator.pop();
      }, color: Colors.red.shade700),
    ]);

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object> avatarImage;
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      avatarImage = CachedNetworkImageProvider(_profileImageUrl!);
    } else if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        avatarImage = FileImage(file);
      } else {
        avatarImage = const AssetImage('assets/images/proffr.png');
      }
    } else {
      avatarImage = const AssetImage('assets/images/proffr.png');
    }

    return Drawer(
      child: Container(
        color: kColorSurface,
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
                        color: kColorTextOnPrimary.withOpacity(0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              currentAccountPicture: GestureDetector(
                onTap: _navigateToProfile,
                child: CircleAvatar(
                  radius: 35,
                  backgroundColor: kColorSurface.withOpacity(0.8),
                  backgroundImage: avatarImage,
                  onBackgroundImageError: (_, __) {
                    print("Error loading profile picture in drawer.");
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
              ),
              decoration: const BoxDecoration(
                color: kColorPrimaryDark,
              ),
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