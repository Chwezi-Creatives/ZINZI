import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'user_cache.dart';
import 'cache_config.dart';
import 'dart:convert';
import 'nutrition+.dart'; // Ensure this file contains your NutritionItem model definition
import 'cart.dart' as cart;
import 'package:cached_network_image/cached_network_image.dart';
import 'producer_selector_bottom_sheet.dart';

const Color primaryColor = Color(0xFF0B5345); // Dark teal
const Color accentColor = Color(0xFF1A7968); // Medium teal
const Color backgroundColor = Color.fromARGB(255, 233, 222, 222); // Light grey background
const Color primaryTextColor = Color(0xFF333333); // Dark text
const Color secondaryTextColor = Color(0xFF666666); // Medium grey text
const Color priceColor = Color(0xFF0B5345); // Price in dark teal
const Color errorIconColor = Colors.redAccent;

class Nutri_DetailPage extends StatefulWidget {
  static final GlobalKey<_Nutri_DetailPageState> globalKey = GlobalKey<_Nutri_DetailPageState>();
  final NutritionItem item;
  final Widget? decodedImage;

  Nutri_DetailPage({required this.item, this.decodedImage}) : super(key: globalKey);

  static Future<void> manualRefreshFromAppBar() async {
    final state = globalKey.currentState;
    if (state != null) {
      await state.manualRefreshFromAppBar();
    }
  }

  @override
  _Nutri_DetailPageState createState() => _Nutri_DetailPageState();
}

