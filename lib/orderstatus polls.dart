import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart'; // For date and currency formatting
import 'dart:async'; // For TimeoutException
import 'package:shimmer/shimmer.dart'; // For loading shimmer

// --- Environment & API ---
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback';

// --- Theme Colors ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFFB2DFDB);
const Color kColorAccent = Color(0xFFFFAB40); // Example Accent
const Color kColorSurface = Colors.white;
const Color kColorBackground = Color(0xFFF5F5F5); // Light grey background
const Color kColorTextPrimary = Color(0xFF212121); // Darker text
const Color kColorTextSecondary = Color(0xFF757575); // Greyer text
const Color kColorError = Colors.redAccent;
const Color kColorSuccess = Color(0xFF4CAF50);
const Color kColorWarning = Color(0xFFFFA000); // For pending/processing
const Color kColorCancelled = Color(0xFFF44336); // For cancelled
const Color kColorInfo = Color(0xFF1976D2); // For other statuses

// --- Shimmer Colors ---
Color kShimmerBaseColor = Colors.grey.shade300;
Color kShimmerHighlightColor = Colors.grey.shade100;

// --- Dimensions ---
const double _horizontalPadding = 16.0;
const double _verticalPadding = 12.0; // Adjusted slightly
const double _cardElevation = 1.0; // Slightly more pronounced
const double _cardCornerRadius = 12.0;
const double _cardSpacing = 12.0; // Spacing between cards

// --- Helper Functions ---
String _formatDate(String? dateString) {
  if (dateString == null) return 'N/A';
  try {
    final dateTime = DateTime.parse(dateString);
    // Example format: Jan 15, 2024 or customize as needed
    return DateFormat.yMMMd().add_jm().format(dateTime);
  } catch (e) {
    return dateString; // Return original if parsing fails
  }
}

String _formatCurrency(dynamic amount) {
  if (amount == null) return 'N/A';
  try {
    final doubleValue = double.parse(amount.toString());
    // Adjust currency symbol and locale as needed
    return NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(doubleValue);
  } catch (e) {
    return amount.toString(); // Return original if parsing fails
  }
}

Color _getStatusColor(String? status) {
  status = status?.toLowerCase();
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
      return kColorInfo; // Default color for unknown statuses
  }
}

String _getStatusDisplay(String? status) {
  return status?.replaceAll('_', ' ').split(' ').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ') ?? 'N/A';
}

// --- Order Status Screen Widget ---
class OrderStatusScreen extends StatefulWidget {
  final int userId;
  final List<int> orderIdList;

  const OrderStatusScreen({
    super.key,
    required this.userId,
    required this.orderIdList,
    orderId,
  });

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  late Future<List<Map<String, dynamic>>> _orderDetailsFuture;
  // State map to track orders by their IDs
  final Map<int, Map<String, dynamic>> _ordersMap = {};
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchOrders();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _fetchOrders() async {
    // Fetch orders for each order ID in the list
    for (var orderId in widget.orderIdList) {
      final uri = Uri.parse('$apiBaseUrl/rr/orders?user_id=${widget.userId}&order_id=$orderId');
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 20)); // Increased timeout slightly

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic> && data['data'] is List) {
            final orderDataList = data['data'] as List;
            for (var orderData in orderDataList) {
              if (orderData is Map<String, dynamic>) {
                // Ensure order_id is parsed correctly
                if (orderData.containsKey('order_id')) {
                  orderData['order_id'] = int.tryParse(orderData['order_id'].toString()) ?? orderData['order_id'];
                  // Update if the status has changed
                  if (_ordersMap[orderData['order_id']] == null || 
                      _ordersMap[orderData['order_id']]!['order_status'] != orderData['order_status']) {
                    _ordersMap[orderData['order_id']] = orderData;
                    setState(() {}); // Trigger a rebuild for the updated status
                  }
                }
              }
            }
          } else {
            // Handle cases where the expected structure isn't returned
            print("Unexpected data format for order $orderId: $data");
          }
        } else {
          // Handle non-200 responses for individual orders if needed
          print("Failed to fetch order $orderId: Status ${response.statusCode}");
        }
      } catch (e) {
        print("Error fetching details for order $orderId: $e");
      }
    }
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
            'My Orders',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: kColorSurface),
          ),
          backgroundColor: kColorPrimary,
          foregroundColor: kColorSurface,
          elevation: 2.0,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        body: _ordersMap.isEmpty
            ? _buildLoadingShimmer()
            : RefreshIndicator(
                onRefresh: () async {
                  _fetchOrders();
                },
                color: kColorPrimary,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: _horizontalPadding / 2,
                      vertical: _verticalPadding),
                  itemCount: widget.orderIdList.length,
                  itemBuilder: (context, index) {
                    final orderId = widget.orderIdList[index];
                    final order = _ordersMap[orderId];
                    if (order == null) return const SizedBox.shrink();
                    return _buildOrderCard(context, order);
                  },
                ),
              ),
      ),
    );
  }

  // --- UI Building Widgets ---
  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order) {
    final String status = order['order_status'] ?? 'Unknown';
    final Color statusColor = _getStatusColor(status);
    final String displayStatus = _getStatusDisplay(status);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding / 2,
        vertical: _cardSpacing / 2,
      ),
      elevation: _cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(_horizontalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order['order_id']}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kColorTextPrimary,
                        ),
                  ),
                  Text(
                    displayStatus,
                    style: TextStyle(color: statusColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: kShimmerBaseColor,
      highlightColor: kShimmerHighlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: _horizontalPadding / 2,
            vertical: _verticalPadding),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: _horizontalPadding / 2,
              vertical: _cardSpacing / 2,
            ),
            elevation: _cardElevation,
            child: Container(height: 100, color: Colors.white), // Shimmer placeholder
          );
        },
      ),
    );
  }
}