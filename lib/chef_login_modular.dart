//cspell:disable
import 'package:flutter/material.dart';
import 'package:zinzi/base_login_modular.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/chef_dash8888.dart';// Ensure this path is correct // Make sure this points to the right dashboard class
import 'package:zinzi/services/notification_service.dart';
import 'package:flutter/foundation.dart';

class ChefLoginPageModular extends StatelessWidget {
  const ChefLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType, {String? phone}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('chef_user_id', userId.toString());
      await prefs.setString('user_type', userType); // Use standardized key
      await prefs.setString('user_id', userId.toString()); // Standard key for splash
      await prefs.setBool('is_logged_in', true);
      if (phone != null) {
        await prefs.setString('user_phone', phone);
      }
      
      // Initialize notification service and register FCM token in background
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
      apiUrl: 'rr/login/chefs', // The API URL for chef login
      pageTitle: 'Chef Login',
      buttonText: 'LOGIN AS CHEF',
      idKey: 'chef_id', // Specific to chef
      expectedUserType: 'chef', // Specific to chef
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
        
        // Navigate to the Chef Dashboard after saving user details
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ChefDashboardScreen()),
        );
       //   } else {
       //     debugPrint(
       //         'Data does not contain required keys: "chef_id" or "user_type".');
       //   }
       // } else {
       //   debugPrint('Key "data" not found in response.');
       // }

        // Return a dummy widget since onLoginSuccess needs to return a Widget
        return Container(); // Return an empty widget
      },
    );
  }
}