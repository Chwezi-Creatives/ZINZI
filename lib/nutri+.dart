import 'package:flutter/material.dart';
import 'dart:math' as math; // For random duration (used in animation example)

// --- Detail Page Import Placeholder ---
// You MUST replace this with the actual import for your detail page
import 'nutri_item_detail.dart'; // Ensure this file exists and is correct

// --- Color Constants ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color accentTeal = Color(0xFF009688); // Teal 500
const Color lightBackgroundColor = Color(0xFFF8F8F8); // Slightly off-white
const Color cardBackgroundColor = Colors.white;
const Color primaryTextColor = Color(0xFF333333); // Dark grey for text
const Color secondaryTextColor = Color(0xFF666666); // Lighter grey
const Color priceColor = primaryTeal;
const Color errorIconColor = Colors.grey;

// --- Nutrition Item Model ---
class NutritionItem {
  final String name;
  final String imagePath;
  final String description;
  final double price;

  NutritionItem({
    required this.name,
    required this.imagePath,
    required this.description,
    required this.price,
  });

  // Generate a potentially unique tag for Hero animation
  // If imagePath isn't guaranteed unique per item, use this:
  // String get heroTag => '$name-$imagePath';
  // If imagePath IS unique per item, this is simpler:
  String get heroTag => imagePath;
}


