import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zinzi2/profile.dart';
import 'package:zinzi2/user_cache.dart';
import 'package:zinzi2/useranalytics.dart';
import 'package:zinzi2/cart.dart' as cart;
import 'package:zinzi2/blogview.dart';
import 'package:zinzi2/splash.dart';
import 'package:zinzi2/signup_or_Login.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/onboard.dart';

const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorDivider = Color(0xFFE0E0E0);

class AppDrawer extends StatelessWidget {
  final String? userName;
  final String? userEmail;
  final String? profilePicUrl;
  final bool isLoadingUserDetails;

  const AppDrawer({
    Key? key,
    this.userName,
    this.userEmail,
    this.profilePicUrl,
    this.isLoadingUserDetails = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use UserCache for user details
    final userCache = UserCache.instance;
    final userDetails = userCache.userDetails;
    final isLoading = userDetails == null;

    ImageProvider<Object> avatarImage = const AssetImage('assets/images/proffr.png');
    String? profilePicUrl = userDetails?['profile_picture'];
    if (!isLoading &&
        profilePicUrl != null &&
        profilePicUrl.isNotEmpty &&
        profilePicUrl.startsWith('http')) {
      avatarImage = CachedNetworkImageProvider(profilePicUrl);
    }

    String userName = userDetails?['Name'] ?? "User Name";
    String userEmail = userDetails?['Email'] ?? "";

    Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap,
        {Color? color}) {
      final textTheme = Theme.of(context).textTheme;
      return ListTile(
        leading: Icon(icon, color: color ?? kColorPrimary),
        title: Text(title,
            style: textTheme.bodyLarge
                ?.copyWith(color: color ?? kColorTextPrimary)),
        onTap: onTap,
        dense: true,
      );
    }

    return Drawer(
      child: Container(
        color: kColorSurface,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                userName,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              accountEmail: (userEmail.isNotEmpty)
                  ? Text(
                      userEmail,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.white.withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              currentAccountPicture: CircleAvatar(
                radius: 35,
                backgroundColor: kColorSurface.withOpacity(0.8),
                backgroundImage: avatarImage,
                onBackgroundImageError: (_, __) {
                  print("Error loading profile picture.");
                },
                child: isLoading
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
              ),
              margin: EdgeInsets.zero,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerTile(Icons.person_outline, 'Profile', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ProfilePage()));
                  }),
                  _buildDrawerTile(
                      Icons.analytics_outlined, 'Analytics Dashboard', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const UserAnalyticsDashboard()));
                  }),
                  const Divider(height: 1, color: kColorDivider),
                  _buildDrawerTile(Icons.shopping_cart_outlined, 'Shopping Cart',
                      () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => cart.ShoppingCartScreen()));
                  }),
                  _buildDrawerTile(Icons.miscellaneous_services_outlined, 'Services', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => LandingPage()));
                  }),
                  _buildDrawerTile(Icons.article_outlined, 'Blog', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const BlogScreen(
                                url: 'https://artchwezi.blogspot.com/')));
                  }),
                  _buildDrawerTile(
                      Icons.health_and_safety_outlined, 'Wellness Communities',
                      () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Wellness Communities Coming Soon!')));
                  }),
                  _buildDrawerTile(Icons.help_outline, 'Help', () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Help Section Coming Soon!')));
                  }),
                  const Divider(height: 1, color: kColorDivider),
                  _buildDrawerTile(Icons.logout, 'Logout', () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    UserCache.instance.clear();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SignUpOrLoginPage()),
                      (Route<dynamic> route) => false,
                    );
                  }, color: Colors.red.shade700),
                  _buildDrawerTile(Icons.close, 'Close App', () async {
                    Navigator.pop(context);
                    await Future.delayed(const Duration(milliseconds: 200));
                    // Show a modal splash overlay for 3 seconds, then close the app
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => WillPopScope(
                        onWillPop: () async => false,
                        child: Container(
                          color: Color(0xFFB2DFDB), // Use explicit light teal background
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 120,
                                  width: 120,
                                  child: Image.asset('assets/images/Logo (1).png', fit: BoxFit.contain),
                                ),
                                const SizedBox(height: 30),
                                const CircularProgressIndicator(color: kColorPrimary),
                                const SizedBox(height: 30),
                                Text(
                                  "ZINZI",
                                  style: GoogleFonts.poppins(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: kColorPrimaryDark,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Closing app...",
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    color: kColorPrimaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    await Future.delayed(const Duration(seconds: 3));
                    SystemNavigator.pop();
                  }, color: Colors.grey.shade700),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}