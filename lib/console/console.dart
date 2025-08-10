// lib/console.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Assuming these are your actual import paths
import 'package:zinzi/console/console_api_service.dart' as console_api; 
import 'console_data_models.dart';   // Restored for clarity
import 'console_plans.dart';         // Plan management tab
import 'console_subscriptions.dart';  // Subscription management tab
import 'package:zinzi/services/api_service.dart' as zinzi_api; // Renamed to avoid conflict
import 'package:zinzi/services/shared_prefs_storage.dart';
import 'package:zinzi/features/subscription/services/plan_service.dart';
import 'package:zinzi/features/subscription/subscription_service.dart';


// --- Color Constants ---
const kTealColor = Colors.teal;
const kLightTealColor = Color(0xFFB2DFDB);
const kWhiteColor = Colors.white;
const kBackgroundColor = Color(0xFFF5F5F5);
const kDarkTextColor = Color(0xFF333333);
const kSubtleTextColor = Colors.grey;

// Added 'plans' and 'subscriptions' to the enum
enum Category { plans, subscriptions, meals, spices, herbals, gadgets, supplements }

class AdminConsolePage extends StatefulWidget {
  const AdminConsolePage({super.key});

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  // Use the specific console API service for products
  final console_api.ApiService _productApiService = console_api.ApiService(); 
  late final PlanService _planService;
  late final SubscriptionService _subscriptionService;

  Category _selectedCategory = Category.plans;
  List<Product> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  late Future<void> _initServicesFuture;

  @override
  void initState() {
    super.initState();
    _initServicesFuture = _initializeServices();
  }

  // Handles async initialization of services required for the console
  Future<void> _initializeServices() async {
    final prefs = await SharedPreferences.getInstance();
    final storageService = SharedPrefsStorage(prefs);
    // Initialize API services
    final apiService = zinzi_api.ApiService(); 
    _planService = PlanService(apiService: apiService, storageService: storageService);
    _subscriptionService = SubscriptionService();
    // Fetch initial data for the default category
    await _fetchData();
  }

