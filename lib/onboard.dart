//cspell:disable
import 'package:flutter/material.dart';
import 'package:zinzi/allmeals.dart';
import 'package:zinzi/chef.dartp';
import 'package:zinzi/chef_net.dart';
//import 'package:zinzi/producer_network_testing.dart';
import 'package:zinzi/nutrition+.dart';
import 'package:zinzi/sensei_view.dart';
import 'Sensei_chat_in_house.dart';
import 'package:zinzi/app_drawer_unified.dart'; // Import AppDrawer

class LandingPage extends StatelessWidget {
  // Custom page route with transition
  static Route createRoute() {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => LandingPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, -1.0);  // Start from top
        const end = Offset.zero;          // End at final position
        const curve = Curves.easeInOutQuart;
        
        // Fade transition
        final fadeAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        );
        
        // Slide transition from top to bottom
        final slideAnimation = Tween<Offset>(
          begin: begin,
          end: end,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: curve,
        ));
        
        // Scale transition
        final scaleAnimation = Tween<double>(
          begin: 0.9,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: curve,
        ));
        
        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(
            position: slideAnimation,
            child: ScaleTransition(
              scale: scaleAnimation,
              child: child,
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 800),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(), // Add the AppDrawer here
      appBar: AppBar(
        title: Text('Welcome'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.teal[50]!,
              //Colors.teal[20]!,
              Colors.teal[50]!,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Welcome to Zinzi',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[900],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 5),
              Text(
                'Your one-stop Nutrition Assistant.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.teal[800],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildChoiceCard(context, 'Hire a Chef', ChooseChefNetwork(),
                      'assets/images/Chef22.png'),
                  _buildChoiceCard(context, 'Meals', AllMealsScreen(),
                      'assets/images/MealsRG.png'),
                ],
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildChoiceCard(context, 'Nutrition +', NutritionPage(), //ChooseProducerNetwork() ,
                      'assets/images/DrugRG.png'),
                  _buildDisabledCard(context, 'Sensei', 'assets/images/SenseiRG.png'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceCard(
      BuildContext context, String title, Widget navigateTo, String imagePath) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => navigateTo,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutQuart;
              
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              final offsetAnimation = animation.drive(tween);
              
              return SlideTransition(
                position: offsetAnimation,
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      },
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.teal[400]!,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              imagePath,
              width: 50,
              height: 50,
            ),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabledCard(BuildContext context, String title, String imagePath) {
    return GestureDetector(
      onTap: () {
        // Navigate to the SenseiWebView with the specified URL
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NutritionChatApp(),
          ),
        );
      },
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.teal[400]!,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              imagePath,
              width: 50,
              height: 50,
            ),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
