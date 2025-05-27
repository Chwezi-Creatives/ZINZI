import 'dart:async';
import 'package:zinzi2/app_drawer_unified.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:geolocator/geolocator.dart'; // Geolocator is now used by LocationService
import 'package:google_fonts/google_fonts.dart';
import 'orderstatus polls.dart' as order_status;
import 'package:zinzi2/cart.dart'; // Import ShoppingCart
import 'package:zinzi2/services/location_service.dart'; // Import LocationService

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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    print('cartItems: ' + widget.items.toString());
    _scaleFactor = 1.0;
    _startAnimation();
    _initializeLocation(); // New method to handle location initialization

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
    
    // The LocationService will handle its own loading state and error reporting.
    // The listeners (_updateLocationFromService, _handleLocationErrorFromService, _updateLoadingStateFromService)
    // will react to changes in the service.
    // The showSnackbarErrors flag is a bit tricky here because the error handling is via a listener.
    // If we want to suppress snackbars for a specific call, the listener itself would need to be aware of this context,
    // or be temporarily detached, which adds complexity.
    // For now, _handleLocationErrorFromService will show any error set in the service.
    await LocationService.instance.fetchAndSetCurrentLocation(forceGeocode: true, updateAddressRegardless: true);
    
    // If !showSnackbarErrors and an error occurred, the listener would still show it.
    // This design means errors from the service are always reported via the listener.
    // If specific suppression is needed for the initial call, _handleLocationErrorFromService
    // would need a way to know it's an "initial, silent" fetch.
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

    // Ensure we have the latest location data
    if (LocationService.instance.currentPosition == null) {
      await _getCurrentLocation(showSnackbarErrors: true);
    }

    // Use the full location string from the service, or fall back to the text field
    final String deliveryLocation = LocationService.instance.fullLocationString ?? _addressController.text;
    
    if (deliveryLocation.trim().isEmpty) {
      _showSnackBar('Please acquire your delivery location before placing the order.');
      return;
    }

    setState(() => _isLoading = true);

    String? userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString('user_id');

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

      Map<String, dynamic> itemPayload;
      if (item['type'] == 'gig') {
        final gigDetails = item['gigDetails'] as Map<String, dynamic>? ?? {};
        itemPayload = {
          'user_id': userId.toString(),
          'chef_id': gigDetails['chef_id'],
          'producer_id': gigDetails['producer_id'],
          'gig_details': {
            'gig_type': gigDetails['gig_type'],
            'location': gigDetails['location'], // This is gig location, not delivery
            'scheduled_date': gigDetails['scheduled_date'],
            'time': gigDetails['time'],
            'estimated_duration': gigDetails['estimated_duration'],
            'number_of_people': gigDetails['number_of_people'],
            'price': gigDetails['price'],
            'detailed_description': gigDetails['detailed_description'],
          }
        };
      } else {
        // Assume meal type
        final meal = item['meal'] as Map<String, dynamic>? ?? {};
        final productIdEntry = meal.entries.firstWhere(
          (e) => e.key.endsWith('_id') && e.key != 'chef_id' && e.key != 'producer_id',
          orElse: () => const MapEntry('product_id', null), // Default if no specific _id found
        );

        itemPayload = {
          'order_type': orderType,
          'type': orderType,
          // Ensure the specific product ID (e.g., meal_id, ingredient_id) is included
          // And also include a generic 'product_id' for potential backend consistency
          productIdEntry.key: productIdEntry.value?.toString(),
          'product_id': productIdEntry.value?.toString(),
          'quantity': (item['quantity'] as num?)?.toInt(),
          'price': (item['price'] as num?)?.toDouble(),
          'chef_id': item['selectedchef']?['chefid']?.toString(),
          'producer_id': item['selectedproducer']?['producer_id']?.toString(),
          'bestservedwith': item['bestservedwith'] ?? [],
        };
      }

      // Include both the full location string and the coordinates in the payload
      Map<String, dynamic> orderPayload = {
        'order_type': orderType,
        'user_id': userId.toString(),
        'items': [itemPayload],
        'delivery_address': deliveryLocation, // Full location string with coordinates and address
        'delivery_coordinates': LocationService.instance.currentPosition != null
            ? {
                'latitude': LocationService.instance.currentPosition!.latitude,
                'longitude': LocationService.instance.currentPosition!.longitude,
              }
            : null,
        'notes': _notesController.text,
        'payment_mode': _selectedPaymentMethod.toLowerCase(),
        'total_price': (item['price'] as num?)?.toDouble() ?? 0.0, // Price for this specific item's order
        'chef_id': item['selectedchef']?['chefid']?.toString(),
        'producer_id': item['selectedproducer']?['producer_id']?.toString(),
      };

      print('Submitting order for item: ${item['title'] ?? item['gigDetails']?['gig_type'] ?? 'Unknown Item'}');
      print('Order Payload: ' + orderPayload.toString());

      try {
        final response = await http.post(
          Uri.parse('$apibaseurl/rr/Aorders'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(orderPayload),
        );

        if (response.statusCode == 201) {
          final responseData = json.decode(response.body);
          final orderId = responseData['order_id'];
          orderIds.add(orderId.toString());
          totalProcessedPrice += (item['price'] as num?)?.toDouble() ?? 0.0;
          print('Successfully submitted order $orderId for item: ${item['title'] ?? 'Gig'}');
          ShoppingCart.removeItems([item]); // Assuming item structure is compatible
        } else {
          allOrdersSuccessful = false;
          print('Failed to place order for item: ${item['title'] ?? 'Gig'}. Response: ${response.statusCode}, Body: ${response.body}');
          _showSnackBar('Failed to place order for ${item['title'] ?? 'Gig'}. Error: ${response.reasonPhrase}');
          break; // Stop processing further items if one fails
        }
      } catch (e) {
        allOrdersSuccessful = false;
        print('Exception while placing order for item: ${item['title'] ?? 'Gig'}. Error: $e');
        _showSnackBar('Error placing order for ${item['title'] ?? 'Gig'}. Please try again.');
        break; // Stop processing further items if an exception occurs
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (allOrdersSuccessful && orderIds.isNotEmpty) {
      _showSnackBar('All orders placed successfully!', duration: Duration(seconds: 2));
      await Future.delayed(Duration(seconds: 2)); // Give time for snackbar
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
       // Optionally navigate to order history or provide a way to see partial success
    } else if (!allOrdersSuccessful) {
      // No orders were successful
      // Snackbars for specific errors would have been shown already
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 4,
        title: Text('Checkout', style: GoogleFonts.poppins()),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/soft.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.white.withOpacity(0.95),
                BlendMode.dstATop,
              ),
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
                          // final chefHasPrice = chef != null && chef['price'] != null && chef['price'] is num;
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
                                        return 'ugx ${gigPrice.toStringAsFixed(2)}';
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
                                    Expanded( // Added Expanded for long titles
                                      child: Text(
                                        '${item['title']} x${item['quantity']}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.teal[700],
                                        ),
                                        overflow: TextOverflow.ellipsis, // Handle overflow
                                      ),
                                    ),
                                    SizedBox(width: 8), // Spacing
                                    Text(
                                      'ugx ${((item['price'] ?? 0.0) * (item['quantity'] ?? 0)).toStringAsFixed(2)}',
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
                                    ],
                                  ),
                                if (bestServedWith.isNotEmpty)
                                  Padding( // Added padding for complements
                                    padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Complements:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.teal[700])),
                                        ...bestServedWith.map((comp) {
                                          final compName = comp['name']?.toString() ?? comp['title']?.toString() ?? '';
                                          final compPrice = (comp['price'] is num) ? (comp['price'] as num).toDouble() : 0.0; // Default to 0 if not num
                                          return Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text(compName, style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800]))),
                                                Text('ugx ${compPrice.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal[800])),
                                              ],
                                            ),
                                          );
                                        }).toList(),
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
                              controller: _addressController, // Use the main controller
                              readOnly: true, // Make the field read-only
                              enableInteractiveSelection: false, // Disable text selection
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
                                fillColor: Colors.grey[100], // Slightly different color to indicate it's not editable
                                contentPadding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                              ),
                              // No validator needed since it's not user-editable
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
                          'Payment Method',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal[800],
                          ),
                        ),
                        RadioListTile<String>(
                          title: Text('Mobile Money (Momo)', style: GoogleFonts.poppins(color: Colors.teal[700])),
                          value: 'Momo',
                          groupValue: _selectedPaymentMethod,
                          onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                          activeColor: Colors.teal[700],
                        ),
                        RadioListTile<String>(
                          title: Text('Card', style: GoogleFonts.poppins(color: Colors.teal[700])),
                          value: 'Card',
                          groupValue: _selectedPaymentMethod,
                          onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                          activeColor: Colors.teal[700],
                        ),
                        RadioListTile<String>(
                          title: Text('Cash on Delivery', style: GoogleFonts.poppins(color: Colors.teal[700])),
                          value: 'Cash',
                          groupValue: _selectedPaymentMethod,
                          onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
                          activeColor: Colors.teal[700],
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
                SizedBox(height: 20), // Added some bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }
}