import 'package:flutter/material.dart'; 
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zinzi2/dashboard_page.dart';

class UserPreferencesPage extends StatefulWidget {
  const UserPreferencesPage({super.key});

  @override
  _UserPreferencesPageState createState() => _UserPreferencesPageState();
}

class _UserPreferencesPageState extends State<UserPreferencesPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _Goals = '';
  String _dietType = '';
  String _foodRestrictions = '';
  int? _userId;
  bool _isLoading = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _GoalsOptions = [
    'Weight Loss',
    'Muscle Gain',
    'Maintain Weight'
  ];
  final List<String> _dietTypeOptions = [
    'Vegan',
    'Keto',
    'Paleo',
    'Mediterranean',
    'Omnivore'
  ];
  final List<String> _foodRestrictionsOptions = [
    'Gluten-Free',
    'Dairy-Free',
    'Nut-Free',
    'None'
  ];

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -1), end: const Offset(0, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
    });
  }

  Future<void> _submitPreferences() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID is missing. Cannot submit preferences.'),
      ));
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.4:5000/rr/add_user_preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId,
          'goals': _Goals,
          'diet_type': _dietType,
          'food_restrictions': _foodRestrictions,
        }),
      );

      if (response.statusCode == 200) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const DashboardPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              const slideBegin = Offset(1.0, 0.0); // Slide in from the right
              const slideEnd = Offset.zero;
              const fadeBegin = 0.0;
              const fadeEnd = 1.0;

              var slideTween = Tween(begin: slideBegin, end: slideEnd)
                  .chain(CurveTween(curve: Curves.easeInOut));
              var fadeTween = Tween(begin: fadeBegin, end: fadeEnd)
                  .chain(CurveTween(curve: Curves.easeIn));

              var slideAnimation = animation.drive(slideTween);
              var fadeAnimation = animation.drive(fadeTween);

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit preferences data. Please try again.'),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SlideTransition(
          position: _slideAnimation,
          child: const Text(
            'Diet Preferences',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
              child: Image.asset('assets/images/soft.jpg', fit: BoxFit.cover)),
          Positioned.fill(
              child: Container(color: Colors.teal.withOpacity(0.2))),
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      SlideTransition(
                          position: _slideAnimation,
                          child: SizedBox(
                              height: 170,
                              width: 170,
                              child: Image.asset(
                                  'assets/images/sensei white.png'))),
                      const SizedBox(height: 30),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildDropdownField(
                              'Goals',
                              _GoalsOptions,
                              (value) {
                                setState(() => _Goals = value!);
                              },
                              _Goals,
                            ),
                            const SizedBox(height: 16),
                            _buildDropdownField(
                              'Diet Type',
                              _dietTypeOptions,
                              (value) {
                                setState(() => _dietType = value!);
                              },
                              _dietType,
                            ),
                            const SizedBox(height: 16),
                            _buildDropdownField(
                              'Food Restrictions',
                              _foodRestrictionsOptions,
                              (value) {
                                setState(() => _foodRestrictions = value!);
                              },
                              _foodRestrictions,
                            ),
                            const SizedBox(height: 50),
                            ScaleTransition(
                              scale: CurvedAnimation(
                                  parent: _controller, curve: Curves.easeOut),
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () {
                                        if (_formKey.currentState!.validate()) {
                                          _submitPreferences();
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  backgroundColor: Colors.teal.shade500,
                                  elevation: 5,
                                  minimumSize: const Size(double.infinity, 60),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text('Submit Preferences',
                                        style: TextStyle(
                                            fontSize: 18, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField(String label, List<String> items,
      Function(String?) onChanged, String value) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.teal.shade800),
        filled: true,
        fillColor: Colors.white.withOpacity(0.6),
        border: InputBorder.none,
      ),
      value: value.isEmpty ? null : value,
      onChanged: onChanged,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      validator: (value) =>
          value == null || value.isEmpty ? 'Please select a $label' : null,
    );
  }
}
