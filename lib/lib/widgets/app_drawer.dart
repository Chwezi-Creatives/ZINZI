import 'package:flutter/material.dart';
import 'package:zinzi2/onboard.dart';
import 'package:zinzi2/chef_net.dart';
import 'package:zinzi2/allmeals.dart' as allmeals;
import 'package:zinzi2/nutri+.dart';
import 'package:zinzi2/chef_net.dart' as chefnet;
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/profile.dart' as profile;
import 'package:zinzi2/useranalytics.dart' as useranalytics;
import 'package:zinzi2/blogview.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue, // Replace with your desired color
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zinzi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Chef',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.food_bank,
                color:
                    Colors.blue), // Replace Colors.blue with your desired color
            title: const Text('Nutri+',
                style: TextStyle(color: allmeals.kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NutritionPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.home, color: kColorPrimary),
            title:
                const Text('Home', style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant, color: kColorPrimary),
            title:
                const Text('Meals', style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart, color: kColorPrimary),
            title: const Text('Orders',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: kColorPrimary),
            title: const Text('Profile',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics, color: kColorPrimary),
            title: const Text('Analytics',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.monetization_on, color: kColorPrimary),
            title: const Text('Earnings',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.help_outline, color: kColorPrimary),
            title:
                const Text('Help', style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: kColorPrimary),
            title: const Text('Settings',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: kColorPrimary),
            title:
                const Text('About', style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.description, color: kColorPrimary),
            title:
                const Text('Terms', style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock, color: kColorPrimary),
            title: const Text('Privacy',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: kColorPrimary),
            title: const Text('Logout',
                style: TextStyle(color: kColorTextPrimary)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
