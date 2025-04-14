import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zinzi2/user_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class UserMetricsPage extends StatefulWidget {
  const UserMetricsPage({super.key});

  @override
  _UserMetricsPageState createState() => _UserMetricsPageState();
}

class _UserMetricsPageState extends State<UserMetricsPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? _ageRange;
  double _weight = 0;
  double _height = 0;
  double _cholesterolLevel = 0;
  double _sysBp = 0;
  double _diaBp = 0;
  double _pulse = 0;
  String? _sex;
  String? _activityLevel;

  int? _userId;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _ageRanges = [
    '18-25',
    '26-35',
    '36-45',
    '46-55',
    '56-65',
    '66+'
  ];

  final List<String> _sexs = ['Male', 'Female'];

  final List<String> _activityLevels = [
    'Sedentary',
    'Lightly Active',
    'Moderately Active',
    'Very Active'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -1), end: const Offset(0, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
    });

    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID not found. Please log in again.'),
      ));
    }
  }

  Future<void> _submitMetrics() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID is missing. Cannot submit metrics.'),
      ));
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/metrics'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId,
          'age_range': _ageRange,
          'weight': _weight,
          'height': _height,
          'cholesterol_level': _cholesterolLevel,
          'sys_bp': _sysBp,
          'dia_bp': _diaBp,
          'pulse': _pulse,
          'sex': _sex,
          'activity_level': _activityLevel,
        }),
      );

      if (response.statusCode == 201) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                UserPreferencesPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit metrics data. Please try again.'),
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
          child: const Text('Health Metrics',
              style: TextStyle(color: Colors.black)),
        ),
        foregroundColor: Colors.white,
        backgroundColor: Colors.teal,
        elevation: 3,
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Semi-transparent overlay
          Positioned.fill(
            child: Container(
              color: Colors.teal.withOpacity(0.2),
            ),
          ),
          // Animated form content
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
                        child: Container(
                          height: 150,
                          width: 150,
                          child: Image.asset('assets/images/Gru whitet.png'),
                        ),
                      ),
                      const SizedBox(height: 01), // Reduced height
                      // Sliding text explaining why we need the metrics
                      SlideTransition(
                        position: _slideAnimation,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            "Provide your health metrics for a personalized experience",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 70), // Increased height
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Age Range',
                                labelStyle:
                                    TextStyle(color: Colors.teal.shade700),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 12),
                              ),
                              value: _ageRange,
                              items: _ageRanges.map((ageRange) {
                                return DropdownMenuItem<String>(
                                  value: ageRange,
                                  child: Text(ageRange),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _ageRange = value),
                              validator: (value) => value == null
                                  ? 'Please select your age range'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Sex',
                                labelStyle:
                                    TextStyle(color: Colors.teal.shade700),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 12),
                              ),
                              value: _sex,
                              items: _sexs.map((sex) {
                                return DropdownMenuItem<String>(
                                  value: sex,
                                  child: Text(sex),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _sex = value),
                              validator: (value) => value == null
                                  ? 'Please select your sex'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: 'Activity Level',
                                labelStyle:
                                    TextStyle(color: Colors.teal.shade700),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 12),
                              ),
                              value: _activityLevel,
                              items: _activityLevels.map((activityLevel) {
                                return DropdownMenuItem<String>(
                                  value: activityLevel,
                                  child: Text(activityLevel),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _activityLevel = value),
                              validator: (value) => value == null
                                  ? 'Please select your activity level'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _buildTextFormField('Weight (in kg)', (value) {
                              _weight = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 12),
                            _buildTextFormField('Height (in cm)', (value) {
                              _height = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 12),
                            _buildTextFormField('Cholesterol Level', (value) {
                              _cholesterolLevel = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 12),
                            _buildTextFormField('Systolic BP', (value) {
                              _sysBp = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 12),
                            _buildTextFormField('Diastolic BP', (value) {
                              _diaBp = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 12),
                            _buildTextFormField('Pulse', (value) {
                              _pulse = double.tryParse(value) ?? 0;
                            }),
                            const SizedBox(height: 20),
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: _controller,
                                curve: Curves.easeOut,
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_formKey.currentState!.validate()) {
                                    _submitMetrics();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor: Colors.teal.shade500,
                                  elevation: 5,
                                  minimumSize: const Size(double.infinity, 60),
                                ),
                                child: const Text(
                                  'Submit Metrics',
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.white),
                                ),
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

  Widget _buildTextFormField(String label, Function(String) onChanged) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.teal.shade700),
        filled: true,
        fillColor: Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      validator: (value) => value!.isEmpty ? 'Please enter $label' : null,
    );
  }
}
