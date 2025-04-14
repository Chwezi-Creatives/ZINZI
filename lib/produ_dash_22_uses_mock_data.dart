import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting

// ** IMPORTANT: Make sure this import points to your actual models file **
import 'models.dart';

// --- Raw API Response Data (Simulated) ---
const String profileJsonResponse = '''
{
  "data": [
    {
      "added_by": 0, "added_by_type": "Producer", "auth_id": null, "email": "kingkobra@example.com",
      "hashed_password": "\$2b\$12\$abc...", "image": "https://via.placeholder.com/150/008080/FFFFFF?text=KK",
      "is_active": true, "is_email_verified": true, "last_login": "Sun, 16 Mar 2025 22:22:27 GMT",
      "location": "0.4004952, 32.5561877, Ttula, Wakiso, Central Region, Uganda",
      "name": "King Kobra Foods", "phone_number": "0712345678", "producer_id": 30,
      "producer_type": "Restaurant", "rating": 4.50,
      "registration_date": "Sat, 15 Mar 2025 10:00:00 GMT", "reviews": "55 Reviews", "user_type": "Producer"
    }
  ],
  "message": "Producer retrieved."
}
''';

const String ordersJsonResponse = '''
{
  "data": [
    { "amount_paid": 0.00, "chef_id": null, "chef_name": null, "delivery_address": "0.330769623144276, 32.5670204858819, Makerere University, Kimera Road, Makerere, Kawempe, Kampala, Central Region, Uganda", "ingredients": "Chai seeds, Mint, Pineapple", "meal_name": "Pineapple Chai Seeds Juice", "notes": "Extra cold please", "order_date": "Sat, 05 Apr 2025 03:12:50 GMT", "order_id": 2069, "order_status": "Pending", "order_type": "meal", "payment_mode": "momo", "payment_status": "Pending", "producer_id": 30, "producer_name": "kingkobra", "product_id": "M181", "quantity": 1, "total_price": 5.00, "transaction_id": null, "user_id": 138 },
    { "amount_paid": 10.00, "chef_id": null, "chef_name": null, "delivery_address": "0.3450727, 32.5611365, Makerere Kavule, Kawempe, Kampala, Central Region, Uganda", "ingredients": "Beef, Carrots, Coriander, Peppers, Garlic, Ginger, Onions, Salt", "meal_name": "Beef Gravy Special", "notes": "No special instructions", "order_date": "Thu, 03 Apr 2025 05:31:21 GMT", "order_id": 1073, "order_status": "Preparing", "order_type": "meal", "payment_mode": "card", "payment_status": "Paid", "producer_id": 30, "producer_name": "kingkobra", "product_id": "M106", "quantity": 2, "total_price": 10.00, "transaction_id": "txn_123", "user_id": 138 },
    { "amount_paid": 5.00, "chef_id": 12, "chef_name": "Chef Ramsey", "delivery_address": "0.3324638, 32.5805475, 3, Kitante Close, Kitante, Central, Kampala, Central Region, Uganda", "ingredients": "Carrots, Coriander, Cumin, Garlic, Ginger, Minced meat, Spice, Onions, Royco, Salt", "meal_name": "Beef Samosas (3pcs)", "notes": "Make them crispy!", "order_date": "Wed, 02 Apr 2025 19:00:34 GMT", "order_id": 70, "order_status": "Delivered", "order_type": "meal", "payment_mode": "cash", "payment_status": "Paid", "producer_id": 30, "producer_name": "kingkobra", "product_id": "M109", "quantity": 1, "total_price": 5.00, "transaction_id": "txn_cash_001", "user_id": 138 },
    { "amount_paid": 0.00, "chef_id": null, "chef_name": null, "delivery_address": "0.3413361, 32.5646712, City Centre Primary School, Makerere, Kampala", "ingredients": "Beef, Carrots, Peppers, Garlic, Ginger, Onions, Salt", "meal_name": "Beef Gravy", "notes": "No onions", "order_date": "Thu, 03 Apr 2025 04:39:26 GMT", "order_id": 1069, "order_status": "Pending", "order_type": "meal", "payment_mode": "momo", "payment_status": "Pending", "producer_id": 30, "producer_name": "kingkobra", "product_id": "M106", "quantity": 1, "total_price": 5.00, "transaction_id": null, "user_id": 139 },
    { "amount_paid": 0.00, "chef_id": null, "chef_name": null, "delivery_address": "0.3307696, 32.5670204, Makerere University Main Gate", "ingredients": "Carrots, Ginger, Green paper, Onions, Salt, Wheat", "meal_name": "Chapati (2pcs)", "notes": "No special instructions", "order_date": "Thu, 03 Apr 2025 04:45:19 GMT", "order_id": 1070, "order_status": "Accepted", "order_type": "meal", "payment_mode": "momo", "payment_status": "Pending", "producer_id": 30, "producer_name": "kingkobra", "product_id": "M115", "quantity": 1, "total_price": 2.00, "transaction_id": null, "user_id": 138}
  ],
  "message": "Orders retrieved successfully."
}
''';

const String produceJsonResponse = '''
{
  "data": [
    { "produce_id": "P101", "produce_name": "African egg plant (nakati)", "calories": 27, "carbohydrates": 4, "proteins": 1.4, "fats": 0.2, "unit_grams": 100, "source": "healthbenefitstimes.com" },
    { "produce_id": "P102", "produce_name": "Almond milk", "calories": 15, "carbohydrates": 0.3, "proteins": 0.6, "fats": 1.2, "unit_grams": 100, "source": "healthline.com" },
    { "produce_id": "P105", "produce_name": "Avocado", "calories": 160, "carbohydrates": 8.5, "proteins": 2, "fats": 14.7, "unit_grams": 100 },
    { "produce_id": "P109", "produce_name": "Bananas (Sweet)", "calories": 89, "carbohydrates": 23, "proteins": 1.1, "fats": 0.3, "unit_grams": 100, "source": "usda.gov" }
   ],
  "message": "Produce retrieved successfully."
}
''';

class ProducerDash22_mock_data extends StatefulWidget {
  const ProducerDash22_mock_data({Key? key}) : super(key: key);

  @override
  _ProducerDash22_mock_dataState createState() =>
      _ProducerDash22_mock_dataState();
}

class _ProducerDash22_mock_dataState extends State<ProducerDash22_mock_data> {
  int _currentIndex = 0;
  ProducerProfile? _profile;
  List<Order> _orders = [];
  List<Product> _produce = [];
  bool _isLoading = true;
  String _error = '';

  // --- Editing State ---
  bool _isEditingProfile = false;
  String? _editingProduceId; // Track which produce item is being edited

  // --- TextEditing Controllers ---
  // Profile Editing Controllers
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  late TextEditingController _profileLocationController;
  // Produce Editing Controllers (will be created/disposed dynamically)
  TextEditingController? _produceNameController;
  TextEditingController? _produceCaloriesController;
  TextEditingController? _produceProteinsController;
  TextEditingController? _produceCarbsController;
  TextEditingController? _produceFatsController;
  TextEditingController? _produceUnitGramsController;
  TextEditingController? _produceSourceController;

  // --- Define Colors ---
  static const Color primaryTeal = Color(0xFF009688);
  static const Color lightTeal = Color(0xFFB2DFDB);
  static const Color faintLightTeal =
      Color(0xFFE0F2F1); // For nutrient chips & toggle track
  static const Color darkTeal = Color(0xFF00695C);
  static const Color whiteColor = Colors.white;
  static const Color textOnTeal = Colors.white;
  static const Color textOnWhite =
      Color(0xFF212121); // Standard text on white/light background
  static const Color subtleText =
      Color(0xFF757575); // Greyish text for less important info
  static const Color cardBackground =
      Color(0xFFF1F8F8); // Used for profile header card
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color starColor = Color(0xFFFFC107);
  static const Color dividerColor = Color(0xFFE0E0E0);
  static final Color pendingColor = Colors.orange.shade600;
  static final Color acceptedColor = Colors.blue.shade600;
  static final Color preparingColor = Colors.deepPurple.shade400;
  static final Color dispatchedColor = primaryTeal;
  static final Color deliveredColor = Colors.green.shade600;
  static final Color cancelledColor = Colors.red.shade600;
  static final Color defaultStatusColor = Colors.grey.shade600;
  static const Color actionButtonBackground = Color(
      0xFFE0F2F1); // Background for standard action buttons (Accept, Prepare, etc.)
  static const Color actionButtonForeground =
      darkTeal; // Text/Icon color for standard action buttons
  static const Color destructiveButtonBackground =
      Color(0xFFFFEBEE); // Background for destructive buttons (Cancel, Delete)
  static const Color destructiveButtonForeground =
      Color(0xFFC62828); // Text/Icon color for destructive buttons

