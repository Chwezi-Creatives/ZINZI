import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/chart_metrics.dart';
import 'package:zinzi2/metrics_history.dart';
import 'dart:convert';
import 'meal_recommendations_page.dart';
import 'user_metrics.dart';
import 'bmi_indicator.dart'; // Import the BMIIndicator widget
import 'weight_indicator.dart'; // Import the WeightIndicator widget
import 'healthtipcard.dart'; // Import the HealthTipCard widget
import 'pay1.dart'; // Import the PaymentScreen

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  int? _userId;
  Map<String, dynamic> _userMetrics = {};
  Map<String, dynamic> _userPreferences = {};
  late AnimationController _controller;
  late Animation<double> _buttonAnimation;

  bool _bmiVisible = false;
  bool _weightVisible = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.6,
      upperBound: 1.0,
    );

    _buttonAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _controller.repeat(reverse: true);
    _loadUserId();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
    });

    if (_userId != null) {
      debugPrint('Loaded userId: $_userId');
      await _fetchMetrics();
      await _fetchPreferences();
    } else {
      debugPrint('No userId found in shared preferences.');
      _showSnackBar('User not logged in.');
    }
  }

  Future<void> _fetchMetrics() async {
    final url = 'http://192.168.1.4:5000/rr/get_user_metrics?user_id=$_userId';
    debugPrint('Fetching metrics from: $url');

    try {
      final response = await http.get(Uri.parse(url));
      debugPrint('Metrics API response status code: ${response.statusCode}');
      debugPrint('Metrics API raw response: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          setState(() {
            _userMetrics = responseData;
          });
        } else {
          _showSnackBar('Invalid metrics data format.');
        }
      } else {
        _showSnackBar('Failed to fetch metrics.');
      }
    } catch (error) {
      _showSnackBar('Error fetching metrics: $error');
    }
  }

  Future<void> _fetchPreferences() async {
    final url =
        'http://192.168.1.4:5000/rr/fetch_user_preferences?user_id=$_userId';
    debugPrint('Fetching preferences from: $url');

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          setState(() {
            _userPreferences = responseData;
          });
        } else {
          _showSnackBar('Invalid preferences data format.');
        }
      } else {
        _showSnackBar('Failed to fetch preferences.');
      }
    } catch (error) {
      _showSnackBar('Error fetching preferences: $error');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getDisplayValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is String) {
      final parsedValue = double.tryParse(value);
      if (parsedValue != null) {
        return parsedValue.toStringAsFixed(1); // Keep one decimal place
      }
    }
    return value.toString();
  }

  Map<String, String> _filterUserPreferences() {
    final Map<String, String> preferences = {};
    _userPreferences.forEach((key, value) {
      if (key != 'user_id') {
        preferences[key.toString().replaceAll('_', ' ').toUpperCase()] =
            value.toString();
      }
    });
    return preferences;
  }

  Widget _getPreferenceIcon(String preference) {
    final iconPaths = {
      'Vegan': 'assets/images/vegan.png',
      'Omnivore': 'assets/images/omnivore.png',
      'Vegetarian': 'assets/images/vegan.png',
      'Keto': 'assets/images/keto.png',
      'Paleo': 'assets/images/paleo.png',
      'Dairy-Free': 'assets/images/dairy_free2.png',
      'Gluten-Free': 'assets/images/glutten.png',
      'Nut-Free': 'assets/images/nut_free.png',
      'Weight Loss': 'assets/images/lose_weight.png',
      'Muscle Gain': 'assets/images/muscle.png',
    };

    final iconPath = iconPaths[preference];
    return iconPath != null
        ? Image.asset(
            iconPath,
            width: 30,
            height: 30,
          )
        : const Icon(Icons.help_outline);
  }

  Widget _buildCard({
    required String title,
    required Map<String, String> data,
    required VoidCallback onEdit,
    bool isPreference = false,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 8.0),
            ...data.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0.9,
                  child: ListTile(
                    leading:
                        isPreference ? _getPreferenceIcon(entry.value) : null,
                    title: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(entry.value),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard', textAlign: TextAlign.center),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard', textAlign: TextAlign.center),
        backgroundColor: Colors.teal,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.teal.withOpacity(0.2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _userMetrics.isEmpty || _userPreferences.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return Wrap(
                          spacing: 16.0,
                          runSpacing: 16.0,
                          alignment: WrapAlignment.start,
                          children: [
                            // User Preferences card
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: _buildCard(
                                title: 'USER PREFERENCES',
                                data: _filterUserPreferences(),
                                onEdit: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LogMetricsScreen(),
                                    ),
                                  );
                                },
                                isPreference: true,
                              ),
                            ),

                            // BMI Indicator card
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4.0,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'BMI',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                      const SizedBox(height: 8.0),
                                      BMIIndicator(
                                        bmi: double.tryParse(_userMetrics['bmi']
                                                    ?.toString() ??
                                                '') ??
                                            0.0,
                                        animate: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Weight Indicator card
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4.0,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'WEIGHT',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                      const SizedBox(height: 8.0),
                                      WeightIndicator(
                                        currentWeight: double.tryParse(
                                                _userMetrics['weight']
                                                        ?.toString() ??
                                                    '') ??
                                            0.0,
                                        idealWeight: double.tryParse(
                                                _userMetrics['ideal_weight']
                                                        ?.toString() ??
                                                    '') ??
                                            0.0,
                                        healthGoal: _userPreferences['Goals'] ??
                                            'Maintain Weight',
                                        animate: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Health Tip card
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: HealthTipCard(
                                bmi: double.tryParse(
                                        _userMetrics['bmi']?.toString() ??
                                            '0') ??
                                    0.0,
                              ),
                            ),

                            // Recommended Meals button
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: ScaleTransition(
                                scale: _buttonAnimation,
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4.0,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              MealRecommendationsPage(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'Recommended Meals',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal,
                                            ),
                                          ),
                                          SizedBox(width: 8.0),
                                          Icon(Icons.arrow_forward,
                                              color: Colors.teal),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Proceed to Payment button
                            SizedBox(
                              width: isWide
                                  ? (constraints.maxWidth - 32) / 2
                                  : constraints.maxWidth,
                              child: ScaleTransition(
                                scale: _buttonAnimation,
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4.0,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PaymentScreen(),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'Proceed to Payment',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal,
                                            ),
                                          ),
                                          SizedBox(width: 8.0),
                                          Icon(Icons.arrow_forward,
                                              color: Colors.teal),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
