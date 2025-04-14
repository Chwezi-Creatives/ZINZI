import 'package:flutter/material.dart';
import 'package:zinzi2/base_login_modular.dart';
import 'package:zinzi2/dashboard_page.dart'; // Ensure this is the correct import for the User Dashboard
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/onboard.dart';
import 'package:zinzi2/profile.dart';

class UserLoginPageModular extends StatelessWidget {
  const UserLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(int userId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
    await prefs.setString('user_type', userType);
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageModular(
      apiUrl: 'rr/login_user', // The API URL for user login
      pageTitle: 'User Login',
      buttonText: 'LOGIN AS USER',
      idKey: 'user_id', // Specific to user
      expectedUserType: 'user', // Specific to user
      onLoginSuccess: (Map<String, dynamic> response) {
        // Print the entire response to the console for debugging purposes
        print('Login response: $response');

        // Ensure that 'data' key exists in the response
        if (response.containsKey('data')) {
          // Access the data object
          var data = response['data'];

          // Confirm that the expected fields are present
          if (data is Map<String, dynamic> &&
              data.containsKey('user_id') &&
              data.containsKey('user_type')) {
            int userId = data['user_id']; // Expect user_id to be an integer
            String userType = data['user_type'];

            // Save user ID and user type to shared preferences
            saveUserDetails(userId, userType).then((_) {
              // Navigate to the User Dashboard after saving user details
              Navigator.pushReplacement(
                context,
                _createSlideTransitionRoute(context),
              );
            });
          } else {
            print('Data does not contain required keys: "user_id" or "user_type".');
          }
        } else {
          print('Key "data" not found in response.');
        }

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