  // Path for placeholder image (ensure this exists in your assets folder and pubspec.yaml)
  static const String placeholderImagePath =
      'assets/images/placeholder_avatar.png';

  // GlobalKey for the Form in Produce tab
  final GlobalKey<FormState> _produceFormKey = GlobalKey<FormState>();
  // GlobalKey for the Form in Profile tab
  final GlobalKey<FormState> _profileFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Initialize profile controllers (empty initially, populated on edit)
    _profileNameController = TextEditingController();
    _profilePhoneController = TextEditingController();
    _profileLocationController = TextEditingController();
    _fetchAllData();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _profileLocationController.dispose();
    _disposeProduceEditControllers(); // Dispose produce controllers if any exist
    super.dispose();
  }

  // Helper to dispose produce editing controllers
  void _disposeProduceEditControllers() {
    _produceNameController?.dispose();
    _produceCaloriesController?.dispose();
    _produceProteinsController?.dispose();
    _produceCarbsController?.dispose();
    _produceFatsController?.dispose();
    _produceUnitGramsController?.dispose();
    _produceSourceController?.dispose();
    _produceNameController = null;
    _produceCaloriesController = null;
    _produceProteinsController = null;
    _produceCarbsController = null;
    _produceFatsController = null;
    _produceUnitGramsController = null;
    _produceSourceController = null;
  }

  // --- Data Fetching and Handling ---
  Future<void> _fetchAllData() async {
    if (!mounted) return;
    bool wasLoading = _isLoading;
    if (!wasLoading) {
      setState(() => _isLoading = true);
    }
    _error = ''; // Clear previous error
    _cancelAllEdits(); // Cancel any ongoing edits on refresh

    try {
      // --- Simulate API Calls ---
      await Future.delayed(const Duration(milliseconds: 900));

      // --- Fetch and Parse Profile ---
      final profileData = jsonDecode(profileJsonResponse);
      ProducerProfile? fetchedProfile;
      if (profileData['data'] != null && profileData['data'].isNotEmpty) {
        try {
          fetchedProfile = ProducerProfile.fromJson(profileData['data'][0]);
        } catch (e) {
          debugPrint(
              'Error parsing Profile JSON: ${profileData['data'][0]}. Error: $e');
          _error += 'Failed to parse profile data. ';
        }
      } else {
        debugPrint('No producer profile data found.');
        _error += 'Producer profile not found. ';
      }

      // --- Fetch and Parse Orders ---
      final ordersData = jsonDecode(ordersJsonResponse);
      List<Order> fetchedOrders = [];
      if (ordersData['data'] != null) {
        try {
          fetchedOrders = (ordersData['data'] as List)
              .map((orderJson) => Order.fromJson(orderJson))
              .toList();
        } catch (e) {
          debugPrint(
              'Error parsing Orders JSON: ${ordersData['data']}. Error: $e');
          _error += 'Failed to parse order data. ';
        }
      } else {
        debugPrint('No order data found.');
      }

      // --- Fetch and Parse Produce ---
      final produceData = jsonDecode(produceJsonResponse);
      List<Product> fetchedProduce = [];
      if (produceData['data'] != null) {
        try {
          fetchedProduce = (produceData['data'] as List)
              .map((produceJson) => Product.fromJson(produceJson))
              .toList();
        } catch (e) {
          debugPrint(
              'Error parsing Produce JSON: ${produceData['data']}. Error: $e');
          _error += 'Failed to parse produce data. ';
        }
      } else {
        debugPrint('No produce data found.');
      }

      // --- Update State After All Fetches ---
      if (mounted) {
        setState(() {
          _profile = fetchedProfile;
          _orders = fetchedOrders;
          _produce = fetchedProduce;

          _sortOrders();
          _produce.sort((a, b) => a.produceName.compareTo(b.produceName));

          _isLoading = false;
          // Combine potential parsing errors with generic message if no data loaded
          if (_profile == null &&
              _orders.isEmpty &&
              _produce.isEmpty &&
              _error.isEmpty) {
            _error = 'No data available for this producer.';
          } else {
            // Keep specific parsing errors if they occurred
            _error = _error.trim(); // Remove trailing space if any
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint("Error fetching data: $e\n$stackTrace");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load dashboard data. Please try again.';
          _profile = null;
          _orders = [];
          _produce = [];
        });
      }
    }
  }

  // --- Sorting Helpers ---
  void _sortOrders() {
    _orders.sort((a, b) {
      int statusCompare = _statusPriority(a.orderStatus)
          .compareTo(_statusPriority(b.orderStatus));
      if (statusCompare != 0) return statusCompare;
      return b.orderDate.compareTo(a.orderDate); // Newest first
    });
  }

  int _statusPriority(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return 0;
      case Order.STATUS_ACCEPTED:
        return 1;
      case Order.STATUS_PREPARING:
        return 2;
      case Order.STATUS_DISPATCHED:
        return 3;
      case Order.STATUS_DELIVERED:
        return 4;
      case Order.STATUS_CANCELLED:
        return 5;
      default:
        return 6;
    }
  }

  // --- Action Handlers (Simulated) ---

  // --- Order Actions ---
  void _handleOrderAction(Order order, String action) {
    debugPrint('Action "$action" triggered for Order ID: ${order.orderId}');
    // **TODO: Implement Real API Call Here to update order status**
    // Example: await ApiService.updateOrderStatus(order.orderId, newStatus);

    // --- Simulation Logic ---
    String newStatus = order.orderStatus;
    switch (action) {
      case 'Accept':
        newStatus = Order.STATUS_ACCEPTED;
        break;
      case 'Prepare':
        newStatus = Order.STATUS_PREPARING;
        break;
      case 'Dispatch':
        newStatus = Order.STATUS_DISPATCHED;
        break;
      case 'Cancel':
        newStatus = Order.STATUS_CANCELLED;
        break;
    }

    if (newStatus != order.orderStatus) {
      _updateLocalOrderState(order.orderId, newStatus);
      _showSnackbar('Order #${order.orderId} marked as $newStatus (simulated).',
          isError: false);
    } else {
      debugPrint(
          "No status change needed for action '$action' on order ${order.orderId}.");
    }
  }

  void _updateLocalOrderState(int orderId, String newStatus) {
    if (!mounted) return;
    setState(() {
      int index = _orders.indexWhere((o) => o.orderId == orderId);
      if (index != -1) {
        // Using copyWith now available on Order model
        try {
          _orders[index] = _orders[index].copyWith(orderStatus: newStatus);
          _sortOrders(); // Re-sort the list
        } catch (e) {
          debugPrint("Error using copyWith on Order: $e.");
          // Fallback should ideally not be needed now, but kept for extreme safety
          final oldOrder = _orders[index];
          _orders[index] = Order(
            orderId: oldOrder.orderId, producerId: oldOrder.producerId,
            userId: oldOrder.userId,
            mealName: oldOrder.mealName, ingredients: oldOrder.ingredients,
            quantity: oldOrder.quantity,
            totalPrice: oldOrder.totalPrice,
            orderStatus: newStatus, // Apply new status
            paymentStatus: oldOrder.paymentStatus,
            paymentMode: oldOrder.paymentMode,
            deliveryAddress: oldOrder.deliveryAddress,
            orderDate: oldOrder.orderDate, notes: oldOrder.notes,
            orderType: oldOrder.orderType, productId: oldOrder.productId,
            chefId: oldOrder.chefId,
            chefName: oldOrder.chefName, amountPaid: oldOrder.amountPaid,
            transactionId: oldOrder.transactionId,
            producerName: oldOrder.producerName,
          );
          _sortOrders();
        }
      }
    });
  }

  // --- Profile Actions ---
  void _handleEditProfile() {
    if (_profile == null || !mounted) return;
    debugPrint('Edit Profile Action Triggered');
    setState(() {
      _isEditingProfile = true;
      // Initialize controllers with current profile data
      _profileNameController.text = _profile!.name;
      _profilePhoneController.text = _profile!.phoneNumber ?? '';
      _profileLocationController.text = _profile!.location ?? '';
    });
  }

  void _saveProfileChanges() {
    if (_profile == null || !mounted || !_isEditingProfile) return;
    // Validate the form first
    if (_profileFormKey.currentState?.validate() ?? false) {
      debugPrint('Save Profile Changes Action Triggered');
      // **TODO: Implement Real API Call Here to save profile data**
      // Example: await ApiService.updateProfile(_profile!.producerId, name: _profileNameController.text, phone: _profilePhoneController.text, location: _profileLocationController.text);

      // --- Simulation Logic ---
      final updatedProfile = _profile!.copyWith(
        name: _profileNameController.text,
        // Use ValueGetter pattern for nullable fields to handle empty strings becoming null
        phoneNumber: () => _profilePhoneController.text.trim().isNotEmpty
            ? _profilePhoneController.text.trim()
            : null,
        location: () => _profileLocationController.text.trim().isNotEmpty
            ? _profileLocationController.text.trim()
            : null,
      );

      setState(() {
        _profile = updatedProfile;
        _isEditingProfile = false; // Exit edit mode
      });
      _showSnackbar('Profile updated successfully (simulated).',
          isError: false);
    } else {
      debugPrint('Profile form validation failed.');
      _showSnackbar('Please fix errors in the profile form.', isError: true);
    }
  }

  void _cancelProfileEdit() {
    if (!mounted) return;
    debugPrint('Cancel Profile Edit Action Triggered');
    setState(() {
      _isEditingProfile = false;
      // Clear validation errors if any by resetting the key (optional, usually happens on next edit)
      // _profileFormKey.currentState?.reset();
    });
  }

  // --- Active Status Toggle ---
  void _handleToggleActiveStatus(bool newStatus) {
    if (_profile == null || !mounted || _isEditingProfile)
      return; // Prevent toggle while editing profile

    debugPrint(
        'Toggle Active Status Action Triggered: New Status = $newStatus');
    // **TODO: Implement Real API Call Here to update profile active status**
    // Example: await ApiService.updateProfileStatus(_profile!.producerId, newStatus);

    // --- Simulation Logic ---
    setState(() {
      _profile = _profile!.copyWith(isActive: newStatus);
    });

    final statusText = newStatus ? "Active" : "Offline";
    String message = 'Profile status updated to $statusText (simulated).';
    if (!newStatus) {
      message +=
          '\nUsers will not be able to find you.'; // Add extra info for offline
    }
    _showSnackbar(message,
        isError: false,
        durationSeconds: 4); // Longer duration for multi-line message
  }

  // --- Produce Actions ---
  void _handleAddProduce() {
    if (_editingProduceId != null || !mounted)
      return; // Don't add if already editing another
    debugPrint('Add Produce Action Triggered');

    // **Option 1: Navigate to a dedicated Add Screen (Recommended for complex forms)**
    // Navigator.push(context, MaterialPageRoute(builder: (_) => AddProduceScreen())).then((newProduct) {
    //    if (newProduct != null && newProduct is Product && mounted) {
    //       setState(() {
    //          _produce.add(newProduct);
    //          _produce.sort((a, b) => a.produceName.compareTo(b.produceName));
    //       });
    //        _showSnackbar('Added "${newProduct.produceName}".', isError: false);
    //    }
    // });

    // **Option 2: Add Blank Item and Enter Edit Mode Inline (Used Here)**
    final newId =
        'P${DateTime.now().millisecondsSinceEpoch % 10000}'; // Slightly more unique ID
    final newProduct = Product(
      produceId: newId,
      produceName: '', // Start blank
      calories: null,
      unitGrams: null, // Start blank or default e.g., 100
      proteins: null,
      fats: null,
      carbohydrates: null,
      source: null,
    );
    setState(() {
      _produce.add(newProduct);
      _produce.sort((a, b) => a.produceName.compareTo(b.produceName));
      // Immediately enter edit mode for the new item:
      _handleEditProduce(newProduct);
    });
    _showSnackbar('Adding new produce item. Please fill in details.',
        isError: false);
  }

  void _handleEditProduce(Product product) {
    if (!mounted || _isEditingProfile)
      return; // Prevent editing produce while editing profile
    debugPrint('Edit Produce Action Triggered for ID: ${product.produceId}');
    _cancelAllEdits(
        exceptProduceId: product.produceId); // Cancel other edits first

    // Initialize controllers for THIS product
    _produceNameController = TextEditingController(text: product.produceName);
    _produceCaloriesController =
        TextEditingController(text: product.calories?.toStringAsFixed(0) ?? '');
    _produceProteinsController =
        TextEditingController(text: product.proteins?.toStringAsFixed(1) ?? '');
    _produceCarbsController = TextEditingController(
        text: product.carbohydrates?.toStringAsFixed(1) ?? '');
    _produceFatsController =
        TextEditingController(text: product.fats?.toStringAsFixed(1) ?? '');
    _produceUnitGramsController = TextEditingController(
        text: product.unitGrams?.toStringAsFixed(0) ?? '');
    _produceSourceController =
        TextEditingController(text: product.source ?? '');

    setState(() {
      _editingProduceId = product.produceId; // Enter edit mode for this item
    });
  }

  void _saveProduceChanges() {
    if (_editingProduceId == null || !mounted) return;

    // Validate the form first
    if (_produceFormKey.currentState?.validate() ?? false) {
      debugPrint(
          'Save Produce Changes Action Triggered for ID: $_editingProduceId');

      final index =
          _produce.indexWhere((p) => p.produceId == _editingProduceId);
      if (index == -1) {
        debugPrint(
            "Error: Could not find produce with ID $_editingProduceId to save.");
        _cancelProduceEdit();
        return;
      }

      // **TODO: Implement Real API Call Here to add/update produce data**
      // Example:
      // bool isNew = _produce[index].produceName.isEmpty; // Check if it was a newly added item
      // if (isNew) {
      //    await ApiService.addProduce(name: _produceNameController?.text ?? '', ...);
      // } else {
      //    await ApiService.updateProduce(_editingProduceId!, name: _produceNameController?.text ?? '', ...);
      // }

      // --- Simulation Logic ---
      try {
        // Helper function to safely parse double, returning null if empty or invalid
        double? parseOptionalDouble(String? text) {
          if (text == null || text.trim().isEmpty) return null;
          return double.tryParse(text.trim());
        }

        final updatedProduct = _produce[index].copyWith(
          produceName: _produceNameController?.text.trim() ??
              _produce[index].produceName,
          // Use ValueGetter with helper for nullable doubles
          calories: () => parseOptionalDouble(_produceCaloriesController?.text),
          proteins: () => parseOptionalDouble(_produceProteinsController?.text),
          carbohydrates: () =>
              parseOptionalDouble(_produceCarbsController?.text),
          fats: () => parseOptionalDouble(_produceFatsController?.text),
          unitGrams: () => parseOptionalDouble(_produceUnitGramsController
              ?.text), // Unit grams might be required by API
          source: () => _produceSourceController?.text.trim().isNotEmpty == true
              ? _produceSourceController?.text.trim()
              : null,
        );

        setState(() {
          _produce[index] = updatedProduct;
          _produce.sort((a, b) => a.produceName.compareTo(b.produceName));
          final savedName = updatedProduct.produceName;
          _editingProduceId = null; // Exit edit mode
          _disposeProduceEditControllers(); // Clean up controllers
          _showSnackbar('Saved "$savedName" (simulated).', isError: false);
        });
      } catch (e) {
        debugPrint("Error preparing updated product data: $e");
        _showSnackbar('Error saving produce data. Please check inputs.',
            isError: true);
      }
    } else {
      debugPrint('Produce form validation failed.');
      _showSnackbar('Please fix errors in the produce form.', isError: true);
    }
  }

  void _cancelProduceEdit() {
    if (!mounted) return;
    debugPrint('Cancel Produce Edit Action Triggered');
    final String? idToCancel =
        _editingProduceId; // Store the ID before clearing

    setState(() {
      _editingProduceId = null; // Exit edit mode
      _disposeProduceEditControllers(); // Clean up controllers

      // If the cancelled item was a newly added blank item, remove it
      if (idToCancel != null) {
        final index = _produce.indexWhere((p) => p.produceId == idToCancel);
        if (index != -1 && _produce[index].produceName.trim().isEmpty) {
          _produce.removeAt(index);
          debugPrint("Removed blank new produce item on cancel.");
        }
      }
    });
  }

  void _handleDeleteProduce(Product product) {
    if (!mounted || _isEditingProfile || _editingProduceId != null)
      return; // Prevent delete while editing anything
    debugPrint('Delete Produce Action Triggered for ID: ${product.produceId}');

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            backgroundColor: whiteColor.withOpacity(0.95),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: errorColor),
                SizedBox(width: 10),
                Text('Confirm Deletion'),
              ],
            ),
            content: Text(
                'Are you sure you want to permanently delete "${product.produceName}"?\nThis action cannot be undone.',
                style: TextStyle(color: subtleText)),
            actions: <Widget>[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: subtleText),
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever_outlined, size: 16),
                label: const Text('Delete'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: destructiveButtonBackground,
                    foregroundColor: destructiveButtonForeground,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _performDeleteProduce(product);
                },
              ),
            ],
          );
        });
  }

  void _performDeleteProduce(Product product) {
    // **TODO: Implement Real API Call Here to delete produce**
    // Example: await ApiService.deleteProduce(product.produceId);
    if (mounted) {
      final deletedName = product.produceName; // Store name before removal
      setState(() {
        _produce.removeWhere((p) => p.produceId == product.produceId);
      });
      _showSnackbar('Deleted "$deletedName" (simulated).', isError: false);
    }
  }

  // Helper to cancel any active edit mode
  void _cancelAllEdits({String? exceptProduceId}) {
    if (!mounted) return;
    bool profileWasEditing = _isEditingProfile;
    String? produceWasEditing = _editingProduceId;

    setState(() {
      _isEditingProfile = false;
      // Only cancel produce edit if it's not the one specified in exceptProduceId
      if (_editingProduceId != null && _editingProduceId != exceptProduceId) {
        _editingProduceId = null;
        _disposeProduceEditControllers();
      } else if (exceptProduceId == null && _editingProduceId != null) {
        // If no exception, clear unconditionally
        _editingProduceId = null;
        _disposeProduceEditControllers();
      }
      // Consider removing blank items if cancelling add-produce action implicitly
      // (Handled in _cancelProduceEdit specifically now)
    });

    if (profileWasEditing ||
        (produceWasEditing != null && produceWasEditing != exceptProduceId)) {
      debugPrint("Cancelled active edits.");
    }
  }

  // --- Utility Functions ---
  void _showSnackbar(String message,
      {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar(); // Hide previous snackbar first
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: TextStyle(
                color:
                    isError ? whiteColor : textOnTeal), // Text color contrast
            textAlign: TextAlign.center),
        backgroundColor: isError
            ? errorColor.withOpacity(0.9)
            : primaryTeal.withOpacity(0.9), // Background color
        duration: Duration(seconds: durationSeconds),
        behavior: SnackBarBehavior.floating, // Make it float (toast-like)
        margin: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 15.0),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        elevation: 4.0,
      ),
    );
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Determine the correct image provider for the AppBar avatar
    ImageProvider? appBarAvatarImage;
    if (!_isLoading && _profile != null) {
      if (_profile!.image != null && _profile!.image!.isNotEmpty) {
        try {
          appBarAvatarImage = NetworkImage(_profile!.image!);
        } catch (e) {
          debugPrint("Invalid URL for AppBar image: ${_profile!.image}");
          appBarAvatarImage =
              const AssetImage(placeholderImagePath); // Fallback on invalid URL
        }
      } else {
        appBarAvatarImage =
            const AssetImage(placeholderImagePath); // Use asset placeholder
      }
    }

    return Scaffold(
      backgroundColor: whiteColor, // Keep app bar solid, body has background
      appBar: AppBar(
        backgroundColor: primaryTeal,
        elevation: 2.0,
        iconTheme: const IconThemeData(color: textOnTeal),
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(
              color: textOnTeal, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: false, // Align title left
        actions: [
          // Updated AppBar profile picture logic
          if (appBarAvatarImage != null)
            Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: CircleAvatar(
                radius: 18,
                backgroundColor:
                    lightTeal.withOpacity(0.5), // Fallback background
                backgroundImage: appBarAvatarImage,
                onBackgroundImageError: (exception, stackTrace) {
                  // This handles network errors AFTER the try-catch for invalid URL format
                  debugPrint('Error loading AppBar network image: $exception');
                  // Optionally force placeholder here if network fails by setting state,
                  // but simpler just letting the error UI show (grey circle)
                },
              ),
            )
          else if (_isLoading) // Show a shimmer or simple placeholder while loading
            Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: CircleAvatar(
                    radius: 18, backgroundColor: lightTeal.withOpacity(0.3)))
          else // Show asset placeholder if profile is null or has no image after loading
            Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: lightTeal.withOpacity(0.5),
                backgroundImage: const AssetImage(placeholderImagePath),
              ),
            ),
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: textOnTeal),
            tooltip: 'Logout',
            onPressed: () {
              // TODO: Implement actual Logout Logic (e.g., clear tokens, navigate to login)
              debugPrint("Logout tapped");
              _showSnackbar('Logout action triggered (simulation).',
                  isError: false);
            },
          ),
          const SizedBox(width: 8), // Add padding to the right edge
        ],
      ),
      // Apply background image to the body area
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                "assets/images/soft.jpg"), // Your background image path
            fit: BoxFit.cover,
            // Optional: Add opacity if image is too vibrant
            colorFilter: ColorFilter.mode(
              Color(0xE6FFFFFF), // Example: Soft white overlay with 90% opacity
              BlendMode.dstATop,
            ),
          ),
        ),
        child: _buildBodyContent(), // Extracted body logic
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index != _currentIndex && mounted) {
            _cancelAllEdits(); // Cancel edits when switching tabs
            setState(() {
              _currentIndex = index;
            });
          }
        },
        backgroundColor:
            whiteColor.withOpacity(0.95), // Slightly transparent white
        selectedItemColor: primaryTeal, // Color for selected text label
        unselectedItemColor: subtleText, // Color for unselected text label
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType
            .fixed, // Ensures all items are always visible
        elevation: 8.0,
        items: [
          _buildBottomNavItem(Icons.account_circle_outlined,
              Icons.account_circle, 'Profile', 0),
          _buildBottomNavItem(
              Icons.receipt_long_outlined, Icons.receipt_long, 'Orders', 1),
          _buildBottomNavItem(
              Icons.inventory_2_outlined, Icons.inventory_2, 'Produce', 2),
        ],
      ),
      floatingActionButton:
          _buildFloatingActionButton(), // Builds FAB based on context
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat, // Standard FAB location
    );
  }

  // --- Helper for Bottom Navigation Item with Highlight ---
  BottomNavigationBarItem _buildBottomNavItem(
      IconData icon, IconData activeIcon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return BottomNavigationBarItem(
      icon: _buildNavItemIcon(icon, isSelected), // Use helper for icon
      // Active icon can be the same or different
      activeIcon: _buildNavItemIcon(isSelected ? activeIcon : icon, isSelected),
      label: label,
    );
  }

  // --- Helper to build the Icon with optional highlight ---
  Widget _buildNavItemIcon(IconData iconData, bool isSelected) {
    // Always use Teal color for the icon itself
    final icon = Icon(iconData,
        color: isSelected
            ? primaryTeal
            : subtleText.withOpacity(0.8), // Teal when selected, grey otherwise
        size: 24);

    if (isSelected) {
      // Add a highlight effect around the selected icon
      return Container(
        padding: const EdgeInsets.all(4), // Adjust padding for highlight size
        decoration: BoxDecoration(
          color: lightTeal.withOpacity(0.25), // Subtle background highlight
          shape: BoxShape.circle, // Circular highlight
        ),
        child: icon,
      );
    } else {
      // Return the plain icon if not selected
      // Wrap in SizedBox to maintain consistent height/layout with highlighted version
      return SizedBox(
        width: 32, // Width = icon size (24) + padding*2 (4*2) = 32
        height: 32, // Height = icon size (24) + padding*2 (4*2) = 32
        child: Center(child: icon),
      );
    }
  }

  // Helper to get dynamic AppBar Title based on tab and edit state
  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return _isEditingProfile ? 'Edit Profile' : 'Producer Profile';
      case 1:
        return 'Manage Orders';
      case 2:
        return _editingProduceId != null ? 'Edit Produce' : 'Manage Produce';
      default:
        return 'Producer Dashboard';
    }
  }

  // Helper to build Floating Action Button based on current tab AND edit state
  Widget? _buildFloatingActionButton() {
    // No FAB if editing profile (Save/Cancel are inline)
    if (_currentIndex == 0 && _isEditingProfile) {
      return null;
    }
    // No FAB if editing a produce item (Save/Cancel are inline)
    if (_currentIndex == 2 && _editingProduceId != null) {
      return null;
    }

    switch (_currentIndex) {
      case 0: // Profile Tab - Edit FAB (only shown when NOT editing)
        return FloatingActionButton.small(
          onPressed: _profile == null
              ? null
              : _handleEditProfile, // Disable if no profile loaded
          tooltip: 'Edit Profile',
          backgroundColor: _profile == null ? Colors.grey : primaryTeal,
          foregroundColor: textOnTeal,
          child: const Icon(Icons.edit_outlined, size: 20),
          heroTag: 'fab_profile_edit', // Unique hero tag
        );
      case 1: // Orders Tab - No FAB needed for orders
        return null;
      case 2: // Produce Tab - Add Produce FAB (only shown when NOT editing an item)
        return FloatingActionButton(
          onPressed: _handleAddProduce,
          tooltip: 'Add Produce Item',
          backgroundColor: primaryTeal,
          foregroundColor: textOnTeal,
          child: const Icon(Icons.add),
          heroTag: 'fab_produce_add', // Unique hero tag
        );
      default:
        return null;
    }
  }

  // Helper widget for the main body content
  Widget _buildBodyContent() {
    if (_isLoading) {
      // Make loader background transparent to show main background
      return Container(
          color: Colors.transparent,
          child: const Center(
              child: CircularProgressIndicator(color: primaryTeal)));
    }
    if (_error.isNotEmpty) {
      // Make error view background transparent
      return Container(color: Colors.transparent, child: _buildErrorView());
    }
    // Use IndexedStack to keep the state of each tab alive
    // Note: When edit state changes (_isEditingProfile, _editingProduceId), the relevant
    // tab's build method is called again, rebuilding its content correctly.
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildProfileTab(),
        _buildOrdersTab(),
        _buildProduceTab(),
      ],
    );
  }

  // Error View Builder
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        // Add a semi-transparent card behind error for readability against background
        child: Card(
          color: whiteColor.withOpacity(0.9), // Semi-transparent white
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Take minimum space
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: errorColor, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error, // Display the specific error message
                  style: const TextStyle(
                      color: textOnWhite,
                      fontSize: 16), // Use standard text color
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: textOnTeal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: _fetchAllData, // Retry fetching ALL data
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ===== TAB BUILDER WIDGETS (Modified for Editing) ==========================
  // ===========================================================================

  // --- Profile Tab Widget ---
  Widget _buildProfileTab() {
    // Handle case where profile data failed to load but other data might be ok
    if (_profile == null) {
      return _buildEmptyState('Producer Profile Unavailable',
          'Could not load profile details. Please try refreshing.',
          icon: Icons.person_off_outlined);
    }

    final profile = _profile!; // Now safe to use !
    final dateFormat =
        DateFormat('MMM d, yyyy, hh:mm a'); // Example: Mar 16, 2025, 10:22 PM
    ImageProvider profileAvatarImage;
    if (profile.image != null && profile.image!.isNotEmpty) {
      try {
        profileAvatarImage = NetworkImage(profile.image!);
      } catch (e) {
        debugPrint("Invalid URL for profile image: ${profile.image}");
        profileAvatarImage = const AssetImage(placeholderImagePath);
      }
    } else {
      profileAvatarImage = const AssetImage(placeholderImagePath);
    }

    // Use a Form widget if editing, associated with the GlobalKey
    final formContent = ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // --- Profile Header Section (Always visible) ---
        Card(
          elevation: 2.0,
          color: cardBackground.withOpacity(0.95), // Slightly transparent card
          margin: EdgeInsets.zero, // No margin around the card itself
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Column(
              children: [
                // --- Avatar ---
                CircleAvatar(
                  radius: 45,
                  backgroundColor: lightTeal.withOpacity(0.5),
                  backgroundImage: profileAvatarImage,
                  onBackgroundImageError: (exception, stackTrace) {
                    debugPrint(
                        'Error loading profile network image: $exception');
                  },
                ),
                const SizedBox(height: 12),
                // --- Name (Editable) ---
                _isEditingProfile
                    ? TextFormField(
                        controller: _profileNameController,
                        decoration: const InputDecoration(
                          labelText: 'Business Name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 12, horizontal: 10),
                          isDense: true,
                        ),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: darkTeal),
                        textAlign: TextAlign.center,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Name cannot be empty'
                                : null,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      )
                    : Text(
                        profile.name,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: darkTeal),
                        textAlign: TextAlign.center,
                      ),
                // --- Producer Type ---
                if (profile.producerType != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.producerType!,
                    style: const TextStyle(fontSize: 14, color: subtleText),
                  ),
                ],
                // --- Rating ---
                if (profile.rating != null && profile.rating! > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded,
                          color: starColor, size: 18),
                      const SizedBox(width: 4),
                      Text(profile.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textOnWhite)),
                      if (profile.reviews != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${profile.reviews})', // Display reviews if available
                          style:
                              const TextStyle(fontSize: 12, color: subtleText),
                        ),
                      ]
                    ],
                  ),
                ]
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // --- Contact Information Section ---
        _buildProfileSectionCard(
          title: 'Contact Information',
          icon: Icons.contact_mail_outlined,
          children: [
            _buildDetailItem(
                Icons.email_outlined,
                'Email',
                profile.email ??
                    'Not provided'), // Email usually not editable here
            // Phone Number (Editable)
            _isEditingProfile
                ? _buildEditableItem(_profilePhoneController, 'Phone Number',
                    Icons.phone_outlined, keyboardType: TextInputType.phone)
                : _buildDetailItem(Icons.phone_outlined, 'Phone',
                    profile.phoneNumber ?? 'Not provided'),
            // Location (Editable)
            _isEditingProfile
                ? _buildEditableItem(_profileLocationController,
                    'Location Address', Icons.location_on_outlined, maxLines: 3)
                : _buildDetailItem(Icons.location_on_outlined, 'Location',
                    profile.location ?? 'Not provided'),
          ],
        ),
        const SizedBox(height: 16),

        // --- Account Details Section ---
        _buildProfileSectionCard(
          title: 'Account Details',
          icon: Icons.manage_accounts_outlined,
          children: [
            _buildDetailItem(Icons.app_registration_rounded, 'Registered',
                dateFormat.format(profile.registrationDate.toLocal())),
            _buildDetailItem(
                Icons.login_outlined,
                'Last Login',
                profile.lastLogin != null
                    ? dateFormat.format(
                        profile.lastLogin!.toLocal()) // Format if available
                    : 'Never logged in'),
            const SizedBox(height: 8), // Add spacing before the toggle
            _buildActiveStatusToggle(profile
                .isActive), // Toggle remains interactive always (unless editing)
          ],
        ),

        // --- Save/Cancel Buttons (Only in Edit Mode) ---
        if (_isEditingProfile) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.end, // Align buttons to the right
            children: [
              // Cancel Button
              TextButton(
                onPressed: _cancelProfileEdit,
                child:
                    const Text('Cancel', style: TextStyle(color: subtleText)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8)),
              ),
              const SizedBox(width: 12),
              // Save Button
              ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryTeal,
                    foregroundColor: textOnTeal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                onPressed: _saveProfileChanges, // Calls validation internally
              ),
            ],
          ),
          const SizedBox(height: 20), // Extra padding at bottom in edit mode
        ],

        // Padding at the bottom to avoid overlap with potential FAB when NOT editing
        if (!_isEditingProfile) const SizedBox(height: 80),
      ],
    );

    // Return simple ListView if not editing, wrap in Form with Key if editing
    return _isEditingProfile
        ? Form(key: _profileFormKey, child: formContent)
        : formContent;
  }

  // Helper for Profile Tab Sections
  Widget _buildProfileSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
      elevation: 1.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      color: whiteColor.withOpacity(0.9), // Make card slightly transparent
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryTeal, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: darkTeal),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 0.8, color: dividerColor),
            // Add children with default spacing
            ...children
                .map((child) => Padding(
                      padding: const EdgeInsets.only(
                          bottom: 4.0), // Add consistent bottom padding
                      child: child,
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  // Helper for Profile Detail Items (Read-only view)
  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 4.0), // Reduced vertical padding
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)),
          const SizedBox(width: 10),
          SizedBox(
            width: 85, // Adjusted width for label consistency
            child: Text(
              label + ':',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textOnWhite,
                  fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty
                  ? 'Not provided'
                  : value, // Show 'Not provided' if empty
              style: TextStyle(
                  color:
                      value.isEmpty ? subtleText.withOpacity(0.7) : subtleText,
                  fontSize: 13),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // Helper for Editable Profile Items using TextFormField
  Widget _buildEditableItem(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          // Use prefixIcon for better alignment than 'icon'
          prefixIcon: Icon(icon, size: 18, color: primaryTeal.withOpacity(0.9)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36), // Ensure space for icon
          isDense: true, // Make field more compact vertically
          contentPadding: const EdgeInsets.symmetric(
              vertical: 12.0, horizontal: 10.0), // Adjust padding
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: dividerColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(color: dividerColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(color: primaryTeal, width: 1.5)),
          labelStyle: const TextStyle(color: subtleText, fontSize: 13),
          floatingLabelStyle:
              const TextStyle(color: primaryTeal), // Label color when focused
        ),
        style: const TextStyle(color: textOnWhite, fontSize: 13),
        maxLines: maxLines,
        keyboardType: keyboardType,
        // Optional: Add validation for specific fields like phone
        validator: (value) {
          if (label.contains('Phone') && value != null && value.isNotEmpty) {
            // Basic phone validation example (adjust regex as needed for your region)
            // This example is very basic: checks for digits, optional +, spaces, hyphens
            if (!RegExp(r'^[\d\s\-+]+$').hasMatch(value)) {
              return 'Invalid phone format';
            }
          }
          // Add other validations if needed
          return null; // Return null if valid
        },
        autovalidateMode:
            AutovalidateMode.onUserInteraction, // Validate as user types
      ),
    );
  }

  // Widget for Active Status Toggle (Style Refinements)
  Widget _buildActiveStatusToggle(bool isActive) {
    return SwitchListTile(
      value: isActive,
      onChanged: _isEditingProfile
          ? null
          : _handleToggleActiveStatus, // Disable while editing profile
      title: Text(
        isActive ? 'Account Active' : 'Account Offline',
        style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _isEditingProfile
                ? subtleText
                : textOnWhite, // Dim text if disabled
            fontSize: 13),
      ),
      secondary: Icon(
          isActive
              ? Icons.check_circle_outline_rounded
              : Icons.power_settings_new_outlined,
          size: 18,
          color: isActive
              ? (_isEditingProfile
                  ? lightTeal.withOpacity(0.5)
                  : primaryTeal) // Dim icon if disabled
              : subtleText),
      activeColor: primaryTeal, // Color of the switch thumb when on
      activeTrackColor:
          lightTeal.withOpacity(0.6), // Color of the track when on
      inactiveThumbColor:
          subtleText.withOpacity(0.8), // Color of thumb when off
      inactiveTrackColor: Colors.grey.shade300, // Color of track when off
      dense: true, // Make it more compact
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 4, vertical: 0), // Fine-tune padding
      visualDensity: VisualDensity.compact, // Make it visually smaller
      controlAffinity:
          ListTileControlAffinity.leading, // Place switch on the left
    );
  }

  // --- Orders Tab Widget ---
  Widget _buildOrdersTab() {
    return RefreshIndicator(
        onRefresh: _fetchAllData,
        color: primaryTeal,
        backgroundColor: whiteColor,
        child: Container(
          // Ensure container allows background through
          color: Colors.transparent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                16.0, 16.0, 16.0, 80.0), // Padding for content and FAB/navbar
            children: [
              _buildSummarySection(), // Show summary cards if orders exist
              if (_orders.isNotEmpty)
                const SizedBox(height: 24), // Space below summary
              _buildOrdersListSection(), // Show list or empty state
            ],
          ),
        ));
  }

  Widget _buildSummarySection() {
    if (_orders.isEmpty)
      return const SizedBox.shrink(); // Don't show if no orders

    int pendingOrders =
        _orders.where((o) => o.orderStatus == Order.STATUS_PENDING).length;
    int activeOrders = _orders
        .where((o) => [
              Order.STATUS_ACCEPTED,
              Order.STATUS_PREPARING,
              Order.STATUS_DISPATCHED
            ].contains(o.orderStatus))
        .length;
    int totalOrders =
        _orders.length; // Could also filter out cancelled/delivered if desired

    return Card(
      elevation: 1.0,
      color: primaryTeal.withOpacity(0.9), // Make card slightly transparent
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryItem('Pending', pendingOrders.toString(),
                Icons.pending_actions_outlined),
            _buildSummaryItem('In Progress', activeOrders.toString(),
                Icons.local_shipping_outlined),
            _buildSummaryItem(
                'Total Today',
                totalOrders.toString(),
                Icons
                    .list_alt_outlined), // Example: Filter for today's orders if needed
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: whiteColor.withOpacity(0.9), size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: whiteColor)),
        const SizedBox(height: 2),
        Text(title,
            style: const TextStyle(
                fontSize: 11, color: lightTeal, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildOrdersListSection() {
    if (_orders.isEmpty) {
      // Show empty state if no orders loaded
      return _buildEmptyState(
          'No Orders Yet', 'New customer orders will appear here.',
          icon: Icons.receipt_long_outlined);
    }
    // Build the list if orders exist
    return ListView.builder(
      shrinkWrap: true, // Important inside another ListView
      physics:
          const NeverScrollableScrollPhysics(), // Disable scrolling for this inner list
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        // Use Padding for spacing between items, except for the last one
        return Padding(
          padding:
              EdgeInsets.only(bottom: (index == _orders.length - 1) ? 0 : 12.0),
          child: _buildOrderItem(_orders[index]), // Build each order item card
        );
      },
    );
  }

  // --- Produce Tab Widget (Modified for Editing) ---
  Widget _buildProduceTab() {
    return RefreshIndicator(
      onRefresh: _fetchAllData,
      color: primaryTeal,
      backgroundColor: whiteColor,
      child: Container(
        // Ensure container allows background through
        color: Colors.transparent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              16.0, 16.0, 16.0, 80.0), // Padding for content and FAB
          children: [
            if (_produce.isEmpty &&
                !_isLoading) // Show empty state only if not loading and no produce
              _buildEmptyState(
                'No Produce Items Found',
                'Tap the (+) button below to add your first produce item.',
                icon: Icons.eco_outlined,
              )
            else
              _buildProduceList(), // Build the list (wrapped in Form)
            // Add padding at the bottom if currently editing an item,
            // to prevent overlap with potential FAB location when keyboard is up
            if (_editingProduceId != null) const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildProduceList() {
    // Use a Form widget to encompass all potential TextFormFields within the list
    // Associate the Form with the GlobalKey for validation
    return Form(
      key: _produceFormKey,
      child: ListView.separated(
        shrinkWrap: true,
        physics:
            const NeverScrollableScrollPhysics(), // List is inside another scrollable (ListView)
        itemCount: _produce.length,
        itemBuilder: (context, index) {
          return _buildProduceItem(
              _produce[index]); // Item builder handles display/edit state
        },
        separatorBuilder: (context, index) =>
            const SizedBox(height: 10), // Space between cards
      ),
    );
  }

  // --- Build Produce Item (Handles Display and Edit States) ---
  Widget _buildProduceItem(Product product) {
    final bool isEditingThisItem = _editingProduceId == product.produceId;

    Widget content; // The content inside the card

    if (isEditingThisItem) {
      // --- EDITING VIEW ---
      content = Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProduceEditableField(_produceNameController, 'Produce Name',
                isRequired: true),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _buildProduceEditableField(
                        _produceCaloriesController, 'Calories',
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildProduceEditableField(
                        _produceProteinsController, 'Protein (g)',
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: _buildProduceEditableField(
                        _produceCarbsController, 'Carbs (g)',
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildProduceEditableField(
                        _produceFatsController, 'Fat (g)',
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start, // Align items at the top
              children: [
                Expanded(
                    child: _buildProduceEditableField(
                        _produceUnitGramsController, 'Unit (g)',
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        isRequired:
                            false)), // Make unit optional for flexibility
                const SizedBox(width: 8),
                Expanded(
                    child: _buildProduceEditableField(
                        _produceSourceController, 'Source (optional)')),
              ],
            ),
            const SizedBox(height: 16),
            // --- Save/Cancel Buttons for Edit Mode ---
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancelProduceEdit,
                  child:
                      const Text('Cancel', style: TextStyle(color: subtleText)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: textOnTeal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: _saveProduceChanges, // Calls validation internally
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // --- DISPLAY VIEW ---
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start, // Align icon, text, buttons to the top
          children: [
            // --- Icon ---
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: lightTeal.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8)),
                child:
                    const Icon(Icons.eco_outlined, color: darkTeal, size: 24)),
            const SizedBox(width: 12),
            // --- Text Details ---
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Produce Name
                  Text(
                    product.produceName.isEmpty
                        ? '(Unnamed Produce)'
                        : product.produceName,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: product.produceName.isEmpty
                            ? subtleText
                            : textOnWhite),
                  ),
                  const SizedBox(height: 4),
                  // Produce ID
                  Text(
                    'ID: ${product.produceId}',
                    style: const TextStyle(fontSize: 11, color: subtleText),
                  ),
                  const SizedBox(height: 8),
                  // Nutrient Chips (only shown if data exists)
                  if (product.calories != null ||
                      product.proteins != null ||
                      product.carbohydrates != null ||
                      product.fats != null ||
                      product.unitGrams != null ||
                      (product.source != null && product.source!.isNotEmpty))
                    Wrap(
                      spacing: 6.0, // Horizontal space between chips
                      runSpacing: 4.0, // Vertical space between lines of chips
                      children: [
                        if (product.calories != null)
                          _buildNutrientChip(
                              'Calories', product.calories!.toStringAsFixed(0)),
                        if (product.proteins != null)
                          _buildNutrientChip('Protein',
                              '${product.proteins!.toStringAsFixed(1)}g'),
                        if (product.carbohydrates != null)
                          _buildNutrientChip('Carbs',
                              '${product.carbohydrates!.toStringAsFixed(1)}g'),
                        if (product.fats != null)
                          _buildNutrientChip(
                              'Fat', '${product.fats!.toStringAsFixed(1)}g'),
                        if (product.unitGrams != null)
                          _buildNutrientChip('Unit',
                              '${product.unitGrams!.toStringAsFixed(0)}g'),
                        // Source chip - only if source is not null and not empty
                        if (product.source != null &&
                            product.source!.isNotEmpty)
                          _buildNutrientChip('Source', product.source!,
                              isLong: true),
                      ],
                    )
                  else // Show placeholder if no nutrient info
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        'No nutrient details available.',
                        style: TextStyle(
                            fontSize: 11,
                            color: subtleText.withOpacity(0.7),
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // --- Action Buttons Column (Edit/Delete) ---
            Column(
              mainAxisAlignment: MainAxisAlignment.start, // Align buttons top
              children: [
                _actionButtonSmall(Icons.edit_outlined, 'Edit',
                    () => _handleEditProduce(product)),
                const SizedBox(height: 4),
                _actionButtonSmall(Icons.delete_outline, 'Delete',
                    () => _handleDeleteProduce(product),
                    isDestructive: true),
              ],
            )
          ],
        ),
      );
    }

    // --- Card Container ---
    return Card(
      elevation:
          isEditingThisItem ? 3.0 : 1.5, // Slightly raise card when editing
      margin: EdgeInsets.zero, // Let ListView handle spacing
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        // Add a subtle border when editing
        side: isEditingThisItem
            ? const BorderSide(color: primaryTeal, width: 1.0)
            : BorderSide.none,
      ),
      color:
          whiteColor.withOpacity(0.95), // Slightly more opaque card background
      child: content,
    );
  }

  // Helper for Editable Produce Fields using TextFormField
  Widget _buildProduceEditableField(
      TextEditingController? controller, String label,
      {TextInputType keyboardType = TextInputType.text,
      bool isRequired = false,
      int maxLines = 1}) {
    if (controller == null)
      return const SizedBox.shrink(); // Should not happen if logic is correct

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''), // Indicate required fields
        isDense: true,
        // Use helper text for optional guidance instead of label for numbers?
        // helperText: keyboardType == TextInputType.text ? null : 'Enter number (optional)',
        contentPadding: const EdgeInsets.symmetric(
            vertical: 10.0, horizontal: 10.0), // Adjusted padding
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: dividerColor.withOpacity(0.7))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: dividerColor.withOpacity(0.7))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: const BorderSide(color: primaryTeal)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: const BorderSide(color: errorColor)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: const BorderSide(color: errorColor, width: 1.5)),
        labelStyle: TextStyle(fontSize: 12, color: subtleText.withOpacity(0.9)),
        floatingLabelStyle: const TextStyle(color: primaryTeal),
        // Error style
        errorStyle: const TextStyle(fontSize: 10, color: errorColor),
      ),
      style: const TextStyle(fontSize: 13, color: textOnWhite),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) {
          return '$label is required';
        }
        // Optional: Validate numeric fields if needed
        if (keyboardType != TextInputType.text &&
            value != null &&
            value.trim().isNotEmpty) {
          if (double.tryParse(value.trim()) == null) {
            return 'Invalid number';
          }
        }
        return null; // Return null if valid
      },
      autovalidateMode:
          AutovalidateMode.onUserInteraction, // Validate as user interacts
    );
  }

  // --- Build Nutrient Chip (Teal Background) ---
  Widget _buildNutrientChip(String label, String value, {bool isLong = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 4), // Adjusted padding
      decoration: BoxDecoration(
          color: faintLightTeal, // Faint light teal background
          borderRadius: BorderRadius.circular(12), // More rounded corners
          border: Border.all(
              color: lightTeal.withOpacity(0.6),
              width: 0.5) // Optional subtle border
          ),
      child: Text(
        isLong
            ? value
            : '$label: $value', // Show only value if 'isLong' (for source)
        style: TextStyle(
            fontSize: 10,
            color: darkTeal.withOpacity(0.9), // Darker teal text for contrast
            fontWeight: FontWeight.w500),
        maxLines: isLong ? 2 : 1, // Allow source to wrap slightly
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // Action Button Small (Used for Edit/Delete icons in Produce list)
  Widget _actionButtonSmall(
      IconData icon, String tooltip, VoidCallback onPressed,
      {bool isDestructive = false}) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      color: isDestructive
          ? destructiveButtonForeground
          : actionButtonForeground.withOpacity(0.8), // Standard action color
      splashRadius: 20, // Size of the ripple effect
      constraints: const BoxConstraints(), // Remove default large constraints
      padding: const EdgeInsets.all(6), // Smaller padding around icon
      visualDensity: VisualDensity.compact, // Make it visually compact
    );
  }

  // Helper for Empty State Views (Used in Orders and Produce)
  Widget _buildEmptyState(String title, String subtitle,
      {IconData icon = Icons.info_outline}) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Card(
          color: whiteColor.withOpacity(0.85), // Semi-transparent background
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0, // No shadow needed if centered
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 50, color: subtleText.withOpacity(0.8)),
                const SizedBox(height: 15),
                Text(
                  title,
                  style: const TextStyle(
                      color: textOnWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(color: subtleText, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ===== REUSABLE WIDGETS (Maintained & Adjusted) ==========================
  // ===========================================================================

  // --- Order Item Builder (Overflow Fix Attempted via Compact Chip) ---
  Widget _buildOrderItem(Order order) {
    final DateFormat dateFormat = DateFormat('MMM d, hh:mm a');
    final statusColor = _getStatusColor(order.orderStatus);

    return Card(
      margin: EdgeInsets.zero, // Let the parent Padding handle spacing
      elevation: 1.5,
      color: whiteColor.withOpacity(0.9), // Semi-transparent card background
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
          // Subtle border color based on status
          side: BorderSide(color: statusColor.withOpacity(0.4), width: 1)),
      child: ExpansionTile(
        // --- Header of the Collapsed Tile ---
        tilePadding: const EdgeInsets.fromLTRB(
            12.0, 8.0, 12.0, 8.0), // Padding inside the header
        childrenPadding:
            EdgeInsets.zero, // Padding for children is handled inside
        expandedAlignment: Alignment.topLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: subtleText, // Color of the dropdown arrow
        collapsedIconColor: subtleText,
        // Leading: Status Icon
        leading: Tooltip(
          message: order.orderStatus,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: statusColor
                .withOpacity(0.15), // Faint background based on status
            child: Icon(_getStatusIcon(order.orderStatus),
                color: statusColor, size: 18),
          ),
        ),
        // Title: Meal Name
        title: Text(
          order.mealName,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 15, color: textOnWhite),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Subtitle: Order ID & Date
        subtitle: Padding(
          padding: const EdgeInsets.only(
              top: 3.0), // Space between title and subtitle
          child: Text(
            '#${order.orderId} • ${dateFormat.format(order.orderDate.toLocal())}',
            style: const TextStyle(fontSize: 12, color: subtleText),
          ),
        ),
        // Trailing: Price & Status Chip
        // Using a Column to stack Price and Status Chip vertically.
        // MainAxisSize.min ensures the column takes only needed vertical space.
        // CrossAxisAlignment.end aligns the items to the right edge.
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              // Price
              // Format currency appropriately (consider using NumberFormat for localization)
              NumberFormat.currency(symbol: '\$', decimalDigits: 2)
                  .format(order.totalPrice),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: darkTeal, fontSize: 14),
            ),
            const SizedBox(height: 3), // Space between price and chip
            _buildStatusChip(order.orderStatus), // Compact status chip
          ],
        ),
        // --- Expanded Content ---
        children: [
          const Divider(
              height: 1, thickness: 0.7, color: dividerColor), // Separator
          Padding(
            padding: const EdgeInsets.fromLTRB(
                16.0, 12.0, 16.0, 12.0), // Padding for details
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Use helper for consistent detail rows
                _buildDetailRow(
                    Icons.person_outline, 'User ID:', order.userId.toString()),
                if (order.producerName !=
                    null) // Show producer name if available (might be redundant)
                  _buildDetailRow(Icons.storefront_outlined, 'Producer:',
                      order.producerName!),
                if (order.chefName != null) // Show chef if assigned
                  _buildDetailRow(
                      Icons.kitchen_outlined, 'Chef:', order.chefName!),
                _buildDetailRow(Icons.location_on_outlined, 'Delivery:',
                    order.deliveryAddress),
                _buildDetailRow(Icons.shopping_bag_outlined, 'Qty:',
                    order.quantity.toString()),
                _buildDetailRow(
                    Icons.receipt_outlined, 'Ingredients:', order.ingredients,
                    maxLines: 3), // Show ingredients
                _buildDetailRow(Icons.credit_card_outlined, 'Payment:',
                    '${order.paymentMode} (${order.paymentStatus})'),
                if (order.amountPaid != null &&
                    order.amountPaid! > 0) // Show amount paid if applicable
                  _buildDetailRow(
                      Icons.attach_money_outlined,
                      'Paid:',
                      NumberFormat.currency(symbol: '\$', decimalDigits: 2)
                          .format(order.amountPaid!)),
                if (order.transactionId !=
                    null) // Show transaction ID if available
                  _buildDetailRow(
                      Icons.vpn_key_outlined, 'Txn ID:', order.transactionId!),
                // Only show notes if they are meaningful
                if (order.notes.isNotEmpty &&
                    order.notes.toLowerCase() != 'no special instructions' &&
                    order.notes.toLowerCase() != 'no notes')
                  _buildDetailRow(Icons.notes_outlined, 'Notes:', order.notes,
                      maxLines: 4),
                const SizedBox(height: 12), // Space before action buttons
                _buildOrderActionButtons(
                    order), // Action buttons based on status
                const SizedBox(height: 4), // Padding at the bottom of expansion
              ],
            ),
          )
        ],
      ),
    );
  }

  // Detail Row for Order Expansion (Improved)
  Widget _buildDetailRow(IconData icon, String label, String value,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 4.5), // Slightly more vertical padding
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align icon/label with top of value
        children: [
          Icon(icon, size: 15, color: primaryTeal.withOpacity(0.9)),
          const SizedBox(width: 10),
          SizedBox(
            width: 80, // Consistent label width
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textOnWhite,
                    fontSize: 13)),
          ),
          Expanded(
              child: Text(
            value.isEmpty ? '-' : value, // Use '-' for empty values
            style: const TextStyle(color: subtleText, fontSize: 13),
            maxLines:
                maxLines, // Allow wrapping for longer values like address/notes
            overflow:
                TextOverflow.ellipsis, // Add ellipsis if it overflows maxLines
          )),
        ],
      ),
    );
  }

  // --- Status Helpers ---
  Widget _buildStatusChip(String status) {
    return Chip(
      label: Text(status),
      labelStyle: const TextStyle(
          fontSize: 9, // Small font
          color: whiteColor,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3),
      backgroundColor: _getStatusColor(status),
      // Minimal padding, compact density to prevent overflow
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none, // Remove default border if any
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6)), // Slightly rounded
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return pendingColor;
      case Order.STATUS_ACCEPTED:
        return acceptedColor;
      case Order.STATUS_PREPARING:
        return preparingColor;
      case Order.STATUS_DISPATCHED:
        return dispatchedColor;
      case Order.STATUS_DELIVERED:
        return deliveredColor;
      case Order.STATUS_CANCELLED:
        return cancelledColor;
      default:
        return defaultStatusColor; // Fallback color
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case Order.STATUS_PENDING:
        return Icons.hourglass_top_rounded;
      case Order.STATUS_ACCEPTED:
        return Icons.thumb_up_alt_outlined;
      case Order.STATUS_PREPARING:
        return Icons.soup_kitchen_outlined;
      case Order.STATUS_DISPATCHED:
        return Icons.local_shipping_outlined;
      case Order.STATUS_DELIVERED:
        return Icons.check_circle_outline_rounded;
      case Order.STATUS_CANCELLED:
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline; // Fallback icon
    }
  }

  // --- Order Action Buttons ---
  Widget _buildOrderActionButtons(Order order) {
    List<Widget> buttons = [];

    // Logic to determine which buttons to show based on order status
    switch (order.orderStatus) {
      case Order.STATUS_PENDING:
        buttons.add(_actionButton('Accept', Icons.check_circle_outline,
            () => _handleOrderAction(order, 'Accept')));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_actionButton('Cancel', Icons.cancel_outlined,
            () => _handleOrderAction(order, 'Cancel'),
            isDestructive: true));
        break;
      case Order.STATUS_ACCEPTED:
        buttons.add(_actionButton('Start Preparing', Icons.play_circle_outline,
            () => _handleOrderAction(order, 'Prepare')));
        buttons.add(const SizedBox(width: 8));
        buttons.add(_actionButton('Cancel', Icons.cancel_outlined,
            () => _handleOrderAction(order, 'Cancel'),
            isDestructive: true));
        break;
      case Order.STATUS_PREPARING:
        buttons.add(_actionButton('Dispatch', Icons.local_shipping_outlined,
            () => _handleOrderAction(order, 'Dispatch')));
        // Optionally allow cancelling while preparing?
        // buttons.add(const SizedBox(width: 8));
        // buttons.add(_actionButton('Cancel', Icons.cancel_outlined, () => _handleOrderAction(order, 'Cancel'), isDestructive: true));
        break;
      case Order.STATUS_DISPATCHED:
        // No actions usually needed once dispatched by producer
        buttons.add(const Text('Out for delivery',
            style: TextStyle(
                color: subtleText, fontStyle: FontStyle.italic, fontSize: 12)));
        // Potentially add a "Mark Delivered" if driver doesn't update? (Less common for producer dash)
        break;
      case Order.STATUS_DELIVERED:
        buttons.add(Text('Order completed',
            style: TextStyle(
                color: deliveredColor.withOpacity(0.9),
                fontStyle: FontStyle.italic,
                fontSize: 12)));
        break;
      case Order.STATUS_CANCELLED:
        buttons.add(Text('Order cancelled',
            style: TextStyle(
                color: cancelledColor.withOpacity(0.9),
                fontStyle: FontStyle.italic,
                fontSize: 12)));
        break;
      default:
        buttons.add(const Text('Unknown Status',
            style: TextStyle(color: subtleText, fontSize: 12)));
    }

    if (buttons.isEmpty)
      return const SizedBox.shrink(); // Return empty container if no buttons

    // Align buttons to the right using Wrap
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8.0, // Horizontal space between buttons
        runSpacing: 6.0, // Vertical space if buttons wrap
        alignment: WrapAlignment.end, // Align wrapped buttons to the end
        children: buttons,
      ),
    );
  }

  // Reusable Action Button Style (for Order Actions)
  Widget _actionButton(String label, IconData icon, VoidCallback onPressed,
      {bool isDestructive = false}) {
    final ButtonStyle style = ElevatedButton.styleFrom(
      backgroundColor: isDestructive
          ? destructiveButtonBackground
              .withOpacity(0.9) // Destructive button background
          : actionButtonBackground
              .withOpacity(0.9), // Standard action button background
      foregroundColor: isDestructive
          ? destructiveButtonForeground // Destructive text/icon color
          : actionButtonForeground, // Standard text/icon color
      elevation: 0, // Flat appearance
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8), // Button padding
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)), // Rounded corners
      visualDensity: VisualDensity.compact, // Make button slightly smaller
      minimumSize: const Size(0, 30), // Ensure minimum height
    );
    return ElevatedButton.icon(
      icon: Icon(icon, size: 14), // Icon size
      label: Text(label),
      style: style,
      onPressed: onPressed,
    );
  }
} // End of _ProducerDash22_mock_dataState class
