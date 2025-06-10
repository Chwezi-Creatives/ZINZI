//cspell:disable
// orderhistory.dart (Corrected)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemUiOverlayStyle
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart'; // For date and currency formatting
import 'dart:async'; // For TimeoutException, Timer
import 'package:shimmer/shimmer.dart'; // For loading shimmer
import 'package:shared_preferences/shared_preferences.dart'; // For Shared Preferences
import 'package:zinzi/user_cache.dart';
import 'package:provider/provider.dart';
import 'notifications/notification_provider.dart'; // For notification refresh functionality

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
    return NumberFormat.currency(symbol: 'ugx ', decimalDigits: 2)
        .format(doubleValue);
  } catch (e) {
    print("Error formatting currency '$amount': $e");
    return amount.toString(); // Return original if parsing fails
  }
}

// Get color for payment status (separate from order status)
Color _getPaymentStatusColor(String? status) {
  if (status == null) return kColorInfo;
  
  status = status.toString().toLowerCase().trim();
  
  // Handle payment status colors
  if (status == 'paid' || status == 'completed') {
    return Colors.green; // Green for successful payments
  } else if (status == 'pending' || status == 'processing_payment') {
    return kColorWarning; // Warning color for pending payments
  } else if (status == 'failed' || status == 'cancelled' || status == 'declined') {
    return kColorCancelled; // Red for failed/cancelled payments
  }
  
  return kColorInfo; // Default color for unknown statuses
}

// Get color for order status
Color _getStatusColor(String? status) {
  if (status == null) return kColorInfo;
  
  status = status.toLowerCase().trim();
  
  // Handle order status colors
  switch (status) {
    case 'delivered':
    case 'completed':
      return kColorSuccess;
    case 'processing':
    case 'shipped':
    case 'preparing':
      return kColorWarning;
    case 'verification needed':
      return Colors.blueGrey;
    case 'cancelled':
    case 'failed':
      return kColorCancelled;
    case 'pending':
      return kColorWarning;
    default:
      return kColorInfo;
  }
}

String _getStatusDisplay(String? status) {
  return status
          ?.trim()
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
          .join(' ')
          .trim() // Ensure no leading/trailing spaces
      ??
      'Unknown'; // Default for null status
}