// --- Main Page Widget ---
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> with SingleTickerProviderStateMixin { // Add TickerProvider
  TabController? _tabController;
  int _previousTabIndex = 0; // To store the previous index for slide direction
  // --- Data Lists (Consider moving to a separate data service/provider) ---
  // (Data lists remain exactly as provided in your request)
  final List<NutritionItem> spices = [
      NutritionItem(name: 'Turmeric', imagePath: 'assets/images/Tumeric powder.jpg', description: 'A spice known for its anti-inflammatory properties.', price: 4.99),
      NutritionItem(name: 'Ginger', imagePath: 'assets/images/Ginger powder.jpg', description: 'A root known for digestion and anti-nausea effects.', price: 2.99),
      NutritionItem(name: 'Cinnamon', imagePath: 'assets/images/Cinnamon powder.jpg', description: 'Known for its sweet flavor and health benefits.', price: 3.49),
      NutritionItem(name: 'Pepper', imagePath: 'assets/images/Whole black peppercorns.jpg', description: 'Common spice known to add heat to dishes.', price: 2.99),
      NutritionItem(name: 'Nutmeg', imagePath: 'assets/images/Nutmeg.jpg', description: 'A spice with a warm flavor, often used in baking.', price: 5.49),
      NutritionItem(name: 'Cardamom', imagePath: 'assets/images/Cardamom.jpg', description: 'A sweet and aromatic spice popular in Indian cuisine.', price: 6.99),
      NutritionItem(name: 'Cloves', imagePath: 'assets/images/Cloves.jpg', description: 'Strongly aromatic, cloves are used in both savory and sweet dishes.', price: 4.49),
      NutritionItem(name: 'Oregano', imagePath: 'assets/images/Dry oregano.jpg', description: 'A herb widely used in Mediterranean cooking.', price: 3.99),
      NutritionItem(name: 'Rosemary', imagePath: 'assets/images/Rose mary spice.jpg', description: 'A fragrant herb often used with roasted meats.', price: 4.99),
      NutritionItem(name: 'Thyme', imagePath: 'assets/images/Thyme.jpg', description: 'An herb known for its earthy flavor, used in various cuisines.', price: 3.79),
    ];

    final List<NutritionItem> supplements = [
      NutritionItem(name: 'Vitamin D', imagePath: 'assets/images/Multi vitamins.jpg', description: 'Essential for bone health and immune function.', price: 9.99),
      NutritionItem(name: 'Omega-3', imagePath: 'assets/images/Fish oils.jpg', description: 'Supports heart health and brain function.', price: 15.99),
      NutritionItem(name: 'Magnesium', imagePath: 'assets/images/Magnesium.jpg', description: 'Supports muscle and nerve function.', price: 12.49),
      NutritionItem(name: 'Zinc', imagePath: 'assets/images/Zinx.jpg', description: 'A mineral important for immune health.', price: 7.99),
      NutritionItem(name: 'Probiotics', imagePath: 'assets/images/Probiotic.jpg', description: 'Supports gut health and digestion.', price: 19.99),
      NutritionItem(name: 'Calcium', imagePath: 'assets/images/Calcium.jpg', description: 'Vital for bone health and muscle function.', price: 8.49),
      NutritionItem(name: 'Vitamin C', imagePath: 'assets/images/vitamin c.jpg', description: 'Antioxidant that supports the immune system.', price: 6.99),
      NutritionItem(name: 'Iron', imagePath: 'assets/images/Iorn.jpg', description: 'Essential for blood production and energy.', price: 10.49),
      NutritionItem(name: 'B-Complex', imagePath: 'assets/images/Multi vitamins.jpg', description: 'Supports energy metabolism and brain health.', price: 11.49),
      NutritionItem(name: 'CoQ10', imagePath: 'assets/images/Coenzyme Q10.jpg', description: 'Supports cardiovascular health and energy.', price: 14.99),
    ];

    final List<NutritionItem> herbals = [
      NutritionItem(name: 'Chamomile', imagePath: 'assets/images/chamomile.png', description: 'Known for its calming effects.', price: 5.99),
      NutritionItem(name: 'Peppermint', imagePath: 'assets/images/peppermint.png', description: 'Aids digestion and relieves headaches.', price: 4.49),
      NutritionItem(name: 'Echinacea', imagePath: 'assets/images/echinacea.png', description: 'Supports the immune system.', price: 8.99),
      NutritionItem(name: 'Ginseng', imagePath: 'assets/images/ginseng.png', description: 'An adaptogen that helps the body respond to stress.', price: 13.49),
      NutritionItem(name: 'Milk Thistle', imagePath: 'assets/images/milk_thistle.png', description: 'Known for liver support and detoxification.', price: 9.99),
      NutritionItem(name: 'Sage', imagePath: 'assets/images/sage.png', description: 'Aromatic herb with various medicinal properties.', price: 4.49),
      NutritionItem(name: 'Lavender', imagePath: 'assets/images/lavender.png', description: 'Used for relaxation and stress relief.', price: 7.49),
      NutritionItem(name: 'Aloe Vera', imagePath: 'assets/images/aloe_vera.png', description: 'Promotes skin health and digestion.', price: 6.49),
      NutritionItem(name: 'Tulsi (Holy Basil)', imagePath: 'assets/images/tulsi.png', description: 'An adaptogenic herb known for its health benefits.', price: 5.99),
      NutritionItem(name: 'Hibiscus', imagePath: 'assets/images/hibiscus.png', description: 'Rich in antioxidants, known for its refreshing tea.', price: 3.99),
    ];

    final List<NutritionItem> healthGadgets = [
      NutritionItem(name: 'Smart Scale', imagePath: 'assets/images/Weighing scale.jpg', description: 'Tracks weight and body composition.', price: 49.99),
      NutritionItem(name: 'Blood Pressure Monitor', imagePath: 'assets/images/Digital BP reader.jpg', description: 'Keeps track of blood pressure levels.', price: 39.99),
      NutritionItem(name: 'Fitness Tracker', imagePath: 'assets/images/Smart watch.jpg', description: 'Monitors activity and heart rate.', price: 99.99),
      NutritionItem(name: 'Smart Water Bottle', imagePath: 'assets/images/smart water bottle.jpg', description: 'Tracks hydration levels and reminds you to drink.', price: 29.99),
      NutritionItem(name: 'Sleep Tracker', imagePath: 'assets/images/sleep tracker.jpg', description: 'Monitors sleep patterns and quality.', price: 59.99),
      NutritionItem(name: 'Heart Rate Monitor', imagePath: 'assets/images/heart rate.jpg', description: 'Monitors heart rate during workouts.', price: 45.99),
      NutritionItem(name: 'Calorie Tracker', imagePath: 'assets/images/Smart watch.jpg', description: 'Tracks daily calorie intake and burns.', price: 24.99),
      NutritionItem(name: 'Posture Corrector', imagePath: 'assets/images/posture_corrector.jpg', description: 'Helps improve posture while sitting or standing.', price: 19.99),
      NutritionItem(name: 'Smartwatch', imagePath: 'assets/images/Smart watch.jpg', description: 'Combines fitness tracking with smartphone notifications.', price: 149.99),
      NutritionItem(name: 'Massage Gun', imagePath: 'assets/images/gun.jpg', description: 'Helps relieve muscle soreness and tension.', price: 89.99),
    ];

  final int _tabCount = 4; // Define number of tabs

  @override
  void initState() {
    super.initState();
    // Initialize the TabController explicitly
    _tabController = TabController(length: _tabCount, vsync: this);
    // Add listener to trigger rebuilds for AnimatedSwitcher
    _tabController!.addListener(() {
      // Store previous index before updating state for the animation
      final newIndex = _tabController!.index;
      if (mounted && !_tabController!.indexIsChanging && newIndex != _previousTabIndex) {
        setState(() {
          // Update previous index *after* the build triggered by setState
          _previousTabIndex = newIndex;
        });
      }
    });
  }

  @override
  @override
  void dispose() {
    // Dispose the explicitly created controller
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Remove DefaultTabController wrapper
    return Scaffold(
      backgroundColor: lightBackgroundColor, // Clean background
      appBar: AppBar(
        title: const Text(
          'Nutrition +',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        elevation: 1.0,
        bottom: TabBar(
          controller: _tabController, // Pass the explicit controller
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          indicatorColor: Colors.white,
          indicatorWeight: 3.0,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
          labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          unselectedLabelStyle: const TextStyle(fontSize: 14.0),
          tabs: const [
            Tab(text: 'Spices'),
            Tab(text: 'Supplements'),
            Tab(text: 'Herbals'),
            Tab(text: 'Gadgets'),
          ],
        ),
      ),
      // Use AnimatedSwitcher for fade effect
      body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300), // Fade duration
                transitionBuilder: (Widget child, Animation<double> animation) {
                  // Combine Scale and Fade
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation), // Scale from 90% to 100%
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentTabContent(), // Build content based on index
              ), // End AnimatedSwitcher
    ); // End Scaffold
// Removed extra closing parenthesis and semicolon
  }

