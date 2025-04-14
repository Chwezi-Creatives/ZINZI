import 'package:flutter/material.dart';
import 'package:zinzi2/stake_dash_redesign.dart';
import 'package:zinzi2/stakeholderdash222.dart';
import 'stake_dash.dart'; // Ensure this points to the correct dashboard class
import 'base_login_modular.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StakeholderLoginPageModular extends StatelessWidget {
  const StakeholderLoginPageModular({Key? key}) : super(key: key);

  Future<void> saveUserDetails(String userId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('stakeholder_user_id', userId);
    await prefs.setString('stakeholder_user_type', userType);
  }

  @override
  Widget build(BuildContext context) {
    return LoginPageModular(
      apiUrl: 'rr/login/stakeholders',
      pageTitle: 'Stakeholder Login',
      buttonText: 'LOGIN AS STAKEHOLDER',
      idKey: 'stakeholder_id', // Specific to stakeholder
      expectedUserType: 'stakeholder', // Specific to stakeholder
      onLoginSuccess: (Map<String, dynamic> response) {
        // Print the entire response to the console for debugging purposes
        print('Login response: $response');

        // Ensure that 'data' key exists in the response
        if (response.containsKey('data')) {
          // Access the data object
          var data = response['data'];

          // Confirm that the expected fields are present
          if (data is Map<String, dynamic> &&
              data.containsKey('stakeholder_id') &&
              data.containsKey('user_type')) {
            String userId = data['stakeholder_id'].toString();
            String userType = data['user_type'];

            // Save user ID and user type to shared preferences
            saveUserDetails(userId, userType).then((_) {
              // Navigate to the Stakeholder Dashboard after saving user details
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => stakeholderdas2222()),
              );
            });
          } else {
            print('Data does not contain required keys: "stakeholder_id" or "user_type".');
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