// --- Order History Screen Widget ---
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  /// Preload order history cache for splash screen (no UI, no context needed)
  static Future<void> preloadCacheForSplash() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('user_id');
    if (userId == null) {
      print('[Splash][OrderHistory] No user ID found, skipping cache preload');
      return;
    }
    
    final String cacheKey = 'order_history_cache';
    final String cacheTsKey = 'order_history_cache_ts';
    final now = DateTime.now();
    
    // Use user-specific cache methods
    final cachedOrders = await UserCache.getUserData(cacheKey, userId: userId);
    final cachedTs = await UserCache.getUserData(cacheTsKey, userId: userId);
    
    bool cacheValid = false;
    if (cachedOrders != null && cachedTs != null) {
      final cacheTime = DateTime.tryParse(cachedTs.toString());
      if (cacheTime != null && now.difference(cacheTime) < const Duration(minutes: 15)) {
        cacheValid = true;
      }
    }
    if (!cacheValid) {
      try {
        final prefs = await SharedPreferences.getInstance();
        String? userId = prefs.getString('user_id');
        if (userId == null || userId.isEmpty) {
          final int? intUserId = prefs.getInt('user_id');
          if (intUserId != null) {
            userId = intUserId.toString();
            await prefs.setString('user_id', userId);
          }
        }
        if (userId != null && userId.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final userType = prefs.getString('user_type') ?? 'customer';
          final uri = Uri.parse('$apiBaseUrl/rr/orders?user_id=$userId&user_type=$userType');
          final response = await http.get(uri).timeout(const Duration(seconds: 35));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data is Map<String, dynamic> && data['data'] is List) {
              final orderDataList = data['data'] as List;
              List<Map<String, dynamic>> orders = [];
              for (final orderItem in orderDataList) {
                if (orderItem is Map<String, dynamic>) {
                  final Map<String, dynamic> orderData = Map<String, dynamic>.from(orderItem);
                  int? parsedId = int.tryParse(orderData['order_id']?.toString() ?? '');
                  if (parsedId != null) {
                    orderData['order_id'] = parsedId;
                    orders.add(orderData);
                  }
                }
              }
              await UserCache.saveUserData(cacheKey, orders, userId: userId);
              await UserCache.saveUserData(cacheTsKey, now.toIso8601String(), userId: userId);
            }
          }
        }
      } catch (e) {
        print('[Splash][OrderHistory] preload error: $e');
      }
    } else {
      print('[Splash][OrderHistory] preload skipped: Cache still valid.');
    }
  }

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> with SingleTickerProviderStateMixin {
  Future<List<Map<String, dynamic>>>? _orderHistoryFuture;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  static const String _cacheKey = 'order_history_cache';
  static const String _cacheTsKey = 'order_history_cache_ts';
  String? _userId; // Store user ID for cache operations
  final Map<int, bool> _isExpandedMap = {};
  Timer? _pollingTimer;
  bool _isRefreshing = false;
  // Track previous order statuses to detect changes
  final Map<int, String> _previousOrderStatuses = {};
  
  // Status filter state
  String? _selectedStatus;
  
  // Available status options for filtering in a logical order
  // Ordered by typical order lifecycle, with most important/most used statuses first
  final List<Map<String, dynamic>> _statusOptions = [
    {'status': 'all', 'label': 'All'},
    {'status': 'pending', 'label': 'Pending'},
    {'status': 'accepted', 'label': 'Accepted'},
    {'status': 'processing', 'label': 'Processing'},
    {'status': 'shipped', 'label': 'Shipped'},
    {'status': 'delivered', 'label': 'Delivered'},
    {'status': 'completed', 'label': 'Completed'},
    {'status': 'verification needed', 'label': 'Needs Verification'},
    // Less common statuses
    {'status': 'cancelled', 'label': 'Cancelled'},
    {'status': 'failed', 'label': 'Failed'},
  ];
  
  // Apply current filters to orders
  void _applyFilters() {
    if (_orders.isEmpty) {
      _filteredOrders = [];
      return;
    }
    
    setState(() {
      if (_selectedStatus == null || _selectedStatus == 'all') {
        _filteredOrders = List.from(_orders);
      } else {
        _filteredOrders = _orders.where((order) {
          final status = order['order_status']?.toString().toLowerCase() ?? 'unknown';
          // Also check for 'assigned' status when looking for 'accepted' as they might be used interchangeably
          if (_selectedStatus == 'accepted' && status == 'assigned') {
            return true;
          }
          return status == _selectedStatus;
        }).toList();
      }
    });
  }
  
  // Set the active status filter
  void _setStatusFilter(String? status) {
    setState(() {
      _selectedStatus = status == _selectedStatus ? null : status;
      if (_selectedStatus == null) {
        _selectedStatus = 'all'; // Default to 'All' if deselected
      }
      _applyFilters();
    });
  }

  // --- State Variables ---
  // Flag to pause polling when verification dialog is active
  bool _isVerificationProcessActive = false;
  // Track which order is currently fetching the verification code for animation
  int? _loadingVerificationOrderId;

  late NotificationProvider _notificationProvider;
  
  // Animation controller for refresh icon
  late AnimationController _refreshController;
  late Animation<double> _refreshAnimation;

  @override
  void initState() {
    super.initState();
    print('[DEBUG] initState called for OrderHistoryScreen');
    print('[OrderHistory] Polling page initialized.'); // DEBUG: Polling page start
    
    // Initialize refresh animation controller
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    // Only start repeating when actually refreshing
    if (_isRefreshing) {
      _refreshController.repeat();
    }
    
    _refreshAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _refreshController,
        curve: Curves.linear,
      ),
    );
    
    _orderHistoryFuture = _loadInitialHistory();
    _startPolling();
    // Listen for notification refreshes
    _notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    _notificationProvider.addListener(_handleNotificationRefresh);
    
    // Initialize filtered orders once data is loaded
    _orderHistoryFuture?.then((orders) {
      if (mounted) {
        setState(() {
          _orders = orders;
          _applyFilters();
        });
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _notificationProvider.removeListener(_handleNotificationRefresh);
    _refreshController.dispose();
    super.dispose();
  }

  void _handleNotificationRefresh() {
    print('[DEBUG] _handleNotificationRefresh called for OrderHistoryScreen');
    if (!_isRefreshing) {
      setState(() {
        _isRefreshing = true;
      });
      _refreshHistorySilently().then((_) {
        if (mounted) {
          setState(() {
            _isRefreshing = false;
          });
        }
      });
    }
  }

  void _startPolling() {
    // Cancel existing timer if any
    _pollingTimer?.cancel();
    print('[OrderHistory] Polling started (interval: 5s).'); // DEBUG: Polling started
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // --- MODIFIED: Only poll if verification process is NOT active ---
      if (!_isVerificationProcessActive && mounted) {
        print("Polling for order updates...");
        _refreshHistorySilently();
      } else {
        print("Polling skipped: Verification process active or widget not mounted.");
      }
    });
  }

  // Fetch history but update state without rebuilding the entire FutureBuilder
  Future<void> _refreshHistorySilently() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString('user_id');
    print('[DEBUG] _refreshHistorySilently called. _isRefreshing=$_isRefreshing, userId=$userId');
    if (_isRefreshing) {
      print('[DEBUG] Early return: _isRefreshing is true, skipping poll.');
      return; // Prevent concurrent refreshes
    }
    
    // Start refresh animation
    if (!_refreshController.isAnimating) {
      _refreshController.repeat();
    } else {
      _refreshController.forward();
    }
    
    setState(() {
      _isRefreshing = true;
    });
    print("Refreshing order history silently...");
    try {
      if (userId == null || userId.isEmpty) {
        final int? intUserId = prefs.getInt('user_id');
        if (intUserId != null) {
          userId = intUserId.toString();
          await prefs.setString('user_id', userId);
        } else {
          print("[DEBUG] Silent Refresh: User ID not found in preferences. Returning early.");
          return;
        }
      }
      print('[DEBUG] Before await _fetchAndUpdateOrderHistory');
      final freshOrders = await _fetchAndUpdateOrderHistory(userId);
      print('[DEBUG] After await _fetchAndUpdateOrderHistory');
      if (mounted) {
        _checkForStatusChanges(freshOrders);
        setState(() {
          _orders = freshOrders;
          _applyFilters();
        });
      }
    } catch (e) {
      print("[DEBUG] Error during silent history refresh: $e");
    } finally {
      // Stop refresh animation
      if (_refreshController.isAnimating) {
        _refreshController.stop();
        _refreshController.value = 0.0; // Reset to initial state
      }
      
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      } else {
        _isRefreshing = false;
      }
      print('[DEBUG] _refreshHistorySilently complete. _isRefreshing=$_isRefreshing');
    }
  }

  Future<List<Map<String, dynamic>>> _loadInitialHistory() async {
    // Reset loading state on full load/refresh
    if (mounted) {
      setState(() {
        _loadingVerificationOrderId = null;
        _isVerificationProcessActive = false; // Ensure reset on full refresh
      });
    }
    
    // Get user ID for cache operations
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    if (_userId == null || _userId!.isEmpty) {
      final int? intUserId = prefs.getInt('user_id');
      if (intUserId != null) {
        _userId = intUserId.toString();
        await prefs.setString('user_id', _userId!);
      } else {
        print("User ID not found in preferences. User needs to log in.");
        throw Exception("User not logged in.");
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) {
        final int? intUserId = prefs.getInt('user_id');
        if (intUserId != null) {
          userId = intUserId.toString();
          await prefs.setString('user_id', userId);
        } else {
          print("User ID not found in preferences. User needs to log in.");
          throw Exception("User not logged in.");
        }
      }
      // --- CACHE-FIRST: Try loading from user-specific cache first ---
      bool cacheValid = false;
      List<Map<String, dynamic>> cachedOrders = [];
      final cachedData = await UserCache.getUserData(_cacheKey, userId: _userId);
      final cachedTs = await UserCache.getUserData(_cacheTsKey, userId: _userId);
      final now = DateTime.now();
      
      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null && now.difference(cacheTime) < const Duration(minutes: 15)) {
          cachedOrders = List<Map<String, dynamic>>.from(cachedData);
          cacheValid = true;
        }
      }
      
      if (cacheValid) {
        print('[OrderHistory] Loaded from user-specific cache.');
        // Start background fetch but return cached data immediately
        _fetchAndUpdateOrderHistory(_userId!);
        if (mounted) {
          setState(() { 
            _orders = List<Map<String, dynamic>>.from(cachedOrders);
            _applyFilters();
          });
        }
        return List<Map<String, dynamic>>.from(cachedOrders);
      } else {
        // No valid cache, fetch from API
        print('[OrderHistory] No valid cache, fetching from API...');
        final freshOrders = await _fetchAndUpdateOrderHistory(_userId!);
        if (mounted) {
          setState(() { 
            _orders = freshOrders;
            _applyFilters();
          });
        }
        return freshOrders;
      }
    } catch (e) {
      print("Error during initial history load setup: $e");
      throw Exception("Failed to initialize order history: "+e.toString());
    }
  }

  // --- Helper to fetch from API and update cache ---
  Future<List<Map<String, dynamic>>> _fetchAndUpdateOrderHistory(String userId) async {
    print('[DEBUG] Entering _fetchAndUpdateOrderHistory for userId=$userId');
    final orders = await _fetchOrderHistoryDetails(userId);
    print('[DEBUG] After await _fetchOrderHistoryDetails in _fetchAndUpdateOrderHistory');
    try {
      // Save to user-specific cache
      await UserCache.saveUserData(_cacheKey, orders, userId: userId);
      await UserCache.saveUserData(_cacheTsKey, DateTime.now().toIso8601String(), userId: userId);
      print('[OrderHistory] Saved to user-specific cache');
    } catch (e) {
      print('[OrderHistory] Error saving to user-specific cache: $e');
    }
    print('[DEBUG] Exiting _fetchAndUpdateOrderHistory for userId=$userId');
    return orders;
  }

  // Track status changes without triggering automatic popups
  void _checkForStatusChanges(List<Map<String, dynamic>> freshOrders) {
    final Map<int, String> currentStatuses = {};
    
    // Build map of current statuses
    for (final order in freshOrders) {
      final orderId = order['order_id'] as int?;
      final status = order['order_status']?.toString();
      if (orderId != null && status != null) {
        currentStatuses[orderId] = status;
      }
    }
    
    // Update previous statuses for reference
    _previousOrderStatuses.clear();
    _previousOrderStatuses.addAll(currentStatuses);
  }

  Future<List<Map<String, dynamic>>> _fetchOrderHistoryDetails(
      String userId) async {
    print('[DEBUG] Entering _fetchOrderHistoryDetails for userId=$userId');
    List<Map<String, dynamic>> orders = [];
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('user_type') ?? 'customer';
    final uri = Uri.parse('$apiBaseUrl/rr/orders?user_id=$userId&user_type=$userType');
    print("Fetching order history from: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 35));
      print('[OrderHistory] Poll result: Status ${response.statusCode}, Body: ${response.body}'); // DEBUG: Show API result

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List) {
          final orderDataList = data['data'] as List;

          for (final orderItem in orderDataList) {
            if (orderItem is Map<String, dynamic>) {
              final Map<String, dynamic> orderData =
                  Map<String, dynamic>.from(orderItem);
              int? parsedId =
                  int.tryParse(orderData['order_id']?.toString() ?? '');
              if (parsedId != null) {
                orderData['order_id'] = parsedId;
                orders.add(orderData);
              } else {
                print(
                    "Warning: Could not parse order_id, skipping: $orderData");
              }
            } else {
              print(
                  "Warning: Non-map item in order data list, skipping: $orderItem");
            }
          }

          // --- Status Change Detection REMOVED ---
          // Dialog is now triggered by user tap, not automatically on status change detection here.
        } else {
          print("Unexpected data format received: $data");
          throw Exception('Invalid data format from server.');
        }
      } else {
        print(
            "Failed fetch: Status ${response.statusCode}, Body: ${response.body}");
        throw Exception(
            'Failed to load order history (Status: ${response.statusCode}).');
      }

      if (orders.isNotEmpty) {
        orders.sort((a, b) {
          DateTime? dateA =
              DateTime.tryParse(a['order_date']?.toString() ?? '');
          DateTime? dateB =
              DateTime.tryParse(b['order_date']?.toString() ?? '');
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
        });
      }

      print("Fetched and sorted ${orders.length} orders.");
      print('[DEBUG] Exiting _fetchOrderHistoryDetails for userId=$userId');
      return orders;
    } on TimeoutException catch (_) {
      print("Order history request timed out.");
      throw Exception('Request timed out. Please check your connection.');
    } on http.ClientException catch (e) {
      print("Network error fetching order history: ${e.message}");
      throw Exception('Network error: Could not connect to the server.');
    } catch (e) {
      print("[DEBUG] Exception in _fetchOrderHistoryDetails for userId=$userId: $e");
      print("Error fetching or processing order history details: $e");
      throw Exception('Failed to load order history. Please try again.');
    }
  }

  // --- NEW: Helper to handle verification tap ---
  Future<void> _handleVerificationRequest(int orderId) async {
    // 1. Pause Polling
    if (mounted) {
      setState(() {
        _isVerificationProcessActive = true;
        // 2. Start Loading Animation for this specific order
        _loadingVerificationOrderId = orderId;
      });
    }
    print("Verification process started for Order #$orderId. Polling paused.");

    // 3. Show Dialog (which includes fetching the code)
    await _showCompletionCodeDialog(orderId);

    // NOTE: Polling resumption (_isVerificationProcessActive = false) happens
    // AFTER the dialog is dismissed (inside _showCompletionCodeDialog's action).
    // Animation stop (_loadingVerificationOrderId = null) happens just BEFORE
    // the dialog is shown (inside _showCompletionCodeDialog).
  }

  // --- MODIFIED: Fetches code AND manages animation/polling state ---
  Future<void> _showCompletionCodeDialog(int orderId) async {
    String completionCode = 'N/A';
    String errorMessage = '';
    bool codeFetchedSuccessfully = false;

    final uri = Uri.parse('$apiBaseUrl/rr/get_completion_code/$orderId');
    print("Fetching completion code for Order #$orderId from: $uri");

    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 35)); // Slightly longer timeout

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['completion_code'] != null) {
          completionCode = data['completion_code'].toString();
          codeFetchedSuccessfully = true; // Mark success
          print("Completion code fetched successfully for Order #$orderId.");
        } else {
          errorMessage = 'Invalid response format for completion code.';
          print("Unexpected completion code response format: $data");
        }
      } else {
        errorMessage =
            'Failed to fetch completion code (Status: ${response.statusCode}).';
        print(
            "Failed to fetch completion code: Status ${response.statusCode}, Body: ${response.body}");
      }
    } on TimeoutException catch (_) {
      errorMessage = 'Request for completion code timed out.';
      print("Completion code request timed out for Order #$orderId.");
    } on http.ClientException catch (e) {
      errorMessage = 'Network error fetching completion code.';
      print(
          "Network error fetching completion code for Order #$orderId: ${e.message}");
    } catch (e) {
      errorMessage = 'Error fetching completion code: ${e.toString()}';
      print("Error fetching completion code for Order #$orderId: $e");
    }

    // --- Stop loading animation BEFORE showing the dialog ---
    if (mounted) {
      setState(() {
        _loadingVerificationOrderId = null;
      });
    }

    // --- Show Dialog ---
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User must tap button to close
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: const Color.fromARGB(
                255, 241, 255, 254), // Added background color
            title: Text(
              // Adjust title based on success
              codeFetchedSuccessfully
                  ? 'Order #$orderId Ready!'
                  : 'Order #$orderId Verification',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: kColorPrimaryDark),
            ),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(
                    errorMessage.isNotEmpty
                        ? 'Could not retrieve verification code: $errorMessage'
                        // Updated message for success state
                        : 'Verification code is ready.',
                    style: GoogleFonts.poppins(color: kColorTextPrimary),
                    textAlign: TextAlign.left, // Added text alignment
                  ),
                  if (errorMessage.isEmpty && codeFetchedSuccessfully) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Verification Code:',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color:
                              kColorPrimaryDark), // Changed color to kColorPrimaryDark
                    ),
                    SelectableText(
                      completionCode,
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color:
                              kColorSuccess), // Color is already kColorSuccess, keeping it
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Provide this code to the rider ONLY after confirming successful delivery.',
                      style: GoogleFonts.poppins(
                          fontStyle: FontStyle.italic,
                          color: kColorTextSecondary,
                          fontSize: 13),
                      textAlign: TextAlign.left,
                    ),
                  ] else if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Please try again shortly or contact support if the issue persists.',
                      style: GoogleFonts.poppins(
                          fontStyle: FontStyle.italic,
                          color: kColorTextSecondary,
                          fontSize: 13),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center, // Center the button
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(
                  // backgroundColor: kColorPrimary.withOpacity(0.1), // Removed background color
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text('OK',
                    style: GoogleFonts.poppins(
                        color: kColorPrimaryDark,
                        fontWeight: FontWeight
                            .bold)), // Changed color to kColorPrimaryDark
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog first
                  // --- Resume polling AFTER dialog is closed ---
                  if (mounted) {
                    setState(() {
                      _isVerificationProcessActive = false;
                    });
                  }
                  print("Verification dialog closed. Polling resumed.");
                  // Optionally trigger a silent refresh now?
                  // _refreshHistorySilently(); // Or let the next poll cycle handle it
                },
              ),
            ],
          );
        },
      );
    } else {
      // If not mounted when dialog should show, ensure polling is resumed
      // This is a fallback, should ideally not happen if logic is correct
      _isVerificationProcessActive = false;
      print("Widget not mounted, ensuring polling is resumed.");
    }
  }

  // Method to refresh the fetch (pull-to-refresh)
  Future<void> _refreshHistory() async {
    print("Refreshing order history via pull-to-refresh...");
    // Ensure verification state is reset on manual refresh
    if (mounted) {
      setState(() {
        _orderHistoryFuture = _loadInitialHistory().then((orders) {
          if (mounted) {
            setState(() {
              _orders = orders;
              _applyFilters();
            });
          }
          return orders;
        });
      });
    }
    // Wait for the refresh to complete (optional, for indicator)
    try {
      await _orderHistoryFuture;
    } catch (e) {
      print("Error caught during manual refresh: $e");
    }
  }

  // Helper to navigate to login
  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
      print("Navigating to login screen.");
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
            'Order History',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: kColorSurface),
          ),
          backgroundColor: kColorPrimary,
          foregroundColor: kColorSurface,
          elevation: 2.0,
          actions: [
            // Refresh button with rotation animation
            AnimatedBuilder(
              animation: _refreshAnimation,
              builder: (context, child) {
                return IconButton(
                  icon: Transform.rotate(
                    angle: _refreshAnimation.value * 2 * 3.14159, // 360 degrees in radians
                    child: Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  onPressed: _isRefreshing
                      ? null // Disable button while refreshing
                      : () {
                          print('Manual refresh triggered from app bar');
                          _refreshHistorySilently();
                        },
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        body: _orderHistoryFuture == null
            ? _buildLoadingShimmer()
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: _orderHistoryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !_isVerificationProcessActive) {
                    return _buildLoadingShimmer();
                  }
                  if (snapshot.hasError) {
                    return _buildErrorWidget(context, snapshot.error);
                  }
                  if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
                    if (snapshot.connectionState == ConnectionState.done && snapshot.error == null) {
                      return _buildEmptyState(context);
                    } else if (snapshot.error != null) {
                      return _buildErrorWidget(context, snapshot.error);
                    } else {
                      return _buildLoadingShimmer();
                    }
                  }
                  // Initial load done, show persistent list
                  return _buildOrderList();
                },
              ),
      ),
    );
  }

  // --- UI Building Widgets ---

  // Build the filter chips for order statuses
  Widget _buildStatusFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: _statusOptions.map((statusData) {
          final status = statusData['status'] as String;
          final label = statusData['label'] as String;
          final isSelected = _selectedStatus == status || 
                           (status == 'all' && (_selectedStatus == null || _selectedStatus == 'all'));
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: ChoiceChip(
              label: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : kColorTextPrimary,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              backgroundColor: Colors.grey[200],
              selectedColor: status == 'all' ? kColorPrimary : _getStatusColor(status),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : kColorTextPrimary,
              ),
              onSelected: (_) => _setStatusFilter(status),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(
                color: isSelected ? 
                  (status == 'all' ? kColorPrimary : _getStatusColor(status)) : 
                  Colors.grey[300]!,
                width: 1,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderList() {
    if (_orders.isEmpty) {
      return _buildEmptyState(context);
    }
    
    return Column(
      children: [
        // Status filter chips
        _buildStatusFilterChips(),
        
        // Order list with pull-to-refresh
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshHistory,
            color: kColorPrimary,
            child: _filteredOrders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No orders match the selected filters',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: kColorTextSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _horizontalPadding / 2,
                      vertical: _verticalPadding / 2,
                    ),
                    itemCount: _filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = _filteredOrders[index];
                      final orderId = order['order_id'] as int;
                      final isExpanded = _isExpandedMap[orderId] ?? false;
                      return _buildOrderCard(context, order, orderId, isExpanded);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order,
      int orderId, bool isExpanded) {
    final String status =
        order['order_status']?.toString().toLowerCase() ?? 'unknown';
    final Color statusColor = _getStatusColor(status);
    final String displayStatus = _getStatusDisplay(
        order['order_status']); // Use original case for display helper
    final bool needsVerification = status == 'verification needed';
    final bool isLoadingVerification =
        _loadingVerificationOrderId == orderId; // Check if THIS card is loading

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
        // Disable tap while loading verification for THIS card
        onTap: isLoadingVerification
            ? null
            : () {
                if (needsVerification) {
                  // Handle tap for verification
                  _handleVerificationRequest(orderId);
                } else {
                  // Toggle expansion for other statuses
                  setState(() {
                    _isExpandedMap[orderId] = !isExpanded;
                  });
                }
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header
            Padding(
              padding: const EdgeInsets.all(_horizontalPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start, // Align items top
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (order['product_name'] != null &&
                            order['product_name'].toString().isNotEmpty)
                          Text(
                            order['product_name'].toString(),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: kColorTextPrimary,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        Text(
                          'Order #$orderId',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: kColorTextSecondary, // Less prominent
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Placed: ${_formatDate(order['order_date'])}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: kColorTextSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // --- MODIFIED: Conditional Status/Loading Indicator ---
                  Container(
                    alignment: Alignment.center,
                    // Give it a minimum size to avoid layout shifts drastically
                    constraints:
                        const BoxConstraints(minHeight: 28, minWidth: 60),
                    child: isLoadingVerification
                        ? const SizedBox(
                            // Use SizedBox to constrain the spinner size
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: kColorPrimary,
                            ),
                          )
                        : Row(
                            // Show icon + chip if not loading
                            mainAxisSize: MainAxisSize.min, // Keep row tight
                            children: [
                              if (needsVerification) // Show warning icon only if verification needed AND not loading
                                Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: Icon(
                                    Icons
                                        .password_rounded, // Icon suggesting code needed
                                    color: kColorWarning,
                                    size: 18,
                                  ),
                                ),
                              Chip(
                                label: Text(
                                  displayStatus,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                backgroundColor: statusColor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                  ),
                  // --- End Conditional Status/Loading Indicator ---
                ],
              ),
            ),

            // Animated Expansion Section
            AnimatedCrossFade(
              firstChild: Container(),
              secondChild: _buildOrderDetails(context, order),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
              firstCurve: Curves.easeOut,
              secondCurve: Curves.easeIn,
              sizeCurve: Curves.easeInOut,
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                  vertical: _verticalPadding / 1.5),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kColorTextSecondary,
                        ),
                  ),
                  Text(
                    _formatCurrency(order['total_price']),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kColorPrimaryDark,
                        ),
                  ),
                ],
              ),
            ),
            // Expansion Indicator (only show if not needing verification or loading)
            if (!needsVerification && !isLoadingVerification)
              Container(
                height: 25,
                color: Colors.grey.shade100,
                alignment: Alignment.center,
                child: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: kColorTextSecondary.withOpacity(0.6),
                  size: 20,
                ),
              )
            else // Provide a similar height empty space if verification needed/loading to maintain layout consistency
              Container(
                height: 25,
                color: Colors.grey.shade100,
              )
          ],
        ),
      ),
    );
  }

  // --- NO CHANGES needed below this line for the requested features ---
  // --- (Assuming _buildOrderDetails, _buildDetailRow, _buildLoadingShimmer, etc. are correct) ---

  Widget _buildOrderDetails(BuildContext context, Map<String, dynamic> order) {
    // Safely extract items list
    final List<dynamic> itemsList =
        order['items'] is List ? order['items'] : [];

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
            icon: Icons.shopping_basket_outlined,
            label: 'Payment Mode',
            value: _getStatusDisplay(order['payment_mode']),
          ),
          _buildDetailRow(
            context,
            icon: Icons.credit_card_outlined,
            label: 'Payment Status',
            value: _getStatusDisplay(order['payment_status']),
            valueColor: _getPaymentStatusColor(order['payment_status']),
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
                if (item is! Map<String, dynamic>) {
                  return const SizedBox.shrink(); // Skip invalid items
                }

                String itemDisplay = 'Unknown Item';
                List<Widget> details = [];
                String? itemType = item['type']?.toString().toLowerCase();

                // Try to get common fields first
                final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
                final pricePerUnit = (item['price'] as num?)?.toDouble();
                final totalPrice =
                    pricePerUnit != null ? pricePerUnit * quantity : null;

                // Try to find a name/title for any item type
                final itemName =
                    item['poduct_name'] ?? // Typo? 'product_name' maybe?
                        item['product_name'] ??
                        item['title'] ??
                        item['meal_name'] ??
                        item['gig_type'] ??
                        'Unknown Item';

                itemDisplay = "$itemName";
                if (quantity > 1) {
                  itemDisplay += " (x$quantity)";
                }
                if (totalPrice != null) {
                  itemDisplay += " - ${_formatCurrency(totalPrice)}";
                } else if (pricePerUnit != null) {
                  itemDisplay += " - ${_formatCurrency(pricePerUnit)}";
                }

                // Add type-specific details
                if (itemType == 'meal') {
                  final chef = item['selectedchef'] as Map<String, dynamic>?;
                  final bestServedWith = (item['bestservedwith'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      [];

                  if (chef != null && chef['name'] != null) {
                    details.add(Text(
                      'Chef: ${chef['name']}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }

                  if (bestServedWith.isNotEmpty) {
                    details.add(Text(
                      'Served with: ${bestServedWith.map((comp) => comp['name'] ?? comp['title'] ?? 'Unknown').join(', ')}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }
                } else if (itemType == 'gig') {
                  final gigDetails =
                      item['gigDetails'] as Map<String, dynamic>? ?? {};
                  final chefName = gigDetails['chef_name'];
                  final producerName = gigDetails['producer_name'];

                  if (chefName != null && chefName.isNotEmpty) {
                    details.add(Text(
                      'Chef: $chefName',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  } else if (producerName != null && producerName.isNotEmpty) {
                    details.add(Text(
                      'Producer: $producerName',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }

                  // Add other relevant gig details here if needed (e.g., date, time, location)
                  if (gigDetails['scheduled_date'] != null) {
                    details.add(Text(
                      'Date: ${_formatDate(gigDetails['scheduled_date'])}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }
                  if (gigDetails['time'] != null) {
                    details.add(Text(
                      'Time: ${gigDetails['time']}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }
                  if (gigDetails['location'] != null) {
                    details.add(Text(
                      'Location: ${gigDetails['location']}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: kColorTextSecondary),
                    ));
                  }
                }
                // Add more else if blocks here for other known item types if needed

                // Generic details for any item type if available
                if (item['description'] != null &&
                    item['description'].toString().isNotEmpty) {
                  details.add(Text(
                    'Description: ${item['description']}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: kColorTextSecondary),
                  ));
                }

                return Padding(
                  padding: const EdgeInsets.only(
                      left: 20.0, top: 4.0), // Indent items
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "- $itemDisplay",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: kColorTextPrimary,
                            ),
                      ),
                      ...details, // Add specific details below the item name
                    ],
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
                  Row(
                    // Shimmer Header
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 100 + (index % 3 * 20),
                              height: 16,
                              color: Colors.white), // Variable width
                          const SizedBox(height: 6),
                          Container(
                              width: 140 + (index % 2 * 30),
                              height: 12,
                              color: Colors.white),
                        ],
                      ),
                      Container(
                          width: 60 + (index % 2 * 10),
                          height: 24,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12))),
                    ],
                  ),
                  const SizedBox(
                      height: 16), // Spacing before footer/details area
                  // Shimmer Footer Area (Mimics total amount row)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: Colors.white.withOpacity(0.7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(width: 60, height: 14, color: Colors.white),
                        Container(width: 80, height: 14, color: Colors.white),
                      ],
                    ),
                  ),
                  Container(
                      height: 25,
                      color: Colors.white
                          .withOpacity(0.7)), // Expansion indicator space
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
        errorMessage = "Please log in to view your order history.";
      } else if (errorMessage.contains("Network error")) {
        errorMessage =
            "Could not connect to the server. Please check your internet connection.";
      } else if (errorMessage.contains("timed out")) {
        errorMessage = "The request took too long. Please try again later.";
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_horizontalPadding * 1.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(showLoginButton ? Icons.login : Icons.error_outline,
                color: kColorError, size: 50),
            const SizedBox(height: _verticalPadding),
            Text(
              showLoginButton ? 'Login Required' : 'Load Failed',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: kColorTextPrimary, fontWeight: FontWeight.w600),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _navigateToLogin,
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kColorPrimary,
                  foregroundColor: kColorSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: _refreshHistory, // Manual refresh
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
            Icon(Icons.receipt_long_outlined,
                color: kColorTextSecondary.withOpacity(0.6), size: 50),
            const SizedBox(height: _verticalPadding),
            Text(
              'Refreshing order list please wait',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: kColorTextPrimary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "You haven't placed any orders yet.\nStart shopping to see your history here!",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: kColorTextSecondary, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: _verticalPadding * 1.5),
            ElevatedButton(
              child: const Text('Start Shopping'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kColorPrimary,
                foregroundColor: kColorSurface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                // Ensure the home route exists and is named '/home'
                if (mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/home', (route) => false);
                }
              },
            )
          ],
        ),
      ),
    );
  }
}
