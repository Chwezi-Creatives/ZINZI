import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class ChefPremiumPlansScreen extends StatefulWidget {
  const ChefPremiumPlansScreen({Key? key}) : super(key: key);

  @override
  _ChefPremiumPlansScreenState createState() => _ChefPremiumPlansScreenState();
}

class _ChefPremiumPlansScreenState extends State<ChefPremiumPlansScreen> {
  List<dynamic> _premiumPlans = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchPremiumPlans();
  }

  Future<void> _fetchPremiumPlans() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    debugPrint('🔍 [PremiumPlans] Starting to fetch premium plans');
    try {
      final prefs = await SharedPreferences.getInstance();
      final chefId = prefs.getString('user_id');
      final token = prefs.getString('auth_token');
      final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';
      final url = '$baseUrl/api/chefs/$chefId/meal-plans';
      debugPrint('🌐 [PremiumPlans] Making request to: $url');
      debugPrint('🔑 [PremiumPlans] Using chefId: $chefId');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      debugPrint('📡 [PremiumPlans] Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        debugPrint('📦 [PremiumPlans] Raw response body: $responseBody');
        final data = jsonDecode(responseBody);
        debugPrint('📊 [PremiumPlans] Parsed data type: ${data.runtimeType}');
        // Parse the meals field from JSON string to List<dynamic>
        final parsedPlans = (data as List).map((plan) {
          if (plan is Map<String, dynamic> && plan['meals'] is String) {
            try {
              plan['meals'] = jsonDecode(plan['meals']);
            } catch (e) {
              debugPrint('⚠️ [PremiumPlans] Error parsing meals: $e');
              plan['meals'] = [];
            }
          }
          // Add fallbacks for missing fields
          plan['status'] = plan['status'] ?? 'UNKNOWN'; // Fallback for status
          plan['meal_count'] = plan['meal_count'] ?? plan['meals'].length; // Fallback for meal_count
          plan['duration'] = plan['duration'] ?? 0; // Fallback for duration
          return plan;
        }).toList();
        if (mounted) {
          setState(() {
            _premiumPlans = parsedPlans;
            _isLoading = false;
            debugPrint('✅ [PremiumPlans] Loaded ${_premiumPlans.length} premium plans');
          });
        }
      } else {
        debugPrint('❌ [PremiumPlans] API Error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to load premium plans: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading premium plans: ${e.toString()}';
          debugPrint('⚠️ [PremiumPlans] Error: ${e.toString()}');
          if (e is Error) {
            debugPrint('🔄 [PremiumPlans] Stack trace: ${e.stackTrace}');
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Premium Customers',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    debugPrint('📱 ========== BUILDING PREMIUM PLANS UI ==========');
    debugPrint('   🔄 Loading: $_isLoading');
    debugPrint('   ❌ Error: ${_errorMessage.isNotEmpty ? _errorMessage : "None"}');
    debugPrint('   📊 Plan count: ${_premiumPlans.length}');
    debugPrint('   📝 Plans data: ${_premiumPlans.take(1).map((p) => {
      'id': p['id'],
      'name': p['plan_name'],
      'user': p['user_name'],
      'meals_count': p['meal_count']
    })}${_premiumPlans.length > 1 ? '...' : ''}');
    if (_isLoading) {
      debugPrint('⏳ [PremiumPlans] Showing loading indicator');
      debugPrint('   ℹ️ Plans data not yet loaded');
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      debugPrint('❌ [PremiumPlans] Showing error message');
      debugPrint('   Error details: $_errorMessage');
      debugPrint('   Plan count at error: ${_premiumPlans.length}');
      if (_premiumPlans.isNotEmpty) {
        debugPrint('   First plan ID: ${_premiumPlans.first['id']}');
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage,
            style: GoogleFonts.poppins(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_premiumPlans.isEmpty) {
      debugPrint('ℹ️ [PremiumPlans] No premium plans to display');
      debugPrint('   Last fetch status: ${_errorMessage.isNotEmpty ? 'Failed' : 'Succeeded but empty'}');
      debugPrint('   Loading state: $_isLoading');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No premium customers yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchPremiumPlans,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _premiumPlans.length,
        itemBuilder: (context, index) {
          return _buildPlanCard(_premiumPlans[index]);
        },
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    debugPrint('🔄 [PremiumPlans] Building plan card for plan: ${plan['id']}');
    // Safely get user name from direct fields (not nested)
    final userName = plan['user_name']?.toString() ?? 'Unknown User';
    debugPrint('   👤 User: $userName');
    // Safely format date range
    final dateFormat = DateFormat('MMM d, y');
    String dateRange = 'Date not available';
    try {
      if (plan['start_date'] != null && plan['end_date'] != null) {
        final startDate = DateTime.parse(plan['start_date'].toString());
        final endDate = DateTime.parse(plan['end_date'].toString());
        dateRange = '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';
      }
    } catch (e) {
      debugPrint('⚠️ [PremiumPlans] Error parsing dates: $e');
    }
    debugPrint('   📅 Date range: $dateRange');
    // Parse meals from JSON string
    List<dynamic> meals = [];
    try {
      if (plan['meals'] != null) {
        if (plan['meals'] is String) {
          // Parse the JSON string
          meals = jsonDecode(plan['meals']) as List<dynamic>;
        } else if (plan['meals'] is List) {
          meals = plan['meals'] as List<dynamic>;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PremiumPlans] Error parsing meals: $e');
    }
    final mealCount = plan['meal_count'] ?? meals.length; // Use fallback meal_count
    final duration = plan['duration'] ?? 0; // Use fallback duration
    debugPrint('   🍽️ Meals in plan: $mealCount');
    if (meals.isNotEmpty) {
      for (var i = 0; i < meals.length; i++) {
        final meal = meals[i];
        debugPrint('      ${i + 1}. ${meal['name'] ?? 'Unnamed Meal'} (ID: ${meal['meal_id'] ?? 'N/A'})');
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Customer info header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: plan['customer']?['profile_image'] != null
                      ? NetworkImage(plan['customer']['profile_image'])
                      : null,
                  child: plan['customer']?['profile_image'] == null
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['plan_name'] ?? 'Unnamed Plan',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      if (userName.isNotEmpty)
                        Text(
                          'For: $userName',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Premium',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Plan details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status and date range
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateRange,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(plan['status']),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getStatusText(plan['status']),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Meal count and status
                Row(
                  children: [
                    _buildInfoChip(
                      Icons.restaurant,
                      '${mealCount} Meals',
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.timelapse,
                      '${duration} Days',
                    ),
                    const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return const Color(0xFF2E7D32); // Green
      case 'pending':
        return const Color(0xFFF57C00); // Orange
      case 'completed':
        return const Color(0xFF1976D2); // Blue
      case 'cancelled':
        return const Color(0xFFC62828); // Red
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    return status?.toUpperCase() ?? 'UNKNOWN';
  }
}