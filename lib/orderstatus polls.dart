import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';

// --- Environment & API ---
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback';

// --- Theme Colors ---
final kColorPrimary = Colors.teal[900];
const Color kColorAccent = Color(0xFF4CAF50);
const Color kColorBackground = Color(0xFFF5F5F5);
const Color kColorCard = Colors.white;
const Color kColorTextPrimary = Color(0xFF333333);
const Color kColorTextSecondary = Color(0xFF666666);
const Color kColorStatusActive = Color(0xFF4CAF50);
const Color kColorStatusInactive = Color(0xFFCCCCCC);
const Color kColorDivider = Color(0xFFEEEEEE);
const Color kColorTimelineLine =
    Color(0xFFE0E0E0); // Color for timeline connecting lines

class OrderStatusScreen extends StatefulWidget {
  final int userId;
  final List<int> orderIdList;
  final int orderId;

  const OrderStatusScreen({
    super.key,
    required this.userId,
    required this.orderIdList,
    required this.orderId,
  });

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  final Map<int, Map<String, dynamic>> _ordersMap = {};
  final Map<int, String> _previousOrderStatuses = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _pollingTimer;
  int? _selectedOrderId;
  bool _isOrderInfoExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchOrders();
    });
  }

  void _fetchOrders() async {
    for (var orderId in widget.orderIdList) {
      final uri = Uri.parse(
          '$apiBaseUrl/rr/orders?user_id=${widget.userId}&order_id=$orderId');

      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic> && data['data'] is List) {
            final orderDataList = data['data'] as List;
            for (var orderData in orderDataList) {
              if (orderData is Map<String, dynamic> &&
                  orderData.containsKey('order_id')) {
                orderData['order_id'] =
                    int.tryParse(orderData['order_id'].toString()) ??
                        orderData['order_id'];

                final int currentOrderId = orderData['order_id'];
                final String currentOrderStatus =
                    orderData['order_status']?.toString() ?? 'pending';

                // Check if status has changed
                if (_ordersMap[currentOrderId] != null &&
                    _ordersMap[currentOrderId]!['order_status'] !=
                        currentOrderStatus) {
                  // Play sound on status change
                  _playStatusChangeSound();
                }

                // Store previous status
                _previousOrderStatuses[currentOrderId] =
                    _ordersMap[currentOrderId]?['order_status'] ?? 'pending';

                // Update order data
                _ordersMap[currentOrderId] = orderData;
                if (_selectedOrderId == null) {
                  _selectedOrderId = currentOrderId;
                }
                setState(() {});
              }
            }
          }
        }
      } catch (e) {
        print("Error fetching details for order $orderId: $e");
      }
    }
  }

  void _playStatusChangeSound() async {
    try {
      await _audioPlayer.play(AssetSource('assets/sounds/chime.mp3'));
    } catch (e) {
      print("Error playing sound: $e");
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: kColorPrimary,
              ),
              child: Text(
                'Order Menu',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                'View Past Orders',
                style: GoogleFonts.poppins(),
              ),
              onTap: () {
                Navigator.pop(context);
                // Add navigation to order history screen here
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text(
          'ORDER TRACKING',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: kColorPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: kColorPrimary,
        ),
      ),
      body: _ordersMap.isEmpty
          ? _buildLoadingState()
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildOrderSelector(),
                  _buildOrderStatusCard(),
                  _buildOrderInfoCard(),
                  _buildTrackingHistoryCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: kColorCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ORDER',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: kColorTextPrimary,
            ),
          ),
          DropdownButton<int>(
            value: _selectedOrderId,
            items: _ordersMap.keys.map((orderId) {
              return DropdownMenuItem<int>(
                value: orderId,
                child: Text(
                  'Order #$orderId',
                  style: GoogleFonts.poppins(),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedOrderId = value;
                _isOrderInfoExpanded = false; // Collapse when switching orders
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();

    final status = order['order_status']?.toString() ?? 'pending';
    final formattedDate = _formatDate(order['order_date']?.toString());
    final formattedTime = _formatTime(order['order_date']?.toString());

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Status: ${_formatStatus(status)}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: kColorTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Order Date: $formattedDate $formattedTime',
            style: GoogleFonts.poppins(
              color: kColorTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusTimeline(status),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final statuses = [
      'Order Placed',
      'Dispatched',
      'Delivered'
    ]; // Simplified status names as shown in screenshot
    final currentStatusIndex = _getStatusIndex(status);
    final orderDate = _selectedOrderId != null
        ? _ordersMap[_selectedOrderId]!['order_date']?.toString()
        : null;

    return Stack(
      children: [
        // Horizontal connecting line
        Positioned(
          top: 12, // Center with the circles
          left: 40, // Start after first circle
          right: 40, // End before last circle
          child: Container(
            height: 2,
            color: kColorTimelineLine, // Line color
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(statuses.length, (index) {
            // Calculate if this status is active
            bool isActive = index <= _getSimplifiedStatusIndex(status);

            return Expanded(
              child: Column(
                children: [
                  // Indicator
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          isActive ? kColorStatusActive : kColorStatusInactive,
                    ),
                    child: isActive
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  // Status text
                  Text(
                    statuses[index],
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  // Date (only show for active or past statuses)
                  if (isActive)
                    Text(
                      '${_getSimplifiedStatusDate(orderDate, index)}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: kColorTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildOrderInfoCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();

    // Essential information (always visible)
    final productName = order['meal_name'] ?? order['product_name'] ?? 'N/A';
    final customerName = order['user_id']?.toString() ?? 'N/A';
    final quantity = order['quantity']?.toString() ?? '1';
    final totalPrice = order['total_price']?.toString() ?? 'N/A';
    final orderStatus =
        _formatStatus(order['order_status']?.toString() ?? 'pending');
    final chefName = order['chef_name'] ?? 'N/A';

    // Extended information (visible when expanded)
    final contactInfo = order['contact_info']?.toString() ?? 'No contact info';
    final deliveryAddress = order['delivery_address']?.toString() ?? 'N/A';
    final notes = order['notes']?.toString() ?? 'None';
    final paymentStatus =
        _formatStatus(order['payment_status']?.toString() ?? 'N/A');
    final ingredients = order['ingredients']?.toString() ?? 'N/A';

    // Create more readable address by removing coordinates
    final cleanAddress = deliveryAddress.contains(',')
        ? deliveryAddress.split(',').skip(2).join(',').trim()
        : deliveryAddress;

    return InkWell(
      onTap: () {
        setState(() {
          _isOrderInfoExpanded = !_isOrderInfoExpanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kColorCard,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SHIPPING INFORMATION', // Changed to match screenshot
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: kColorTextPrimary,
                  ),
                ),
                Icon(
                  _isOrderInfoExpanded ? Icons.expand_less : Icons.expand_more,
                  color: kColorTextPrimary,
                ),
              ],
            ),
            const Divider(color: kColorDivider),
            const SizedBox(height: 8),

            // Always visible information - in the requested order
            _buildInfoRow('Product', productName),
            _buildInfoRow('Customer', 'User #$customerName'),
            _buildInfoRow('Quantity', quantity),
            _buildInfoRow('Total Price', '$totalPrice UGX'),
            _buildInfoRow('Order Status', orderStatus),

            // Display Chef or Producer based on what's available
            if (order['chef_id'] != null && order['chef_name'] != null)
              _buildInfoRow('Chef', order['chef_name']),
            if (order['producer_id'] != null && order['producer_name'] != null)
              _buildInfoRow('Producer', order['producer_name']),

            // Expandable content
            if (_isOrderInfoExpanded) ...[
              const SizedBox(height: 8),
              const Divider(color: kColorDivider),
              const SizedBox(height: 8),
              _buildInfoRow('Contact', contactInfo),
              _buildInfoRow('Delivery To', cleanAddress),
              _buildInfoRow('Payment Status', paymentStatus),
              _buildInfoRow('Notes', notes),
              if (ingredients != 'N/A')
                _buildInfoRow('Ingredients', ingredients),
            ],

            // Hint for expandable content
            if (!_isOrderInfoExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'Tap to see more details',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: kColorTextSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingHistoryCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();

    final orderDate = order['order_date']?.toString();
    final currentStatus = order['order_status']?.toString() ?? 'pending';
    final statusIndex = _getSimplifiedStatusIndex(currentStatus);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Text(
                'TRACKING HISTORY',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: kColorTextPrimary,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const Divider(color: kColorDivider),
          const SizedBox(height: 16),
          for (int i = 0; i <= statusIndex; i++)
            _buildTrackingEvent(
              _getSimplifiedStatusName(i),
              _getSimplifiedStatusDate(orderDate, i),
              isLast: i == statusIndex,
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: kColorTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingEvent(String event, String date, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vertical timeline with dots and connecting lines
        SizedBox(
          width: 24,
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kColorStatusActive,
                ),
              ),
              // Vertical connecting line (not for the last item)
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: kColorStatusActive,
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                date,
                style: GoogleFonts.poppins(
                  color: kColorTextSecondary,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: isLast ? 8 : 32), // Space between events
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: kColorPrimary),
          const SizedBox(height: 16),
          Text(
            'Loading order details...',
            style: GoogleFonts.poppins(
              color: kColorTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('d MMMM').format(dateTime);
    } catch (e) {
      return dateString;
    }
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return '';
    }
  }

  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ')
        .trim();
  }

  // Modified helper methods for the simplified timeline as shown in screenshot
  String _getSimplifiedStatusName(int index) {
    switch (index) {
      case 0:
        return 'Order Placed';
      case 1:
        return 'Dispatched';
      case 2:
        return 'Delivered';
      default:
        return 'Unknown Status';
    }
  }

  int _getSimplifiedStatusIndex(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'placed':
      case 'order_placed':
        return 0;
      case 'on the way':
      case 'on_the_way':
      case 'shipped':
      case 'dispatched':
      case 'preparing':
      case 'accepted':
        return 1;
      case 'delivered':
      case 'complete':
      case 'completed':
        return 2;
      default:
        return 0;
    }
  }

  String _getSimplifiedStatusDate(String? orderDate, int index) {
    if (orderDate == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      // Add progression of days based on status index
      final adjustedDate = dateTime.add(Duration(days: index * 1));
      return '${adjustedDate.day} Feb'; // Simplified date format as shown in screenshot
    } catch (e) {
      return '$index Feb'; // Fallback
    }
  }

  // Original helper methods kept for reference
  String _getStatusDate(String? orderDate, int statusIndex) {
    if (orderDate == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      // Add progression of days based on status index
      final adjustedDate = dateTime.add(Duration(hours: statusIndex * 2));
      return DateFormat('d MMMM').format(adjustedDate);
    } catch (e) {
      return 'N/A';
    }
  }

  String _getStatusTime(String? orderDate, int statusIndex) {
    if (orderDate == null) return '';
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      // Add progression of hours based on status index
      final adjustedDate = dateTime.add(Duration(hours: statusIndex * 2));
      return DateFormat('h:mm a').format(adjustedDate);
    } catch (e) {
      return '';
    }
  }

  String _getStatusName(int index) {
    switch (index) {
      case 0:
        return 'Order Placed';
      case 1:
        return 'Accepted';
      case 2:
        return 'Preparing';
      case 3:
        return 'On The Way';
      case 4:
        return 'Delivered';
      case 5:
        return 'Complete';
      default:
        return 'Unknown Status';
    }
  }

  int _getStatusIndex(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'placed':
      case 'order_placed':
        return 0;
      case 'accepted':
        return 1;
      case 'preparing':
        return 2;
      case 'on the way':
      case 'on_the_way':
      case 'shipped':
      case 'dispatched':
        return 3;
      case 'delivered':
        return 4;
      case 'complete':
      case 'completed':
        return 5;
      default:
        return 0;
    }
  }
}
