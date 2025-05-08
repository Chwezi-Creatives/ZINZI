import 'package:flutter/material.dart';
import 'package:zinzi2/produ_dash22.dart';
// Ensure this path is correct
//import 'package:zinzi2/producer_dash_redesign.dartp';
import 'base_login_modular.dart'; // Ensure you have the base_login_modular.dart file
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications/fcm_service.dart';

class ProducerLoginPageModular extends StatelessWidget {
  const ProducerLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String producerId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('producer_id', producerId); // Already a string
    await prefs.setString('user_type', userType); // Save user_type
    await prefs.setBool('is_logged_in', true);
    print('Producer ID saved: $producerId');
    print('User Type saved: $userType');
    // Register FCM token with user info (async, do not await)
    FCMService.registerTokenWithUserInfo();
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
        print('Login response: $loginData');

        // Extract data from the loginData map
        final String userId = loginData['userId'];
        final String userType = loginData['userType'];
        // Save user ID and user type to shared preferences
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('user_type', 'producer');
          prefs.setString('user_id', userId);
          saveUserDetails(userId, userType);
          // Navigate to the Producer Dashboard after saving user details
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProducerDash22()), // Ensure this class is defined and imported
          );
        });
       //   } else {
       //     print('Data does not contain required keys: "producer_id" or "user_type".');
       //     ScaffoldMessenger.of(context).showSnackBar(
       //       SnackBar(content: Text('Invalid response data. Please try again.')),
       //     );
       //   }
       // } else {
       //   print('Key "data" not found in response.');
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
