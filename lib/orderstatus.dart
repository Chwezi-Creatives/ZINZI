import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:async'; // For TimeoutException
import 'package:shimmer/shimmer.dart'; // For loading shimmer

// Assuming API_BASE_URL-intranet is set in your .env file
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ?? dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback'; // Provide a sensible fallback

// --- Color Palette (Hardcoded Teal/White Shades) ---
const Color kColorPrimaryDark = Color(0xFF004D40); // Darkest Teal
const Color kColorPrimary = Color(0xFF00796B); // Medium Teal
const Color kColorPrimaryLight = Color(0xFF4DB6AC); // Lighter Teal
const Color kColorPrimaryLighter = Color(0xFFB2DFDB); // Very Light Teal
const Color kColorPrimaryLightest = Color(0xFFE0F2F1); // Lightest Teal (added to fix null color bug)
const Color kColorBackground = Color(0xFFF8F8F8); // Off-White Background
const Color kColorSurface = Colors.white; // White for cards
const Color kColorTextPrimary = kColorPrimaryDark; // Dark teal for primary text
const Color kColorTextSecondary = Color(0xFF546E7A); // Blue Grey for secondary text
const Color kColorTextOnPrimary = Colors.white; // White text on teal backgrounds
const Color kColorDivider = Color(0xFFE0E0E0); // Light grey divider
const Color kColorError = Colors.redAccent; // Error color
const Color kColorSuccess = Color(0xFF2E7D32); // Darker Green for Success
const Color kColorWarning = Colors.orangeAccent; // Warning color
final Color kShimmerBaseColor = Colors.grey.shade300;
final Color kShimmerHighlightColor = Colors.grey.shade100;
// --- End Color Palette ---

class OrderStatusScreen extends StatefulWidget {
  final int orderId;
  final int userId;

  const OrderStatusScreen({
    super.key,
    required this.orderId,
    required this.userId,
  });

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  late Future<Map<String, dynamic>> _orderDetailsFuture;

  // --- UI Styling Constants ---
  static const double _horizontalPadding = 16.0;
  static const double _verticalPadding = 16.0;
  static const double _sectionSpacing = 24.0;
  static const double _cardElevation = 2.0; // Slightly more elevation
  static const double _cardCornerRadius = 12.0;

  @override
  void initState() {
    super.initState();
    _orderDetailsFuture = _fetchOrderDetails();
  }

