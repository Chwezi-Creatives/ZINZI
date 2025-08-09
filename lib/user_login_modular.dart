//cspell:disable
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:zinzi/base_login_modular.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/onboard.dart';
import 'package:zinzi/services/notification_service.dart';

class UserLoginPageModular extends StatelessWidget {
  const UserLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType, {String? phone}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId); // Store as string
      await prefs.setString('user_type', userType);
      await prefs.setBool('is_logged_in', true);
      if (phone != null) {
        await prefs.setString('user_phone', phone);
      }
      
      // Initialize and register FCM token in background
      Future.microtask(() async {
        try {
          final notificationService = NotificationService();
          await notificationService.initialize();
          final token = await notificationService.getFcmToken();
          if (token != null) {
            debugPrint('FCM token obtained, registering with backend...');
            await notificationService.registerPendingFcmToken();
            debugPrint('FCM token registered with user info');
          }
        } catch (e) {
          debugPrint('Error registering FCM token: $e');
          // Continue with login even if FCM registration fails
        }
      });
    } catch (e) {
      debugPrint('Error in saveUserDetails: $e');
      rethrow;
    }
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
        debugPrint('Login response: $loginData');

        // Extract data from the loginData map
        final String userId = loginData['userId'];
        final String userType = loginData['userType'];
        final bool verified = loginData['verified'] ?? false; // Default to false if null
        final String? phone = loginData['phone']; // Extract phone number if available

        // Save user details including phone number to shared preferences
        saveUserDetails(userId, userType, phone: phone);
        
        // Navigate to the LandingPage after saving user details
        Navigator.of(context).pushReplacement(LandingPage.createRoute());
       // Note: Error handling is now done in the base_login_modular.dart file

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
