import 'package:flutter/material.dart';
import 'dart:math' as math; // For random duration (used in animation example)
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
// --- Detail Page Import Placeholder ---
// You MUST replace this with the actual import for your detail page
import 'nutri_detail.dart'; // Ensure this file exists and is correct

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
  final String? imagePath;
  final String? description;
  final double? price;

  NutritionItem({
    required this.name,
    this.imagePath,
    this.description,
    this.price,
  });

  factory NutritionItem.fromApi(Map<String, dynamic> json) {
    return NutritionItem(
      name: json['spice_name'] ?? 'Unknown',
      imagePath: json['image_url'],
      description: json['description'],
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : null,
    );
  }

  String get heroTag => imagePath ?? name;
}

// --- Main Page Widget ---
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _previousTabIndex = 0;
  List<NutritionItem> fetchedSpices = [];
  bool spicesLoading = false;
  String? spicesError;

  // (Keep hardcoded lists for other categories)
  final List<NutritionItem> spices = [ // legacy, will not be used

    NutritionItem(
        name: 'Turmeric',
        imagePath: 'assets/images/Tumeric powder.jpg',
        description: 'A spice known for its anti-inflammatory properties.',
        price: 4.99),
    NutritionItem(
        name: 'Ginger',
        imagePath: 'assets/images/Ginger powder.jpg',
        description: 'A root known for digestion and anti-nausea effects.',
        price: 2.99),
    NutritionItem(
        name: 'Cinnamon',
        imagePath: 'assets/images/Cinnamon powder.jpg',
        description: 'Known for its sweet flavor and health benefits.',
        price: 3.49),
    NutritionItem(
        name: 'Pepper',
        imagePath: 'assets/images/Whole black peppercorns.jpg',
        description: 'Common spice known to add heat to dishes.',
        price: 2.99),
    NutritionItem(
        name: 'Nutmeg',
        imagePath: 'assets/images/Nutmeg.jpg',
        description: 'A spice with a warm flavor, often used in baking.',
        price: 5.49),
    NutritionItem(
        name: 'Cardamom',
        imagePath: 'assets/images/Cardamom.jpg',
        description: 'A sweet and aromatic spice popular in Indian cuisine.',
        price: 6.99),
    NutritionItem(
        name: 'Cloves',
        imagePath: 'assets/images/Cloves.jpg',
        description:
            'Strongly aromatic, cloves are used in both savory and sweet dishes.',
        price: 4.49),
    NutritionItem(
        name: 'Oregano',
        imagePath: 'assets/images/Dry oregano.jpg',
        description: 'A herb widely used in Mediterranean cooking.',
        price: 3.99),
    NutritionItem(
        name: 'Rosemary',
        imagePath: 'assets/images/Rose mary spice.jpg',
        description: 'A fragrant herb often used with roasted meats.',
        price: 4.99),
    NutritionItem(
        name: 'Thyme',
        imagePath: 'assets/images/Thyme.jpg',
        description:
            'An herb known for its earthy flavor, used in various cuisines.',
        price: 3.79),
  ];

  final List<NutritionItem> supplements = [
    NutritionItem(
        name: 'Vitamin D',
        imagePath: 'assets/images/Multi vitamins.jpg',
        description: 'Essential for bone health and immune function.',
        price: 9.99),
    NutritionItem(
        name: 'Omega-3',
        imagePath: 'assets/images/Fish oils.jpg',
        description: 'Supports heart health and brain function.',
        price: 15.99),
    NutritionItem(
        name: 'Magnesium',
        imagePath: 'assets/images/Magnesium.jpg',
        description: 'Supports muscle and nerve function.',
        price: 12.49),
    NutritionItem(
        name: 'Zinc',
        imagePath: 'assets/images/Zinx.jpg',
        description: 'A mineral important for immune health.',
        price: 7.99),
    NutritionItem(
        name: 'Probiotics',
        imagePath: 'assets/images/Probiotic.jpg',
        description: 'Supports gut health and digestion.',
        price: 19.99),
    NutritionItem(
        name: 'Calcium',
        imagePath: 'assets/images/Calcium.jpg',
        description: 'Vital for bone health and muscle function.',
        price: 8.49),
    NutritionItem(
        name: 'Vitamin C',
        imagePath: 'assets/images/vitamin c.jpg',
        description: 'Antioxidant that supports the immune system.',
        price: 6.99),
    NutritionItem(
        name: 'Iron',
        imagePath: 'assets/images/Iorn.jpg',
        description: 'Essential for blood production and energy.',
        price: 10.49),
    NutritionItem(
        name: 'B-Complex',
        imagePath: 'assets/images/Multi vitamins.jpg',
        description: 'Supports energy metabolism and brain health.',
        price: 11.49),
    NutritionItem(
        name: 'CoQ10',
        imagePath: 'assets/images/Coenzyme Q10.jpg',
        description: 'Supports cardiovascular health and energy.',
        price: 14.99),
  ];

  final List<NutritionItem> herbals = [
    NutritionItem(
        name: 'Chamomile',
        imagePath: 'assets/images/chamomile.png',
        description: 'Known for its calming effects.',
        price: 5.99),
    NutritionItem(
        name: 'Peppermint',
        imagePath: 'assets/images/peppermint.png',
        description: 'Aids digestion and relieves headaches.',
        price: 4.49),
    NutritionItem(
        name: 'Echinacea',
        imagePath: 'assets/images/echinacea.png',
        description: 'Supports the immune system.',
        price: 8.99),
    NutritionItem(
        name: 'Ginseng',
        imagePath: 'assets/images/ginseng.png',
        description: 'An adaptogen that helps the body respond to stress.',
        price: 13.49),
    NutritionItem(
        name: 'Milk Thistle',
        imagePath: 'assets/images/milk_thistle.png',
        description: 'Known for liver support and detoxification.',
        price: 9.99),
    NutritionItem(
        name: 'Sage',
        imagePath: 'assets/images/sage.png',
        description: 'Aromatic herb with various medicinal properties.',
        price: 4.49),
    NutritionItem(
        name: 'Lavender',
        imagePath: 'assets/images/lavender.png',
        description: 'Used for relaxation and stress relief.',
        price: 7.49),
    NutritionItem(
        name: 'Aloe Vera',
        imagePath: 'assets/images/aloe_vera.png',
        description: 'Promotes skin health and digestion.',
        price: 6.49),
    NutritionItem(
        name: 'Tulsi (Holy Basil)',
        imagePath: 'assets/images/tulsi.png',
        description: 'An adaptogenic herb known for its health benefits.',
        price: 5.99),
    NutritionItem(
        name: 'Hibiscus',
        imagePath: 'assets/images/hibiscus.png',
        description: 'Rich in antioxidants, known for its refreshing tea.',
        price: 3.99),
  ];

  final List<NutritionItem> healthGadgets = [
    NutritionItem(
        name: 'Smart Scale',
        imagePath: 'assets/images/Weighing scale.jpg',
        description: 'Tracks weight and body composition.',
        price: 49.99),
    NutritionItem(
        name: 'Blood Pressure Monitor',
        imagePath: 'assets/images/Digital BP reader.jpg',
        description: 'Keeps track of blood pressure levels.',
        price: 39.99),
    NutritionItem(
        name: 'Fitness Tracker',
        imagePath: 'assets/images/Smart watch.jpg',
        description: 'Monitors activity and heart rate.',
        price: 99.99),
    NutritionItem(
        name: 'Smart Water Bottle',
        imagePath: 'assets/images/smart water bottle.jpg',
        description: 'Tracks hydration levels and reminds you to drink.',
        price: 29.99),
    NutritionItem(
        name: 'Sleep Tracker',
        imagePath: 'assets/images/sleep tracker.jpg',
        description: 'Monitors sleep patterns and quality.',
        price: 59.99),
    NutritionItem(
        name: 'Heart Rate Monitor',
        imagePath: 'assets/images/heart rate.jpg',
        description: 'Monitors heart rate during workouts.',
        price: 45.99),
    NutritionItem(
        name: 'Calorie Tracker',
        imagePath: 'assets/images/Smart watch.jpg',
        description: 'Tracks daily calorie intake and burns.',
        price: 24.99),
    NutritionItem(
        name: 'Posture Corrector',
        imagePath: 'assets/images/posture_corrector.jpg',
        description: 'Helps improve posture while sitting or standing.',
        price: 19.99),
    NutritionItem(
        name: 'Smartwatch',
        imagePath: 'assets/images/Smart watch.jpg',
        description: 'Combines fitness tracking with smartphone notifications.',
        price: 149.99),
    NutritionItem(
        name: 'Massage Gun',
        imagePath: 'assets/images/gun.jpg',
        description: 'Helps relieve muscle soreness and tension.',
        price: 89.99),
  ];

  final int _tabCount = 4; // Define number of tabs


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition+'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Spices'),
            Tab(text: 'Herbs'),
            Tab(text: 'Supplements'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCategoryGrid(fetchedSpices, context),
          _buildCategoryGrid(supplements, context),
          _buildCategoryGrid(herbals, context),
          _buildCategoryGrid(healthGadgets, context),
        ],
      ),
    );
  }

  Future<void> _fetchSpices() async {
    setState(() {
      spicesLoading = true;
      spicesError = null;
    });
    try {
      final String baseUrl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/spices'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(jsonDecode(response.body));
        final List<dynamic> spicesList = data['data'] ?? [];
        setState(() {
          fetchedSpices = spicesList.map((json) => NutritionItem.fromApi(json)).toList();
          spicesLoading = false;
        });
      } else {
        setState(() {
          spicesError = 'Failed to load spices (${response.statusCode})';
          spicesLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        spicesError = 'Error loading spices: $e';
        spicesLoading = false;
      });
    }
  }

  String? getDisplayImageUrl(String? url) {
    if (url == null) return null;
    final RegExp driveShare = RegExp(r'^https://drive.google.com/file/d/(.*?)/');
    final RegExp driveShare2 = RegExp(r'^https://drive.google.com/open\?id=(.*?)(&|#|\\s|\n|\r|\s|$)');
    final match = driveShare.firstMatch(url) ?? driveShare2.firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      final id = match.group(1);
      return 'https://drive.google.com/uc?export=view&id=$id';
    }
    return url;
  }

  Widget _buildCategoryGrid(List<NutritionItem> items, BuildContext context, {String? defaultItemImagePath}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 0),
      child: GridView.builder(
        physics: const ClampingScrollPhysics(),
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
            child: _buildItemCard(items[index], context, defaultItemImagePath: defaultItemImagePath),
          );
        },
      ),
    );
  }

  Widget _buildItemCard(NutritionItem item, BuildContext context, {String? defaultItemImagePath}) {
    final imageUrl = getDisplayImageUrl(item.imagePath);
    final borderRadius = BorderRadius.circular(15.0);
    final heroTag = item.heroTag;

    return Card(
      elevation: 3.0,
      shadowColor: Colors.grey.withAlpha(50),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: cardBackgroundColor,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: lightTeal.withAlpha(50),
          highlightColor: lightTeal.withAlpha(25),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Nutri_DetailPage(item: item),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Hero(
                  tag: heroTag,
                  flightShuttleBuilder: (
                    BuildContext flightContext,
                    Animation<double> animation,
                    HeroFlightDirection flightDirection,
                    BuildContext fromHeroContext,
                    BuildContext toHeroContext,
                  ) {
                    final Hero toHero = toHeroContext.widget as Hero;
                    return FadeTransition(
                      opacity: animation.drive(
                        Tween<double>(begin: 0.85, end: 1.0).chain(
                          CurveTween(curve: Curves.easeInOut),
                        ),
                      ),
                      child: toHero.child,
                    );
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(15.0)),
                      child: imageUrl != null && imageUrl.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 110,
                              placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  width: double.infinity,
                                  height: 110,
                                  color: Colors.white,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: errorIconColor,
                                    size: 40.0,
                                  ),
                                ),
                              ),
                            )
                          : (defaultItemImagePath != null
                              ? Image.asset(
                                  defaultItemImagePath,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: 110,
                                )
                              : Container(
                                  color: Colors.grey[200],
                                  width: double.infinity,
                                  height: 110,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: errorIconColor,
                                      size: 40.0,
                                    ),
                                  ),
                                )),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      item.price != null ? 'ugx ${item.price!.toStringAsFixed(2)}' : 'Price: N/A',
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
}
