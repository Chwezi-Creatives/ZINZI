import 'package:flutter/material.dart';
import 'package:zinzi2/base_login_modular.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/chef_dash8888.dart'; // Ensure this path is correct // Make sure this points to the right dashboard class
import 'package:zinzi2/chef__dash__latest__uses_mock_data.dart';

class ChefLoginPageModular extends StatelessWidget {
  const ChefLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('chef_user_id', userId);
    await prefs.setString('chef_user_type', userType);
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageModular(
      apiUrl: 'rr/login/chefs', // The API URL for chef login
      pageTitle: 'Chef Login',
      buttonText: 'LOGIN AS CHEF',
      idKey: 'chef_id', // Specific to chef
      expectedUserType: 'chef', // Specific to chef
      onLoginSuccess: (Map<String, dynamic> response) {
        // Print the entire response to the console for debugging purposes
        print('Login response: $response');

        // Ensure that 'data' key exists in the response
        if (response.containsKey('data')) {
          // Access the data object
          var data = response['data'];

          // Confirm that the expected fields are present
          if (data is Map<String, dynamic> &&
              data.containsKey('chef_id') &&
              data.containsKey('user_type')) {
            String userId = data['chef_id'].toString();
            String userType = data['user_type'];

            // Save user ID and user type to shared preferences
            saveUserDetails(userId, userType).then((_) {
              // Navigate to the Chef Dashboard after saving user details
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => ChefDash88new()),
              );
            });
          } else {
            print(
                'Data does not contain required keys: "chef_id" or "user_type".');
          }
        } else {
          print('Key "data" not found in response.');
        }

        // Return a dummy widget since onLoginSuccess needs to return a Widget
        return Container(); // Return an empty widget
      },
    );
  }
}
