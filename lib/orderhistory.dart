// orderhistory.dart (Corrected)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart'; // For date and currency formatting
import 'dart:async'; // For TimeoutException
import 'package:shimmer/shimmer.dart'; // For loading shimmer
import 'package:shared_preferences/shared_preferences.dart'; // For Shared Preferences

// --- Environment & API ---
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback';

// --- Theme Colors ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFFB2DFDB);
const Color kColorAccent = Color(0xFFFFAB40);
const Color kColorSurface = Colors.white;
const Color kColorBackground = Color(0xFFF5F5F5);
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary = Color(0xFF757575);
const Color kColorError = Colors.redAccent;
const Color kColorSuccess = Color(0xFF4CAF50);
const Color kColorWarning = Color(0xFFFFA000);
const Color kColorCancelled = Color(0xFFF44336);
const Color kColorInfo = Color(0xFF1976D2);

// --- Shimmer Colors ---
Color kShimmerBaseColor = Colors.grey.shade300;
Color kShimmerHighlightColor = Colors.grey.shade100;

// --- Dimensions ---
const double _horizontalPadding = 16.0;
const double _verticalPadding = 12.0;
const double _cardElevation = 1.0;
const double _cardCornerRadius = 12.0;
const double _cardSpacing = 12.0;

// --- Helper Functions ---
String _formatDate(String? dateString) {
  if (dateString == null) return 'N/A';
  try {
    final dateTime = DateTime.parse(dateString);
    // Example Format: Jan 15, 2024, 10:30 AM
    return DateFormat.yMMMd().add_jm().format(dateTime);
  } catch (e) {
    print("Error formatting date '$dateString': $e");
    return dateString; // Return original if parsing fails
  }
}

String _formatCurrency(dynamic amount) {
  if (amount == null) return 'N/A';
  try {
    final doubleValue = double.parse(amount.toString());
    return NumberFormat.currency(symbol: '\$', decimalDigits: 2)
        .format(doubleValue);
  } catch (e) {
     print("Error formatting currency '$amount': $e");
    return amount.toString(); // Return original if parsing fails
  }
}

Color _getStatusColor(String? status) {
  status = status?.toLowerCase().trim();
  switch (status) {
    case 'delivered':
    case 'completed':
      return kColorSuccess;
    case 'processing':
    case 'shipped':
    case 'pending':
      return kColorWarning;
    case 'cancelled':
    case 'failed':
      return kColorCancelled;
    default:
      return kColorInfo; // Default for unknown or null statuses
  }
}

String _getStatusDisplay(String? status) {
  return status
          ?.trim()
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
          .join(' ')
          .trim() // Ensure no leading/trailing spaces
          ?? 'Unknown'; // Default for null status
}

