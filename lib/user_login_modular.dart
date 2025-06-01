import 'package:flutter/material.dart';
import 'package:zinzi2/base_login_modular.dart';
import 'package:zinzi2/dashboard_page.dart'; // Ensure this is the correct import for the User Dashboard
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/onboard.dart';
import 'package:zinzi2/profile.dart';
import 'notifications/fcm_service.dart';

class UserLoginPageModular extends StatelessWidget {
  const UserLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType, {String? phone}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId); // Store as string
    await prefs.setString('user_type', userType);
    await prefs.setBool('is_logged_in', true);
    if (phone != null) {
      await prefs.setString('user_phone', phone);
    }
    // Register FCM token with user info (async, do not await)
    FCMService.registerTokenWithUserInfo();
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageModular(
      apiUrl: 'rr/login_user', // The API URL for user login
      pageTitle: 'User Login',
      buttonText: 'LOGIN AS USER',
      idKey: 'user_id', // Specific to user
      expectedUserType: 'user', // Specific to user
      onLoginSuccess: (Map<String, dynamic> loginData) {
        // Print the entire response to the console for debugging purposes
        print('Login response: $loginData');

        // Extract data from the loginData map
        final String userId = loginData['userId'];
        final String userType = loginData['userType'];
        final bool verified = loginData['verified'] ?? false; // Default to false if null
        final String? phone = loginData['phone']; // Extract phone number if available

        // Save user details including phone number to shared preferences
        saveUserDetails(userId, userType, phone: phone);
        
        // Navigate to the User Dashboard after saving user details
        Navigator.pushReplacement(
          context,
          _createSlideTransitionRoute(context),
        );
       //   } else {
       //     print('Data does not contain required keys: "user_id" or "user_type".');
       //   }
       // } else {
       //   print('Key "data" not found in response.');
       // }

        // Return a dummy widget since onLoginSuccess needs to return a Widget
        return Container(); // Return an empty widget
      },
    );
  }

  // Creates a slide transition route to LandingPage
  Route _createSlideTransitionRoute(BuildContext context) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => LandingPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Slide transition setup
        const begin = Offset(1.0, 0.0); // Start from the right
        const end = Offset.zero; // End at the center of the screen
        const curve = Curves.easeInOut; // Animation curve

        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300), // Transition duration
    );
  }
}
