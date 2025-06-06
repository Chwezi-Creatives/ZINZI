import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:zinzi/app_drawer_unified.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'notifications/notification_provider.dart';

// Add this to your main.dart or a separate routes.dart file
class AppRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  static final AppRouteObserver _instance = AppRouteObserver._internal();

  factory AppRouteObserver() => _instance;

  AppRouteObserver._internal();
}

// Add this to your MaterialApp's navigatorObservers:
// navigatorObservers: [AppRouteObserver()],

// --- Environment & API ---
// Ensure you have initialized dotenv in your main.dart: await dotenv.load(fileName: ".env");
final String _apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://your.default.api.url/fallback'; // Provide a sensible fallback

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
const Color kColorTimelineLine = Color(0xFFE0E0E0);

class OrderStatusScreen extends StatefulWidget {
  final String userId;
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

class _OrderStatusScreenState extends State<OrderStatusScreen>
    with RouteAware, WidgetsBindingObserver, TickerProviderStateMixin {
  // Track if the route is currently visible
  bool _isRouteActive = false;
  // Controllers
  late final TabController _tabController;
  late final AnimationController _refreshIconController;
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _pollingTimer;
  int? _selectedOrderId;
  bool _isOrderInfoExpanded = false;
  bool _isLoading = true; // For initial page load
  bool _isRefreshing =
      false; // For any data fetch operation (poll, pull-to-refresh, notification)
  final Map<int, Map<String, dynamic>> _ordersMap = {};
  final Map<int, String> _previousOrderStatuses = {};
  bool _isVerificationProcessActive = false;
  int? _loadingVerificationOrderId;

  // Logging helper
  void _log(String message) {
    // In a real app, you might use a dedicated logger package (e.g., 'logger')
    print('[OrderStatusScreen] $message');
  }

  @override
  void initState() {
    super.initState();
    _log('initState called.');

    // Initialize controllers
    _tabController = TabController(length: 4, vsync: this);
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Set up audio player
    _audioPlayer.setReleaseMode(ReleaseMode.release);

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    _log('API Base URL: $_apiBaseUrl');
    _log('Initial User ID: ${widget.userId}');
    _log('Initial Order ID List: ${widget.orderIdList}');

    if (widget.orderIdList.isNotEmpty) {
      _selectedOrderId = widget.orderIdList.length > 1
          ? widget.orderIdList.first
          : widget.orderIdList.first;
      _log('Selected Order ID set to: $_selectedOrderId');
      _fetchOrders(isInitialFetch: true);
    }

    final notificationProvider =
        Provider.of<NotificationProvider>(context, listen: false);
    notificationProvider.addListener(_handleNotificationRefresh);
    _log('Notification listener added.');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final route = ModalRoute.of(context);
    if (route != null) {
      AppRouteObserver().subscribe(this, route as PageRoute);
      // Update route status based on current route state
      _updateRouteStatus(route.isCurrent);
    }
  }

  @override
  void dispose() {
    _log('dispose() called.');

    // Cancel any active polling
    _stopPolling();

    // Cancel any pending callbacks
    _tabController.animation?.removeListener(() {});

    // Dispose audio player
    try {
      _audioPlayer.dispose();
    } catch (e) {
      _log('Error disposing audio player: $e');
    }

    // Remove route observer
    try {
      AppRouteObserver().unsubscribe(this);
    } catch (e) {
      _log('Error unsubscribing from route observer: $e');
    }

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Remove notification listener
    try {
      final notificationProvider = Provider.of<NotificationProvider>(
        context,
        listen: false,
      );
      notificationProvider.removeListener(_handleNotificationRefresh);
    } catch (e) {
      _log('Error removing notification listener: $e');
    }

    // Dispose controllers
    _tabController.dispose();
    _refreshIconController.dispose();
    _scrollController.dispose();

    _log('All resources disposed.');
    super.dispose();
  }

  void _handleNotificationRefresh() {
    _log('Notification refresh triggered.');
    if (!_isRefreshing) {
      _log('Starting fetch due to notification.');
      _fetchOrders();
    } else {
      _log(
          'Skipping notification refresh, another fetch is already in progress.');
    }
  }

  Widget _buildComplementaryMealsRow(dynamic complementaryMealsRaw) {
    if (complementaryMealsRaw == null ||
        complementaryMealsRaw.toString().trim().isEmpty) {
      return const SizedBox.shrink();
    }
    List<dynamic> mealsList;
    try {
      if (complementaryMealsRaw is String) {
        final decoded = json.decode(complementaryMealsRaw);
        if (decoded is List) {
          mealsList = decoded;
        } else {
          _log(
              'Complementary meals raw string is not a list after decoding: $complementaryMealsRaw');
          return const SizedBox.shrink();
        }
      } else if (complementaryMealsRaw is List) {
        mealsList = complementaryMealsRaw;
      } else {
        _log(
            'Complementary meals raw data is not a string or list: $complementaryMealsRaw');
        return const SizedBox.shrink();
      }
      final names = mealsList
          .map((item) => (item is Map && item['name'] != null)
              ? item['name'].toString().replaceAll(RegExp(r'[\/]+'), '').trim()
              : null)
          .where((name) => name != null && name.isNotEmpty)
          .toList();

      if (names.isEmpty) {
        _log('No valid names found in complementary meals list.');
        return const SizedBox.shrink();
      }
      return _buildInfoRow('Best served with', names.join(', '));
    } catch (e, s) {
      _log(
          'Error parsing complementary meals: $e. Raw data: $complementaryMealsRaw. Stack: $s');
      return const SizedBox.shrink();
    }
  }

  // List of terminal order statuses where we can stop polling (case insensitive)
  final List<String> _terminalStatuses = [
    'completed',
    'complete',
    'delivered',
    'cancelled',
    'rejected',
    'failed',
    'refunded'
  ];

  // Check if all orders are in a terminal state
  bool _allOrdersInTerminalState() {
    if (_ordersMap.isEmpty) return false;

    return _ordersMap.values.every((order) {
      final status =
          order['order_status']?.toString().toLowerCase().trim() ?? '';
      return _terminalStatuses.any(
          (terminalStatus) => status == terminalStatus.toLowerCase().trim());
    });
  }

  void _stopPolling() {
    _log('Stopping polling timer...');
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _log('Polling timer stopped.');
  }

  void _startPolling() {
    _log('Attempting to start polling...');

    // Don't start polling if the route is not active
    if (!_isRouteActive) {
      _log('Not starting polling - route is not active.');
      return;
    }

    // Don't start polling if all orders are in terminal state
    if (_allOrdersInTerminalState()) {
      _log('Not starting polling - all orders are in terminal state.');
      return;
    }

    // If already polling, just return
    if (_pollingTimer != null && _pollingTimer!.isActive) {
      _log('Polling timer already active. Not starting a new one.');
      return;
    }

    // Cancel any existing timer just in case
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _log(
          'Polling timer tick. mounted: $mounted, _isVerificationProcessActive: $_isVerificationProcessActive, _isRefreshing: $_isRefreshing');

      // Check if widget is still mounted
      if (!mounted) {
        _log('Widget not mounted, cancelling timer.');
        timer.cancel();
        return;
      }

      // Check if route is still active
      if (!_isRouteActive) {
        _log('Route is no longer active, stopping polling.');
        _stopPolling();
        return;
      }

      // Check if all orders are in terminal state
      if (_allOrdersInTerminalState()) {
        _log('All orders in terminal state, stopping polling.');
        _stopPolling();
        return;
      }

      // Check if we should skip this poll
      if (_isVerificationProcessActive || _isRefreshing) {
        String reason = '';
        if (_isVerificationProcessActive)
          reason += 'Verification process active. ';
        if (_isRefreshing) reason += 'A refresh is already in progress. ';
        _log('Polling: Skipped. Reason: ${reason.isEmpty ? "None" : reason}');
        return;
      }

      // All checks passed, fetch orders
      _log('Polling: Conditions met, calling _fetchOrders.');
      _fetchOrders().then((_) {
        _log('Polling fetch completed.');
      }).catchError((error, stackTrace) {
        _log('Error during polling fetch: $error\n$stackTrace');
      });
    });

