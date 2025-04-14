import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:zinzi2/allmeals.dart';
// import 'package:zinzi2/checkout.dart'; // Assuming not directly needed here
// import 'package:zinzi2/reco.dart'; // Assuming not directly needed here
// import 'package:zinzi2/repeat.dart'; // Assuming not directly needed here
import 'package:zinzi2/cart.dart' as cart; // Use prefix
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For cached network images
import 'package:google_fonts/google_fonts.dart'; // For custom fonts
import 'package:shimmer/shimmer.dart'; // For loading effect
import 'dart:async'; // For Timer, Future
import 'dart:math'; // For min

// --- Color Constants (Import or define) ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Clean background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
// Shimmer Colors
final Color kShimmerBaseColor = Colors.grey.shade300;
final Color kShimmerHighlightColor = Colors.grey.shade100;
// --- End Color Constants ---

final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// --- Chef List Screen (Remains largely the same, only minor style updates) ---
class ChooseChefNetwork extends StatefulWidget {
  const ChooseChefNetwork({super.key}); // Use const constructor

  @override
  _ChooseChefNetworkState createState() => _ChooseChefNetworkState();
}

class _ChooseChefNetworkState extends State<ChooseChefNetwork> {
  List<dynamic> chefs = [];
  bool isLoading = true;
  String? fetchError; // Store fetch error message

  @override
  void initState() {
    super.initState();
    fetchChefs();
  }