  Future<void> _fetchData() async {
    // If plans or subscriptions tab is selected, do nothing as they handle their own state
    if (_selectedCategory == Category.plans || _selectedCategory == Category.subscriptions) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Logic restored from the original working file
      switch (_selectedCategory) {
        case Category.meals:
          _items = await _productApiService.fetchItems('meals', Meal.fromJson);
          break;
        case Category.spices:
          _items = await _productApiService.fetchItems('spices', Spice.fromJson);
          break;
        case Category.herbals:
          // Corrected endpoint from 'rherbals' to 'herbals'
          _items = await _productApiService.fetchItems('herbals', Herbal.fromJson);
          break;
        case Category.gadgets:
          _items = await _productApiService.fetchItems('gadgets', Gadget.fromJson);
          break;
        case Category.supplements:
          _items = await _productApiService.fetchItems('supplements', Supplement.fromJson);
          break;
        case Category.plans:
        case Category.subscriptions:
          // These cases are handled by the initial check, but here for completeness
          _items = []; 
          break;
      }
    } catch (e) {
      _errorMessage = 'Failed to load data. Please try again.';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onCategorySelected(Category category) {
    if (_selectedCategory != category) {
      setState(() {
        _selectedCategory = category;
        _items = []; // Clear old items for better UX
        _isLoading = true; // Show loading indicator immediately
        _errorMessage = null;
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        backgroundColor: kTealColor,
        foregroundColor: kWhiteColor,
      ),
      body: FutureBuilder<void>(
        future: _initServicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            return Column(
              children: [
                _buildCategorySelector(),
                // Only show batch update for product categories (not for subscriptions or plans)
                if (_selectedCategory != Category.subscriptions && _selectedCategory != Category.plans) _buildBatchUpdateCard(),
                const Divider(height: 1),
                Expanded(child: _buildContent()),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      color: kWhiteColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: Category.values
              .map((cat) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(
                          cat.name[0].toUpperCase() + cat.name.substring(1)),
                      selected: _selectedCategory == cat,
                      onSelected: (_) => _onCategorySelected(cat),
                      selectedColor: kTealColor,
                      labelStyle: TextStyle(
                        color: _selectedCategory == cat
                            ? kWhiteColor
                            : kDarkTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.grey.shade200,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: _selectedCategory == cat
                              ? kTealColor
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildBatchUpdateCard() {
    final percentageController = TextEditingController();

    return Card(
      margin: const EdgeInsets.all(12.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Batch Update All ${_selectedCategory.name.toUpperCase()}',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: kDarkTextColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: percentageController,
                    decoration: InputDecoration(
                      labelText: 'Percentage %',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      _buildBatchButton('Increase', Icons.arrow_upward,
                          Colors.green, percentageController, true),
                      const SizedBox(width: 8),
                      _buildBatchButton('Decrease', Icons.arrow_downward,
                          Colors.blue, percentageController, false),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchButton(String label, IconData icon, Color color,
      TextEditingController controller, bool isIncrease) {
    return Expanded(
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 16, color: kWhiteColor),
        label: Text(label, style: const TextStyle(color: kWhiteColor)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _handleBatchUpdate(controller.text, isIncrease),
      ),
    );
  }

  Widget _buildContent() {
    // If 'plans' is selected, show the dedicated widget
    if (_selectedCategory == Category.plans) {
      return ConsolePlansTab(planService: _planService);
    }
    // If 'subscriptions' is selected, show the dedicated widget
    if (_selectedCategory == Category.subscriptions) {
      return ConsoleSubscriptionsTab(subscriptionService: _subscriptionService);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kTealColor));
    }
    if (_errorMessage != null) {
      return Center(
          child:
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }
    if (_items.isEmpty) {
      return Center(
          child: Text('No items found for ${_selectedCategory.name}.',
              style: const TextStyle(color: kSubtleTextColor, fontSize: 16)));
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      color: kTealColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          // Use the restored item card builder
          return _buildItemCard(item); 
        },
      ),
    );
  }

  // Restored from original working file
  Widget _buildItemCard(Product item) {
    String imageUrl = '';
    // This logic is crucial and was missing in the broken version
    if (item is Meal) imageUrl = item.imageUrl;
    if (item is Spice) imageUrl = item.imageUrl ?? '';
    if (item is Herbal) imageUrl = item.imageUrl ?? '';
    if (item is Gadget) imageUrl = item.imageUrl ?? '';
    if (item is Supplement) imageUrl = item.imageUrl ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: kLightTealColor,
          child: imageUrl.isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(kTealColor),
                    ),
                    errorWidget: (context, url, error) =>
                        _buildFallbackAvatar(item.name),
                  ),
                )
              : _buildFallbackAvatar(item.name),
        ),
        title: Text(item.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: kDarkTextColor)),
        subtitle: Text(
            'Current Price: ${item.price?.toStringAsFixed(0) ?? 'Not Set'}',
            style: const TextStyle(color: kSubtleTextColor)),
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: kTealColor),
          onPressed: () => _showUpdateDialog(item),
        ),
      ),
    );
  }