class _Nutri_DetailPageState extends State<Nutri_DetailPage>
    with SingleTickerProviderStateMixin {
  // Add manualRefreshFromAppBar to match dashboard refresh pattern
  Future<void> manualRefreshFromAppBar() async {
    await _refreshProducersWithAnimation();
  }
  late AnimationController _refreshIconController;
  Map<String, dynamic>? selectedProducer;
  bool isFavorite = false;
  bool isInCart = false;

  List<Map<String, dynamic>>? _cachedProducers;
  bool _isLoadingProducers = false;
  bool _isCacheValid = false;

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    // Use prefix for classes from cart.dart
    isFavorite = cart.Favorites.isFavorite(widget.item.name);
    isInCart = cart.ShoppingCart.getItems()
        .any((item) => item['title'] == widget.item.name);
    
    // Check cache validity in background without blocking UI
    _checkCacheAndPreloadIfNeeded();
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    super.dispose();
  }

  // Check if cache exists and is valid, preload if needed
  Future<void> _checkCacheAndPreloadIfNeeded() async {
    final String cacheKey =
        'producers_for_item_${widget.item.productIdKey}_${widget.item.productIdValue}';
    final String cacheTsKey =
        'producers_for_item_ts_${widget.item.productIdKey}_${widget.item.productIdValue}';
    
    try {
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();
      
      if (cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) <
                CacheConfig.chefProducerDetailCacheDuration) {
          // Cache is valid, load it
          _cachedProducers = List<Map<String, dynamic>>.from(cachedData);
          if (mounted) {
            setState(() {
              _isCacheValid = true;
            });
          }
          print('[NutriDetail] Loaded producers from valid cache');
          return;
        }
      }
      
      // Cache is invalid or doesn't exist, preload in background
      if (mounted) {
        setState(() {
          _isLoadingProducers = true;
        });
      }
      
      _cachedProducers = await _fetchProducersForItem();
      
      if (mounted) {
        setState(() {
          _isLoadingProducers = false;
          _isCacheValid = true;
        });
      }
      print('[NutriDetail] Preloaded producers (cache was invalid or missing)');
    } catch (e) {
      print('[NutriDetail] Error checking cache: $e');
      if (mounted) {
        setState(() {
          _isLoadingProducers = false;
        });
      }
    }
  }

  Future<void> _showProducerSelector() async {
    // If we're already loading or cache check is in progress, show loading indicator
    if (_isLoadingProducers) {
      // Show loading dialog if still fetching data
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading producers...'),
                ],
              ),
            ),
          ),
        ),
      );
      
      // Wait for loading to complete
      while (_isLoadingProducers) {
        await Future.delayed(Duration(milliseconds: 100));
        if (!mounted) return;
      }
      
      // Close loading dialog
      Navigator.of(context).pop();
    }
    
    // If cache is not valid and we're not already loading, fetch now
    if (!_isCacheValid && !_isLoadingProducers) {
      setState(() {
        _isLoadingProducers = true;
      });
      
      _cachedProducers = await _fetchProducersForItem();
      
      if (mounted) {
        setState(() {
          _isLoadingProducers = false;
          _isCacheValid = true;
        });
      }
    }
    
    if (!mounted) return;
    
    // Show bottom sheet with producers
    await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5, // Half screen height
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        if (_cachedProducers == null || _cachedProducers!.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('No producers available'),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _refreshProducersWithAnimation();
                  },
                  child: Text('Refresh'),
                ),
              ],
            ),
          );
        }
        return ProducerSelectorBottomSheet(
          producers: _cachedProducers!,
          onSelected: (producer) {
            setState(() {
              selectedProducer = producer;
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Producer selected: ${producer['name'] ?? ''}')),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchProducersForItem(
      {bool forceRefresh = false}) async {
    final String cacheKey =
        'producers_for_item_${widget.item.productIdKey}_${widget.item.productIdValue}';
    final String cacheTsKey =
        'producers_for_item_ts_${widget.item.productIdKey}_${widget.item.productIdValue}';
    try {
      // Check cache first unless forced refresh
      if (!forceRefresh) {
        final cachedData = await UserCache.getData(cacheKey);
        final cachedTs = await UserCache.getData(cacheTsKey);
        final now = DateTime.now();
        if (cachedData != null && cachedTs != null) {
          final cacheTime = DateTime.tryParse(cachedTs.toString());
          if (cacheTime != null &&
              now.difference(cacheTime) <
                  CacheConfig.chefProducerDetailCacheDuration) {
            print(
                '[NutriDetail] Loaded producers from cache for ${widget.item.productIdKey}:${widget.item.productIdValue}');
            return List<Map<String, dynamic>>.from(cachedData);
          }
        }
      }
      
      // Fetch from API if not in cache or cache expired
      final String baseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
      final response = await http.get(Uri.parse('$baseUrl/rr/rproducers'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<Map<String, dynamic>> producersList;
        if (data is List) {
          producersList = List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data['data'] is List) {
          producersList = List<Map<String, dynamic>>.from(data['data']);
        } else {
          producersList = [];
        }
        await UserCache.saveData(cacheKey, producersList);
        await UserCache.saveData(cacheTsKey, DateTime.now().toIso8601String());
        return producersList;
      }
    } catch (e) {
      print('[NutriDetail] Error fetching producers: $e');
    }
    return [];
  }

  void _addToCartWithProducer(Map<String, dynamic> producer) {
    cart.ShoppingCart.addItem(
      widget.item.name,
      widget.item.price ?? 0.0,
      quantity: 1,
      selectedproducer: producer,
      meal: {
        'name': widget.item.name,
        'image_link': widget.item.imagePath,
        'description': widget.item.description,
        'price': widget.item.price,
        'order_type': widget.item.orderType, // e.g., 'spice', 'gadget', etc.
        widget.item.productIdKey:
            widget.item.productIdValue, // e.g., 'spice_id': '12'
      },
      bestservedwith: [], // No complementary section for these items
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: BackButton(color: Colors.white),
        title: Text(
          widget.item.name,
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: AnimatedBuilder(
              animation: _refreshIconController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _refreshIconController.value * 6.28,
                  child: Icon(
                    Icons.refresh,
                    color: _isLoadingProducers ? Colors.grey : Colors.white,
                  ),
                );
              },
            ),
            onPressed: _isLoadingProducers ? null : _refreshProducersWithAnimation,
          ),
          IconButton(
            icon: Icon(
              Icons.favorite_border,
              color: Colors.white,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              Icons.shopping_cart,
              color: Colors.white,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => cart.ShoppingCartScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image only with no overlay text
            _buildHeroImage(),
            
            // Title and description section moved below image
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and description on the left
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.item.description ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action buttons on the right
                  Row(
                    children: [
                      _buildFavoriteButton(),
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          isInCart ? Icons.shopping_cart : Icons.add_shopping_cart,
                          color: primaryColor,
                          size: 26,
                        ),
                        onPressed: () {
                          if (isInCart) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${widget.item.name} is already in your cart!')),
                            );
                            return;
                          }
                          _showProducerSelector();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Price section
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Price: ugx ${widget.item.price != null ? widget.item.price!.toStringAsFixed(0) : '0'}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: priceColor,
                ),
              ),
            ),
            
            Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
            
            // Producer selection section
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Producer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                  SizedBox(height: 8),
                  _buildSelectedProducerCard(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildProceedToCartButton(),
    );
  }

  Widget _buildHeroImage() {
    return Container(
      height: 240,
      width: double.infinity,
      child: widget.decodedImage != null
          ? widget.decodedImage!
          : (widget.item.imagePath?.startsWith('http') ?? false)
              ? CachedNetworkImage(
                  imageUrl: widget.item.imagePath ?? '',
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) {
                    return Image.asset(
                      'assets/images/DrugRG.png',
                      fit: BoxFit.cover,
                    );
                  },
                )
              : Image.asset(
                  widget.item.imagePath ?? 'assets/images/DrugRG.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const Center(
                    child: Icon(Icons.error_outline, color: errorIconColor, size: 60),
                  ),
                ),
    );
  }

  Widget _buildFavoriteButton() {
    return IconButton(
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: Colors.red,
        size: 26,
      ),
      onPressed: () {
        setState(() {
          if (isFavorite) {
            cart.Favorites.removeItem(widget.item.name);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${widget.item.name} removed from favorites!'),
            ));
          } else {
            cart.Favorites.addItem(widget.item.name ?? '',
                widget.item.price ?? 0.0, widget.item.imagePath ?? '');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${widget.item.name} added to favorites!'),
            ));
          }
          isFavorite = !isFavorite;
        });
      },
    );
  }

  Widget _buildSelectedProducerCard() {
    if (selectedProducer != null) {
      return Container(
        margin: EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            child: Icon(Icons.person, color: Colors.green),
          ),
          title: Text(
            selectedProducer!['name'] ?? 'Producer Name',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              Icon(Icons.location_on, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  selectedProducer!['location'] ?? 'Unknown Location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: TextButton(
            onPressed: _showProducerSelector,
            child: Text(
              'Change',
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    } else {
      return Container(
        margin: EdgeInsets.only(top: 8),
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 40, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No Producer Selected',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _showProducerSelector,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Select Producer'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildProceedToCartButton() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            offset: Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      child: ElevatedButton.icon(
        icon: Icon(Icons.shopping_cart),
        label: Text(
          'Proceed to Cart',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        onPressed: selectedProducer != null
            ? () {
                if (!isInCart) {
                  _addToCartWithProducer(selectedProducer!);
                  setState(() {
                    isInCart = true;
                  });
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => cart.ShoppingCartScreen()),
                );
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          disabledBackgroundColor: Colors.grey.shade400,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // Method for refreshing producers with animation
  Future<void> _refreshProducersWithAnimation() async {
    setState(() {
      _isLoadingProducers = true;
      _isCacheValid = false;
    });
    _refreshIconController.repeat();
    
    _cachedProducers = await _fetchProducersForItem(forceRefresh: true);
    
    if (mounted) {
      setState(() {
        _isLoadingProducers = false;
        _isCacheValid = true;
      });
      _refreshIconController.stop();
      _refreshIconController.reset();
      
      // Show confirmation to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Producer list refreshed'))
      );
    }
  }
}