    _log('Polling timer started with 10-second interval.');
  }

  void _checkForStatusChanges(Map<int, Map<String, dynamic>> updatedOrders) {
    _log('Checking for status changes...');
    final Map<int, String> currentStatuses = {};

    updatedOrders.forEach((orderId, orderData) {
      final status = orderData['order_status']
          ?.toString()
          .toLowerCase(); // Convert to lowercase
      if (status != null) {
        currentStatuses[orderId] = status;
      }
    });

    currentStatuses.forEach((orderId, newStatus) {
      final previousStatus = _previousOrderStatuses[orderId];
      _log(
          'Order #$orderId: New status "$newStatus", Previous status "$previousStatus"');
      if (newStatus.toLowerCase() ==
              'verification needed'.toLowerCase() && // Compare with lowercase
          newStatus.toLowerCase() !=
              (previousStatus?.toLowerCase() ?? '') && // Compare with lowercase
          !_isVerificationProcessActive) {
        _log(
            'Order #$orderId requires verification. Current status: "$newStatus", Previous: "$previousStatus". Triggering verification.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleVerificationRequest(orderId);
          } else {
            _log(
                'Widget not mounted when trying to show verification dialog for order #$orderId via postFrameCallback.');
          }
        });
      }
    });

    _previousOrderStatuses.clear();
    _previousOrderStatuses.addAll(currentStatuses);
    _log('Previous statuses updated.');
  }

  Future<void> _handleVerificationRequest(int orderId) async {
    _log('Starting verification process for Order #$orderId.');
    if (!mounted) {
      _log(
          'Cannot handle verification request, widget not mounted for Order #$orderId.');
      return;
    }

    setState(() {
      _isVerificationProcessActive = true;
      _loadingVerificationOrderId = orderId;
      _log(
          'State updated: _isVerificationProcessActive = true, _loadingVerificationOrderId = $orderId. Polling will be paused.');
    });

    await _showCompletionCodeDialog(orderId);
    // _isVerificationProcessActive will be set to false when dialog is closed or an error occurs that prevents dialog showing.
  }

  Future<void> _showCompletionCodeDialog(int orderId) async {
    String completionCode = 'N/A';
    String errorMessage = '';
    bool codeFetchedSuccessfully = false;

    final uri = Uri.parse('$_apiBaseUrl/rr/get_completion_code/$orderId');
    _log("Fetching completion code for Order #$orderId from: $uri");

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      String responseBodySummary = response.body;
      if (responseBodySummary.length > 200)
        responseBodySummary = "${responseBodySummary.substring(0, 200)}...";
      _log(
          "Completion code API response for Order #$orderId: Status ${response.statusCode}, Body (summary): $responseBodySummary");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['completion_code'] != null) {
          completionCode = data['completion_code'].toString();
          codeFetchedSuccessfully = true;
          _log(
              "Completion code '$completionCode' fetched successfully for Order #$orderId.");
        } else {
          errorMessage = 'Invalid response format for completion code.';
          _log(
              "Unexpected completion code response format for Order #$orderId: $data");
        }
      } else {
        errorMessage =
            'Failed to fetch completion code (Status: ${response.statusCode}).';
        _log(
            "Failed to fetch completion code for Order #$orderId: Status ${response.statusCode}, Body: ${response.body}");
      }
    } on TimeoutException catch (e, s) {
      errorMessage = 'Request for completion code timed out.';
      _log(
          "Completion code request timed out for Order #$orderId. Error: $e, Stack: $s");
    } on http.ClientException catch (e, s) {
      errorMessage = 'Network error fetching completion code: ${e.message}.';
      _log(
          "Network error fetching completion code for Order #$orderId: ${e.message}. Error: $e, Stack: $s");
    } catch (e, s) {
      errorMessage = 'Error fetching completion code: ${e.toString()}';
      _log(
          "Generic error fetching completion code for Order #$orderId: $e, Stack: $s");
    }

    if (!mounted) {
      _log(
          'Widget not mounted after fetching completion code for Order #$orderId. Dialog will not be shown.');
      // If not mounted, ensure verification process is reset if it was started.
      if (_isVerificationProcessActive &&
          _loadingVerificationOrderId == orderId) {
        // No setState here as widget is not mounted. Just log and ensure state is eventually consistent if re-mounted.
        _isVerificationProcessActive = false;
        _loadingVerificationOrderId = null;
        _log(
            'Reset _isVerificationProcessActive and _loadingVerificationOrderId as widget unmounted during code fetch.');
      }
      return;
    }

    // Stop loading animation for this specific order before showing the dialog
    setState(() {
      if (_loadingVerificationOrderId == orderId) {
        _loadingVerificationOrderId = null;
      }
      _log('State updated: _loadingVerificationOrderId reset for $orderId.');
    });

    showDialog(
      context: context,
      barrierDismissible: false, // User must explicitly close
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 241, 255, 254),
          title: Text(
            codeFetchedSuccessfully
                ? 'Order #$orderId Ready!'
                : 'Order #$orderId Verification',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, color: kColorPrimary),
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
                  Text('Verification Code:',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold, color: kColorPrimary)),
                  SelectableText(completionCode,
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kColorStatusActive),
                      textAlign: TextAlign.left),
                  const SizedBox(height: 16),
                  Text(
                      'Provide this code to the rider ONLY after confirming successful delivery.',
                      style: GoogleFonts.poppins(
                          fontStyle: FontStyle.italic,
                          color: kColorTextSecondary,
                          fontSize: 13),
                      textAlign: TextAlign.left),
                ] else if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                      'Please try again shortly or contact support if the issue persists.',
                      style: GoogleFonts.poppins(
                          fontStyle: FontStyle.italic,
                          color: kColorTextSecondary,
                          fontSize: 13),
                      textAlign: TextAlign.left),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // State update handled by .then() block after showDialog
              },
              child: Text('CLOSE',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold, color: kColorPrimary)),
            ),
          ],
        );
      },
    ).then((_) {
      // This block executes after the dialog is popped, regardless of how it's popped.
      if (mounted) {
        setState(() {
          _isVerificationProcessActive = false;
          // _loadingVerificationOrderId should have been cleared before showing dialog,
          // but ensure it's clear if the dialog was for the currently loading order.
          if (_loadingVerificationOrderId == orderId)
            _loadingVerificationOrderId = null;
          _log(
              'Verification dialog for Order #$orderId closed. State updated: _isVerificationProcessActive = false. Polling will resume if conditions met.');
        });
      } else {
        _log(
            'Widget not mounted when verification dialog for Order #$orderId was closed.');
      }
    });
  }

  // Check if we should continue polling based on order statuses and route visibility
  void _checkAndUpdatePolling() {
    if (!mounted) {
      _log('Widget not mounted, not updating polling state.');
      return;
    }

    if (!_isRouteActive) {
      _log('Route is not active, not starting polling.');
      _stopPolling();
      return;
    }

    if (_allOrdersInTerminalState()) {
      _log('All orders in terminal state, stopping polling.');
      _stopPolling();
    } else if (_pollingTimer == null || !_pollingTimer!.isActive) {
      _log(
          'Not all orders in terminal state and polling not active, starting polling.');
      _startPolling();
    } else {
      _log('Polling already active, no action needed.');
    }
  }

  // Called when the current route has been pushed.
  @override
  void didPush() {
    _log('Route was pushed');
    _updateRouteStatus(true);
  }

  @override
  void didPopNext() {
    _log('Route was popped next (user returned to this route)');
    _updateRouteStatus(true);
  }

  @override
  void didPushNext() {
    _log('Route push next');
    _updateRouteStatus(false);
  }

  @override
  void didPop() {
    _log('Route was popped');
    _updateRouteStatus(false);
  }

  // Update route status and manage polling
  void _updateRouteStatus(bool isActive) {
    if (!mounted) {
      _log('Widget not mounted, skipping route status update');
      return;
    }

    _log('Route active state changed to: $isActive');

    setState(() {
      _isRouteActive = isActive;
    });

    if (isActive) {
      // If route became active, check if we need to start polling
      _checkAndUpdatePolling();
      // Also do an immediate fetch to get fresh data
      _fetchOrders();
    } else {
      // If route is no longer active, stop polling
      _stopPolling();
    }
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('App lifecycle state changed to: $state');

    if (state == AppLifecycleState.resumed) {
      // App came back to the foreground
      if (_isRouteActive) {
        _log(
            'App resumed and route is active, checking if polling should resume');
        _checkAndUpdatePolling();
        // Do an immediate fetch to get fresh data
        _fetchOrders();
      }
    } else if (state == AppLifecycleState.paused) {
      // App went to the background
      _log('App paused, stopping polling');
      _stopPolling();
    }
  }

  Future<void> _fetchOrders({bool isInitialFetch = false}) async {
    _log(
        '_fetchOrders called. isInitialFetch: $isInitialFetch, current _isRefreshing: $_isRefreshing, current _isLoading: $_isLoading');

    if (_isRefreshing && !isInitialFetch) {
      _log(
          '_fetchOrders: Already refreshing (and not initial fetch), skipping this call.');
      return;
    }
    if (widget.orderIdList.isEmpty) {
      _log('_fetchOrders: Order ID list is empty. Nothing to fetch.');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        if (isInitialFetch) _isLoading = true;
        _isRefreshing = true;
        _log(
            '_fetchOrders: Set _isRefreshing = true. _isLoading is now $_isLoading.');
      });
    } else {
      // If not mounted, cannot proceed with fetch that updates state.
      _log(
          '_fetchOrders: Widget not mounted at the beginning of fetch. Aborting.');
      return;
    }

    try {
      _log('Fetching data for order IDs: ${widget.orderIdList}');
      final prefs = await SharedPreferences.getInstance();
      final userType = prefs.getString('user_type') ?? 'customer';
      final fetchFutures = widget.orderIdList.map((orderId) async {
        try {
          final uri = Uri.parse(
              '$_apiBaseUrl/rr/orders?user_id=${widget.userId}&order_id=$orderId&user_type=$userType');
          _log('Fetching details for Order #$orderId from: $uri');
          final response =
              await http.get(uri).timeout(const Duration(seconds: 25));

          String responseBodySummary = response.body;
          if (responseBodySummary.length > 200)
            responseBodySummary = "${responseBodySummary.substring(0, 200)}...";
          _log(
              'API Response for Order #$orderId: Status ${response.statusCode}, Body (summary): $responseBodySummary');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data is Map<String, dynamic> && data['data'] is List) {
              final orderDataList = data['data'] as List;
              if (orderDataList.isNotEmpty &&
                  orderDataList.first is Map<String, dynamic>) {
                final Map<String, dynamic> orderData =
                    Map<String, dynamic>.from(orderDataList.first);
                orderData['order_id'] =
                    int.tryParse(orderData['order_id']?.toString() ?? '') ??
                        orderId;
                _log('Successfully parsed data for Order #$orderId.');
                return orderData;
              } else {
                _log(
                    'Order #$orderId: Data list is empty or first item is not a map. Response data: ${data['data']}');
              }
            } else {
              _log(
                  'Unexpected response format for Order #$orderId. Expected Map with "data" as List. Got: ${data.runtimeType}');
            }
          } else {
            _log(
                'Error fetching details for Order #$orderId: Status ${response.statusCode}. Body: ${response.body}');
          }
        } on TimeoutException catch (e, s) {
          _log(
              'Timeout error fetching details for Order #$orderId: $e, Stack: $s');
        } on http.ClientException catch (e, s) {
          _log(
              'Client/Network error fetching details for Order #$orderId: ${e.message}. Error: $e, Stack: $s');
        } catch (e, s) {
          _log(
              'Generic error fetching details for Order #$orderId: $e, Stack: $s');
        }
        return null;
      }).toList();

      final results = await Future.wait(fetchFutures);
      _log(
          'All order fetch futures completed. Number of results: ${results.length}');

      if (!mounted) {
        _log(
            '_fetchOrders: Widget not mounted after awaiting fetch futures. Aborting state update.');
        // Set _isRefreshing to false as the operation is done, even if no UI update.
        _isRefreshing = false;
        return;
      }

      bool dataUpdated = false;
      final Map<int, Map<String, dynamic>> updatedOrders = {};

      for (final orderData in results) {
        if (orderData != null && orderData['order_id'] != null) {
          final int currentOrderId = orderData['order_id'];
          updatedOrders[currentOrderId] = orderData;

          final String currentOrderStatus =
              orderData['order_status']?.toString() ?? 'pending';

          if (_ordersMap.containsKey(currentOrderId)) {
            if (_ordersMap[currentOrderId]?['order_status'] !=
                currentOrderStatus) {
              _log(
                  'Order #$currentOrderId status changed from "${_ordersMap[currentOrderId]?['order_status']}" to "$currentOrderStatus". Playing sound.');
              _playStatusChangeSound();
              dataUpdated = true;
            } else if (jsonEncode(_ordersMap[currentOrderId]) !=
                jsonEncode(orderData)) {
              _log('Order #$currentOrderId data changed (other than status).');
              dataUpdated = true;
            }
          } else {
            _log('New order data received for Order #$currentOrderId.');
            dataUpdated = true;
          }
        }
      }

      if (dataUpdated || _isLoading) {
        _log(
            'Data updated or initial load. Updating state. dataUpdated: $dataUpdated, _isLoading (before setState): $_isLoading');
        setState(() {
          _ordersMap.clear();
          _ordersMap.addAll(updatedOrders);
          if (_selectedOrderId == null ||
              !_ordersMap.containsKey(_selectedOrderId)) {
            _selectedOrderId = _ordersMap.keys.firstOrNull;
            _isOrderInfoExpanded = false;
            _log(
                'Selected order ID re-evaluated to: $_selectedOrderId. Order info expansion reset.');
          }
          if (_isLoading) _isLoading = false;
        });
        _log(
            'State updated with new order data. Order map size: ${_ordersMap.length}. _isLoading is now $_isLoading.');
        _checkForStatusChanges(updatedOrders);
      } else {
        _log('No data changes detected for existing orders.');
        if (_isLoading && mounted) {
          setState(() {
            _isLoading = false;
          });
          _log(
              'Initial load resulted in no data changes (or all fetches failed silently). Setting _isLoading to false.');
        }
      }
    } catch (e, s) {
      _log('Error in _fetchOrders main try block: $e, Stack: $s');
      if (mounted) {
        setState(() {
          if (_isLoading) _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _log('_fetchOrders: finally block. Set _isRefreshing = false.');
          if (widget.orderIdList.isEmpty && _isLoading) {
            _isLoading = false; // Ensure isLoading is false if list was empty
          }

          // Update polling state based on current order statuses
          _checkAndUpdatePolling();
        });
      } else {
        // If not mounted, still ensure _isRefreshing is reset if it was set.
        _isRefreshing = false;
        _log(
            '_fetchOrders: finally block. Widget not mounted. Set _isRefreshing = false.');
      }
    }
    _log(
        '_fetchOrders completed. Final state: _isLoading: $_isLoading, _isRefreshing: $_isRefreshing');
  }

  void _playStatusChangeSound() async {
    _log('Playing status change sound.');
    try {
      await _audioPlayer.play(AssetSource(
          'sounds/chime.mp3')); // Ensure path is correct in pubspec.yaml and assets folder
      _log('Sound played successfully.');
    } catch (e) {
      _log("Error playing status change sound: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    _log(
        'Build method called. _isLoading: $_isLoading, _ordersMap empty: ${_ordersMap.isEmpty}, _selectedOrderId: $_selectedOrderId, orderIdList empty: ${widget.orderIdList.isEmpty}');
    return Scaffold(
      backgroundColor: kColorBackground,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text('ORDER STATUS',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18)),
        centerTitle: true,
        backgroundColor: kColorPrimary,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle:
            SystemUiOverlayStyle.light.copyWith(statusBarColor: kColorPrimary),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      _log('_buildBody: Showing loading state.');
      return _buildLoadingState();
    }
    // If orderIdList was initially empty, or if _ordersMap became empty after fetches and no order is selected.
    if (widget.orderIdList.isEmpty ||
        (_ordersMap.isEmpty && _selectedOrderId == null)) {
      _log(
          '_buildBody: Showing empty state (orderIdList empty: ${widget.orderIdList.isEmpty}, _ordersMap empty: ${_ordersMap.isEmpty}, _selectedOrderId: $_selectedOrderId).');
      return _buildEmptyState();
    }
    // If selected order ID is invalid or its data is missing, but other orders might exist.
    if (_selectedOrderId == null || !_ordersMap.containsKey(_selectedOrderId)) {
      _log(
          '_buildBody: Selected order ID ($_selectedOrderId) is invalid or its data is missing from map. Keys: ${_ordersMap.keys}');
      if (_ordersMap.isNotEmpty) {
        _log(
            '_buildBody: Attempting to auto-select first available order as fallback.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedOrderId = _ordersMap.keys.first;
              _isOrderInfoExpanded = false;
              _log(
                  '_buildBody: Auto-selected order ID: $_selectedOrderId via postFrameCallback.');
            });
          }
        });
        return _buildLoadingState(); // Show loading briefly while state updates
      } else {
        // This case means orderIdList was not empty, but _ordersMap is empty (all fetches failed or returned no data)
        _log(
            '_buildBody: Showing empty state because _ordersMap is empty despite non-empty orderIdList.');
        return _buildEmptyState();
      }
    }

    _log('_buildBody: Showing main content for order ID: $_selectedOrderId.');
    return RefreshIndicator(
      onRefresh: () async {
        _log('Pull-to-refresh triggered.');
        await _fetchOrders();
      },
      color: kColorPrimary ?? Colors.teal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
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
    if (_ordersMap.isEmpty) {
      _log(
          '_buildOrderSelector: Orders map is empty, rendering SizedBox.shrink().');
      return const SizedBox.shrink();
    }
    _log(
        '_buildOrderSelector: Building dropdown. Selected: $_selectedOrderId. Available: ${_ordersMap.keys.toList()}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('SELECTED ORDER',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: kColorTextPrimary)),
          DropdownButton<int>(
            value:
                _selectedOrderId, // Should be valid if we reach here due to _buildBody checks
            items: _ordersMap.keys.map((orderId) {
              return DropdownMenuItem<int>(
                  value: orderId,
                  child: Text('Order #$orderId',
                      style: GoogleFonts.poppins(fontSize: 14)));
            }).toList(),
            onChanged: (value) {
              if (value != null && _ordersMap.containsKey(value)) {
                _log('Order selection changed to: $value');
                if (mounted) {
                  setState(() {
                    _selectedOrderId = value;
                    _isOrderInfoExpanded = false;
                  });
                }
              } else {
                _log(
                    'Invalid order selection attempt: $value. Current _selectedOrderId: $_selectedOrderId');
              }
            },
            underline: Container(),
            icon: Icon(Icons.arrow_drop_down, color: kColorPrimary),
            style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 14),
            dropdownColor: kColorCard,
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
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Status: ${_formatStatus(status)}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: kColorPrimary)),
          const SizedBox(height: 8),
          if (formattedDate != 'N/A')
            Text('Placed on: $formattedDate ${formattedTime ?? ""}',
                style: GoogleFonts.poppins(
                    color: kColorTextSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          _buildStatusTimeline(status),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final timelineStatuses = ['Order Placed', 'Accepted', 'Delivered'];
    final currentSimplifiedIndex = _getSimplifiedStatusIndex(status);
    final orderDate = _selectedOrderId != null
        ? (_ordersMap[_selectedOrderId]?['order_date']?.toString())
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double segmentWidth =
            constraints.maxWidth / timelineStatuses.length;
        final double circleRadius = 12.0;
        final double horizontalPadding = segmentWidth / 2 - circleRadius;

        return Stack(
          children: [
            Positioned(
              top: circleRadius - 1,
              left: horizontalPadding + circleRadius,
              right: horizontalPadding + circleRadius,
              child: Container(height: 2, color: kColorTimelineLine),
            ),
            Positioned(
              top: circleRadius - 1,
              left: horizontalPadding + circleRadius,
              width: currentSimplifiedIndex >= 0 // ensure non-negative width
                  ? (segmentWidth *
                      (currentSimplifiedIndex < timelineStatuses.length
                          ? currentSimplifiedIndex
                          : timelineStatuses.length - 1)) // Cap at max index
                  : 0,
              child: Container(height: 2, color: kColorStatusActive),
            ),
            Row(
              children: List.generate(timelineStatuses.length, (index) {
                bool isActive = index <= currentSimplifiedIndex;
                String stepDate =
                    isActive ? _getSimplifiedStatusDate(orderDate, index) : '';
                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: circleRadius * 2,
                        height: circleRadius * 2,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? kColorStatusActive
                                : kColorStatusInactive,
                            border: Border.all(
                                color: isActive
                                    ? kColorStatusActive
                                    : kColorTimelineLine,
                                width: 1.5)),
                        child: isActive
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(timelineStatuses[index],
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w500,
                              color: isActive
                                  ? kColorTextPrimary
                                  : kColorTextSecondary),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      if (stepDate.isNotEmpty && stepDate != 'N/A')
                        Text(stepDate,
                            style: GoogleFonts.poppins(
                                fontSize: 10, color: kColorTextSecondary),
                            textAlign: TextAlign.center),
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

  Widget _buildOrderInfoCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) {
      _log(
          '_buildOrderInfoCard: Selected order data is null for ID: $_selectedOrderId. Rendering empty container.');
      return Container();
    }
    // Shorten log for order data to avoid excessive output
    String orderDataSummary = order.toString();
    if (orderDataSummary.length > 200)
      orderDataSummary = "${orderDataSummary.substring(0, 200)}...";
    _log(
        '_buildOrderInfoCard: Building for order ID: $_selectedOrderId. Data (summary): $orderDataSummary');

    final bool needsVerification =
        order['order_status']?.toString() == 'verification needed';
    final bool isLoadingVerification =
        _loadingVerificationOrderId == _selectedOrderId;

    String productName;
    final orderType = order['order_type']?.toString();
    _log('_buildOrderInfoCard: Order type: $orderType');

    if (orderType == 'gig') {
      final gigDetailsData = order['gig_details'];
      if (gigDetailsData is Map<String, dynamic>) {
        productName = gigDetailsData['gig_name']?.toString() ??
            gigDetailsData['gig_type']?.toString() ??
            'N/A (Gig Name/Type Missing)';
        _log('_buildOrderInfoCard: Gig product name (from map): $productName');
      } else if (gigDetailsData is String) {
        try {
          final decodedDetails = json.decode(gigDetailsData);
          if (decodedDetails is Map<String, dynamic>) {
            productName = decodedDetails['gig_name']?.toString() ??
                decodedDetails['gig_type']?.toString() ??
                'N/A (Gig Name/Type Missing)';
            _log(
                '_buildOrderInfoCard: Gig product name (from decoded string): $productName');
          } else {
            productName = 'N/A (Invalid Gig Details Format after decode)';
            _log(
                '_buildOrderInfoCard: Decoded gig_details string is not a map.');
          }
        } catch (e) {
          _log(
              "_buildOrderInfoCard: Error decoding gig_details string: $e. Details: $gigDetailsData");
          productName = 'N/A (Error in Gig Details)';
        }
      } else {
        _log(
            "_buildOrderInfoCard: Warning: Order type is 'gig' but 'gig_details' is missing or not a map/string for order $_selectedOrderId. Details: $gigDetailsData");
        productName = 'N/A (Invalid Gig Details)';
      }
    } else {
      productName = order['meal_name']?.toString() ??
          order['product_name']?.toString() ??
          'N/A';
      _log('_buildOrderInfoCard: Product name (non-gig): $productName');
    }

    final String actualCustomerName = order['customer_name']?.toString() ?? '';
    final String userIdForDisplay = order['user_id']?.toString() ??
        widget.userId; // Use widget.userId as ultimate fallback
    final String displayCustomer = actualCustomerName.isNotEmpty
        ? actualCustomerName
        : 'User #$userIdForDisplay';

    final quantity = order['quantity']?.toString() ?? '1';
    final totalPrice = order['total_price']?.toString() ?? 'N/A';
    final orderStatus =
        _formatStatus(order['order_status']?.toString() ?? 'pending');
    final chefName = order['chef_name'];
    final producerName = order['producer_name'];
    final contactInfo = order['contact_info']?.toString() ?? 'Not provided';
    final deliveryAddress = order['delivery_address']?.toString();
    final notes = order['notes']?.toString();
    final paymentStatus =
        _formatStatus(order['payment_status']?.toString() ?? 'N/A');
    final ingredients = order['ingredients']?.toString();

    String cleanAddress = 'Not specified';
    if (deliveryAddress != null && deliveryAddress.isNotEmpty) {
      cleanAddress =
          deliveryAddress.contains(',') && deliveryAddress.length > 40
              ? deliveryAddress.split(',').skip(2).join(',').trim()
              : deliveryAddress;
      if (cleanAddress.isEmpty) cleanAddress = deliveryAddress;
    }

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              if (mounted) {
                setState(() {
                  _isOrderInfoExpanded = !_isOrderInfoExpanded;
                  _log(
                      '_buildOrderInfoCard: Toggled _isOrderInfoExpanded to $_isOrderInfoExpanded');
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ORDER DETAILS',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: kColorTextPrimary)),
                  Row(
                    children: [
                      Text('Tap for details',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: kColorTextSecondary,
                              fontStyle: FontStyle.italic)),
                      const SizedBox(width: 8),
                      Icon(
                          _isOrderInfoExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: kColorTextPrimary,
                          size: 28),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: kColorDivider),
          Padding(
            padding: const EdgeInsets.only(
                left: 16.0, right: 16.0, top: 12.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Product', productName),
                _buildInfoRow('Customer', displayCustomer),
                _buildInfoRow('Quantity', quantity),
                _buildInfoRow('Total Price', '$totalPrice UGX'),
                _buildInfoRow('Order Status', orderStatus),
                _buildInfoRow('Payment Status', paymentStatus,
                  textStyle: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: paymentStatus.toLowerCase() != 'pending' 
                        ? Colors.green 
                        : kColorTextPrimary,
                    fontSize: 13,
                  )
                ),
                if (needsVerification) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: isLoadingVerification
                          ? null
                          : () {
                              _log(
                                  '_buildOrderInfoCard: VERIFY DELIVERY button pressed for order #$_selectedOrderId.');
                              _handleVerificationRequest(_selectedOrderId!);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kColorPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: isLoadingVerification
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('VERIFY DELIVERY',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white)),
                    ),
                  ),
                ],
                _buildComplementaryMealsRow(order['complementary_meals']),
                if (chefName != null && chefName.isNotEmpty)
                  _buildInfoRow('Chef', chefName),
                if (producerName != null && producerName.isNotEmpty)
                  _buildInfoRow('Producer', producerName),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            firstChild: Container(),
            secondChild: Padding(
              padding:
                  const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: kColorDivider, height: 16, thickness: 1),
                  _buildInfoRow('Contact', contactInfo),
                  _buildInfoRow('Delivery To', cleanAddress),
                  // Payment status moved above to be right after order status
                  if (notes != null && notes.isNotEmpty)
                    _buildInfoRow('Notes', notes),
                  if (ingredients != null &&
                      ingredients.isNotEmpty &&
                      orderType != 'gig')
                    _buildInfoRow('Ingredients', ingredients),
                ],
              ),
            ),
            crossFadeState: _isOrderInfoExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),

        ],
      ),
    );
  }

  Widget _buildTrackingHistoryCard() {
    final order =
        _selectedOrderId != null ? _ordersMap[_selectedOrderId] : null;
    if (order == null) return Container();

    final orderDate = order['order_date']?.toString();
    final currentStatus = order['order_status']?.toString() ?? 'pending';
    final currentSimplifiedIndex = _getSimplifiedStatusIndex(currentStatus);

    final List<Widget> trackingEvents = [];
    final timelineStatusNames = [
      'Order Placed',
      'Accepted',
      'Delivered'
    ]; // Consistent with _buildStatusTimeline

    // Only generate events up to the current actual step, or max defined steps
    int maxEventsToShow = currentSimplifiedIndex;
    if (maxEventsToShow < 0)
      maxEventsToShow = 0; // Handle cancelled/failed if mapped to -1
    if (maxEventsToShow >= timelineStatusNames.length)
      maxEventsToShow = timelineStatusNames.length - 1;

    for (int i = 0; i <= maxEventsToShow; i++) {
      final String eventDate = _getSimplifiedStatusDate(orderDate, i);
      final String? eventTime = _getSimplifiedStatusTime(orderDate, i);
      trackingEvents.add(_buildTrackingEvent(
        _getSimplifiedStatusName(i),
        eventDate != 'N/A' ? '$eventDate ${eventTime ?? ""}' : 'Pending',
        isLast: i == maxEventsToShow,
      ));
    }

    if (trackingEvents.isEmpty && currentSimplifiedIndex >= 0) {
      // If no events but status is valid (e.g. 'Order Placed')
      final String eventDate = _getSimplifiedStatusDate(orderDate, 0);
      final String? eventTime = _getSimplifiedStatusTime(orderDate, 0);
      trackingEvents.add(_buildTrackingEvent(_getSimplifiedStatusName(0),
          eventDate != 'N/A' ? '$eventDate ${eventTime ?? ""}' : 'Pending',
          isLast: true));
    } else if (trackingEvents.isEmpty) {
      // Truly no events, status might be unknown or error
      trackingEvents
          .add(_buildTrackingEvent('Order Status Pending', '', isLast: true));
    }

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kColorCard,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text('TRACKING HISTORY',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: kColorTextPrimary,
                      fontSize: 16))),
          const Divider(color: kColorDivider, height: 1, thickness: 1),
          const SizedBox(height: 16),
          ...trackingEvents,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {TextStyle? textStyle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: kColorTextSecondary))),
          const SizedBox(width: 30),
          Expanded(
              child: Text(value.isEmpty ? 'N/A' : value,
                  style: textStyle ?? GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: kColorTextPrimary))),
        ],
      ),
    );
  }

  Widget _buildTrackingEvent(String event, String dateTime,
      {bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: kColorStatusActive)),
                if (!isLast)
                  Expanded(
                      child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 4, bottom: 4),
                          color: kColorStatusActive)),
                if (isLast && !isLast)
                  const Spacer(), // This line was 'if (isLast) const Spacer()' which is fine. Redundant !isLast here.
                // If it's the last item, we don't need a spacer IF there's no line.
                // The structure implies the spacer is only needed if the line is absent.
                // Correct logic: If isLast, then no line is drawn. If not isLast, line is drawn. Spacer is for height alignment with text.
                // Let's keep it simple: If not last, draw line. If last, nothing extra here.
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(event,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kColorTextPrimary)),
                  const SizedBox(height: 2),
                  if (dateTime.isNotEmpty)
                    Text(dateTime,
                        style: GoogleFonts.poppins(
                            color: kColorTextSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    _log('Building loading state widget.');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
              color: kColorPrimary ?? Colors.teal, strokeWidth: 3),
          const SizedBox(height: 20),
          Text('Loading order details...',
              style:
                  GoogleFonts.poppins(fontSize: 16, color: kColorTextPrimary)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    _log('Building empty state widget.');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 60, color: kColorTextSecondary),
          const SizedBox(height: 16),
          Text('No active orders found',
              style:
                  GoogleFonts.poppins(fontSize: 18, color: kColorTextPrimary)),
          const SizedBox(height: 8),
          Text(
            widget.orderIdList.isEmpty
                ? 'Your order list is currently empty.'
                : 'No order data could be fetched for the provided list. Please try again.',
            style: GoogleFonts.poppins(color: kColorTextSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('Retry', style: GoogleFonts.poppins()),
            onPressed: () {
              _log('Retry button pressed from empty state.');
              _fetchOrders(isInitialFetch: true); // Treat as an initial fetch
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: kColorPrimary, foregroundColor: Colors.white),
          )
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    _log('Building error state widget. Message: $message');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red[700]),
            const SizedBox(height: 16),
            Text('Error Loading Order',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kColorTextPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message,
                style: GoogleFonts.poppins(color: kColorTextSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Retry', style: GoogleFonts.poppins()),
              onPressed: () {
                _log('Retry button pressed from error state.');
                _fetchOrders(isInitialFetch: true); // Treat as an initial fetch
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: kColorPrimary,
                  foregroundColor: Colors.white),
            )
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('d MMMM yyyy').format(dateTime);
    } catch (e) {
      _log("Error formatting date '$dateString': $e");
      return 'Invalid Date';
    }
  }

  String? _formatTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      _log("Error formatting time '$dateString': $e");
      return null;
    }
  }

  String _formatStatus(String status) {
    if (status.isEmpty) return 'Pending';
    switch (status.toLowerCase()) {
      case 'on_the_way':
        return 'On The Way';
      case 'order_placed':
        return 'Order Placed';
      case 'verification needed':
        return 'Verification Needed';
    }
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ')
        .trim();
  }

  int _getSimplifiedStatusIndex(String status) {
    // Maps backend status string to a simplified index (0, 1, 2) for timeline
    // Ensure 'verification needed' is handled appropriately in your timeline logic.
    // For this example, it's placed before 'Delivered'.
    switch (status.toLowerCase()) {
      case 'pending':
      case 'placed':
      case 'order_placed':
        return 0; // Order Placed

      case 'accepted':
      case 'preparing':
      case 'ready_for_pickup':
      case 'shipped':
      case 'assigned':
      case 'picked up':
      case 'picked_up':
      case 'on the way':
      case 'on_the_way':
      case 'verification needed': // Rider is likely on the way or has arrived
        return 1; // Accepted / On The Way / Awaiting Verification

      case 'delivered':
      case 'complete':
      case 'Delivered':
      case 'completed':
        return 2; // Delivered

      case 'cancelled':
      case 'failed':
        return -1; // Represents a non-progressive state, handle separately if needed
      default:
        _log(
            "Warning: Unmapped status encountered in _getSimplifiedStatusIndex: '$status'");
        return 0; // Default to the first step if unknown
    }
  }

  String _getSimplifiedStatusName(int index) {
    // Gets the display name for a simplified timeline index
    switch (index) {
      case 0:
        return 'Order Placed';
      case 1:
        return 'Accepted'; // Could also be 'Processing' or 'Awaiting Verification' based on context
      case 2:
        return 'Delivered';
      default:
        return 'Unknown Status';
    }
  }

  // Gets an *estimated* date for a simplified timeline step.
  // TODO: Replace with actual status timestamp data from the API if available.
  String _getSimplifiedStatusDate(String? orderDate, int index) {
    if (orderDate == null || orderDate.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      // Basic estimation: Add some hours per step.
      final adjustedDate = dateTime.add(Duration(
          hours: index * 2 +
              index)); // e.g., step 0: +0h, step 1: +3h, step 2: +6h
      return DateFormat('d MMM').format(adjustedDate); // e.g., "15 Feb"
    } catch (e) {
      _log(
          "Error calculating simplified status date for index $index from '$orderDate': $e");
      return 'N/A';
    }
  }

  String? _getSimplifiedStatusTime(String? orderDate, int index) {
    if (orderDate == null || orderDate.isEmpty) return null;
    try {
      final dateTime = DateTime.parse(orderDate).toLocal();
      final adjustedDate = dateTime.add(Duration(hours: index * 2 + index));
      return DateFormat('h:mm a').format(adjustedDate);
    } catch (e) {
      _log(
          "Error calculating simplified status time for index $index from '$orderDate': $e");
      return null;
    }
  }
}
