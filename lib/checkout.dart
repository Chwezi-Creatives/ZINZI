//cspell:disable
import 'dart:async';
import 'package:zinzi/app_drawer_unified.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
// import 'package:geolocator/geolocator.dart'; // Geolocator is now used by LocationService
import 'package:google_fonts/google_fonts.dart';
import 'orderstatus polls.dart' as order_status;
import 'package:zinzi/cart.dart'; // Import ShoppingCart
import 'package:zinzi/services/location_service.dart'; // Import LocationService

final String apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double totalPrice;

  const CheckoutScreen({
    Key? key,
    required this.items,
    required this.totalPrice,
  }) : super(key: key);

  @override
  _CheckoutScreenState createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  // Helper method to parse price from dynamic value
  static double _parsePrice(dynamic price) {
    if (price == null) return 0.0;
    if (price is num) return price.toDouble();
    if (price is String) {
      // Remove any non-numeric characters except decimal point
      final numericString = price.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(numericString) ?? 0.0;
    }
    return 0.0;
  }

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(); // Optional general phone number
  final _paymentPhoneNumberController = TextEditingController(); // Phone number for payment
  final _addressController = TextEditingController(); // Source of truth for location text
  final _notesController = TextEditingController();
  String _selectedPaymentMethod = 'Momo';
  bool _isLoading = false; // For overall order submission
  // bool _isLocationLoading = false; // Now driven by LocationService.instance.isLoadingNotifier
  bool _isOptionalInfoExpanded = false;
  late double _scaleFactor;
  late Timer _timer;

  String _extractGuests(dynamic numberOfPeople) {
    if (numberOfPeople == null) return 'ugx';
    final str = numberOfPeople.toString();
    final match = RegExp(r'\d+').firstMatch(str);
    return match != null ? match.group(0)! : 'ugx';
  }

  Widget _buildPaymentMethodChoice(String method, String assetPath, {bool showImage = true}) {
    final bool isSelected = _selectedPaymentMethod == method;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
          _paymentPhoneNumberController.clear(); // Clear the phone number when payment method changes
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // Always white background
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.teal.shade700 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Only show image if showImage is true
            if (showImage) Image.asset(assetPath, height: 20, width: 20),
            SizedBox(width: 8),
            Text(
              method,
              style: GoogleFonts.poppins(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: Colors.black87, // Consistent text color
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserPhoneNumber() async {
    if (!kDebugMode) return; // Only run debug code in debug mode
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (!prefs.containsKey('user_phone')) {
        debugPrint('🔍 [Checkout] user_phone key not found in SharedPreferences');
        return;
      }
      
      final userPhone = prefs.getString('user_phone');
      if (userPhone == null) {
        debugPrint('🔍 [Checkout] user_phone is null in SharedPreferences');
        return;
      }
      
      if (userPhone.isEmpty) {
        debugPrint('🔍 [Checkout] user_phone is empty in SharedPreferences');
        return;
      }
      
      if (!mounted) {
        debugPrint('🔍 [Checkout] Widget not mounted, not setting phone number');
        return;
      }
      
      debugPrint('🔍 [Checkout] Setting payment phone number from SharedPreferences: $userPhone');
      setState(() {
        _paymentPhoneNumberController.text = userPhone;
      });
      
    } catch (e) {
      debugPrint('⚠️ [Checkout] Error loading user phone number: $e');
      // Silently fail in production, but log in debug mode
    }
  }

  @override
  void initState() {
    super.initState();
    print('cartItems: ' + widget.items.toString());
    _scaleFactor = 1.0;
    _startAnimation();
    _initializeLocation(); // New method to handle location initialization
    _loadUserPhoneNumber(); // Load saved phone number if available

    // Listen to location updates from the service
    LocationService.instance.currentAddressNotifier.addListener(_updateLocationFromService);
    LocationService.instance.currentPositionNotifier.addListener(_updateLocationFromService); // Also listen to position for coordinate display
    LocationService.instance.isLoadingNotifier.addListener(_updateLoadingStateFromService);
    LocationService.instance.errorNotifier.addListener(_handleLocationErrorFromService);
  }

  void _initializeLocation() {
    final locationService = LocationService.instance;
    if (locationService.currentAddress != null && locationService.currentAddress!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _addressController.text = locationService.currentAddress!;
        });
      }
      debugPrint('[Checkout] Initialized location from LocationService address: ${locationService.currentAddress}');
    } else if (locationService.currentPosition != null) {
      final pos = locationService.currentPosition!;
      final initialDisplay = "${pos.latitude}, ${pos.longitude}";
       if (mounted) {
        setState(() {
          _addressController.text = initialDisplay;
        });
      }
      debugPrint('[Checkout] Initialized location from LocationService position: $initialDisplay. Triggering geocoding.');
      // Trigger geocoding if only position is available and address is not
      locationService.getAddressFromPosition(pos);
    } else {
      debugPrint('[Checkout] No pre-fetched location found. Calling _getCurrentLocation to fetch fresh.');
      _getCurrentLocation(showSnackbarErrors: false); // Fetch fresh, suppress snackbar for initial auto-fetch
    }
  }

  void _updateLocationFromService() {
    if (!mounted) return;
    final locationService = LocationService.instance;
    String displayLocation = _addressController.text; // Default to current text

    if (locationService.currentAddress != null && locationService.currentAddress!.isNotEmpty) {
      displayLocation = locationService.currentAddress!;
    } else if (locationService.currentPosition != null) {
      // Fallback to coordinates if address is not available
      final pos = locationService.currentPosition!;
      displayLocation = "${pos.latitude}, ${pos.longitude}";
    }

    if (_addressController.text != displayLocation) {
       setState(() {
        _addressController.text = displayLocation;
      });
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.tryParse(dateString);
      if (date == null) return 'Invalid date';
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  void _updateLoadingStateFromService() {
    if (!mounted) return;
    // This setState call will trigger a rebuild if the loading state changes,
    // allowing the ValueListenableBuilder for the location TextFormField to update.
    setState(() {});
  }

  void _handleLocationErrorFromService() {
    if (!mounted) return;
    final error = LocationService.instance.error;
    if (error != null && error.isNotEmpty) {
      // Check if we are in a state where we want to show this error (e.g., not during initial silent fetch)
      // For now, always show if an error is set.
      _showSnackBar('Location Error: $error');
      // LocationService.instance.errorNotifier.value = null; // Clear error after showing
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    LocationService.instance.currentAddressNotifier.removeListener(_updateLocationFromService);
    LocationService.instance.currentPositionNotifier.removeListener(_updateLocationFromService);
    LocationService.instance.isLoadingNotifier.removeListener(_updateLoadingStateFromService);
    LocationService.instance.errorNotifier.removeListener(_handleLocationErrorFromService);
    _nameController.dispose();
    _phoneController.dispose();
    _paymentPhoneNumberController.dispose(); // Dispose the new controller
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _scaleFactor = _scaleFactor == 1.0 ? 0.95 : 1.0;
      });
    });
  }

  Future<void> _getCurrentLocation({bool showSnackbarErrors = true}) async {
    if (!mounted) return;
    debugPrint('[Checkout] _getCurrentLocation called. Forcing geocode and address update. showSnackbarErrors: $showSnackbarErrors');

    await LocationService.instance.fetchAndSetCurrentLocation(forceGeocode: true, updateAddressRegardless: true);
  }

  void _showSnackBar(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.teal[800],
      ),
    );
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    if (LocationService.instance.currentPosition == null) {
      await _getCurrentLocation(showSnackbarErrors: true);
       // Re-check after attempting to get location if it was missing
      if (LocationService.instance.currentPosition == null) {
         _showSnackBar('Please acquire your delivery location before placing the order.');
        return;
      }
    }

    final String deliveryLocation = LocationService.instance.fullLocationString ?? _addressController.text;

    if (deliveryLocation.trim().isEmpty) {
      _showSnackBar('Please acquire your delivery location before placing the order.');
      return;
    }

    setState(() => _isLoading = true);

    String? userId;
    String? userType;
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString('user_id');
      userType = prefs.getString('user_type');

      if (userId == null || userId.isEmpty) {
        _showSnackBar('User is not logged in.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } catch (e) {
      print('Error getting user ID: $e');
      _showSnackBar('Failed to get user information. Please try again.');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final String paymentPhoneNumber = _paymentPhoneNumberController.text.trim(); // Get payment phone number

    List<String> orderIds = [];
    double totalProcessedPrice = 0.0;
    bool allOrdersSuccessful = true;

    for (final item in widget.items) {
      String orderType = 'meal';
      if (item.containsKey('meal') && item['meal'] is Map && item['meal']['order_type'] != null) {
        orderType = item['meal']['order_type'].toString();
      } else if (item['type'] != null) {
        orderType = item['type'].toString();
      }

        // Calculate item total price with breakdown
        double itemTotalPrice = 0.0;
        double complementaryTotal = 0.0;
        double basePrice = 0.0;
        double chefPrice = 0.0;
        int quantity = 1;
        
        if (item['type'] == 'meal') {
          // Get base price (either from item or calculate from meal)
          basePrice = (item['basePrice'] as num?)?.toDouble() ?? 
                     (item['price'] as num?)?.toDouble() ?? 0.0;
                      
          quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          
          // Chef price if selected
          chefPrice = item['selectedchef'] != null
              ? _parsePrice(item['selectedchef']?['price'])
              : 0.0;
          
          // Get complementary items and total
          complementaryTotal = (item['complementaryTotal'] as num?)?.toDouble() ?? 0.0;
          
          // Ensure basePrice is properly initialized
          final effectiveBasePrice = basePrice;
          
          // Calculate price per single unit (base + chef + complements)
          final pricePerSingleUnit = effectiveBasePrice + chefPrice + complementaryTotal;
          
          // For bulk orders, multiply by quantity and number of days
          if (item['isBulkOrder'] == true) {
            final planDays = item['planSelectedDays'] as List?;
            final numberOfDays = planDays?.length ?? 0;
            itemTotalPrice = pricePerSingleUnit * quantity * numberOfDays;
          } else {
            // For regular orders, just multiply by quantity
            itemTotalPrice = pricePerSingleUnit * quantity;
          }
          
          // Debug output
          print('Price breakdown for $quantity x ${item['title']}:');
          print('- Base price: $basePrice');
          print('- Chef price: $chefPrice');
          print('- Complementary total: $complementaryTotal');
          print('- Price per unit: $pricePerSingleUnit');
          print('- Total: $itemTotalPrice');
      }

      Map<String, dynamic> itemPayload;
      if (item['type'] == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        itemPayload = {
          'user_id': userId.toString(),
          'chef_id': gigDetails['chef_id'],
          'producer_id': gigDetails['producer_id'],
          'gig_details': {
            'gig_type': gigDetails['gig_type'],
            'location': gigDetails['location'],
            'scheduled_date': gigDetails['scheduled_date'],
            'time': gigDetails['time'],
            'estimated_duration': gigDetails['estimated_duration'],
            'number_of_people': gigDetails['number_of_people'],
            'price': gigDetails['price'],
            'detailed_description': gigDetails['detailed_description'],
          },
          'total_price': itemTotalPrice,  // Add total price for gigs
        };
      } else {
        // Assume meal type
        final meal = item['meal'] as Map<String, dynamic>? ?? {};
        final productIdEntry = meal.entries.firstWhere(
          (e) => e.key.endsWith('_id') && e.key != 'chef_id' && e.key != 'producer_id',
          orElse: () => const MapEntry('product_id', null),
        );

        // Build base item payload with detailed price breakdown
        final effectiveBasePrice = basePrice; // Ensure basePrice is properly scoped
        itemPayload = {
          'order_type': orderType,
          'type': orderType,
          productIdEntry.key: productIdEntry.value?.toString(),
          'product_id': productIdEntry.value?.toString(),
          'quantity': quantity,
          
          // Price breakdown
          'price': itemTotalPrice, // Total price per unit (base + chef + complements)
          'base_price': effectiveBasePrice, // Base meal price only
          'chef_price': chefPrice, // Chef service fee if any
          'complementary_total': complementaryTotal, // Total of all complements
          'total_price': itemTotalPrice, // Final total (base + chef + complements) * quantity
          
          // Item details
          'meal_id': item['meal']?['Meal_id']?.toString() ?? productIdEntry.value?.toString(),
          'chef_id': item['selectedchef']?['chef_id']?.toString() ?? item['selectedchef']?['chefid']?.toString(),
          'producer_id': item['selectedproducer']?['producer_id']?.toString(),
          
          // Include complementary items with details
          'bestservedwith': (item['complementaryItems'] as List?)?.map((comp) => {
            'name': comp['name'] ?? '',
            'price': (comp['price'] as num?)?.toDouble() ?? 0.0,
            'image': comp['image'] ?? '',
          }).toList() ?? [],
          
          // Include original bestservedwith for backward compatibility
          'original_bestservedwith': item['bestservedwith'] ?? [],
        };

        // Add meal plan data if this is a bulk order
        if (item['isBulkOrder'] == true) {
          itemPayload.addAll({
            'is_bulk_order': true,
            'bulk_order_details': {
              'plan_start_date': item['planStartDate'],
              'plan_end_date': item['planEndDate'],
              'plan_frequency': item['planFrequency'],
              'plan_selected_days': item['planSelectedDays'],
            }
          });
        }
      }

      // Build the order payload with bulk order flag and payment details at the top
      final paymentMode = _selectedPaymentMethod.toLowerCase() == 'momo' ? 'momo' : 'cash';
      
      // Start with bulk order flag for quick backend access
      Map<String, dynamic> orderPayload = {
        // Bulk order flag at the very top for quick access
        if (item['isBulkOrder'] == true) 'is_bulk_order': true,
        
        // Payment details
        'payment_mode': paymentMode,
        'payment_phone_number': paymentPhoneNumber,
        'total_price': itemTotalPrice,
        
        // Core order details
        'order_type': orderType,
        'user_id': userId.toString(),
        'user_type': userType ?? 'customer',
        'items': [itemPayload],
        'delivery_address': deliveryLocation,
      };

      // Add delivery details to the payload
      orderPayload.addAll({
        'delivery_location': deliveryLocation,
        'delivery_latitude': LocationService.instance.currentPosition?.latitude,
        'delivery_longitude': LocationService.instance.currentPosition?.longitude,
        'delivery_notes': _notesController.text.trim(),
        'payment_phone_number': paymentPhoneNumber,
      });
      
      // Add bulk order details if this is a bulk order
      if (item['isBulkOrder'] == true) {
        orderPayload['bulk_order_details'] = {
          'plan_start_date': item['planStartDate'],
          'plan_end_date': item['planEndDate'],
          'plan_frequency': item['planFrequency'],
          'plan_selected_days': item['planSelectedDays'],
        };
      }

      print('Submitting order for item: ${item['title'] ?? item['gigDetails']?['gig_type'] ?? 'Unknown Item'}');
      print('Order Payload: ' + orderPayload.toString());

      // Log the payload for debugging
      print('Submitting order with payload: ${jsonEncode(orderPayload)}');

      // Make the API call
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/Aorders'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(orderPayload),
      ).timeout(Duration(seconds: 30));

      // Log the response for debugging
      print('Order submission response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final orderId = responseData['order_id'];
        orderIds.add(orderId.toString());
        
        // Update total processed price using the itemTotalPrice we already calculated
        totalProcessedPrice += itemTotalPrice;
        
        print('Successfully submitted order $orderId for item: ${item['title'] ?? 'Gig'}');
        print('Price breakdown - Base: $basePrice, Chef: $chefPrice, Complements: $complementaryTotal, Total: $itemTotalPrice');
        ShoppingCart.removeItems([item]);
      } else {
        final errorMessage = jsonDecode(response.body)?['detail'] ?? response.reasonPhrase ?? 'Unknown error';
        print('Failed to place order: ${response.statusCode} - $errorMessage');
        
        // Show more specific error messages for validation issues
        if (response.statusCode == 400) {
          _showSnackBar('Validation error: $errorMessage');
        } else {
          _showSnackBar('Failed to place order: $errorMessage');
        }
        allOrdersSuccessful = false;
        break;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (allOrdersSuccessful && orderIds.isNotEmpty) {
      _showSnackBar('All orders placed successfully!', duration: Duration(seconds: 2));
      await Future.delayed(Duration(seconds: 2));
      if(mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => order_status.OrderStatusScreen(
              userId: userId!,
              orderIdList: orderIds.map(int.parse).toList(),
              orderId: int.parse(orderIds.first),
            ),
          ),
        );
      }
    } else if (orderIds.isNotEmpty && !allOrdersSuccessful) {
       _showSnackBar('Some orders were placed, but others failed. Check order history.', duration: Duration(seconds: 5));
    } else if (!allOrdersSuccessful) {
      // Errors already shown
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        title: Text('Checkout', style: GoogleFonts.poppins()),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.teal.shade50,
                Colors.teal.shade50,
              ],
            ),
          ),
          padding: EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Summary Card
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Summary',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        ...List.generate(widget.items.length, (i) {
                          final item = widget.items[i];
                          final bestServedWith = (item['bestservedwith'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final chef = item['selectedchef'] as Map<String, dynamic>?;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (i != 0) Divider(height: 18, color: Colors.teal[100]),
                              if ((item['type'] ?? 'meal') == 'gig') ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item['gigDetails']?['gig_type'] ?? 'Gig'}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.teal[700],
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Guests (${_extractGuests(item['gigDetails']?['number_of_people'])})',
                                          style: GoogleFonts.poppins(
                                            color: Colors.teal[700],
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      () {
                                        final gigPrice = (item['gigDetails']?['price'] is num)
                                            ? (item['gigDetails']['price'] as num)
                                            : (item['price'] ?? 0.0);
                                        return 'ugx ${gigPrice.toStringAsFixed(0)}';
                                      }(),
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal[700],
                                      ),
                                    ),
                                  ],
                                ),
                                if (item['gigDetails'] != null && item['gigDetails']['chef_name'] != null && item['gigDetails']['chef_name'].toString().isNotEmpty)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Chef: ${item['gigDetails']['chef_name']}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.teal[800])),
                                    ],
                                  ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item['title']} x${item['quantity']}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.teal[700],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'ugx ${((item['price'] ?? 0.0) * (item['quantity'] ?? 0)).toStringAsFixed(0)}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.teal[700],
                                      ),
                                    ),
                                  ],
                                ),
                                if (chef != null && chef['name'] != null && chef['name'].toString().isNotEmpty)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Chef: ${chef['name']}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.teal[800])),
                                      if (chef['price'] != null)
                                        Text(
                                          'ugx ${(chef['price'] is num ? (chef['price'] as num).toDouble() : double.tryParse(chef['price'].toString()) ?? 0.0).toStringAsFixed(0)}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.teal[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                if (bestServedWith.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Complements:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.teal[700])),
                                        ...bestServedWith.map((comp) {
                                          final compName = comp['name']?.toString() ?? comp['title']?.toString() ?? '';
                                          final compPrice = (comp['price'] is num) ? (comp['price'] as num).toDouble() : 0.0;
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text(compName, style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800]))),
                                                Text('ugx ${compPrice.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800])),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                                // Display meal plan details if this is a bulk order
                                if ((item['isBulkOrder'] ?? false) == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Meal Plan Details:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.teal[700])),
                                        if (item['planStartDate'] != null && item['planEndDate'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                                            child: Text(
                                              '${_formatDate(item['planStartDate'])} - ${_formatDate(item['planEndDate'])}',
                                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800]),
                                            ),
                                          ),
                                        if (item['planFrequency'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                            child: Text(
                                              'Frequency: ${item['planFrequency']}',
                                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800]),
                                            ),
                                          ),
                                        if (item['planSelectedDays'] != null && (item['planSelectedDays'] as List).isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                            child: Text(
                                              'Delivery Days: ${(item['planSelectedDays'] as List).join(', ')}',
                                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800]),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          );
                        }).toList(),
                        Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.teal[900],
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'ugx ${widget.totalPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.teal[900],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Delivery Location
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Location',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        ValueListenableBuilder<bool>(
                          valueListenable: LocationService.instance.isLoadingNotifier,
                          builder: (context, isLoadingFromService, child) {
                            return TextFormField(
                              controller: _addressController,
                              readOnly: true,
                              enableInteractiveSelection: false,
                              decoration: InputDecoration(
                                labelText: 'Location',
                                hintText: 'Tap the refresh button to update location',
                                labelStyle: GoogleFonts.poppins(color: Colors.teal[400]),
                                hintStyle: GoogleFonts.poppins(color: Colors.teal[200]),
                                suffixIcon: isLoadingFromService
                                    ? SizedBox(
                                        width: 24.0,
                                        height: 24.0,
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.teal[400]),
                                        ),
                                      )
                                    : IconButton(
                                        icon: Icon(Icons.refresh, color: Colors.teal[600]),
                                        tooltip: "Update Location",
                                        onPressed: () => _getCurrentLocation(showSnackbarErrors: true),
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide(color: Colors.teal[200]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide(color: Colors.teal[600]!, width: 2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8.0),
                                  borderSide: BorderSide(color: Colors.teal[300]!),
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                              ),
                              validator: (value) => (value?.trim().isEmpty ?? true) && !isLoadingFromService
                                  ? 'Please update your location using the refresh button'
                                  : null,
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // Optional Information
                ExpansionTile(
                  title: Text(
                    'Optional Information',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[800],
                    ),
                  ),
                  initiallyExpanded: _isOptionalInfoExpanded,
                  onExpansionChanged: (bool expanding) =>
                      setState(() => _isOptionalInfoExpanded = expanding),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name (Optional)',
                              prefixIcon: Icon(Icons.person_outline, color: Colors.teal[600]),
                               border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[200]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[600]!, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[300]!),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.8),
                            ),
                            style: GoogleFonts.poppins(),
                          ),
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              labelText: 'Phone Number (Optional)',
                              prefixIcon: Icon(Icons.phone_outlined, color: Colors.teal[600]),
                               border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[200]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[600]!, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[300]!),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.8),
                            ),
                            keyboardType: TextInputType.phone,
                            style: GoogleFonts.poppins(),
                          ),
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'Special Instructions (Optional)',
                              prefixIcon: Icon(Icons.notes_outlined, color: Colors.teal[600]),
                               border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[200]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[600]!, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: BorderSide(color: Colors.teal[300]!),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.8),
                            ),
                            maxLines: 3,
                            style: GoogleFonts.poppins(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),

                // Payment Method Card
                Card(
                  color: Colors.teal[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose a payment method',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              _buildPaymentMethodChoice('Momo', 'assets/images/mtn.png', showImage: true),
                              SizedBox(width: 12),
                              _buildPaymentMethodChoice('Airtel', 'assets/images/airtel.png', showImage: true),
                            ],
                          ),
                        ),
                        SizedBox(height: 16), // Space before the phone number field
                        TextFormField(
                          controller: _paymentPhoneNumberController,
                          decoration: InputDecoration(
                            labelText: 'Payment Phone Number',
                            hintText: 'Enter number for selected payment method',
                            prefixIcon: Icon(Icons.phone_android_outlined, color: Colors.teal[600]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide(color: Colors.teal[200]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide(color: Colors.teal[600]!, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide(color: Colors.teal[300]!),
                            ),
                            filled: true,
                            fillColor: Colors.white, // Slightly different or consistent fill
                          ),
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.poppins(),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter the phone number for payment';
                            }
                            // Basic Ugandan phone number validation (e.g., 07xxxxxxxx or +2567xxxxxxxx)
                            // Adjust regex as per specific requirements
                            if (!RegExp(r'^(0|\+?256)?[7]\d{8}$').hasMatch(value.trim())) {
                                return 'Enter a valid Ugandan phone number (e.g., 07xx..., +2567xx...)';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Center(
                  child: _isLoading
                      ? CircularProgressIndicator(color: Colors.teal[700])
                      : ElevatedButton(
                          onPressed: _submitOrder,
                          child: Text('Place Order', style: GoogleFonts.poppins(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal[700],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 3,
                          ),
                        ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}