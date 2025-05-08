import 'package:flutter/material.dart';
import 'package:zinzi2/base_login_modular.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/chef_dash8888.dart';// Ensure this path is correct // Make sure this points to the right dashboard class
import 'notifications/fcm_service.dart';

class ChefLoginPageModular extends StatelessWidget {
  const ChefLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('chef_user_id', userId.toString());
    await prefs.setString('user_type', userType); // Use standardized key
    await prefs.setBool('is_logged_in', true);
    // Register FCM token with user info (async, do not await)
    FCMService.registerTokenWithUserInfo();
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
        print('Login response: $loginData');

        // Extract data from the loginData map
        final String userId = loginData['userId'];
        final String userType = loginData['userType'];
        final bool verified = loginData['verified'] ?? false; // Default to false if null

            // Save user ID and user type to shared preferences
            saveUserDetails(userId, userType);
            // Navigate to the Chef Dashboard after saving user details
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => ChefDashboardScreen()),
            );
       //   } else {
       //     print(
       //         'Data does not contain required keys: "chef_id" or "user_type".');
       //   }
       // } else {
       //   print('Key "data" not found in response.');
       // }

        // Return a dummy widget since onLoginSuccess needs to return a Widget
        return Container(); // Return an empty widget
      },
    );
  }
}