// --- Order History Screen Widget ---
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  // Initialize Future directly in initState, make it nullable initially
  Future<List<Map<String, dynamic>>>? _orderHistoryFuture;
  // State map to track expansion per order ID
  final Map<int, bool> _isExpandedMap = {};

  @override
  void initState() {
    super.initState();
    // Assign the future directly here
    _orderHistoryFuture = _loadInitialHistory();
  }

  // Helper function to perform async operations needed before fetching
  Future<List<Map<String, dynamic>>> _loadInitialHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('user_id'); // Assuming user_id is stored as an int

      if (userId == null) {
        print("User ID not found for order history. User needs to log in.");
        // Throw a specific error that FutureBuilder can catch
        throw Exception("User not logged in.");
      }
      // If userId is valid, fetch the details
      return _fetchOrderHistoryDetails(userId);
    } catch (e) {
       // Rethrow any other unexpected errors during initial load
       print("Error during initial history load setup: $e");
       throw Exception("Failed to initialize order history: ${e.toString()}");
    }
  }


  // Fetches actual order details (remains mostly the same)
  Future<List<Map<String, dynamic>>> _fetchOrderHistoryDetails(int userId) async {
    List<Map<String, dynamic>> orders = [];
    final uri = Uri.parse('$apiBaseUrl/rr/orders?user_id=$userId');
    print("Fetching order history from: $uri"); // Debug log

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List) {
          final orderDataList = data['data'] as List;
          orders = orderDataList
              .whereType<Map<String, dynamic>>() // Ensure items are maps
              .map((orderData) {
                 // Try parsing order_id safely within the map
                 int? parsedId = int.tryParse(orderData['order_id']?.toString() ?? '');
                 if (parsedId != null) {
                   orderData['order_id'] = parsedId; // Replace original with parsed int
                 } else {
                    print("Warning: Could not parse order_id for order data: $orderData");
                    // Decide how to handle invalid IDs (e.g., assign a temp negative ID or filter out)
                    orderData['order_id'] = -1; // Assign temporary invalid ID
                 }
                 return orderData;
              })
              .where((order) => order['order_id'] != -1) // Filter out items with invalid IDs
              .toList();

        } else {
          print("Unexpected data format received for order history: $data");
          throw Exception('Invalid data format from server.');
        }
      } else {
        print("Failed to fetch history orders: Status ${response.statusCode}, Body: ${response.body}");
        throw Exception('Failed to load order history (Status: ${response.statusCode}).');
      }

      // Sort orders (newest first)
      orders.sort((a, b) {
        DateTime? dateA = DateTime.tryParse(a['order_date'] ?? '');
        DateTime? dateB = DateTime.tryParse(b['order_date'] ?? '');
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1; // Put null dates last
        if (dateB == null) return -1; // Put null dates last
        return dateB.compareTo(dateA); // Newest first
      });

       print("Fetched and sorted ${orders.length} orders."); // Debug log
      return orders;
    } on TimeoutException catch (_) {
      print("Order history request timed out.");
      throw Exception('Request timed out. Please check your connection.');
    } on http.ClientException catch (e) {
       print("Network error fetching order history: ${e.message}");
      throw Exception('Network error: Could not connect to the server.');
    } catch (e) {
      print("Error fetching or processing order history details: $e");
      throw Exception('Failed to load order history. Please try again.');
    }
  }

  // Method to refresh the fetch
  Future<void> _refreshHistory() async {
    print("Refreshing order history...");
    // Clear expansion state on refresh if desired
    // _isExpandedMap.clear();
    setState(() {
      // Assign a new future by re-running the initial load logic
      _orderHistoryFuture = _loadInitialHistory();
    });
    // Wait for the refresh to complete (optional, useful for showing indicator correctly)
    try {
       await _orderHistoryFuture;
    } catch (e) {
       // Error during refresh is handled by FutureBuilder, but you could log here
       print("Error caught during refresh: $e");
    }
  }

  // Helper to navigate to login
  void _navigateToLogin() {
     // Use pushReplacementNamed to prevent coming back here without logging in
      Navigator.pushReplacementNamed(context, '/login'); // Ensure '/login' route exists
       print("Navigating to login screen.");
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme.apply(
          fontFamily: GoogleFonts.poppins().fontFamily,
          bodyColor: kColorTextPrimary,
          displayColor: kColorTextPrimary,
        );

    return Theme(
      data: Theme.of(context).copyWith(textTheme: textTheme),
      child: Scaffold(
        backgroundColor: kColorBackground,
        appBar: AppBar(
          title: Text(
            'Order History',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: kColorSurface),
          ),
          backgroundColor: kColorPrimary,
          foregroundColor: kColorSurface,
          elevation: 2.0,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        // Use FutureBuilder to handle the Future state
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _orderHistoryFuture, // Use the initialized future
          builder: (context, snapshot) {
            // --- Loading State ---
            if (snapshot.connectionState == ConnectionState.waiting) {
               print("FutureBuilder: Waiting for order history...");
              return _buildLoadingShimmer();
            }

            // --- Error State ---
            if (snapshot.hasError) {
               print("FutureBuilder: Error loading order history: ${snapshot.error}");
              // Pass the specific error to the error widget
              return _buildErrorWidget(context, snapshot.error);
            }

            // --- Empty or No Data State ---
            // Check specifically for null or empty list AFTER checking for errors
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              print("FutureBuilder: No order history data found.");
              return _buildEmptyState(context);
            }

            // --- Success State ---
            final orders = snapshot.data!;
             print("FutureBuilder: Successfully loaded ${orders.length} orders.");
            return RefreshIndicator(
              onRefresh: _refreshHistory, // Use the refresh method
              color: kColorPrimary,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: _horizontalPadding / 2,
                    vertical: _verticalPadding),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  // Ensure order_id is treated as int after potential parsing/filtering
                  final orderId = order['order_id'] as int;
                  // Use local map to track expansion state
                  final isExpanded = _isExpandedMap[orderId] ?? false;

                  return _buildOrderCard(context, order, orderId, isExpanded);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  // --- UI Building Widgets ---

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order,
      int orderId, bool isExpanded) {
    final String status = order['order_status'] ?? 'Unknown';
    final Color statusColor = _getStatusColor(status);
    final String displayStatus = _getStatusDisplay(status);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding / 2,
        vertical: _cardSpacing / 2,
      ),
      elevation: _cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardCornerRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Toggle expansion state locally
          setState(() {
            _isExpandedMap[orderId] = !isExpanded;
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Padding(
              padding: const EdgeInsets.all(_horizontalPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #$orderId', // Use the validated integer ID
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: kColorTextPrimary,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Placed: ${_formatDate(order['order_date'])}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: kColorTextSecondary,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      displayStatus,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    backgroundColor: statusColor,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),

            // Animated Expansion Section
            AnimatedCrossFade(
              firstChild: Container(), // Empty container when collapsed
              secondChild: _buildOrderDetails(context, order),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250), // Slightly faster animation
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeIn,
              sizeCurve: Curves.easeInOut,
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                  vertical: _verticalPadding / 1.5), // Adjusted padding
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kColorTextSecondary,
                        ),
                  ),
                  Text(
                    _formatCurrency(order['price']),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kColorPrimaryDark,
                        ),
                  ),
                ],
              ),
            ),
            // Expansion Indicator (Subtle)
            Container(
              height: 25, // Reduced height
              color: Colors.grey.shade100, // Match footer background
              alignment: Alignment.center,
              child: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: kColorTextSecondary.withOpacity(0.6), // More subtle color
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetails(BuildContext context, Map<String, dynamic> order) {
     // Safely extract items list
    final List<dynamic> itemsList = order['items'] is List ? order['items'] : [];

    return Padding(
      padding: const EdgeInsets.only(
          left: _horizontalPadding,
          right: _horizontalPadding,
          bottom: _verticalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 12),
          _buildDetailRow(
            context,
            icon: Icons.location_on_outlined,
            label: 'Delivery Address',
            value: order['delivery_address'] ?? 'N/A',
          ),
          _buildDetailRow(
            context,
            icon: Icons.payment_outlined,
            label: 'Payment Mode',
            value: _getStatusDisplay(order['payment_mode']), // Use formatter
          ),
          _buildDetailRow(
            context,
            icon: Icons.credit_card_outlined,
            label: 'Payment Status',
            value: _getStatusDisplay(order['payment_status']),
            valueColor: _getStatusColor(order['payment_status']),
          ),
          // Display Order Items (if available)
          if (itemsList.isNotEmpty) ...[
             const SizedBox(height: 12),
             Text(
                "Items:",
                 style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kColorTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
             ),
             const SizedBox(height: 6),
             // Using Column + map for simplicity, could use ListView if many items
             Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: itemsList.map((item) {
                  if (item is! Map<String, dynamic>) return const SizedBox.shrink(); // Skip invalid items
                  final itemName = item['meal_name'] ?? item['gig_type'] ?? 'Unknown Item';
                  final quantity = item['quantity'] as int?; // Nullable int
                  final price = (item['price'] as num?)?.toDouble(); // Nullable double

                  String displayString = "- $itemName";
                  if (quantity != null && quantity > 0) {
                     displayString += " (x$quantity)";
                  }
                   if (price != null) {
                      // Optional: Show price per item if needed
                      // displayString += " @ ${_formatCurrency(price)}";
                  }

                 return Padding(
                   padding: const EdgeInsets.only(left: 20.0, top: 4.0), // Indent items
                   child: Text(
                      displayString,
                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: kColorTextPrimary,
                          ),
                   ),
                 );
               }).toList(),
             ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context,
      {required IconData icon,
      required String label,
      required String value,
      Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kColorPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kColorTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: valueColor ?? kColorTextPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 3, // Allow address to wrap
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: kShimmerBaseColor,
      highlightColor: kShimmerHighlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: _horizontalPadding / 2, vertical: _verticalPadding),
        itemCount: 6, // Show more shimmer items
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: _horizontalPadding / 2,
              vertical: _cardSpacing / 2,
            ),
            elevation: _cardElevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_cardCornerRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row( // Shimmer Header
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 100 + (index % 3 * 20), height: 16, color: Colors.white), // Variable width
                          const SizedBox(height: 6),
                          Container(width: 140 + (index % 2 * 30), height: 12, color: Colors.white),
                        ],
                      ),
                      Container(width: 60 + (index % 2 * 10), height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
                    ],
                  ),
                   const SizedBox(height: 12),
                   const Divider(height: 1),
                   const SizedBox(height: 12),
                   // Shimmer Details
                   Container(width: double.infinity, height: 14, color: Colors.white),
                   const SizedBox(height: 8),
                   Container(width: MediaQuery.of(context).size.width * 0.6, height: 14, color: Colors.white), // 60% width
                   const SizedBox(height: 16),
                   // Shimmer Footer
                   Container( height: 35, color: Colors.white.withOpacity(0.7))
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, Object? error) {
     String errorMessage = 'An unexpected error occurred.';
     bool showLoginButton = false;

     if (error is Exception) {
       String errorString = error.toString();
        errorMessage = errorString.replaceFirst("Exception: ", "");
        if (errorMessage.contains("User not logged in")) {
           showLoginButton = true;
           errorMessage = "Please log in to view your order history."; // User-friendly message
        } else if (errorMessage.contains("Network error")) {
          errorMessage = "Could not connect to the server. Please check your internet connection.";
        } else if (errorMessage.contains("timed out")) {
           errorMessage = "The request took too long to respond. Please try again later.";
        }
        // Keep other specific error messages if needed
     }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_horizontalPadding * 1.5), // Reduced padding
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
                showLoginButton ? Icons.login : Icons.error_outline, // Different icon for login
                color: kColorError, size: 50),
            const SizedBox(height: _verticalPadding),
            Text(
              showLoginButton ? 'Login Required' : 'Load Failed',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: kColorTextPrimary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: kColorTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: _verticalPadding * 1.5),
            if (showLoginButton)
              ElevatedButton.icon(
                 icon: const Icon(Icons.login_rounded),
                 label: const Text('Go to Login'),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: kColorPrimary,
                   foregroundColor: kColorSurface,
                   shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30)),
                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                 ),
                 onPressed: _navigateToLogin, // Navigate to login
              )
            else // Show Retry button for other errors
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kColorPrimary,
                  foregroundColor: kColorSurface,
                  shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _refreshHistory, // Call refresh method
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_horizontalPadding * 1.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, // More relevant icon
                color: kColorTextSecondary.withOpacity(0.6), size: 50),
            const SizedBox(height: _verticalPadding),
            Text(
              'No Orders Found',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: kColorTextPrimary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "You haven't placed any orders yet.\nStart shopping to see your history here!",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: kColorTextSecondary, height: 1.4), // Added line height
              textAlign: TextAlign.center,
            ),
             const SizedBox(height: _verticalPadding * 1.5),
             // Optional: Button to go shopping
              ElevatedButton(
                child: const Text('Start Shopping'),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: kColorPrimary,
                   foregroundColor: kColorSurface,
                   shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30)),
                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                 ),
                 onPressed: () {
                    // TODO: Navigate to your main shopping/home screen
                    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                 },
              )
          ],
        ),
      ),
    );
  }
}