import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import the subscription provider
import '../subscription/subscription_provider.dart';

// App color constants
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorBackground = Color(0xFFF8F8F8);
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary = Color(0xFF757575);
const Color kColorAccent = Color(0xFF00BFA5);
const Color kColorError = Color(0xFFD32F2F);
const Color kColorSuccess = Color(0xFF388E3C);

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
    with TickerProviderStateMixin {
  // Flag to control dropdown border visibility
  static const bool _showDropdownBorder = false; // Set to false to hide border
  // Animation controller for tap effects
  late final AnimationController _animationController;

  // Animation controller for save button
  late final AnimationController _saveButtonController;
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

  void _filterMeals() {
    final searchTerm = _searchController.text.toLowerCase();

    setState(() {
      if (searchTerm.isEmpty) {
        _filteredMeals = List.from(_allMeals);
      } else {
        _filteredMeals = _allMeals.where((meal) {
          return (meal['Meal_name']
                      ?.toString()
                      .toLowerCase()
                      .contains(searchTerm) ??
                  false) ||
              (meal['Meal_description']
                      ?.toString()
                      .toLowerCase()
                      .contains(searchTerm) ??
                  false);
        }).toList();
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationController.reverse();
        }
      });

    _saveButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    // Animation for save button press effect
    final saveButtonScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _saveButtonController,
      curve: Curves.easeInOut,
    ));

    // Add listener to handle button press animation
    _saveButtonController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _saveButtonController.reverse();
      }
    });

    apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'https://api.zinzi.ug';
    _fetchChefs();
    _fetchMeals();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _saveButtonController.dispose();
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
          _selectedChefId = null; // No default selection
          debugPrint(
              'Fetched chefs: ${_chefs.map((c) => '${c['name']} (${c['chefid']})').toList()}');
          if (_chefs.isEmpty) {
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
    final mealName = meal['Meal_name']?.toString() ?? 'Unnamed Meal';

    // Animation controller for the card
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return GestureDetector(
          onTapDown: (_) {
            // Scale down animation when pressed
            _animationController.forward();
            _toggleMealSelection(mealId);
          },
          onTapUp: (_) => _animationController.reverse(),
          onTapCancel: () => _animationController.reverse(),
          child: Transform.scale(
            scale: isSelected ? 0.95 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              transform: Matrix4.identity()
                ..scale(_animationController.value * 0.05 + 0.95),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(
                        0.05 + (_animationController.value * 0.05)),
                    blurRadius: 4 + (_animationController.value * 2),
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isSelected
                    ? Border.all(color: kColorPrimary, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Image with selection overlay
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Meal Image
                        Hero(
                          tag: 'meal-image-$mealId',
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        kColorPrimary),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.fastfood,
                                    color: Colors.grey),
                              ),
                            ),
                          ),
                        ),

                        // Selection Overlay
                        AnimatedOpacity(
                          opacity: isSelected ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kColorPrimary.withOpacity(0.4),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Meal Name
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        height: 1.2,
                        color: isSelected
                            ? kColorPrimary
                            : const Color(0xFF424242),
                      ),
                      child: Text(
                        mealName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChefDropdown() {
    if (_chefs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: DropdownButtonFormField<String>(
        value: _selectedChefId,
        isDense: true,
        dropdownColor: Colors.white,
        iconEnabledColor: Colors.teal,
        decoration: InputDecoration(
          labelText: 'Chef',
          labelStyle:
              const TextStyle(fontSize: 13, height: 1.0, color: Colors.teal),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          border: _showDropdownBorder
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: Colors.teal.shade300),
                )
              : InputBorder.none,
          enabledBorder: _showDropdownBorder
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: Colors.teal.shade300),
                )
              : InputBorder.none,
          focusedBorder: _showDropdownBorder
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                )
              : InputBorder.none,
          filled: true,
          fillColor: Colors.grey[100], // Match search field color
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 13, height: 1.2, color: Colors.teal),
        icon: const Icon(Icons.arrow_drop_down, size: 20),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('All Chefs',
                style: TextStyle(fontSize: 13, color: Colors.teal)),
          ),
          ..._chefs.map<DropdownMenuItem<String>>((chef) {
            return DropdownMenuItem<String>(
              value: chef['chefid']?.toString(),
              child: Text(
                chef['name']?.toString() ?? 'Unnamed Chef',
                style: const TextStyle(fontSize: 13, color: Colors.teal),
              ),
            );
          }).toList(),
        ],
        onChanged: (value) {
          setState(() {
            _selectedChefId = value;
            _filterMeals();
          });
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13, height: 1.2),
        decoration: InputDecoration(
          hintText: 'Search meals...',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          isDense: true,
        ),
        onChanged: (value) {
          _filterMeals();
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No meals found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75, // Slightly taller cards
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
    if (_isSaving) return;

    if (_selectedMealIds.isEmpty) {
      await _showErrorFeedback();
      return;
    }

    // Validate chef selection
    if (_selectedChefId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a chef')),
      );
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

      // Get subscription provider from context
      final subscriptionProvider = Provider.of<SubscriptionProvider>(
        context,
        listen: false,
      );
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

  Future<void> _showErrorFeedback() async {
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Trigger haptic feedback
    HapticFeedback.lightImpact();

    // Show error message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one meal'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }

    // Play shake animation
    await animationController.forward();
    await animationController.reverse();
    animationController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Choose Meals',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: kColorPrimary,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        elevation: 0,
        toolbarHeight: 48,
      ),
      // Floating Action Button for saving
      floatingActionButton: _selectedMealIds.isNotEmpty
          ? Container(
              height: 40, // Reduced height
              margin:
                  const EdgeInsets.only(bottom: 16), // Add some bottom margin
              child: FloatingActionButton.extended(
                onPressed: _isSaving ? null : _saveMealPlan,
                backgroundColor: kColorPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(20), // More compact border radius
                ),
                label: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Save (${_selectedMealIds.length})',
                        style: const TextStyle(
                          color: Colors.white, // Explicit white text
                          fontSize: 13, // Slightly smaller font
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                icon: _isSaving
                    ? const SizedBox.shrink()
                    : const Icon(Icons.check,
                        size: 18, color: Colors.white), // White icon
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _isLoading || _isLoadingChefs
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Compact Header Section
                Container(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildChefDropdown()),
                          const SizedBox(width: 8),
                          Expanded(child: _buildSearchField()),
                        ],
                      ),
                    ],
                  ),
                ),

                // Meals Grid (scrollable)
                Expanded(
                  child: _buildMealGrid(),
                ),
              ],
            ),
    );
  }
}
