//cspell:disable
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/signup_or_Login.dart';

class RoleSelectionPage extends StatefulWidget {
  @override
  _RoleSelectionPageState createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  final List<String> roles = ["User", "Chef", "Producer", "Stakeholder"];
  String? selectedRole;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Role'),
        backgroundColor: Colors.teal,
        elevation: 4,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50, Colors.teal.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<String>(
                  value: selectedRole,
                  hint: const Text("Select your role"),
                  items: roles.map((String role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) async {
                    setState(() {
                      selectedRole = newValue;
                    });

                    // Store selected role in SharedPreferences
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('user_role', newValue!);

                    // Navigate to SignUpOrLoginPage with the selected role
                    /*Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SignUpOrLoginPage(role: newValue),
                      ),
                    );*/
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