  Future<void> fetchChefs() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      fetchError = null; // Reset error
    });
    final url = '$apiBaseUrl/rr/rchefs';
    print("Fetching Chefs from URL: $url");

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (!mounted) return; // Check after await

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        // Adjusted extraction logic for flexibility
        final List<dynamic>? chefsList = responseData.containsKey('data') && responseData['data'] is List
             ? responseData['data']
             : responseData.containsKey('chefs') && responseData['chefs'] is List
                 ? responseData['chefs']
                 : null; // Add more checks if API structure varies

        if (chefsList != null) {
           setState(() {
             // Ensure all items in the list are maps
             chefs = chefsList.whereType<Map<String, dynamic>>().toList();
             isLoading = false;
           });
        } else {
             print("Could not find chef list in response: $responseData");
             throw Exception('Unexpected response format from server.');
        }
      } else {
        print('Failed to load chefs: ${response.statusCode}');
        throw Exception('Failed to load chefs (Status: ${response.statusCode})');
      }
    } on TimeoutException {
         print('Chef fetch timed out.');
         if(mounted) setState(() { fetchError = "Server took too long to respond."; isLoading = false; });
    } catch (e) {
      print('Error fetching chefs: $e');
      if (mounted) {
        setState(() {
          fetchError = "Could not load chefs. Please try again.";
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground, // Use clean background
      appBar: AppBar(
        title: Text('Available Chefs', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: kColorPrimaryDark, // Use themed color
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0, // Subtle elevation
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), // Color inherited from foregroundColor
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? _buildLoadingShimmerList() // Use shimmer effect for loading
          : fetchError != null
              ? _buildErrorState(fetchError!) // Show error state
              : chefs.isEmpty
                  ? _buildEmptyState() // Show empty state
                  : _buildChefListView(),
    );
  }

  // --- Loading Shimmer List ---
  Widget _buildLoadingShimmerList() {
     return Shimmer.fromColors(
       baseColor: kShimmerBaseColor,
       highlightColor: kShimmerHighlightColor,
       child: ListView.builder(
         itemCount: 6, // Show several shimmer placeholders
         itemBuilder: (_, __) => Padding(
           padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
           child: Row(
             children: [
               const CircleAvatar(radius: 30, backgroundColor: Colors.white),
               const SizedBox(width: 12),
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Container(height: 16, width: 150, color: Colors.white),
                     const SizedBox(height: 6),
                     Container(height: 14, width: 200, color: Colors.white),
                     const SizedBox(height: 6),
                     Container(height: 12, width: 100, color: Colors.white),
                   ],
                 ),
               ),
             ],
           ),
         ),
       ),
     );
   }

  // --- Error State ---
   Widget _buildErrorState(String message) {
     return Center(
        child: Padding(
           padding: const EdgeInsets.all(20.0),
           child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Icon( Icons.error_outline, size: 60, color: Colors.red.shade300, ),
                 const SizedBox(height: 16),
                 Text( message, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 16, color: Colors.red.shade700), ),
                 const SizedBox(height: 20),
                 ElevatedButton.icon(
                     icon: const Icon(Icons.refresh),
                     label: const Text("Retry"),
                     onPressed: fetchChefs, // Retry fetching
                      style: ElevatedButton.styleFrom(
                         foregroundColor: kColorTextOnPrimary, backgroundColor: kColorPrimary,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                 )
              ],
           ),
        ),
     );
  }

   // --- Empty State ---
   Widget _buildEmptyState() {
     return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Icon( Icons.person_search_outlined, size: 60, color: Colors.grey.shade400, ),
               const SizedBox(height: 16),
               Text( "No chefs available at the moment.", textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey.shade600), ),
               const SizedBox(height: 10),
               Text( "Pull down to refresh.", style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500), ),
            ],
        ),
     );
   }


  // --- Chef List View ---
  Widget _buildChefListView() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0), // Add horizontal padding too
      itemCount: chefs.length,
      itemBuilder: (context, index) {
        final chef = chefs[index];
        return _buildChefListItem(context, chef); // Use helper for list item
      },
      separatorBuilder: (context, index) => const SizedBox(height: 8), // Space between cards
    );
  }

  // --- Individual Chef List Item ---
  Widget _buildChefListItem(BuildContext context, Map<String, dynamic> chef) {
     // --- Data Extraction and Formatting (with safety checks) ---
     final chefName = chef['name']?.toString() ?? 'Unknown Chef';
     final chefImage = chef['image']?.toString() ?? ''; // Default to empty string
     final fullLocation = chef['location']?.toString() ?? 'Location N/A';
     final humanReadableLocation = _extractHumanReadableLocation(fullLocation);
     final priceStr = chef['price']?.toString() ?? '0'; // Handle potential null price
     final chefPrice = double.tryParse(priceStr) ?? 0.0; // Safely parse price

     final ratingDouble = double.tryParse(chef['rating']?.toString() ?? '0.0') ?? 0.0;
     final chefRating = ratingDouble.round().clamp(0, 5); // Round and clamp rating

     final specialties = chef['specialties'];
     final specialtiesText = specialties is List && specialties.isNotEmpty
         ? specialties.join(', ')
         : specialties is String && specialties.isNotEmpty
             ? specialties
             : 'General Cuisine'; // Default specialty

     final chefId = chef['chefid']?.toString() ?? 'chef_$chefName'; // Unique ID for Hero tag

    return Card( // Keep Card for subtle elevation and shape
      elevation: 1.5,
      shadowColor: kColorPrimaryLighter.withOpacity(0.4),
      shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12) ),
      margin: EdgeInsets.zero, // Margin controlled by ListView separator
      clipBehavior: Clip.antiAlias, // Clip content
      child: InkWell(
        onTap: () async {
          // Pre-cache image if URL exists
          if (chefImage.isNotEmpty && chefImage.startsWith('http')) {
             // Use try-catch as precacheImage can throw if URL is invalid/unreachable
             try { await precacheImage(NetworkImage(chefImage), context); }
             catch (e) { print("Error precaching chef image $chefId: $e"); }
          }
          // Navigate to Detail Screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChefDetailScreen(chef: chef), // Pass full chef data
            ),
          );
        },
        splashColor: kColorPrimaryLight.withOpacity(0.1), // Subtle splash
        highlightColor: kColorPrimaryLightest.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'chef-image-$chefId', // Use chefId in tag
                child: CircleAvatar( // Use CircleAvatar for consistent shape
                  radius: 30,
                  backgroundColor: kColorPrimaryLightest, // Placeholder color
                  backgroundImage: (chefImage.isNotEmpty && chefImage.startsWith('http'))
                      ? CachedNetworkImageProvider(chefImage)
                      : const AssetImage('assets/images/placeholderchef.jpeg') as ImageProvider,
                   onBackgroundImageError: (chefImage.isNotEmpty && chefImage.startsWith('http'))
                        ? (exception, stackTrace) { print("Error loading chef list image $chefId: $exception"); }
                        : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chefName,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w600, // Semi-bold
                        color: kColorTextPrimary,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row( // Location and Price/Rating Row
                      children: [
                        // Location (Takes available space)
                        Expanded(
                           child: Row(
                              mainAxisSize: MainAxisSize.min, // Prevent row from taking full width if text is short
                              children: [
                                 Icon(Icons.location_on_outlined, color: kColorTextSecondary, size: 14),
                                 const SizedBox(width: 4),
                                 Flexible( // Allow text to wrap or ellipsize
                                    child: Text(
                                      humanReadableLocation.isNotEmpty ? humanReadableLocation : fullLocation,
                                      style: GoogleFonts.poppins(fontSize: 13, color: kColorTextSecondary),
                                      overflow: TextOverflow.ellipsis, maxLines: 1,
                                    ),
                                 ),
                              ],
                           ),
                        ),
                         // Price/Rating (Fixed width or flexible depending on design)
                         const SizedBox(width: 10), // Spacer
                         if (chefPrice > 0) // Show price only if available and > 0
                            Text(
                                '\$${chefPrice.toStringAsFixed(0)}', // Display price, maybe format later
                                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: kColorPrimary),
                            ),
                         const SizedBox(width: 4),
                         // Star Rating
                         Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (i) => Icon(
                                i < chefRating ? Icons.star_rounded : Icons.star_border_rounded,
                                color: i < chefRating ? Colors.amber.shade600 : kColorBorder,
                                size: 16,
                            )),
                         ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text( // Specialties
                      specialtiesText,
                      style: GoogleFonts.poppins(fontSize: 13, color: kColorTextSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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


  String _extractHumanReadableLocation(String fullLocation) {
    // Split by comma and space, take last 2 parts if available
    final parts = fullLocation.split(', ');
    if (parts.length >= 2) {
      // Return the last two parts joined by ", "
      return parts.sublist(parts.length - 2).join(', ');
    }
    // If fewer than 2 parts, return the original (or empty if original was empty)
    return fullLocation;
  }
}


// --- Chef Detail Screen ---
class ChefDetailScreen extends StatelessWidget {
  final Map<String, dynamic> chef;

  const ChefDetailScreen({super.key, required this.chef});

  // Helper to safely get string list from dynamic data
  List<String> _getListFromStringOrList(dynamic data) {
      if (data is List) {
          // Filter out nulls and convert items to string
          return data.where((item) => item != null).map((item) => item.toString().trim()).where((s) => s.isNotEmpty).toList();
      } else if (data is String && data.isNotEmpty) {
          // Split string, trim, and filter empty
          return data.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      return []; // Return empty list otherwise
  }

  @override
  Widget build(BuildContext context) {
    // --- Data Extraction with Safety ---
    final chefName = chef['name']?.toString() ?? 'Unknown Chef';
    final chefImage = chef['image']?.toString() ?? '';
    final chefId = chef['chefid']?.toString() ?? 'chef_$chefName'; // Unique ID for Hero tag
    final bio = chef['bio']?.toString() ?? 'No bio available.';
    final priceStr = chef['price']?.toString() ?? '0';
    final chefPrice = double.tryParse(priceStr) ?? 0.0;

    // Extract lists safely
    final certificationsList = _getListFromStringOrList(chef['certifications']);
    final availabilityList = _getListFromStringOrList(chef['availability']);
    final specialtiesList = _getListFromStringOrList(chef['specialties']);
    final sampleMenuList = _getListFromStringOrList(chef['samplemenu']);
    final reviewsList = chef['reviews'] is List ? List<Map<String, dynamic>>.from(chef['reviews'].whereType<Map<String, dynamic>>()) : <Map<String, dynamic>>[];

    // Extract other details safely
    final experience = chef['experience']?.toString() ?? 'N/A';
    final serviceRadius = chef['serviceradius']?.toString() ?? 'N/A';
    final responseTime = chef['responsetime']?.toString() ?? 'N/A';
    final minNotice = chef['minnotice']?.toString() ?? 'N/A';
    final ratingDouble = double.tryParse(chef['rating']?.toString() ?? '0.0') ?? 0.0;
    final chefRating = ratingDouble.round().clamp(0, 5);


    return Scaffold(
      backgroundColor: kColorBackground, // Consistent background
      body: CustomScrollView( // Use CustomScrollView for flexible scrolling behavior
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0, // Height of the header image area
            floating: false,
            pinned: true, // Keep AppBar visible while scrolling
            stretch: true, // Allow stretching on overscroll
            backgroundColor: kColorPrimaryDark,
            foregroundColor: kColorTextOnPrimary,
            elevation: 2.0,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                 chefName,
                 style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: kColorTextOnPrimary, fontSize: 18),
              ),
              titlePadding: const EdgeInsets.symmetric(horizontal: 50, vertical: 12), // Adjust padding
              centerTitle: true, // Center title within FlexibleSpaceBar
              background: Hero(
                tag: 'chef-image-$chefId',
                child: Stack(
                   fit: StackFit.expand,
                   children: [
                      // Background Image
                      (chefImage.isNotEmpty && chefImage.startsWith('http'))
                        ? CachedNetworkImage(
                            imageUrl: chefImage,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Shimmer.fromColors(
                               baseColor: kShimmerBaseColor,
                               highlightColor: kShimmerHighlightColor,
                               child: Container(color: kColorSurface),
                            ),
                            errorWidget: (context, url, error) => Image.asset(
                               'assets/images/placeholderchef.jpeg', fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset('assets/images/placeholderchef.jpeg', fit: BoxFit.cover),
                      // Gradient overlay for title contrast
                      DecoratedBox(
                         decoration: BoxDecoration(
                           gradient: LinearGradient(
                             begin: Alignment.topCenter,
                             end: Alignment.bottomCenter,
                             colors: [ Colors.transparent, Colors.black.withOpacity(0.6) ],
                             stops: const [0.5, 1.0], // Gradient starts halfway down
                           ),
                         ),
                      ),
                   ],
                ),
              ),
            ),
          ),

          // --- Main Content Area ---
          SliverPadding(
             padding: const EdgeInsets.all(16.0),
             sliver: SliverList(
                delegate: SliverChildListDelegate([
                   // --- Quick Info Grid ---
                   _buildSectionHeader('Quick Info', icon: Icons.info_outline),
                   GridView.count(
                     crossAxisCount: 2, // Adjust based on screen width if needed
                     shrinkWrap: true,
                     physics: const NeverScrollableScrollPhysics(),
                     mainAxisSpacing: 10,
                     crossAxisSpacing: 10,
                     childAspectRatio: 2.8, // Adjust for content height
                     children: [
                       _buildInfoChip(Icons.work_outline, '$experience years exp.'),
                       _buildInfoChip(Icons.social_distance_outlined, '$serviceRadius km radius'),
                       _buildInfoChip(Icons.access_time, responseTime),
                       _buildInfoChip(Icons.notifications_active_outlined, '$minNotice hrs notice'),
                     ],
                   ),
                   const SizedBox(height: 20),

                   // --- Specialties ---
                   _buildSectionHeader('Specialties', icon: Icons.restaurant_menu),
                   if (specialtiesList.isNotEmpty)
                      Wrap( // Use Wrap for chip-like display
                         spacing: 8.0,
                         runSpacing: 4.0,
                         children: specialtiesList.map((specialty) => Chip(
                             label: Text(specialty),
                             backgroundColor: kColorPrimaryLightest,
                             labelStyle: GoogleFonts.poppins(color: kColorPrimaryDark, fontSize: 13),
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             visualDensity: VisualDensity.compact,
                         )).toList(),
                      )
                   else
                      const Text("No specialties listed.", style: TextStyle(color: kColorTextSecondary)),
                   const SizedBox(height: 20),

                   // --- About Section ---
                   _buildSectionHeader('About $chefName', icon: Icons.person_outline),
                   Text(bio, style: GoogleFonts.poppins(fontSize: 15, color: kColorTextOnSurface, height: 1.5)),
                   const SizedBox(height: 20),

                   // --- Certifications ---
                   _buildSectionHeader('Certifications', icon: Icons.verified_outlined),
                   if (certificationsList.isNotEmpty)
                      Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: certificationsList.map((cert) => Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Row(
                                 children: [
                                    const Icon(Icons.check_circle_outline, color: kColorPrimary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(cert, style: GoogleFonts.poppins(fontSize: 14, color: kColorTextOnSurface))),
                                 ],
                              ),
                           )).toList(),
                      )
                   else
                      const Text("No certifications listed.", style: TextStyle(color: kColorTextSecondary)),
                   const SizedBox(height: 20),

                   // --- Availability ---
                   _buildSectionHeader('Availability', icon: Icons.event_available_outlined),
                    // Display availability list nicely
                    if (availabilityList.isNotEmpty)
                         Text(availabilityList.join(' | '), style: GoogleFonts.poppins(fontSize: 14, color: kColorTextOnSurface))
                    else
                         const Text("Availability not specified.", style: TextStyle(color: kColorTextSecondary)),
                   const SizedBox(height: 20),

                    // --- Sample Menu (Optional: could be more visual) ---
                   _buildSectionHeader('Sample Menu Items', icon: Icons.menu_book_outlined),
                   if (sampleMenuList.isNotEmpty)
                       Wrap(
                           spacing: 8.0, runSpacing: 8.0,
                           children: sampleMenuList.map((item) => Container(
                               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                               decoration: BoxDecoration(
                                   color: kColorPrimaryLightest,
                                   borderRadius: BorderRadius.circular(8),
                                   border: Border.all(color: kColorBorder, width: 0.5),
                               ),
                               child: Text(item, style: GoogleFonts.poppins(fontSize: 13, color: kColorPrimaryDark)),
                           )).toList(),
                       )
                   else
                       const Text("No sample menu items provided.", style: TextStyle(color: kColorTextSecondary)),
                   const SizedBox(height: 20),

                    // --- Reviews ---
                   _buildSectionHeader('Reviews (${reviewsList.length})', icon: Icons.reviews_outlined),
                   if (reviewsList.isNotEmpty)
                      ListView.separated(
                         shrinkWrap: true,
                         physics: const NeverScrollableScrollPhysics(),
                         itemCount: reviewsList.length > 3 ? 3 : reviewsList.length, // Show limited reviews initially
                         itemBuilder: (context, index) => _buildReviewItem(reviewsList[index]),
                         separatorBuilder: (_, __) => const Divider(height: 16, color: kColorDivider),
                      )
                   else
                      const Text("No reviews yet.", style: TextStyle(color: kColorTextSecondary)),
                   // Optional: Add a "See all reviews" button if list > 3
                   if (reviewsList.length > 3) ...[
                        const SizedBox(height: 10),
                        TextButton(
                           onPressed: () { /* TODO: Navigate to full reviews page */ },
                           child: Text("See all ${reviewsList.length} reviews", style: GoogleFonts.poppins(color: kColorPrimary, fontWeight: FontWeight.w500)),
                        ),
                   ],

                   const SizedBox(height: 30), // Bottom spacing before button
                ]),
             ),
          ),
        ],
      ),
      // --- Floating Action Button or Bottom Navigation Bar for Action ---
      bottomNavigationBar: Padding( // Use Padding to avoid FAB overlapping content intensely
         padding: const EdgeInsets.all(16.0),
         child: ElevatedButton.icon(
            icon: const Icon(Icons.restaurant_outlined, size: 20),
            label: Text('Book Chef (\$${chefPrice.toStringAsFixed(0)})'),
            style: ElevatedButton.styleFrom(
               backgroundColor: kColorPrimaryDark, // Use dark color for primary action
               foregroundColor: kColorTextOnPrimary,
               padding: const EdgeInsets.symmetric(vertical: 14),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
               textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
               // Add item to cart logic
               cart.ShoppingCart.addItem(
                 chefName,
                 chefPrice, // Ensure price is double
                 quantity: 1,
                 selectedchef: chef, // Pass the full chef map
                 meal: {}, // Pass empty or relevant meal data if applicable
                 bestservedwith: <Map<String, String>>[], // Ensure correct type
               );
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(
                   content: Text('$chefName selected!'),
                   duration: const Duration(seconds: 2),
                   backgroundColor: Colors.green.shade700,
                 ),
               );
               // Navigate back or to cart? Navigate back to list is common.
               Navigator.pop(context);
               // Or navigate to Cart:
               // Navigator.push(context, MaterialPageRoute(builder: (context) => cart.ShoppingCartScreen()));
            },
          ),
      ),
    );
  }

  // --- Helper Widgets for Detail Screen ---

  Widget _buildSectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: kColorPrimary, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600, // Semi-bold
              color: kColorPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kColorPrimaryLightest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kColorBorder, width: 0.5),
      ),
      child: Row(
         mainAxisSize: MainAxisSize.min, // Fit content
         children: [
            Icon(icon, color: kColorPrimary, size: 16),
            const SizedBox(width: 6),
            // Use Flexible to prevent overflow on small chips
            Flexible(child: Text(text, style: GoogleFonts.poppins(fontSize: 12, color: kColorTextPrimary), overflow: TextOverflow.ellipsis)),
         ],
      ),
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
     final userName = review['user']?.toString() ?? 'Anonymous';
     final comment = review['comment']?.toString() ?? 'No comment provided.';
     final ratingDouble = double.tryParse(review['rating']?.toString() ?? '0.0') ?? 0.0;
     final rating = ratingDouble.round().clamp(0, 5);

     return Padding(
       padding: const EdgeInsets.symmetric(vertical: 8.0),
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(userName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: kColorTextOnSurface)),
                   _buildRatingStars(rating), // Use helper for stars
                ],
             ),
             const SizedBox(height: 4),
             Text(comment, style: GoogleFonts.poppins(fontSize: 14, color: kColorTextSecondary)),
          ],
       ),
     );
  }

  Widget _buildRatingStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) => Icon(
          index < rating ? Icons.star_rounded : Icons.star_border_rounded,
          color: index < rating ? Colors.amber.shade600 : kColorBorder,
          size: 18,
      )),
    );
  }
}