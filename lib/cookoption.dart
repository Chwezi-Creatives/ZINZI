import 'package:flutter/material.dart';
import 'package:zinzi2/chef.dart';
import 'package:zinzi2/chefdata.dart'; // Ensure this is the correct path to the Chef class // Ensure this is the correct path
import 'package:zinzi2/customer.dart'; // Ensure this is the correct path

class CookingChoicePage extends StatelessWidget {
  const CookingChoicePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Cooking Option'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal[800],
        elevation: 0,
      ),
      body: SizedBox.expand(
        child: Container(padding: const EdgeInsets.all(6.0),
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                  'assets/images/soft.jpg'), // Ensure this path is correct
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white.withOpacity(0.8), // Overlay color for better visibility
                BlendMode.dstATop,
              ),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                      shadows: [
                        Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Would you like to cook for yourself or hire a chef?',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 50),

                  // Cook for Myself Button
                  _buildOptionButton(context, 'Cook for Myself', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CustomerTypeSelectionPage()),
                    );
                  }),

                  const SizedBox(height: 20),

                  // Hire a Chef Button
                  _buildOptionButton(context, 'Hire a Chef', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ChooseChef()),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton(
      BuildContext context, String text, VoidCallback onPressed) {
    return Container(
      width: 320, // Makes the button take full width if possible
      height: 60, // Set a fixed height for all buttons
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal, // Consistent button color
          padding: const EdgeInsets.symmetric(vertical: 16.0), // Keep vertical padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // Rounded corners
          ),
          elevation: 5, // Slight elevation for shadow
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white, // Consistent text color
          ),
        ),
      ),
    );
  }
}
