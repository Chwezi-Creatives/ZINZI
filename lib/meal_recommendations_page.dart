import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MealRecommendationsPage extends StatefulWidget {
  const MealRecommendationsPage({super.key});

  @override
  _MealRecommendationsPageState createState() =>
      _MealRecommendationsPageState();
}

class _MealRecommendationsPageState extends State<MealRecommendationsPage> {
  int? _userId; // User ID retrieved from storage
  List<dynamic> _recommendedMeals = [];
  bool _isLoading = true; // Track loading state

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('userId');
    });

    if (_userId != null) {
      await _getMealRecommendations();
    } else {
      _showSnackBar('User ID not found. Please log in again.');
      setState(() {
        _isLoading = false; // Stop loading if user ID is not found
      });
    }
  }

  Future<void> _getMealRecommendations() async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://24.ip.gl.ply.gg:18851/get_meal_recommendations?user_id=$_userId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _recommendedMeals = data['recommended_meals'];
          _isLoading = false; // Stop loading once data is fetched
        });
      } else {
        _showSnackBar('Failed to load meal recommendations');
        setState(() {
          _isLoading = false; // Stop loading even if API fails
        });
      }
    } catch (error) {
      _showSnackBar('Error loading meal recommendations: $error');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Meal Recommendations')),
      body: _isLoading
          ? Center(
              child:
                  CircularProgressIndicator()) // Show loading spinner while fetching data
          : _recommendedMeals.isEmpty
              ? Center(child: Text('No meal recommendations available.'))
              : ListView.builder(
                  itemCount: _recommendedMeals.length,
                  itemBuilder: (context, index) {
                    final meal = _recommendedMeals[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16.0),
                      child: ListTile(
                        title: Text(meal['meal_name']),
                        subtitle: Text(
                            meal['description'] ?? 'No description available'),
                      ),
                    );
                  },
                ),
    );
  }
}