  // --- Fetch Logic ---
  Future<Map<String, dynamic>> _fetchOrderDetails() async {
    // Construct URL safely
    final uri = Uri.parse(
        '$apiBaseUrl/rr/orders?user_id=${widget.userId}&order_id=${widget.orderId}');
    debugPrint('Fetching order details from: $uri');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15)); // Shorter timeout

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('API Response: $data');

        // Robust handling of API response structure
        dynamic orderDataResult;
        if (data is Map<String, dynamic> && data.containsKey('data') && data['data'] is List) {
          if (data['data'].isNotEmpty) {
             orderDataResult = data['data'][0];
          }
        } else if (data is List && data.isNotEmpty) {
           orderDataResult = data[0]; // Handle direct list response
        } else if (data is Map<String, dynamic> && !data.containsKey('message')) {
            // Handle case where the map itself might be the order (less common)
            // Might need more specific checks based on your API
            orderDataResult = data;
        }

        if (orderDataResult is Map<String, dynamic>) {
          orderDataResult['order_id'] ??= widget.orderId; // Ensure order_id is present
          return orderDataResult;
        } else {
          // Handle case where data was found but not in expected format or was empty list
          throw Exception('Order #${widget.orderId} not found or data format is incorrect.');
        }
      } else {
        // Handle non-200 status codes
        debugPrint('Failed to load order details. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to load order details (Code: ${response.statusCode})');
      }
    } on TimeoutException {
        debugPrint('Request timed out fetching order details.');
        throw Exception('Could not reach server. Please check connection.');
    } catch (e) {
      // Catch other errors (network, parsing, etc.)
      debugPrint('Error fetching order details: $e');
      // Rethrow a user-friendly exception
      throw Exception(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'An unexpected error occurred.');
    }
  }
  // --- End Fetch Logic ---

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: kColorBackground, // Use clean background
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Transparent AppBar
        elevation: 0,
        foregroundColor: kColorTextPrimary, // Dark text/icons on light background
        centerTitle: true,
        title: Text(
          'Order Confirmation',
          style: GoogleFonts.poppins( // Use Google Fonts
            fontWeight: FontWeight.w600, // Semi-bold
            color: kColorTextPrimary, // Dark teal text
            fontSize: 18,
          ),
        ),
        leading: IconButton(
           icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
           onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true, // Allow body content behind AppBar
      body: FutureBuilder<Map<String, dynamic>>(
        future: _orderDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Use Shimmer for a nicer loading state
            return _buildLoadingShimmer();
          }

          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            final error = snapshot.error ?? 'Order data is unavailable.';
            return _buildErrorWidget(context, error, textTheme);
          }

          final order = snapshot.data!;

          // Use SafeArea to avoid overlap with status/navigation bars
          return SafeArea(
            top: false, // Already handled by extendBodyBehindAppBar + AppBar padding
            child: RefreshIndicator(
              onRefresh: () async {
                // Trigger fetch and wait for it to complete
                setState(() { _orderDetailsFuture = _fetchOrderDetails(); });
                await _orderDetailsFuture;
              },
              color: kColorPrimary, // Themed refresh indicator
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable for refresh
                padding: EdgeInsets.only(
                  left: _horizontalPadding,
                  right: _horizontalPadding,
                  bottom: _verticalPadding,
                  top: kToolbarHeight + MediaQuery.of(context).padding.top + 10, // Adjust top padding dynamically
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSuccessHeader(context, textTheme),
                    const SizedBox(height: _sectionSpacing),
                    _buildOrderSummaryCard(context, order, textTheme),
                    const SizedBox(height: _sectionSpacing),
                    // Conditionally build item card
                    if (order['meal_name'] != null)
                      _buildOrderItemCard(context, order, textTheme)
                    else
                      _buildPlaceholderItemCard(context, textTheme), // Show placeholder if no meal name
                    const SizedBox(height: _sectionSpacing * 1.5),
                    _buildDoneButton(context, textTheme),
                    const SizedBox(height: _verticalPadding), // Bottom padding
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Shimmer Loading Widget ---
  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
       baseColor: kShimmerBaseColor,
       highlightColor: kShimmerHighlightColor,
       child: SingleChildScrollView( // Make shimmer scrollable if needed
         physics: const NeverScrollableScrollPhysics(), // Prevent scrolling during shimmer
         padding: EdgeInsets.only(
             left: _horizontalPadding, right: _horizontalPadding, bottom: _verticalPadding,
             top: kToolbarHeight + MediaQuery.of(context).padding.top + 10, // Match body padding
         ),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           children: [
             // Shimmer Success Header
             Container( height: 150, decoration: BoxDecoration(color: kColorSurface, borderRadius: BorderRadius.circular(_cardCornerRadius)), ),
             const SizedBox(height: _sectionSpacing),
             // Shimmer Summary Card
             Container( height: 300, decoration: BoxDecoration(color: kColorSurface, borderRadius: BorderRadius.circular(_cardCornerRadius)), ),
              const SizedBox(height: _sectionSpacing),
             // Shimmer Item Card
             Container( height: 150, decoration: BoxDecoration(color: kColorSurface, borderRadius: BorderRadius.circular(_cardCornerRadius)), ),
             const SizedBox(height: _sectionSpacing * 1.5),
             // Shimmer Button
             Container( height: 50, decoration: BoxDecoration(color: kColorSurface, borderRadius: BorderRadius.circular(_cardCornerRadius)), ),
           ],
         ),
       ),
    );
  }


  // --- Error Widget ---
  Widget _buildErrorWidget(BuildContext context, Object? error, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.all(_horizontalPadding * 1.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon( Icons.error_outline_rounded, color: kColorError, size: 50, ),
            const SizedBox(height: 16),
            Text( 'Oops! Something Went Wrong', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: kColorTextPrimary), textAlign: TextAlign.center, ),
            const SizedBox(height: 8),
            Text(
              error is Exception ? error.toString().replaceFirst('Exception: ', '') : error?.toString() ?? 'Could not load order details.',
              style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              onPressed: () { setState(() { _orderDetailsFuture = _fetchOrderDetails(); }); },
              style: ElevatedButton.styleFrom(
                backgroundColor: kColorPrimary,
                foregroundColor: kColorTextOnPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // --- Enhanced Success Header ---
  Widget _buildSuccessHeader(BuildContext context, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: _verticalPadding, horizontal: _horizontalPadding),
      decoration: BoxDecoration(
        // Use a gradient for a slightly richer look
        gradient: LinearGradient(
           colors: [ kColorPrimaryLightest.withOpacity(0.6), kColorPrimaryLighter.withOpacity(0.3) ],
           begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_cardCornerRadius),
        border: Border.all(color: kColorSuccess.withOpacity(0.3)) // Subtle success border
      ),
      child: Column(
        children: [
          Icon( Icons.check_circle_outline_rounded, color: kColorSuccess, size: 45, ),
          const SizedBox(height: 10),
          Text(
            'Order Placed Successfully!',
            style: GoogleFonts.poppins( fontSize: 20, fontWeight: FontWeight.w600, color: kColorSuccess, ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Thank you! Your order details are below.',
            style: GoogleFonts.poppins(fontSize: 14, color: kColorSuccess.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // --- Enhanced Order Summary Card ---
  Widget _buildOrderSummaryCard( BuildContext context, Map<String, dynamic> order, TextTheme textTheme) {
    // Date Formatting (keep as is)
    final String orderDateStr = order['order_date']?.toString() ?? ''; String formattedDate = 'N/A'; try { if (orderDateStr.isNotEmpty) { final dateTime = DateTime.parse(orderDateStr).toLocal(); formattedDate = DateFormat('MMM d, yyyy hh:mm a').format(dateTime); } } catch (e) { formattedDate = orderDateStr; }

    return Card(
        elevation: _cardElevation,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)),
        color: kColorSurface, // Use surface color
        shadowColor: kColorPrimary.withOpacity(0.1), // Subtle shadow
        child: Padding(
          padding: const EdgeInsets.all(_verticalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Use Row for title and potentially an action button (e.g., View Invoice)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    Text('Order Summary', style: GoogleFonts.poppins(fontSize: 17, color: kColorPrimary, fontWeight: FontWeight.w600)),
                    // Optional: Add action like 'View Invoice'
                    // TextButton(onPressed: (){}, child: Text("View Invoice"))
                ],
              ),
              const Divider(height: 20, thickness: 0.8, color: kColorDivider), // Themed divider
              _buildDetailTile(context, textTheme, icon: Icons.tag_rounded, label: 'Order ID', value: '#${order['order_id']?.toString() ?? 'N/A'}', isBoldValue: true),
              _buildDetailTile(context, textTheme, icon: Icons.calendar_today_rounded, label: 'Placed On', value: formattedDate),
              _buildDetailTile(context, textTheme, icon: Icons.info_outline_rounded, label: 'Order Status', valueWidget: _buildStatusChip( context, textTheme, order['order_status']?.toString(), isPaymentStatus: false)),
              _buildDetailTile(context, textTheme, icon: Icons.location_on_outlined, label: 'Deliver To', value: order['delivery_address']?.toString() ?? 'N/A'),
              _buildDetailTile(context, textTheme, icon: Icons.receipt_long_outlined, label: 'Order Type', value: order['order_type']?.toString() ?? 'N/A'),
              _buildDetailTile(context, textTheme, icon: Icons.credit_card, label: 'Payment Mode', value: order['payment_mode']?.toString() ?? 'N/A'),
              _buildDetailTile(context, textTheme, icon: Icons.payment, label: 'Payment Status', valueWidget: _buildStatusChip( context, textTheme, order['payment_status']?.toString(), isPaymentStatus: true)),
              const Divider(height: 20, thickness: 0.8, color: kColorDivider),
              _buildDetailTile(context, textTheme, icon: Icons.monetization_on_outlined, label: 'Order Total', value: '\$${(_parseDouble(order['total_price']) ?? 0.0).toStringAsFixed(2)}', isBoldValue: true, valueColor: kColorPrimaryDark), // Darker total color
            ],
          ),
        ),
      );
  }

  // --- Refined Detail Tile ---
  Widget _buildDetailTile( BuildContext context, TextTheme textTheme, { required IconData icon, required String label, String? value, Widget? valueWidget, Color? valueColor, bool isBoldValue = false, }) {
    return Padding( // Add padding for better spacing
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align icon/label top
        children: [
          Icon(icon, size: 20, color: kColorPrimary.withOpacity(0.9)), // Slightly smaller icon
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 14)),
          const Spacer(), // Push value/widget to the right
          Flexible( // Allow value/widget to wrap or shrink
            child: valueWidget ?? (value != null
                  ? Text( value, overflow: TextOverflow.ellipsis, maxLines: 3, textAlign: TextAlign.end,
                      style: GoogleFonts.poppins(
                          color: valueColor ?? kColorTextPrimary, // Use primary text color by default
                          fontSize: 14,
                          fontWeight: isBoldValue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    )
                  : const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }

  // --- Refined Status Chip ---
  Widget _buildStatusChip( BuildContext context, TextTheme textTheme, String? status, {bool isPaymentStatus = false}) {
    final statusText = status?.toUpperCase() ?? (isPaymentStatus ? 'UNKNOWN' : 'N/A');
    final Color chipColor = isPaymentStatus ? _getPaymentStatusColor(context, status) : _getOrderStatusColor(context, status);
    // Removed unused textColor variable

    return Material( // Wrap with Material for InkWell effect
      color: Colors.transparent,
      child: InkWell( // Make chip tappable
        onTap: () => _showStatusExplanationDialog(context, status, isPaymentStatus, textTheme),
        borderRadius: BorderRadius.circular(16), // Match chip shape
        splashColor: chipColor.withOpacity(0.3),
        child: Chip(
          avatar: CircleAvatar( // Add colored circle avatar for visual cue
              backgroundColor: chipColor,
              radius: 5,
          ),
          label: Text(
            statusText,
            style: GoogleFonts.poppins( // Use GoogleFonts
                color: chipColor, // Text color matches status
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 0.3
            ),
          ),
          backgroundColor: chipColor.withOpacity(0.12), // Very subtle background
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: chipColor.withOpacity(0.3)), // Subtle border
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // --- Status Colors (keep as is) ---
  Color _getOrderStatusColor(BuildContext context, String? status) { /* ... */ switch (status?.toLowerCase()) { case 'completed': case 'delivered': return kColorSuccess; case 'processing': case 'preparing': return Colors.blue.shade600; case 'pending': return kColorWarning; case 'cancelled': case 'failed': return kColorError; default: return Colors.grey.shade500; } }
  Color _getPaymentStatusColor(BuildContext context, String? status) { /* ... */ switch (status?.toLowerCase()) { case 'paid': case 'completed': return kColorSuccess; case 'pending': return kColorWarning; case 'failed': return kColorError; case 'unpaid': return Colors.grey.shade500; default: return Colors.grey.shade500; } }

  // --- Item Card (keep as is) ---
  Widget _buildOrderItemCard( BuildContext context, Map<String, dynamic> order, TextTheme textTheme) { /* ... */ final String mealName = order['meal_name']?.toString() ?? 'N/A'; final String ingredients = order['ingredients']?.toString() ?? ''; final String producerName = order['producer_name']?.toString() ?? ''; final String chefName = order['chef_name']?.toString() ?? ''; final String quantity = order['quantity']?.toString() ?? '?'; final String displayPrice = order['quantity'] == 1 ? '\$${(_parseDouble(order['total_price']) ?? 0.0).toStringAsFixed(2)}' : '(See Order Total)'; return Card( elevation: _cardElevation, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardCornerRadius)), color: kColorSurface, shadowColor: Colors.grey.withOpacity(0.2), clipBehavior: Clip.antiAlias, child: Padding( padding: const EdgeInsets.all(_verticalPadding), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Padding( padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text('Item Details', style: textTheme.titleMedium?.copyWith( color: kColorPrimary, fontWeight: FontWeight.bold)), ), Divider(height: 1, color: Colors.grey[200]), const SizedBox(height: _verticalPadding), Row( crossAxisAlignment: CrossAxisAlignment.start, children: [ Container( width: 70, height: 70, decoration: BoxDecoration( color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8.0), ), child: Icon(Icons.fastfood_outlined, color: Colors.grey.shade400, size: 35), ), const SizedBox(width: 12), Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(mealName, style: textTheme.titleMedium?.copyWith( fontWeight: FontWeight.w600, color: kColorTextPrimary)), if (ingredients.isNotEmpty) ...[ const SizedBox(height: 4), Text('Ingredients: $ingredients', style: textTheme.bodySmall ?.copyWith(color: kColorTextSecondary), maxLines: 2, overflow: TextOverflow.ellipsis), ], const SizedBox(height: 8), if (chefName.isNotEmpty) _buildInfoChip(context, textTheme, Icons.kitchen_rounded, 'Chef: $chefName') else if (producerName.isNotEmpty) _buildInfoChip( context, textTheme, Icons.storefront_outlined, 'Producer: $producerName') else _buildInfoChip(context, textTheme, Icons.help_outline, 'Preparation details N/A'), const SizedBox(height: 8), Text('Qty: $quantity • $displayPrice', style: textTheme.bodyMedium?.copyWith( fontWeight: FontWeight.w500, color: kColorTextPrimary)), ], ), ), ], ), ], ), ), ); }
  Widget _buildPlaceholderItemCard(BuildContext context, TextTheme textTheme) { /* ... */ return Card( elevation: _cardElevation, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(_cardCornerRadius)), color: Colors .grey.shade100, child: Padding( padding: const EdgeInsets.all(_verticalPadding * 1.5), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.receipt_long_outlined, color: kColorTextSecondary, size: 20), const SizedBox(width: 8), Text( 'Specific item details not available.', style: textTheme.bodyMedium?.copyWith(color: kColorTextSecondary), ), ], ), ), ); }
  Widget _buildInfoChip(BuildContext context, TextTheme textTheme, IconData icon, String text) { /* ... */ return Row( mainAxisSize: MainAxisSize.min, children: [ Icon(icon, size: 16, color: kColorPrimary.withOpacity(0.9)), const SizedBox(width: 6), Flexible( child: Text(text, style: textTheme.bodySmall?.copyWith(color: kColorTextSecondary), overflow: TextOverflow.ellipsis), ), ], ); }

  // --- Enhanced Done Button ---
  Widget _buildDoneButton(BuildContext context, TextTheme textTheme) {
    return Center(
      child: ElevatedButton( // Use ElevatedButton for more prominence
        onPressed: () {
          // Navigate back to a specific screen like home or orders list?
          // Example: Navigate back to AllMealsScreen if appropriate
          // Navigator.of(context).pushAndRemoveUntil(
          //   MaterialPageRoute(builder: (context) => AllMealsScreen()),
          //   (Route<dynamic> route) => false, // Remove all routes behind
          // );
          if (Navigator.canPop(context)) {
             Navigator.pop(context); // Default: just pop
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: kColorPrimaryDark, // Darker Teal for final action
          foregroundColor: kColorTextOnPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 14),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), // Pill shape
          elevation: 3,
        ),
        child: const Text('Done'),
      ),
    );
  }

  double? _parseDouble(dynamic value) {
    // (Keep implementation the same)
     if (value is num) return value.toDouble(); if (value is String) return double.tryParse(value); return null;
  }

  // --- Status Explanation Dialog ---
  void _showStatusExplanationDialog(BuildContext context, String? status, bool isPaymentStatus, TextTheme textTheme) {
    // (Keep implementation the same, uses themed colors/fonts)
     String title = ''; String explanation = ''; final statusLower = status?.toLowerCase() ?? 'unknown'; if (isPaymentStatus) { title = 'Payment Status: ${statusLower.toUpperCase()}'; switch (statusLower) { case 'pending': explanation = 'Your payment is being processed or awaiting confirmation (e.g., from MoMo). This usually takes a few moments.'; break; case 'paid': case 'completed': explanation = 'Your payment has been successfully received.'; break; case 'failed': explanation = 'Your payment could not be completed. Please check your payment details or try a different method.'; break; case 'unpaid': explanation = 'Payment for this order has not been made yet.'; break; default: explanation = 'The payment status is currently unknown or not specified.'; } } else { title = 'Order Status: ${statusLower.toUpperCase()}'; switch (statusLower) { case 'pending': explanation = 'Your order has been received and is awaiting confirmation and processing by the kitchen or producer.'; break; case 'processing': case 'preparing': explanation = 'Your order is being prepared by the chef or sourced by the producer.'; break; case 'completed': explanation = 'Your order preparation is complete and it\'s ready for the next step (delivery or pickup).'; break; case 'delivered': explanation = 'Your order has been successfully delivered.'; break; case 'cancelled': case 'rejected': explanation = 'This order has been cancelled.'; break; case 'failed': explanation = 'There was an issue processing this order. Please contact support if this persists.'; break; case 'shipped': explanation = 'Your order has been shipped and is on its way.'; break; case 'delivering': explanation = 'Your order is currently out for delivery.'; break; default: explanation = 'The order status is currently unknown or not specified.'; } } showDialog( context: context, builder: (BuildContext dialogContext) { return AlertDialog( shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(_cardCornerRadius)), backgroundColor: kColorSurface, title: Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: kColorPrimaryDark)), content: Text(explanation, style: GoogleFonts.poppins(fontSize: 14, color: kColorTextPrimary)), actions: <Widget>[ TextButton( child: Text('OK', style: GoogleFonts.poppins(color: kColorPrimary, fontWeight: FontWeight.bold)), onPressed: () { Navigator.of(dialogContext).pop(); }, ), ], ); }, );
  }
  // --- End Status Explanation Function ---

}

 // End of _OrderStatusScreenState