import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../utils/debouncer.dart';

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
  static const int _mealsPerPage = 20;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSaving = false;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));
  final Map<String, AnimationController> _animationControllers = {};

  // State variables
  List<Map<String, dynamic>> _allMeals = [];
  List<Map<String, dynamic>> _filteredMeals = [];
  List<Map<String, dynamic>> _chefs = [];
  Map<String, dynamic>? _selectedChef;
  final Set<String> _selectedMealIds = {};

  @override
  void initState() {
    super.initState();
    apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'https://api.zinzi.ug';
    _loadInitialData();
    _setupScrollListener();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debouncer.cancel();
    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    _animationControllers.clear();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _loadMoreMeals();
      }
    });
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoading = true);
      await Future.wait([
        _fetchMeals(),
        _fetchChefs(),
      ]);
    } catch (e) {
      final errorMessage = 'Failed to load data: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchMeals({bool loadMore = false}) async {
    if ((loadMore && !_hasMore) || _isLoadingMore) return;

    setState(() => loadMore ? _isLoadingMore = true : _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final params = {
        'page': loadMore ? _currentPage + 1 : 1,
        'per_page': _mealsPerPage.toString(),
        if (_selectedChef != null) 'chef_id': _selectedChef!['id'].toString(),
        'search': _searchController.text,
      }..removeWhere((key, value) => value == null);

      final uri = Uri.parse('$apiBaseUrl/api/meals').replace(
        queryParameters: params,
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> meals = data['data'] ?? [];
        
        setState(() {
          if (loadMore) {
            _allMeals.addAll(meals.cast<Map<String, dynamic>>());
            _currentPage++;
          } else {
            _allMeals = meals.cast<Map<String, dynamic>>();
            _currentPage = 1;
          }
          _filteredMeals = List.from(_allMeals);
          _hasMore = (data['meta']?['next_page_url'] ?? null) != null;
        });
      } else {
        throw Exception('Failed to load meals');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading meals: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _fetchChefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/chefs'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _chefs = List<Map<String, dynamic>>.from(data['data'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading chefs: $e');
    }
  }

  Future<void> _loadMoreMeals() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchMeals(loadMore: true);
  }

  Future<void> _saveMealPlan() async {
    if (_selectedMealIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one meal')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/subscriptions/${widget.subscriptionId}/meals'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'meal_ids': _selectedMealIds.toList(),
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop(true); // Return success
        }
      } else {
        throw Exception('Failed to save meal plan');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving meal plan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _filterMeals(String query) {
    _debouncer.run(() {
      setState(() {
        if (query.isEmpty) {
          _filteredMeals = List.from(_allMeals);
        } else {
          _filteredMeals = _allMeals.where((meal) {
            final name = meal['name']?.toString().toLowerCase() ?? '';
            final description = meal['description']?.toString().toLowerCase() ?? '';
            final searchTerm = query.toLowerCase();
            return name.contains(searchTerm) || description.contains(searchTerm);
          }).toList();
        }
      });
    });
  }

  String _processImagePath(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    return '$apiBaseUrl/storage/$imageUrl';
  }

  Future<void> _toggleMealSelection(String mealId) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    
    setState(() {
      if (_selectedMealIds.contains(mealId)) {
        _selectedMealIds.remove(mealId);
      } else {
        _selectedMealIds.add(mealId);
      }
    });
  }

  Widget _buildChefDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        value: _selectedChef,
        decoration: InputDecoration(
          labelText: 'Filter by Chef',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        items: [
          const DropdownMenuItem(
            value: null,
            child: Text('All Chefs'),
          ),
          ..._chefs.map((chef) {
            return DropdownMenuItem(
              value: chef,
              child: Text(chef['name'] ?? 'Unknown Chef'),
            );
          }).toList(),
        ],
        onChanged: (chef) {
          setState(() {
            _selectedChef = chef;
            _fetchMeals();
          });
        },
      ),
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal) {
    final mealId = meal['id']?.toString() ?? '';
    final isSelected = _selectedMealIds.contains(mealId);
    final imageUrl = _processImagePath(meal['image_url']);
    final price = meal['price'] is num ? (meal['price'] as num).toDouble() : 0.0;
    final rating = meal['rating']?.toDouble() ?? 0.0;
    final restrictions = (meal['dietary_restrictions'] as List<dynamic>?)?.cast<String>() ?? [];

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
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 100,
                            height: 100,
                            color: Colors.grey[200],
                            child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                meal['name'] ?? 'Unnamed Meal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rating > 0) ...[
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UGX ${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: kColorPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (restrictions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: restrictions.take(2).map((restriction) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green[100]!),
                              ),
                              child: Text(
                                restriction,
                                style: TextStyle(
                                  color: Colors.green[800],
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )).toList(),
                          ),
                        ],
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search meals...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterMeals('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        onChanged: _filterMeals,
      ),
    );
  }

  Widget _buildMealGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: _filteredMeals.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _filteredMeals.length) {
          if (!_isLoadingMore) {
            _loadMoreMeals();
          }
          return const Center(child: CircularProgressIndicator());
        }
        return _buildMealCard(_filteredMeals[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose Meals - ${widget.subscriptionPlanName}'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading && _filteredMeals.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchField(),
                _buildChefDropdown(),
                Expanded(
                  child: _filteredMeals.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.fastfood,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No meals found',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Try adjusting your search or filters',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : _buildMealGrid(),
                ),
                if (_isLoadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
      floatingActionButton: _selectedMealIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveMealPlan,
              label: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Save Selection'),
              icon: const Icon(Icons.save),
            )
          : null,
    );
  }
}