// Removed the original _buildCategoryGrid definition here.
// The new definition below (which accepts a Key) will be used.

  // Builds a single item card with Hero animation and optional default image
  Widget _buildItemCard(NutritionItem item, BuildContext context, {String? defaultImagePath}) {
    final borderRadius = BorderRadius.circular(15.0);
    final heroTag = item.heroTag; // Get tag from the model getter

    return Card(
      elevation: 3.0,
      shadowColor: Colors.grey.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: cardBackgroundColor,
      child: Material( // Needed for InkWell clipping
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: lightTeal.withOpacity(0.3), // Add splash feedback
          highlightColor: lightTeal.withOpacity(0.1), // Add highlight feedback
          onTap: () {
            Navigator.push(
              context,
              // Use standard MaterialPageRoute for potentially more robust navigation
              MaterialPageRoute(
                builder: (context) => NutritionItemDetailPage(item: item),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Image Section with Hero ---
              Expanded(
                flex: 3, // Give image more visual weight
                child: Hero(
                  tag: heroTag, // Unique tag for the animation
                  // Custom flight shuttle for smoother scaling/fading
                  flightShuttleBuilder: (
                    BuildContext flightContext,
                    Animation<double> animation,
                    HeroFlightDirection flightDirection,
                    BuildContext fromHeroContext,
                    BuildContext toHeroContext,
                  ) {
                    final Hero toHero = toHeroContext.widget as Hero;
                    // Fade slightly during transition
                    return FadeTransition(
                         opacity: animation.drive(
                           Tween<double>(begin: 0.85, end: 1.0).chain( // Start slightly less transparent
                             CurveTween(curve: Curves.easeInOut)
                           )
                         ),
                         child: toHero.child, // Animate the destination Hero's child
                    );
                  },
                  child: Material(
                    type: MaterialType.transparency, // Avoid double background issues
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(15.0)),
                      child: Image.asset(
                        item.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                          // Use defaultImagePath if provided, otherwise show icon
                          if (defaultImagePath != null && defaultImagePath.isNotEmpty) {
                            return Image.asset(
                              defaultImagePath,
                              fit: BoxFit.cover, // Or adjust fit as needed for default
                              // Optional: Add another error builder for the default image itself
                              errorBuilder: (ctx, err, st) => Container(
                                color: Colors.grey[200],
                                child: const Center(child: Icon(Icons.error_outline, color: errorIconColor, size: 40.0)),
                              ),
                            );
                          } else {
                            // Fallback to generic icon if no default path
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: errorIconColor,
                                  size: 40.0,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // --- Text Section ---
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600, // Slightly bolder
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0), // Consistent spacing
                    Text(
                      '\$${item.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: priceColor,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to get the content for the currently selected tab
  Widget _buildCurrentTabContent() {
    // Ensure controller is not null before accessing index
    final index = _tabController?.index ?? 0;
    // Use ValueKey to ensure AnimatedSwitcher detects child change
    switch (index) {
      case 0:
        return _buildCategoryGrid(spices, context, key: const ValueKey('spices'));
      case 1:
        return _buildCategoryGrid(supplements, context, key: const ValueKey('supplements'));
      case 2:
        // Pass the default image path for herbals
        return _buildCategoryGrid(herbals, context, key: const ValueKey('herbals'), defaultItemImagePath: 'assets/images/DrugRG.png');
      case 3:
        return _buildCategoryGrid(healthGadgets, context, key: const ValueKey('gadgets'));
      default:
        return Container(); // Should not happen
    }
  }

  // Modify _buildCategoryGrid to accept an optional Key and defaultItemImagePath
  Widget _buildCategoryGrid(List<NutritionItem> items, BuildContext context, {Key? key, String? defaultItemImagePath}) {
    final String categoryKey = items.isNotEmpty ? items[0].name : math.Random().nextDouble().toString();

    return Padding(
      key: key, // Assign the key here
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
      child: GridView.builder(
        key: PageStorageKey<String>(categoryKey), // Keep key for scroll position preservation
        physics: const ClampingScrollPhysics(), // Change to ClampingScrollPhysics
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12.0,
          mainAxisSpacing: 12.0,
          childAspectRatio: 0.80,
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) {
          return AnimatedOpacity(
             opacity: 1.0,
             duration: Duration(milliseconds: 400 + (index % 5 * 100)),
             curve: Curves.easeOut,
             // Pass the default image path down to the item card
             child: _buildItemCard(items[index], context, defaultImagePath: defaultItemImagePath),
          );
        },
      ),
    );
  }
}