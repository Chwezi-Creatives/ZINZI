import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'meal_plan_details_screen.dart';

class MyMealPlansScreen extends StatefulWidget {
  const MyMealPlansScreen({Key? key}) : super(key: key);

  @override
  _MyMealPlansScreenState createState() => _MyMealPlansScreenState();
}

class _MyMealPlansScreenState extends State<MyMealPlansScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mealPlans = [];
  final String apiBaseUrl =
      dotenv.env['API_BASE_URL'] ?? 'https://api.zinzi.ug';

  @override
  void initState() {
    super.initState();
    _fetchMealPlans();
  }

  Future<void> _fetchMealPlans() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final userType = prefs.getString('user_type');

      if (userId == null || userType == null) {
        throw Exception('User not authenticated');
      }

      final url = Uri.parse('$apiBaseUrl/api/users/$userId/meal-plans');
      debugPrint('[MEAL_PLANS_SCREEN] Fetching meal plans from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'user-type': userType,
        },
      );

      debugPrint('[MEAL_PLANS_SCREEN] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint('[MEAL_PLANS_SCREEN] Successfully parsed response data');

        if (mounted) {
          final List<dynamic> mealPlansData = data is List ? data : (data['data'] ?? []);
          final List<Map<String, dynamic>> parsedMealPlans = [];

          for (var plan in mealPlansData) {
            try {
              if (plan is Map<String, dynamic>) {
                final Map<String, dynamic> parsedPlan = Map<String, dynamic>.from(plan);
                
                // Parse meals if it's a string
                if (parsedPlan['meals'] is String) {
                  try {
                    parsedPlan['meals'] = jsonDecode(parsedPlan['meals']);
                  } catch (e) {
                    debugPrint('[MEAL_PLANS_SCREEN] Error parsing meals JSON: $e');
                    parsedPlan['meals'] = [];
                  }
                }
                
                // Calculate duration in days
                try {
                  final startDate = DateTime.parse(parsedPlan['start_date']);
                  final endDate = DateTime.parse(parsedPlan['end_date']);
                  parsedPlan['duration'] = endDate.difference(startDate).inDays;
                  
                  // Calculate progress
                  final now = DateTime.now();
                  if (now.isBefore(startDate)) {
                    parsedPlan['progress'] = 0;
                  } else if (now.isAfter(endDate)) {
                    parsedPlan['progress'] = 100;
                  } else {
                    final totalDays = endDate.difference(startDate).inDays;
                    final daysPassed = now.difference(startDate).inDays;
                    parsedPlan['progress'] = (daysPassed / totalDays * 100).round();
                  }
                } catch (e) {
                  debugPrint('[MEAL_PLANS_SCREEN] Error calculating dates: $e');
                  parsedPlan['duration'] = 0;
                  parsedPlan['progress'] = 0;
                }
                
                // Set meal count
                if (parsedPlan['meals'] is List) {
                  parsedPlan['meal_count'] = (parsedPlan['meals'] as List).length;
                } else {
                  parsedPlan['meal_count'] = 0;
                }
                
                parsedMealPlans.add(parsedPlan);
                debugPrint('[MEAL_PLANS_SCREEN] Successfully parsed plan: ${parsedPlan['id']}');
              }
            } catch (e) {
              debugPrint('[MEAL_PLANS_SCREEN] Error parsing meal plan: $e');
              // Skip invalid plans
            }
          }

          if (mounted) {
            setState(() {
              _mealPlans = parsedMealPlans;
              debugPrint('[MEAL_PLANS_SCREEN] Loaded ${_mealPlans.length} meal plans');
            });
          }
        }
      } else {
        String errorMessage = 'Failed to load meal plans';
        try {
          final error = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = error['detail'] ?? error['message'] ?? errorMessage;
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('[MEAL_PLANS_SCREEN] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Meal Plans'),
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchMealPlans,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _mealPlans.isEmpty
                ? ListView(
                    children: [
                      Container(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.restaurant_menu_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No meal plans yet',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your meal plans will appear here',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _mealPlans.length,
                    itemBuilder: (context, index) {
                      final plan = _mealPlans[index];
                      debugPrint('[MEAL_PLANS_SCREEN] Meal plan $index: $plan');
                      return _buildMealPlanCard(plan);
                    },
                  ),
      ),
    );
  }

  Widget _buildMealPlanCard(Map<String, dynamic> plan) {
    final dateFormat = DateFormat('MMM d, y');
    String dateRange = '';
    try {
      final startDate = DateTime.parse(plan['start_date']);
      final endDate = DateTime.parse(plan['end_date']);
      dateRange = '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';
    } catch (e) {
      dateRange = 'Date not available';
    }

    // Get the first meal's image URL if available
    String? mealImageUrl;
    if (plan['meals'] is List && (plan['meals'] as List).isNotEmpty) {
      final firstMeal = (plan['meals'] as List).firstWhere(
        (meal) => meal is Map && meal['image_url'] != null,
        orElse: () => null,
      );
      if (firstMeal != null) {
        mealImageUrl = firstMeal['image_url'];
      }
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MealPlanDetailsScreen(mealPlan: plan),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section with gradient overlay
            Stack(
              children: [
                // Meal image
                SizedBox(
                  height: 150,
                  child: mealImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: mealImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
                          ),
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
                          ),
                        ),
                ),
                // Gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Plan name
                Positioned(
                  left: 16,
                  bottom: 16,
                  right: 16,
                  child: Text(
                    plan['plan_name']?.toString() ?? 'My Meal Plan',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          offset: const Offset(1, 1),
                          blurRadius: 3.0,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Details section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chef info
                  if (plan['chef_name'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: plan['chef_image'] != null
                                ? NetworkImage(plan['chef_image'])
                                : null,
                            child: plan['chef_image'] == null
                                ? const Icon(Icons.person, size: 12, color: Colors.grey)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'chef ${plan['chef_name']}',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Date range
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        dateRange,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Meal count and duration
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoChip(Icons.restaurant, '${plan['meal_count'] ?? 0} Meals'),
                      const SizedBox(width: 8),
                      _buildInfoChip(Icons.timelapse, '${plan['duration'] ?? 0} Days'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Progress',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            '${plan['progress'] ?? 0}%',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (plan['progress'] ?? 0) / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.green[400] ?? Colors.green,
                        ),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