  // Restored from original working file
  Widget _buildFallbackAvatar(String name) {
    if (name.isNotEmpty) {
      return Text(
        name[0].toUpperCase(),
        style:
            const TextStyle(color: kDarkTextColor, fontWeight: FontWeight.bold),
      );
    }
    // Assuming you have this placeholder in your assets
    return Image.asset(
      'images/mealimageplaceholder.png',
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.fastfood, color: kDarkTextColor),
    );
  }

  // --- LOGIC FOR UPDATES (Restored from original) ---

  void _showUpdateDialog(Product item) {
    final priceController = TextEditingController();
    final percentageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Price for ${item.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'New Price',
                  hintText: item.price?.toString() ?? '0.0',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kTealColor),
                child: const Text('Set New Price',
                    style: TextStyle(color: kWhiteColor)),
                onPressed: () {
                  _handleSingleUpdate(item, priceController.text, null, null);
                  Navigator.of(context).pop();
                },
              ),
              const Divider(height: 30),
              TextField(
                controller: percentageController,
                decoration: const InputDecoration(
                  labelText: 'Update by Percentage %',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Increase',
                        style: TextStyle(color: kWhiteColor)),
                    onPressed: () {
                      _handleSingleUpdate(
                          item, null, percentageController.text, true);
                      Navigator.of(context).pop();
                    },
                  ),
                  ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text('Decrease',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      _handleSingleUpdate(
                          item, null, percentageController.text, false);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: kTealColor)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSingleUpdate(Product item, String? newPriceStr,
      String? percentageStr, bool? isIncrease) async {
    double? newPrice;
    final currentPrice = item.price ?? 0.0;

    if (newPriceStr != null && newPriceStr.isNotEmpty) {
      newPrice = double.tryParse(newPriceStr);
    } else if (percentageStr != null &&
        percentageStr.isNotEmpty &&
        isIncrease != null) {
      final percentage = double.tryParse(percentageStr);
      if (percentage != null) {
        final factor = percentage / 100.0;
        newPrice = isIncrease
            ? currentPrice * (1 + factor)
            : currentPrice * (1 - factor);
      }
    }

    if (newPrice != null) {
      await _updateAndRefresh(item.id, newPrice);
    } else {
      _showErrorSnackBar('Invalid input.');
    }
  }

  // This is the fully-featured, working batch update handler from the original
  Future<void> _handleBatchUpdate(String percentageStr, bool isIncrease) async {
     if (percentageStr.isEmpty) {
      _showErrorSnackBar('Please enter a percentage value');
      return;
    }

    final percentage = double.tryParse(percentageStr);
    if (percentage == null || percentage <= 0) {
      _showErrorSnackBar('Please enter a valid positive percentage');
      return;
    }

    if (_items.isEmpty) {
      _showErrorSnackBar('No items to update');
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Batch Update'),
        content: Text(
            'Are you sure you want to ${isIncrease ? 'increase' : 'decrease'} all ${_selectedCategory.name} prices by $percentage%?\n\nThis will update ${_items.length} items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kTealColor),
            child: const Text('Confirm', style: TextStyle(color: kWhiteColor)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(SnackBar(
      content: Row(children: const [
        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kWhiteColor)),
        SizedBox(width: 16),
        Text('Updating prices...'),
      ]),
      duration: Duration(minutes: 5), // Long duration
    ));

    try {
      final updates = _items.map((item) {
        final currentPrice = item.price ?? 0.0;
        double newPrice = isIncrease
            ? currentPrice * (1 + (percentage / 100))
            : currentPrice * (1 - (percentage / 100));
        newPrice = newPrice < 0 ? 0 : newPrice;
        return {'id': item.id, 'price': double.parse(newPrice.toStringAsFixed(0))};
      }).toList();

      final categoryName = _selectedCategory.name;

      final result = await _productApiService.batchUpdatePrices(
        category: categoryName,
        updates: updates,
      );

      scaffoldMessenger.hideCurrentSnackBar();

      if (result.success) {
        String message = '✅ Successfully updated ${result.successCount} items';
        if (result.failureCount > 0) {
          message += '\n❌ ${result.failureCount} items failed to update.';
          // Optionally show detailed errors in a dialog as in the original
        }
        _showSuccessSnackBar(message);
        await _fetchData();
      } else {
        _showErrorSnackBar(result.message ?? 'Batch update failed.');
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      _showErrorSnackBar('An error occurred: $e');
    }
  }

  Future<void> _updateAndRefresh(dynamic id, double newPrice) async {
    setState(() => _isLoading = true);
    final success = await _productApiService.updatePrice(_selectedCategory.name, id, newPrice);
    if (success) {
      await _fetchData(); // Refresh the list
    } else {
      _showErrorSnackBar('Update failed. Please try again.');
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}