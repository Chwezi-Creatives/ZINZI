import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'notifications/notification_provider.dart';

// --- Environment & API ---
// Ensure you have initialized dotenv in your main.dart: await dotenv.load(fileName: ".env");
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback'; // Provide a sensible fallback

// --- Theme Colors ---
final kColorPrimary = Colors.teal[900];
const Color kColorAccent = Color(0xFF4CAF50); // Keep consistent naming if possible
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
  final int orderId; // Initial orderId to potentially focus on

  const OrderStatusScreen({
    super.key,
    required this.userId,
    required this.orderIdList,
    required this.orderId, // Consider if this is still needed if using _selectedOrderId
  });

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _pollingTimer;
  int? _selectedOrderId;
  bool _isOrderInfoExpanded = false;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final Map<int, Map<String, dynamic>> _ordersMap = {};
  final Map<int, String> _previousOrderStatuses = {};
  bool _isVerificationProcessActive = false;
  int? _loadingVerificationOrderId;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.orderIdList.contains(widget.orderId) ? widget.orderId : (widget.orderIdList.isNotEmpty ? widget.orderIdList.first : null);
    _fetchOrders();
    _startPolling();
    
    // Listen for notification refreshes
    final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    notificationProvider.addListener(_handleNotificationRefresh);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    notificationProvider.removeListener(_handleNotificationRefresh);
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleNotificationRefresh() {
    if (!_isRefreshing) {
      setState(() {
        _isRefreshing = true;
      });
      _fetchOrders().then((_) {
        if (mounted) {
          setState(() {
            _isRefreshing = false;
          });
        }
      });
    }
  }

  // Helper to build the complementary meals row
  Widget _buildComplementaryMealsRow(dynamic complementaryMealsRaw) {
    if (complementaryMealsRaw == null || complementaryMealsRaw.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    List<dynamic> mealsList;
    try {
      if (complementaryMealsRaw is String) {
        // Try to decode JSON string
        final decoded = json.decode(complementaryMealsRaw);
        if (decoded is List) {
          mealsList = decoded;
        } else {
          return const SizedBox.shrink();
        }
      } else if (complementaryMealsRaw is List) {
        mealsList = complementaryMealsRaw;
      } else {
        return const SizedBox.shrink();
      }
      // Extract names, strip extra slashes/spaces
      final names = mealsList
        .map((item) => (item is Map && item['name'] != null) ? item['name'].toString().replaceAll(RegExp(r'[\/]+'), '').trim() : null)
        .where((name) => name != null && name.isNotEmpty)
        .toList();
      if (names.isEmpty) return const SizedBox.shrink();
      return _buildInfoRow('Best served with', names.join(', '));
    } catch (e) {
      // If any error in decoding/parsing, just hide the row
      return const SizedBox.shrink();
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isVerificationProcessActive) {
        _fetchOrders();
      } else {
        print("Polling skipped - verification dialog active");
      }
    });
  }

  // Check for status changes and trigger verification dialog if needed
  void _checkForStatusChanges(Map<int, Map<String, dynamic>> updatedOrders) {
    final Map<int, String> currentStatuses = {};
    
    // Build map of current statuses
    for (final entry in updatedOrders.entries) {
      final orderId = entry.key;
      final status = entry.value['order_status']?.toString();
      if (status != null) {
        currentStatuses[orderId] = status;
      }
    }
    
    // Check for changes and trigger dialogs
    for (final entry in currentStatuses.entries) {
      final orderId = entry.key;
      final newStatus = entry.value;
      final previousStatus = _previousOrderStatuses[orderId];
      
      // If status changed to 'verification needed' and not already showing the dialog
      if (newStatus == 'verification needed' && 
          newStatus != previousStatus &&
          !_isVerificationProcessActive) {
        // Use postFrameCallback to ensure the dialog is shown after the build is complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleVerificationRequest(orderId);
        });
      }
    }
    
    // Update previous statuses for next comparison
    _previousOrderStatuses.clear();
    _previousOrderStatuses.addAll(currentStatuses);
  }

  // Handle verification request (called on tap or status change)
  Future<void> _handleVerificationRequest(int orderId) async {
    if (mounted) {
      setState(() {
        _isVerificationProcessActive = true;
        _loadingVerificationOrderId = orderId;
      });
    }
    
    print("Verification process started for Order #$orderId. Polling paused.");
    
    // Show the verification dialog
    await _showCompletionCodeDialog(orderId);
  }
  
  // Show completion code dialog
  Future<void> _showCompletionCodeDialog(int orderId) async {
    String completionCode = 'N/A';
    String errorMessage = '';
    bool codeFetchedSuccessfully = false;

    final uri = Uri.parse('$apiBaseUrl/rr/get_completion_code/$orderId');
    print("Fetching completion code for Order #$orderId from: $uri");

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['completion_code'] != null) {
          completionCode = data['completion_code'].toString();
          codeFetchedSuccessfully = true;
          print("Completion code fetched successfully for Order #$orderId.");
        } else {
          errorMessage = 'Invalid response format for completion code.';
          print("Unexpected completion code response format: $data");
        }
      } else {
        errorMessage = 'Failed to fetch completion code (Status: ${response.statusCode}).';
        print("Failed to fetch completion code: Status ${response.statusCode}, Body: ${response.body}");
      }
    } on TimeoutException catch (_) {
      errorMessage = 'Request for completion code timed out.';
      print("Completion code request timed out for Order #$orderId.");
    } on http.ClientException catch (e) {
      errorMessage = 'Network error fetching completion code.';
      print("Network error fetching completion code for Order #$orderId: ${e.message}");
    } catch (e) {
      errorMessage = 'Error fetching completion code: ${e.toString()}';
      print("Error fetching completion code for Order #$orderId: $e");
    }

    // Stop loading animation before showing the dialog
    if (mounted) {
      setState(() {
        _loadingVerificationOrderId = null;
      });
    }

    // Show the dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: const Color.fromARGB(255, 241, 255, 254),
            title: Text(
              codeFetchedSuccessfully
                  ? 'Order #$orderId Ready!'
                  : 'Order #$orderId Verification',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, 
                  color: kColorPrimary),
            ),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(
                    errorMessage.isNotEmpty
                        ? 'Could not retrieve verification code: $errorMessage'
                        : 'Verification code is ready.',
                    style: GoogleFonts.poppins(color: kColorTextPrimary),
                    textAlign: TextAlign.left,
                  ),
                  if (errorMessage.isEmpty && codeFetchedSuccessfully) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Verification Code:',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: kColorPrimary,
                      ),
                    ),
                    SelectableText(
                      completionCode,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kColorStatusActive,
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Provide this code to the rider ONLY after confirming successful delivery.',
                      style: GoogleFonts.poppins(
                        fontStyle: FontStyle.italic,
                        color: kColorTextSecondary,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ] else if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Please try again shortly or contact support if the issue persists.',
                      style: GoogleFonts.poppins(
                        fontStyle: FontStyle.italic,
                        color: kColorTextSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Resume polling when dialog is dismissed
                  if (mounted) {
                    setState(() {
                      _isVerificationProcessActive = false;
                    });
                  }
                },
                child: Text(
                  'CLOSE',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: kColorPrimary,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _fetchOrders() async {
    if (_isRefreshing) return; // Prevent concurrent refreshes
    
    if (widget.orderIdList.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
      return;
    }
    
    setState(() {
      _isRefreshing = true;
    });

    // Fetch details for all orders in the list concurrently
    final fetchFutures = widget.orderIdList.map((orderId) async {
      final uri = Uri.parse('$apiBaseUrl/rr/orders?user_id=${widget.userId}&order_id=$orderId');
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic> && data['data'] is List) {
            final orderDataList = data['data'] as List;
            if (orderDataList.isNotEmpty && orderDataList.first is Map<String, dynamic>) {
              final Map<String, dynamic> orderData = Map<String, dynamic>.from(orderDataList.first); // Ensure it's mutable

              // Ensure order_id is an integer
              orderData['order_id'] = int.tryParse(orderData['order_id']?.toString() ?? '') ?? orderId; // Use loop orderId as fallback

              return orderData; // Return the single order data
            }
          } else {
             print("Unexpected response format for order $orderId: ${response.body}");
          }
        } else {
          print("Error fetching details for order $orderId: Status ${response.statusCode}");
        }
      } catch (e) {
        print("Error fetching details for order $orderId: $e");
      }
      return null; // Return null on error or if data not found
    }).toList();

    final results = await Future.wait(fetchFutures);

    bool dataUpdated = false;
    final Map<int, Map<String, dynamic>> updatedOrders = {};

    for (final orderData in results) {
      if (orderData != null && orderData['order_id'] != null) {
        final int currentOrderId = orderData['order_id'];
        updatedOrders[currentOrderId] = orderData; // Add to temporary map

        final String currentOrderStatus = orderData['order_status']?.toString() ?? 'pending';

        // Check if status has changed from the previously stored status
        if (_ordersMap.containsKey(currentOrderId) &&
            _ordersMap[currentOrderId]?['order_status'] != currentOrderStatus) {
          _playStatusChangeSound();
          dataUpdated = true;
        } else if (!_ordersMap.containsKey(currentOrderId)) {
          // If it's a new order being added
          dataUpdated = true;
        } else if (_ordersMap[currentOrderId] != orderData) {
           // Check if any other data changed (optional, could be noisy)
           dataUpdated = true;
        }

        // Store previous status (might not be needed anymore if just comparing current vs new fetch)
        // _previousOrderStatuses[currentOrderId] = _ordersMap[currentOrderId]?['order_status'] ?? 'pending';
      }
    }

    // Update the main map and state only if there are changes or it's the initial load
    if (dataUpdated || _isLoading) {
      if (mounted) { // Check if widget is still in the tree
        setState(() {
          _ordersMap.clear();
          _ordersMap.addAll(updatedOrders);
          // Ensure _selectedOrderId is still valid
          if (_selectedOrderId == null || !_ordersMap.containsKey(_selectedOrderId)) {
            _selectedOrderId = _ordersMap.keys.firstOrNull;
            _isOrderInfoExpanded = false; // Reset expansion if selected order changes
          }
          _isLoading = false; // Mark loading as complete
        });
        
        // Check for status changes that should trigger verification dialog
        _checkForStatusChanges(updatedOrders);
      }
    } else {
       // Even if no data *changed*, ensure loading state is off after first fetch attempt
       if (_isLoading && mounted) {
         setState(() {
           _isLoading = false;
         });
       }
    }
  }


  void _playStatusChangeSound() async {
    if (_isRefreshing) return; // Prevent sound during refresh
    
    try {
      await _audioPlayer.play(AssetSource('sounds/chime.mp3'));
    } catch (e) {
      print("Error playing status change sound: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
    if (_isRefreshing) return; // Prevent sound during refresh
    
    try {
      await _audioPlayer.play(AssetSource('sounds/chime.mp3'));
    } catch (e) {
      print("Error playing status change sound: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
    if (_isRefreshing) return; // Prevent sound during refresh
    // Play sound only if status changed during normal operation
    try {
      // Consider adding a debounce mechanism if status changes can happen very rapidly
      await _audioPlayer.play(AssetSource('sounds/chime.mp3')); // Ensure path is correct in pubspec.yaml
    } catch (e) {
      print("Error playing sound: $e");
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground,
      drawer: const AppDrawer(), // Unified drawer,
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
        elevation: 2, // Subtle shadow
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: kColorPrimary, // Match AppBar color
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    if (_ordersMap.isEmpty) {
      return _buildEmptyState();
    }
    // Check if _selectedOrderId is valid before building content
    if (_selectedOrderId == null || !_ordersMap.containsKey(_selectedOrderId)) {
      return _buildErrorState("No order selected or order data missing.");
    }

    return RefreshIndicator( // Add pull-to-refresh
       onRefresh: _fetchOrders,
       color: kColorPrimary ?? Colors.teal,
       child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16), // Add padding at the bottom
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
    // Ensure _ordersMap is not empty and keys exist before building dropdown
    if (_ordersMap.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16), // Add margin
      decoration: BoxDecoration( // Add decoration
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'SELECTED ORDER', // Changed label
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 14, // Slightly smaller
              color: kColorTextPrimary,
            ),
          ),
          DropdownButton<int>(
            value: _selectedOrderId,
            // Ensure items list is not empty and contains _selectedOrderId
            items: _ordersMap.keys.map((orderId) {
              return DropdownMenuItem<int>(
                value: orderId,
                child: Text(
                  'Order #$orderId',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) {
               if (value != null && _ordersMap.containsKey(value)) {
                 setState(() {
                  _selectedOrderId = value;
                  _isOrderInfoExpanded = false; // Collapse details when switching orders
                 });
               }
            },
            underline: Container(), // Remove default underline
            icon: Icon(Icons.arrow_drop_down, color: kColorPrimary),
            style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 14),
            dropdownColor: kColorCard, // Match card background
          ),
        ],
      ),
    );
  }

  Widget _buildOrderStatusCard() {
    final order = _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container(); // Should not happen if _buildBody checks correctly

    final status = order['order_status']?.toString() ?? 'pending';
    final formattedDate = _formatDate(order['order_date']?.toString());
    final formattedTime = _formatTime(order['order_date']?.toString());

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16), // Consistent margin
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
              color: kColorPrimary, // Use primary color for emphasis
            ),
          ),
          const SizedBox(height: 8),
           if (formattedDate != 'N/A') // Only show if date is valid
             Text(
              'Placed on: $formattedDate ${formattedTime ?? ""}', // Combine date and time
              style: GoogleFonts.poppins(
                color: kColorTextSecondary,
                fontSize: 13,
              ),
            ),
          const SizedBox(height: 20), // Increased spacing
          _buildStatusTimeline(status),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    // Simplified statuses for the timeline visual
    final timelineStatuses = ['Order Placed', 'Dispatched', 'Delivered'];
    final currentSimplifiedIndex = _getSimplifiedStatusIndex(status);
    final orderDate = _selectedOrderId != null
        ? (_selectedOrderId != null && _ordersMap[_selectedOrderId] != null ? _ordersMap[_selectedOrderId]!['order_date']?.toString() : null)
        : null;

    return LayoutBuilder( // Use LayoutBuilder to calculate line width
      builder: (context, constraints) {
        final double segmentWidth = constraints.maxWidth / timelineStatuses.length;
        final double circleRadius = 12.0;
        final double horizontalPadding = segmentWidth / 2 - circleRadius; // Center circles in segments

        return Stack(
          children: [
            // Horizontal connecting line - Position adjusted based on layout
            Positioned(
              top: circleRadius - 1, // Center vertically with the circles
              left: horizontalPadding + circleRadius, // Start after first half-circle
              right: horizontalPadding + circleRadius, // End before last half-circle
              child: Container(
                height: 2,
                color: kColorTimelineLine,
              ),
            ),
            // Active part of the line
             Positioned(
              top: circleRadius - 1,
              left: horizontalPadding + circleRadius,
              // Calculate width based on current status index
              width: currentSimplifiedIndex > 0
                  ? (segmentWidth * currentSimplifiedIndex)
                  : 0,
              child: Container(
                height: 2,
                color: kColorStatusActive, // Active line color
              ),
            ),
            Row(
              children: List.generate(timelineStatuses.length, (index) {
                bool isActive = index <= currentSimplifiedIndex;
                // Determine date for this step
                String stepDate = isActive ? _getSimplifiedStatusDate(orderDate, index) : '';

                return Expanded(
                  child: Column(
                    children: [
                      // Indicator Circle
                      Container(
                        width: circleRadius * 2,
                        height: circleRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive ? kColorStatusActive : kColorStatusInactive,
                           border: Border.all( // Add subtle border
                             color: isActive ? kColorStatusActive : kColorTimelineLine,
                             width: 1.5,
                           ),
                        ),
                        child: isActive
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      // Status text
                      Text(
                        timelineStatuses[index],
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? kColorTextPrimary : kColorTextSecondary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Date (only show for active steps with valid dates)
                      if (stepDate.isNotEmpty && stepDate != 'N/A')
                        Text(
                          stepDate,
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
      },
    );
  }

  // --- Updated _buildOrderInfoCard ---
  Widget _buildOrderInfoCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();
    
    // Check if verification is needed and if this order is loading verification
    final bool needsVerification = order['order_status']?.toString() == 'verification needed';
    final bool isLoadingVerification = _loadingVerificationOrderId == _selectedOrderId;

    // --- MODIFICATION START ---
    // Determine product name based on order_type
    String productName;
    final orderType = order['order_type']?.toString();

    if (orderType == 'gig') {
      final gigDetailsData = order['gig_details'];
      if (gigDetailsData is Map<String, dynamic>) {
        // Prioritize 'gig_name', then 'gig_type'
        productName = gigDetailsData['gig_name']?.toString() ??
                      gigDetailsData['gig_type']?.toString() ??
                      'N/A (Gig Name/Type Missing)';
      } else if (gigDetailsData is String) {
         // Handle if gig_details is just a string (less ideal, but possible)
         try {
            final decodedDetails = json.decode(gigDetailsData);
             if (decodedDetails is Map<String, dynamic>) {
                 productName = decodedDetails['gig_name']?.toString() ??
                               decodedDetails['gig_type']?.toString() ??
                               'N/A (Gig Name/Type Missing)';
            } else {
                 productName = 'N/A (Invalid Gig Details Format)';
            }
         } catch (e) {
           print("Error decoding gig_details string: $e");
           productName = 'N/A (Error in Gig Details)';
         }
      } else {
        // Handle cases where gig_details might be missing or not a map/string
        print("Warning: Order type is 'gig' but 'gig_details' is missing or not a map/string for order ${_selectedOrderId}");
        productName = 'N/A (Invalid Gig Details)';
      }
    } else {
      // Fallback to existing logic for other order types (e.g., meal, product)
      productName = order['meal_name']?.toString() ??
                    order['product_name']?.toString() ??
                    'N/A';
    }
    // --- MODIFICATION END ---

    // Essential information (always visible)
    final customerName = order['customer_name'] ?? order['user_id']?.toString() ?? 'N/A'; // Prefer customer_name if available
    final quantity = order['quantity']?.toString() ?? '1';
    final totalPrice = order['total_price']?.toString() ?? 'N/A';
    final orderStatus =
        _formatStatus(order['order_status']?.toString() ?? 'pending');
    final chefName = order['chef_name']; // May be null
    final producerName = order['producer_name']; // May be null

    // Extended information (visible when expanded)
    final contactInfo = order['contact_info']?.toString() ?? 'Not provided';
    final deliveryAddress = order['delivery_address']?.toString(); // Can be null
    final notes = order['notes']?.toString(); // Can be null
    final paymentStatus =
        _formatStatus(order['payment_status']?.toString() ?? 'N/A');
    final ingredients = order['ingredients']?.toString(); // Can be null

    // Create more readable address by removing potential coordinates
    String cleanAddress = 'Not specified';
    if (deliveryAddress != null && deliveryAddress.isNotEmpty) {
      cleanAddress = deliveryAddress.contains(',') && deliveryAddress.length > 40 // Basic check for coordinates format
          ? deliveryAddress.split(',').skip(2).join(',').trim()
          : deliveryAddress;
      if (cleanAddress.isEmpty) cleanAddress = deliveryAddress; // Fallback if splitting removes everything
    }


    return Container( // Use Container instead of InkWell for better structure control
        margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
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
            InkWell( // Wrap the header in InkWell for tap detection
              onTap: () {
                setState(() {
                  _isOrderInfoExpanded = !_isOrderInfoExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ORDER DETAILS',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: kColorTextPrimary,
                      ),
                    ),
                    Icon(
                      _isOrderInfoExpanded ? Icons.expand_less : Icons.expand_more,
                      color: kColorTextPrimary,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: kColorDivider), // Divider below header

            // Always visible content
             Padding(
               padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 8.0),
               child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      _buildInfoRow('Product', productName),
                      _buildInfoRow('Customer', customerName == 'N/A' ? 'User #$customerName' : customerName), // Show 'User #' only if name missing
                      _buildInfoRow('Quantity', quantity),
                      _buildInfoRow('Total Price', '$totalPrice UGX'),
                      _buildInfoRow('Order Status', orderStatus),
                      if (needsVerification) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton(
                            onPressed: isLoadingVerification 
                                ? null 
                                : () => _handleVerificationRequest(_selectedOrderId!),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kColorPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: isLoadingVerification
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'VERIFY DELIVERY',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],

                      // Display complementary meals if present
                      _buildComplementaryMealsRow(order['complementary_meals']),

                      // Display Chef or Producer only if they have a value
                      if (chefName != null && chefName.isNotEmpty)
                        _buildInfoRow('Chef', chefName),
                      if (producerName != null && producerName.isNotEmpty)
                        _buildInfoRow('Producer', producerName),
                 ],
               ),
             ),

            // Expandable content using AnimatedCrossFade for smooth transition
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              firstChild: Container(), // Empty container when collapsed
              secondChild: Padding( // Content when expanded
                 padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     const Divider(color: kColorDivider, height: 16, thickness: 1), // Divider before expanded content
                     _buildInfoRow('Contact', contactInfo),
                     _buildInfoRow('Delivery To', cleanAddress),
                     _buildInfoRow('Payment Status', paymentStatus),
                     if (notes != null && notes.isNotEmpty) // Only show if notes exist
                        _buildInfoRow('Notes', notes),
                     // Conditionally show ingredients if relevant and exist
                     if (ingredients != null && ingredients.isNotEmpty && orderType != 'gig')
                       _buildInfoRow('Ingredients', ingredients),
                   ],
                 ),
              ),
              crossFadeState: _isOrderInfoExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            ),

            // Hint for expandable content - adjusted padding and style
            if (!_isOrderInfoExpanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0, top: 0), // Adjusted padding
                child: Center(
                  child: Text(
                    'Tap here for more details', // Changed text
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
    );
  }
  // --- End of Updated _buildOrderInfoCard ---


  Widget _buildTrackingHistoryCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();

    final orderDate = order['order_date']?.toString();
    final currentStatus = order['order_status']?.toString() ?? 'pending';
    final currentSimplifiedIndex = _getSimplifiedStatusIndex(currentStatus);

    // Generate the list of events that have occurred
    final List<Widget> trackingEvents = [];
    for (int i = 0; i <= currentSimplifiedIndex; i++) {
      // Use actual status change times if available, otherwise estimate based on order date
      // TODO: Implement logic to get actual timestamps for each status from order data if available
      final String eventDate = _getSimplifiedStatusDate(orderDate, i); // Using estimated date for now
      final String? eventTime = _getSimplifiedStatusTime(orderDate, i); // Using estimated time for now

      trackingEvents.add(
        _buildTrackingEvent(
          _getSimplifiedStatusName(i),
          eventDate != 'N/A' ? '$eventDate ${eventTime ?? ""}' : 'Pending', // Combine date and time
          isLast: i == currentSimplifiedIndex,
        ),
      );
    }

    if (trackingEvents.isEmpty) {
      // Handle case where even 'Order Placed' hasn't registered (should be rare)
      trackingEvents.add(_buildTrackingEvent('Order Status Pending', '', isLast: true));
    }

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16), // Consistent margin
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
            padding: const EdgeInsets.only(bottom: 12.0), // Add padding below title
            child: Text( // Removed Center, let it align start
              'TRACKING HISTORY',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: kColorTextPrimary,
                fontSize: 16,
              ),
            ),
          ),
          const Divider(color: kColorDivider, height: 1, thickness: 1),
          const SizedBox(height: 16),
          ...trackingEvents, // Spread the list of event widgets
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6), // Increased vertical padding
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
          width: 105, // Slightly reduced label width to give more space to value
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: kColorTextSecondary,
            ),
          ),
        ),
        const SizedBox(width: 20), // Increased spacing between label and value
        Expanded(
          child: Text(
            value.isEmpty ? 'N/A' : value, // Handle empty strings
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kColorTextPrimary,
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildTrackingEvent(String event, String dateTime, {bool isLast = false}) {
    return IntrinsicHeight( // Ensure Row elements align vertically correctly
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children vertically
        children: [
          // Vertical timeline column
          SizedBox(
            width: 30, // Increased width for better spacing
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center, // Center dot/line horizontally
              children: [
                 // Dot
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4), // Align dot with first line of text
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kColorStatusActive,
                  ),
                ),
                // Vertical connecting line (only if not the last item)
                if (!isLast)
                  Expanded( // Let the line fill the remaining space
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4, bottom: 4), // Spacing around line
                      color: kColorStatusActive, // Line color
                    ),
                  ),
                 // Add Spacer if it's the last item to take up equivalent space
                 if (isLast) const Spacer(),
              ],
            ),
          ),
          // Event details column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : 24, // Space below each event, except the last
                top: 2 // Align text slightly below the top of the dot
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    event,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, // Bolder event name
                      fontSize: 14,
                      color: kColorTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (dateTime.isNotEmpty) // Only show date/time if available
                    Text(
                      dateTime,
                      style: GoogleFonts.poppins(
                        color: kColorTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


   Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: kColorPrimary ?? Colors.teal,
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          Text(
            'Loading order details...',
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: kColorTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 60, color: kColorTextSecondary),
          const SizedBox(height: 16),
          Text(
            'No active orders found',
            style: GoogleFonts.poppins(fontSize: 18, color: kColorTextPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'There are no orders matching the provided list.',
            style: GoogleFonts.poppins(color: kColorTextSecondary),
            textAlign: TextAlign.center,
          ),
           const SizedBox(height: 20),
           ElevatedButton.icon(
             icon: const Icon(Icons.refresh, size: 18),
             label: Text('Retry', style: GoogleFonts.poppins()),
             onPressed: _fetchOrders,
             style: ElevatedButton.styleFrom(
               backgroundColor: kColorPrimary,
               foregroundColor: Colors.white,
             ),
           )
        ],
      ),
    );
  }

   Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red[700]),
            const SizedBox(height: 16),
            Text(
              'Error Loading Order',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: kColorTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.poppins(color: kColorTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Retry', style: GoogleFonts.poppins()),
              onPressed: _fetchOrders,
               style: ElevatedButton.styleFrom(
                 backgroundColor: kColorPrimary,
                 foregroundColor: Colors.white,
               ),
            )
          ],
        ),
      ),
    );
  }

  // Helper methods
  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      // Attempt to parse, handling potential timezone offsets
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('d MMMM yyyy').format(dateTime); // Include year
    } catch (e) {
      print("Error formatting date '$dateString': $e");
      return 'Invalid Date'; // Return specific error string
    }
  }

  String? _formatTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('h:mm a').format(dateTime); // Format time
    } catch (e) {
      print("Error formatting time '$dateString': $e");
      return null;
    }
  }

  String _formatStatus(String status) {
     if (status.isEmpty) return 'Pending';
     // Handle specific known statuses for better readability if needed
     switch (status.toLowerCase()) {
        case 'on_the_way': return 'On The Way';
        case 'order_placed': return 'Order Placed';
        // Add more specific cases if your backend uses snake_case frequently
     }
     // General formatting for other cases
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ')
        .trim();
  }

  // --- Simplified Timeline Helpers (as used in _buildStatusTimeline and _buildTrackingHistoryCard) ---

  // Maps backend status string to a simplified index (0, 1, 2)
  int _getSimplifiedStatusIndex(String status) {
    switch (status.toLowerCase()) {
      // Order Placed group
      case 'pending':
      case 'placed':
      case 'order_placed':
        return 0;

      // Dispatched group (covers preparation, acceptance, shipping)
      case 'accepted':
      case 'preparing':
      case 'ready_for_pickup': // Example of another potential status
      case 'shipped':
      case 'dispatched':
      case 'on the way':
      case 'on_the_way':
        return 1;

      // Delivered group
      case 'delivered':
      case 'complete':
      case 'completed':
        return 2;

      // Consider adding cases for failed/cancelled states if needed
      case 'cancelled':
      case 'failed':
        return -1; // Or handle separately

      default:
        print("Warning: Unmapped status encountered in _getSimplifiedStatusIndex: '$status'");
        return 0; // Default to the first step if unknown
    }
  }

  // Gets the display name for a simplified index
  String _getSimplifiedStatusName(int index) {
    switch (index) {
      case 0:
        return 'Order Placed';
      case 1:
        return 'Dispatched'; // Or 'Processing' / 'On The Way' depending on desired label
      case 2:
        return 'Delivered';
      default:
        return 'Unknown Status';
    }
  }

  // Gets an *estimated* date for a simplified timeline step based on the order date
  // TODO: Replace this with actual status timestamp data from the API if available
  String _getSimplifiedStatusDate(String? orderDate, int index) {
    if (orderDate == null || orderDate.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      // Basic estimation: Add some hours/days per step for demonstration
      // In a real app, you'd use actual timestamps for each status change from the API.
      final adjustedDate = dateTime.add(Duration(hours: index * 6)); // Example: 6 hours per step
      return DateFormat('d MMM').format(adjustedDate); // e.g., "15 Feb"
    } catch (e) {
      print("Error calculating simplified status date for index $index from '$orderDate': $e");
      return 'N/A';
    }
  }

  // Gets an *estimated* time for a simplified timeline step
  // TODO: Replace with actual timestamps
   String? _getSimplifiedStatusTime(String? orderDate, int index) {
    if (orderDate == null || orderDate.isEmpty) return null;
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      final adjustedDate = dateTime.add(Duration(hours: index * 6)); // Same estimation as date
      return DateFormat('h:mm a').format(adjustedDate);
    } catch (e) {
      print("Error calculating simplified status time for index $index from '$orderDate': $e");
      return null;
    }
  }

  // --- Original Detailed Status Helpers (kept for reference or potential future use) ---

  // int _getStatusIndex(String status) {
  //   switch (status.toLowerCase()) {
  //     case 'pending': return 0;
  //     case 'placed': return 0; // Alias
  //     case 'order_placed': return 0; // Alias
  //     case 'accepted': return 1;
  //     case 'preparing': return 2;
  //     case 'on the way': return 3;
  //     case 'on_the_way': return 3; // Alias
  //     case 'shipped': return 3; // Alias
  //     case 'dispatched': return 3; // Alias
  //     case 'delivered': return 4;
  //     case 'complete': return 5;
  //     case 'completed': return 5; // Alias
  //     default: return 0;
  //   }
  // }

  // String _getStatusName(int index) {
  //   switch (index) {
  //     case 0: return 'Order Placed';
  //     case 1: return 'Accepted';
  //     case 2: return 'Preparing';
  //     case 3: return 'On The Way';
  //     case 4: return 'Delivered';
  //     case 5: return 'Complete';
  //     default: return 'Unknown Status';
  //   }
  // }

  // String _getStatusDate(String? orderDate, int statusIndex) {
  //    // ... (original estimation logic) ...
  // }

  // String _getStatusTime(String? orderDate, int statusIndex) {
  //    // ... (original estimation logic) ...
  // }

}