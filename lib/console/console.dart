// lib/console.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'console_api_service.dart';
import 'console_data_models.dart';
import 'package:flutter/foundation.dart';

// --- Color Constants ---
const kTealColor = Colors.teal;
const kLightTealColor = Color(0xFFB2DFDB);
const kWhiteColor = Colors.white;
const kBackgroundColor = Color(0xFFF5F5F5);
const kDarkTextColor = Color(0xFF333333);
const kSubtleTextColor = Colors.grey;

enum Category { meals, spices, herbals, gadgets, supplements }

class AdminConsolePage extends StatefulWidget {
  const AdminConsolePage({super.key});

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  final ApiService _apiService = ApiService();
  Category _selectedCategory = Category.meals;
  List<Product> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      switch (_selectedCategory) {
        case Category.meals:
          _items = await _apiService.fetchItems('meals', Meal.fromJson);
          break;
        case Category.spices:
          _items = await _apiService.fetchItems('spices', Spice.fromJson);
          break;
        case Category.herbals:
           _items = await _apiService.fetchItems('rherbals', Herbal.fromJson);
          break;
        case Category.gadgets:
           _items = await _apiService.fetchItems('gadgets', Gadget.fromJson);
          break;
        case Category.supplements:
           _items = await _apiService.fetchItems('supplements', Supplement.fromJson);
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
        _items = []; // Clear old items immediately for better UX
      });
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Admin Price Console', style: TextStyle(color: kWhiteColor, fontWeight: FontWeight.bold)),
        backgroundColor: kTealColor,
        elevation: 2,
        iconTheme: const IconThemeData(color: kWhiteColor),
      ),
      body: Column(
        children: [
          _buildCategorySelector(),
          _buildBatchUpdateCard(),
          Expanded(child: _buildContent()),
        ],
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
                      label: Text(cat.name[0].toUpperCase() + cat.name.substring(1)),
                      selected: _selectedCategory == cat,
                      onSelected: (_) => _onCategorySelected(cat),
                      selectedColor: kTealColor,
                      labelStyle: TextStyle(
                        color: _selectedCategory == cat ? kWhiteColor : kDarkTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.grey.shade200,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: _selectedCategory == cat ? kTealColor : Colors.grey.shade300,
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kDarkTextColor),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      _buildBatchButton(
                          'Increase', Icons.arrow_upward, Colors.green, percentageController, true),
                      const SizedBox(width: 8),
                      _buildBatchButton(
                          'Decrease', Icons.arrow_downward, Colors.blue, percentageController, false),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kTealColor));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
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
          return _buildItemCard(item);
        },
      ),
    );
  }

  Widget _buildItemCard(Product item) {
    String imageUrl = '';
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
                    placeholder: (context, url) => const CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(kTealColor),
                    ),
                    errorWidget: (context, url, error) => _buildFallbackAvatar(item.name),
                  ),
                )
              : _buildFallbackAvatar(item.name),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, color: kDarkTextColor)),
        subtitle: Text('Current Price: ${item.price?.toStringAsFixed(0) ?? 'Not Set'}',
            style: const TextStyle(color: kSubtleTextColor)),
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: kTealColor),
          onPressed: () => _showUpdateDialog(item),
        ),
      ),
    );
  }

  // Build fallback avatar with first letter or placeholder image
  Widget _buildFallbackAvatar(String name) {
    if (name.isNotEmpty) {
      return Text(
        name[0].toUpperCase(),
        style: const TextStyle(color: kDarkTextColor, fontWeight: FontWeight.bold),
      );
    }
    return Image.asset(
      'images/mealimageplaceholder.png',
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.fastfood, color: kDarkTextColor),
    );
  }

  // --- LOGIC FOR UPDATES ---

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
              // Granular update
              TextField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'New Price',
                  hintText: item.price?.toString() ?? '0.0',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kTealColor),
                child: const Text('Set New Price', style: TextStyle(color: kWhiteColor)),
                onPressed: () {
                  _handleSingleUpdate(item, priceController.text, null, null);
                  Navigator.of(context).pop();
                },
              ),
              const Divider(height: 30),
              // Percentage update
              TextField(
                controller: percentageController,
                decoration: const InputDecoration(
                  labelText: 'Update by Percentage %',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Increase', style: TextStyle(color: kWhiteColor)),
                    onPressed: () {
                      _handleSingleUpdate(item, null, percentageController.text, true);
                      Navigator.of(context).pop();
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text('Decrease', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      _handleSingleUpdate(item, null, percentageController.text, false);
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

  Future<void> _handleSingleUpdate(Product item, String? newPriceStr, String? percentageStr, bool? isIncrease) async {
    double? newPrice;
    final currentPrice = item.price ?? 0.0;
    
    if (newPriceStr != null && newPriceStr.isNotEmpty) {
      newPrice = double.tryParse(newPriceStr);
    } else if (percentageStr != null && percentageStr.isNotEmpty && isIncrease != null) {
      final percentage = double.tryParse(percentageStr);
      if (percentage != null) {
        final factor = percentage / 100.0;
        newPrice = isIncrease ? currentPrice * (1 + factor) : currentPrice * (1 - factor);
      }
    }

    if (newPrice != null) {
      await _updateAndRefresh(item.id, newPrice);
    } else {
      _showErrorSnackBar('Invalid input.');
    }
  }

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
    
    // Show a confirmation dialog
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

    if (shouldProceed != true) {
      return;
    }

    // Show loading indicator with countdown
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    int remainingItems = _items.length;
    
    // Create a controller to manage the snackbar content
    final snackbarController = StreamController<int>.broadcast();
    
    // Show initial snackbar
    final snackbar = SnackBar(
      content: StreamBuilder<int>(
        stream: snackbarController.stream,
        initialData: remainingItems,
        builder: (context, snapshot) {
          final currentCount = snapshot.data ?? remainingItems;
          final total = _items.length;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: null,
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12.0),
              Flexible(
                child: Text(
                  'Updating $currentCount/$total items...',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          );
        },
      ),
      duration: const Duration(minutes: 1), // Long duration to prevent auto-dismissal
    );
    
    scaffoldMessenger.showSnackBar(snackbar);
    
    // Start countdown timer
    final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingItems > 0) {
        remainingItems--;
        snackbarController.add(remainingItems);
      } else {
        timer.cancel();
      }
    });

    try {
      // Prepare updates
      final updates = _items.map((item) {
        final currentPrice = item.price ?? 0.0;
        double newPrice;
        
        if (isIncrease) {
          newPrice = currentPrice * (1 + (percentage / 100));
        } else {
          newPrice = currentPrice * (1 - (percentage / 100));
          // Ensure price doesn't go below 0
          newPrice = newPrice < 0 ? 0 : newPrice;
        }
        
        // Round to 0 decimal places for whole number prices
        newPrice = double.parse(newPrice.toStringAsFixed(0));
        
        return {
          'id': item.id,
          'price': newPrice,
        };
      }).toList();

      // Get the category name that matches our API endpoint
      String getCategoryName() {
        switch (_selectedCategory) {
          case Category.meals:
            return 'meals';
          case Category.spices:
            return 'spices';
          case Category.herbals:
            return 'herbals'; // Note: This should match your backend endpoint
          case Category.gadgets:
            return 'gadgets';
          case Category.supplements:
            return 'supplements';
        }
      }

      // Call the batch update API
      final result = await _apiService.batchUpdatePrices(
        category: getCategoryName(),
        updates: updates,
      );

      // Cancel the timer and close the controller
      timer.cancel();
      await snackbarController.close();
      
      // Remove loading indicator
      scaffoldMessenger.hideCurrentSnackBar();

      if (result.success) {
        // Handle successful batch update (even if some items failed)
        String message = '✅ Successfully updated ${result.successCount} items';
        bool hasErrors = result.failureCount > 0;
        
        if (hasErrors) {
          message += '\n❌ ${result.failureCount} items failed to update';
        }
        
        // Show detailed errors if any
        if (result.errors != null && result.errors!.isNotEmpty) {
          final errorMessages = result.errors!.take(3).map((e) => '• ID ${e.id}: ${e.error}').join('\n');
          final more = result.errors!.length > 3 ? '\n...and ${result.errors!.length - 3} more errors' : '';
          
          // Show detailed errors in a scrollable dialog
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Update Results'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✅ ${result.successCount} items updated successfully'),
                    if (hasErrors) ...[
                      const SizedBox(height: 16),
                      const Text('❌ The following items had issues:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(errorMessages + more),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // Show simple success message if no errors
          if (!mounted) return;
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Always refresh the data to show current state
        if (mounted) {
          await _fetchData();
        }
      } else {
        // Show detailed error message if the entire batch failed
        String errorMessage = result.message ?? 'Failed to update prices';
        if (result.errors != null && result.errors!.isNotEmpty) {
          errorMessage += '\n\nFirst error: ${result.errors!.first.error}';
        }
        
        if (mounted) {
          _showErrorSnackBar(errorMessage);
        }
      }
    } catch (e, stackTrace) {
      // Log the full error for debugging
      debugPrint('Batch update error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Cancel the timer and close the controller in case of error
      timer.cancel();
      await snackbarController.close();
      
      // Remove loading indicator
      scaffoldMessenger.hideCurrentSnackBar();
      _showErrorSnackBar('Error during batch update: $e');
      if (mounted) {
        _showErrorSnackBar(
          'An error occurred while updating prices. Please try again. ' 
          'If the problem persists, contact support.'
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _updateAndRefresh(dynamic id, double newPrice) async {
    setState(() => _isLoading = true);
    final success = await _apiService.updatePrice(_selectedCategory.name, id, newPrice);
    if (success) {
      await _fetchData(); // Refresh the list
    } else {
       _showErrorSnackBar('Update failed. Please try again.');
       setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
     if(mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
     }
  }
}