import 'package:flutter/material.dart';
import 'package:zinzi2/reco.dart';
import 'package:zinzi2/repeat.dart'; // Ensure this is the correct path

class CustomerTypeSelectionPage extends StatelessWidget {
  const CustomerTypeSelectionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Customer Type'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal[800],
        elevation: 0,
      ),
      body: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                  'assets/images/soft.jpg'), // Ensure this path is correct
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white
                    .withOpacity(0.8), // Overlay color for better visibility
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
                        Shadow(
                            color: Colors.black,
                            offset: Offset(1, 1),
                            blurRadius: 2),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Are you a one-time customer or a repeat customer?',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 50),

                  // One-Time Customer Button
                  _buildCustomerButton(context, 'One-Time Customer', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => RecommendedMealsScreen()),
                    );
                  }),

                  const SizedBox(height: 20),

                  // Repeat Customer Button
                  _buildCustomerButton(context, '  Repeat Customer  ', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => RepeatCustomerSelectionPage()),
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

  Widget _buildCustomerButton(
      BuildContext context, String text, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal, // Consistent button color
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // Rounded corners
        ),
        elevation: 5, // Slight elevation for shadow
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          color: Colors.white, // Consistent text color
        ),
      ),
    );
  }
}
