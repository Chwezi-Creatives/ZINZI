import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../features/subscription/subscription_provider.dart';

// Color constants
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorBackground = Color(0xFFF8F8F8);

class ChooseMealPlanMealsScreen extends StatefulWidget {
  final int subscriptionId;
  final String subscriptionPlanName;

  const ChooseMealPlanMealsScreen({
    Key? key,
    required this.subscriptionId,
    required this.subscriptionPlanName,
  }) : super(key: key);

  @override
  _ChooseMealPlanMealsScreenState createState() =>
      _ChooseMealPlanMealsScreenState();
}

class _ChooseMealPlanMealsScreenState extends State<ChooseMealPlanMealsScreen>
    with SingleTickerProviderStateMixin {
  // API Configuration
  late final String apiBaseUrl;
  // Loading state
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingChefs = false;
  List<Map<String, dynamic>> _chefs = [];
  String? _selectedChefId;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allMeals = [];
  List<Map<String, dynamic>> _filteredMeals = [];
  final Set<String> _selectedMealIds = {};

  @override
  void initState() {
    super.initState();
    apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'https://api.zinzi.ug';
    _fetchChefs();
    _fetchMeals();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchChefs() async {
    if (_isLoadingChefs) return;

    setState(() {
      _isLoadingChefs = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.get(
        Uri.parse('$apiBaseUrl/rr/rchefs'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Handle both direct list and wrapped in 'data' key responses
        final List<dynamic> data = responseData is List
            ? responseData
            : (responseData['data'] as List? ?? []);

        setState(() {
          _chefs = List<Map<String, dynamic>>.from(data);
          if (_chefs.isNotEmpty) {
            _selectedChefId = _chefs.first['chefid']?.toString() ?? '';
            debugPrint(
                'Fetched chefs: ${_chefs.map((c) => '${c['name']} (${c['chefid']})').toList()}');
          } else {
            _selectedChefId = null;
            debugPrint('No chefs available');
          }
        });
      } else {
        throw Exception('Failed to load chefs');
      }
    } catch (e) {
      debugPrint('Error fetching chefs: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading chefs')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingChefs = false;
        });
      }
    }
  }

  Future<void> _fetchMeals() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final uri = Uri.parse('$apiBaseUrl/rr/meals');
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> mealsList = responseData['data'] ?? [];
        setState(() {
          _allMeals = List<Map<String, dynamic>>.from(mealsList);
          _filteredMeals = List<Map<String, dynamic>>.from(_allMeals);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load meals: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error fetching meals')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _processImagePath(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    return '$apiBaseUrl/storage/$imageUrl';
  }

  Future<void> _toggleMealSelection(String mealId) async {
    await HapticFeedback.selectionClick();

    setState(() {
      if (_selectedMealIds.contains(mealId)) {
        _selectedMealIds.remove(mealId);
      } else {
        _selectedMealIds.add(mealId);
      }
    });
  }

  Widget _buildMealCard(Map<String, dynamic> meal) {
    final mealId = meal['Meal_id']?.toString() ?? '';
    final isSelected = _selectedMealIds.contains(mealId);
    final imageUrl = _processImagePath(meal['Image_link']);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: kColorPrimary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _toggleMealSelection(mealId),
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // Meal image with selection overlay
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 100,
                            height: 100,
                            color: Colors.grey[200],
                            child: const Center(
                                child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 100,
                            height: 100,
                            color: Colors.grey[200],
                            child: const Icon(Icons.fastfood,
                                size: 40, color: Colors.grey),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: kColorPrimary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          meal['Meal_name'] ?? 'Unnamed Meal',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UGX ${meal['Price'] ?? 0}',
                          style: const TextStyle(
                            color: kColorPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Selection checkmark in top-right corner
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: kColorPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChefDropdown() {
    if (_isLoadingChefs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chefs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text('No chefs available'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: _selectedChefId,
        decoration: InputDecoration(
          labelText: 'Select Chef',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        items: _chefs.map<DropdownMenuItem<String>>((chef) {
          return DropdownMenuItem<String>(
            value: chef['chefid']?.toString() ?? '',
            child: Text(chef['name']?.toString() ?? 'Unnamed Chef'),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedChefId = value;
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a chef';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search meals...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        ),
        onChanged: (value) {
          setState(() {
            if (value.isEmpty) {
              _filteredMeals = List.from(_allMeals);
            } else {
              final searchLower = value.toLowerCase();
              _filteredMeals = _allMeals.where((meal) {
                return (meal['Meal_name']
                            ?.toString()
                            .toLowerCase()
                            .contains(searchLower) ??
                        false) ||
                    (meal['Meal_description']
                            ?.toString()
                            .toLowerCase()
                            .contains(searchLower) ??
                        false);
              }).toList();
            }
          });
        },
      ),
    );
  }

  Widget _buildMealGrid() {
    if (_isLoading && _allMeals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isLoadingChefs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredMeals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No meals found. Please try a different search.'),
        ),
      );
    }

    if (_filteredMeals.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No meals found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Try adjusting your search',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: _filteredMeals.length,
      itemBuilder: (context, index) {
        return _buildMealCard(_filteredMeals[index]);
      },
    );
  }

  Future<void> _saveMealPlan() async {
    if (_isSaving || _selectedMealIds.isEmpty) return;

    // Validate chef selection
    if (_selectedChefId == null || _selectedChefId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a chef')),
        );
      }
      return;
    }

    // Validate chef exists in the list
    try {
      final selectedChef = _chefs.firstWhere(
        (chef) => chef['chefid']?.toString() == _selectedChefId,
      );
      debugPrint(
          'Selected chef: ${selectedChef['name']} (${selectedChef['chefid']})');
    } catch (e) {
      debugPrint('Error finding selected chef: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Selected chef not found. Please try again.')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    debugPrint('[_saveMealPlan] Starting meal plan save process...');
    debugPrint('[_saveMealPlan] Selected meal IDs: $_selectedMealIds');
    debugPrint('[_saveMealPlan] Selected chef ID: $_selectedChefId');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      debugPrint('[_saveMealPlan] Getting user ID...');
      // Safely get user_id whether it's stored as int or string
      dynamic userId = prefs.get('user_id');
      debugPrint(
          '[_saveMealPlan] Raw user ID from prefs: $userId (type: ${userId.runtimeType})');

      if (userId == null) {
        final error = 'User not authenticated - user_id is null';
        debugPrint('[_saveMealPlan] ERROR: $error');
        throw Exception(error);
      }

      // Convert userId to int if it's a string
      final int userIdInt =
          userId is int ? userId : int.tryParse(userId.toString()) ?? 0;

      debugPrint('[_saveMealPlan] Processed user ID (int): $userIdInt');

      if (userIdInt == 0) {
        final error = 'Invalid user ID format: $userId';
        debugPrint('[_saveMealPlan] ERROR: $error');
        throw Exception(error);
      }

      debugPrint('[_saveMealPlan] Finding first selected meal...');
      // Get the first selected meal's chef ID (assuming all selected meals are from the same chef)
      final firstMeal = _allMeals.firstWhere(
        (meal) => _selectedMealIds.contains(meal['Meal_id']),
        orElse: () => <String, dynamic>{},
      );

      if (firstMeal.isEmpty) {
        final error = 'No valid meals found in _allMeals for selected IDs';
        debugPrint('[_saveMealPlan] ERROR: $error');
        debugPrint(
            '[_saveMealPlan] Available meal IDs in _allMeals: ${_allMeals.map((m) => m['Meal_id']).toList()}');
        throw Exception(error);
      }

      final chefId = int.tryParse(_selectedChefId!);
      if (chefId == null) {
        debugPrint('Invalid chef ID: $_selectedChefId');
        throw Exception('Invalid chef ID');
      }

      // Get subscription details to use the correct dates
      final subscriptionProvider =
          Provider.of<SubscriptionProvider>(context, listen: false);
      await subscriptionProvider.loadSubscriptionStatus();

      if (subscriptionProvider.subscriptionStatus == null ||
          subscriptionProvider.subscriptionStatus!['current_plan'] == null) {
        throw Exception(
            'Could not load subscription details. Please try again.');
      }

      final currentPlan =
          subscriptionProvider.subscriptionStatus!['current_plan'];

      // Parse subscription dates
      DateTime startDate;
      DateTime endDate;

      try {
        startDate = DateTime.parse(currentPlan['start_date'].toString());
        endDate = DateTime.parse(currentPlan['end_date'].toString());

        if (startDate.isAfter(endDate)) {
          throw Exception(
              'Invalid subscription dates: start date is after end date');
        }
      } catch (e) {
        debugPrint('Error parsing subscription dates: $e');
        // Fallback to current date + 1 month if there's an issue with subscription dates
        final now = DateTime.now();
        startDate = now;
        endDate = DateTime(now.year, now.month + 1, now.day);
      }

      // Format dates as YYYY-MM-DD without time
      final String formattedStartDate =
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final String formattedEndDate =
          '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

      debugPrint('[_saveMealPlan] Preparing API request with:');
      debugPrint('  - chefId: $chefId');
      debugPrint('  - subscriptionId: ${widget.subscriptionId}');
      debugPrint('  - startDate: $formattedStartDate');
      debugPrint('  - endDate: $formattedEndDate');
      debugPrint('  - selectedMealIds: $_selectedMealIds');

      final requestBody = {
        'user_id': userIdInt,
        'chefid': chefId,
        'subscription_id': widget.subscriptionId,
        'name': 'My Meal Plan',
        'start_date': formattedStartDate,
        'end_date': formattedEndDate,
        'meals': _selectedMealIds
            .map((mealId) => {
                  'meal_id': mealId,
                  'quantity':
                      1, // Default quantity to 1, can be made configurable
                })
            .toList(),
      };

      debugPrint('[_saveMealPlan] Request body: ${jsonEncode(requestBody)}');

      final url = '$apiBaseUrl/api/meal-plans';
      debugPrint('[_saveMealPlan] Sending POST request to: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      debugPrint('[_saveMealPlan] Response status: ${response.statusCode}');
      debugPrint('[_saveMealPlan] Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[_saveMealPlan] Meal plan saved successfully!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Meal plan saved successfully!')),
          );
          Navigator.of(context).pop(true); // Return success
        }
      } else {
        final error = json.decode(response.body);
        final errorMsg =
            'Failed to save meal plan: ${response.statusCode} - ${error['detail'] ?? response.body}';
        debugPrint('[_saveMealPlan] ERROR: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e, stackTrace) {
      debugPrint('[_saveMealPlan] EXCEPTION: $e');
      debugPrint('[_saveMealPlan] Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving meal plan: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      debugPrint('[_saveMealPlan] Save process completed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Meals'),
        backgroundColor: kColorPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchMeals();
              _fetchChefs();
            },
          ),
        ],
      ),
      body: _isLoading || _isLoadingChefs
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Section (fixed height)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Chef Selection Dropdown
                      _buildChefDropdown(),
                      const SizedBox(height: 16),
                      // Search Field
                      _buildSearchField(),
                    ],
                  ),
                ),

                // Meals Grid (scrollable)
                Expanded(
                  child: _buildMealGrid(),
                ),

                // Save Button (fixed at bottom)
                if (_selectedMealIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveMealPlan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kColorPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Save Meal Plan',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
              ],
            ),
    );
  }
}
