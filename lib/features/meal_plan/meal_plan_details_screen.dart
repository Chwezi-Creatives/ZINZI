import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class MealPlanDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> mealPlan;

  const MealPlanDetailsScreen({
    Key? key,
    required this.mealPlan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y');
    final startDate = DateTime.parse(mealPlan['start_date']);
    final endDate = DateTime.parse(mealPlan['end_date']);
    final duration = endDate.difference(startDate).inDays;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
        title: Text(
          mealPlan['plan_name']?.toString() ?? 'Meal Plan Details',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
        
          ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with image and basic info
            _buildHeaderSection(context, dateFormat, startDate, endDate, duration),
            
            // Meals list section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Meals (${mealPlan['meal_count'] ?? 0})\n',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            // Meals grid
            _buildMealsGrid(),
            
            // Additional details
            _buildDetailsSection(),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context, DateFormat dateFormat, 
      DateTime startDate, DateTime endDate, int duration) {
    return Stack(
      children: [
        // Meal plan image
        SizedBox(
          height: 200,
          width: double.infinity,
          child: _buildMealPlanImage(),
        ),
        
        // Gradient overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
          ),
        ),
        
        // Plan info
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mealPlan['plan_name']?.toString() ?? 'Meal Plan',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
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
              const SizedBox(height: 4),
              Text(
                '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)} • $duration days',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [
                    Shadow(
                      offset: const Offset(1, 1),
                      blurRadius: 3.0,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMealPlanImage() {
    // Try to get the first meal's image
    String? imageUrl;
    if (mealPlan['meals'] is List && (mealPlan['meals'] as List).isNotEmpty) {
      final firstMeal = (mealPlan['meals'] as List).firstWhere(
        (meal) => meal is Map && meal['image_url'] != null,
        orElse: () => null,
      );
      if (firstMeal != null) {
        imageUrl = firstMeal['image_url'];
      }
    }

    return CachedNetworkImage(
      imageUrl: imageUrl ?? '',
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.restaurant_menu, size: 50, color: Colors.grey),
      ),
    );
  }

  Widget _buildMealsGrid() {
    final meals = mealPlan['meals'] is List ? (mealPlan['meals'] as List) : [];
    
    if (meals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text('No meals in this plan')),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: meals.length,
      itemBuilder: (context, index) {
        final meal = meals[index];
        return _buildMealCard(meal);
      },
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Meal image
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: meal['image_url'] ?? '',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.restaurant_menu, size: 30, color: Colors.grey),
                ),
              ),
            ),
          ),
          // Meal name
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              meal['name']?.toString() ?? 'Unnamed Meal',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan Details',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailItem(Icons.calendar_today, 'Duration', '${mealPlan['duration'] ?? 0} days'),
          _buildDetailItem(Icons.restaurant, 'Total Meals', '${mealPlan['meal_count'] ?? 0}'),
          if (mealPlan['chef_name'] != null)
            _buildDetailItem(Icons.person, 'Chef', mealPlan['chef_name']),
          _buildDetailItem(Icons.timelapse, 'Progress', '${mealPlan['progress'] ?? 0}% complete'),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
