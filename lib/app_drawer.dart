import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemNavigator
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_or_Login.dart'; // Correct filename
import 'signup_or_Login.dart' show SignUpOrLoginPage; // Import the specific class

import 'splash.dart';

class AppDrawer extends StatelessWidget {
  final String userType; // e.g., 'Chef', 'Transporter', 'Producer'
  final String userIdKey; // The SharedPreferences key for the user ID (e.g., 'chef_id')

  const AppDrawer({
    Key? key,
    required this.userType,
    required this.userIdKey,
  }) : super(key: key);

  // --- Logout Function ---
  Future<void> _logout(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context); // Capture context
    final navigator = Navigator.of(context); // Capture context

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(userIdKey); // Remove the specific user ID
      print('User ID key "$userIdKey" removed from SharedPreferences.');

      // Clear all routes and navigate to the initial route (which should lead to splash)
      // Clear all routes and navigate to the initial route (which should lead to splash)
      // Assuming the initial route is set up correctly in main.dart to go to the splash screen.
      // Navigate directly to the SplashScreen and remove all previous routes
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SplashScreen()),
        (Route<dynamic> route) => false, // Remove all routes
      );
    } catch (e) {
      print("Error during logout: $e");
      // Show an error message if logout fails
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Close App Function ---
  void _closeApp() {
    print("Closing application.");
    SystemNavigator.pop(); // Closes the app but keeps SharedPreferences intact
  }

  @override
  Widget build(BuildContext context) {
    // Define a primary color, falling back if theme doesn't provide one
    final Color primaryColor = Theme.of(context).colorScheme.primary ?? Colors.teal;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: primaryColor, // Use primary color from theme
            ),
            child: Text(
              '$userType Dashboard',
              style: TextStyle(
                color: Colors.white, // Ensure text is visible on primary color
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined), // Icon for orders
            title: const Text('View Orders'),
            onTap: () {
              // Simply close the drawer - assumes user is on the main dashboard
              Navigator.pop(context);
            },
          ),
          const Divider(), // Visual separator
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text('Logout'),
            onTap: () => _logout(context), // Call logout function
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app_outlined),
            title: const Text('Close App'),
            onTap: _closeApp, // Call close app function
          ),
        ],
      ),
    );
  }
}