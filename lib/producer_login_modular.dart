//cspell:disable
import 'package:flutter/material.dart';
import 'package:zinzi/produ_dash22.dart';
// Ensure this path is correct
//import 'package:zinzi/producer_dash_redesign.dartp';
import 'base_login_modular.dart'; // Ensure you have the base_login_modular.dart file
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/services/notification_service.dart';
import 'package:flutter/foundation.dart';

class ProducerLoginPageModular extends StatelessWidget {
  const ProducerLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String producerId, String userType, {String? phone}) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('producer_id', producerId);
      await prefs.setString('user_type', userType);
      await prefs.setString('user_id', producerId); // Standard key for splash
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
      
      debugPrint('Producer ID saved: $producerId');
      debugPrint('User Type saved: $userType');
      debugPrint('FCM token registered with user info');
    } catch (e) {
      debugPrint('Error in saveUserDetails: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageModular(
      apiUrl: 'rr/login/producers', // Your API URL for producer login
      pageTitle: 'Producer Login',
      buttonText: 'LOGIN AS PRODUCER',
      idKey: 'producer_id', // Specific to producer
      expectedUserType: 'producer', // Specific to producer
      onLoginSuccess: (Map<String, dynamic> loginData) {
        // Print the entire response to the console for debugging purposes
        debugPrint('Login response: $loginData');

        // Extract data from the loginData map
        final String userId = loginData['userId'];
        final String userType = loginData['userType'];
        final String? phone = loginData['phone']; // Extract phone number if available
        
        // Save user ID, user type, and phone number to shared preferences
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('user_type', 'producer');
          prefs.setString('user_id', userId);
          if (phone != null) {
            prefs.setString('user_phone', phone);
          }
          saveUserDetails(userId, userType, phone: phone);
          // Navigate to the Producer Dashboard after saving user details
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProducerDash22()),
          );
        });
       //   } else {
       //     debugPrint('Data does not contain required keys: "producer_id" or "user_type".');
       //     ScaffoldMessenger.of(context).showSnackBar(
       //       SnackBar(content: Text('Invalid response data. Please try again.')),
       //     );
       //   }
       // } else {
       //   debugPrint('Key "data" not found in response.');
       //   ScaffoldMessenger.of(context).showSnackBar(
       //     SnackBar(content: Text('Invalid response format. Please try again.')),
       //   );
       // }

        // Return a dummy widget since onLoginSuccess needs to return a Widget
        return Container(); // Return an empty widget
      },
    );
  }
}