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

class Nutri_DetailPage extends StatefulWidget {
  final NutritionItem item;
  final Widget? decodedImage; // Widget holding the already-decoded image

  Nutri_DetailPage({required this.item, this.decodedImage});

  @override
  _Nutri_DetailPageState createState() => _Nutri_DetailPageState();
}

class _Nutri_DetailPageState extends State<Nutri_DetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _refreshIconController;
  Map<String, dynamic>? selectedProducer;
  bool isFavorite = false;
  bool isInCart = false;

  List<Map<String, dynamic>>? _cachedProducers;
  bool _isLoadingProducers = false;

  Future<void> _showProducerSelector() async {
    if (_cachedProducers == null && !_isLoadingProducers) {
      setState(() {
        _isLoadingProducers = true;
      });
      _cachedProducers = await _fetchProducersForItem();
      setState(() {
        _isLoadingProducers = false;
      });
    }
    if (!mounted) return;
    await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        if (_cachedProducers == null) {
          return Center(child: CircularProgressIndicator());
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
      final cachedData = await UserCache.getData(cacheKey);
      final cachedTs = await UserCache.getData(cacheTsKey);
      final now = DateTime.now();
      if (!forceRefresh && cachedData != null && cachedTs != null) {
        final cacheTime = DateTime.tryParse(cachedTs.toString());
        if (cacheTime != null &&
            now.difference(cacheTime) <
                CacheConfig.chefProducerDetailCacheDuration) {
          print(
              '[NutriDetail] Loaded producers from cache for ${widget.item.productIdKey}:${widget.item.productIdValue}');
          return List<Map<String, dynamic>>.from(cachedData);
        }
      }
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
        await UserCache.saveData(cacheTsKey, now.toIso8601String());
        return producersList;
      }
    } catch (e) {
      // ignore, handled in builder
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
  }

  @override
  void dispose() {
    _refreshIconController.dispose();
    super.dispose();
  }

  // ignore: unused_element
  Future<void> _refreshProducersWithAnimation() async {
    _refreshIconController.repeat();
    setState(() {
      _isLoadingProducers = true;
    });
    _cachedProducers = await _fetchProducersForItem(forceRefresh: true);
    setState(() {
      _isLoadingProducers = false;
    });
    _refreshIconController.stop();
    _refreshIconController.reset();
  }

  @override
  Widget build(BuildContext context) {
    // Use as a bottom sheet: see instructions below.
    return DraggableScrollableSheet(
      initialChildSize: 1.0, // Fill the parent (which should be half screen)
      minChildSize: 1.0,
      maxChildSize: 1.0,
      expand: true,
      builder: (context, scrollController) {
        Widget imageWidget;
        if (widget.decodedImage != null) {
          imageWidget = widget.decodedImage!;
        } else if (widget.item.imagePath != null &&
            widget.item.imagePath!.startsWith('http')) {
          imageWidget = CachedNetworkImage(
            imageUrl: widget.item.imagePath!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
            placeholder: (context, url) =>
                Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) =>
                Icon(Icons.broken_image_outlined, size: 80, color: Colors.grey),
          );
        } else if (widget.item.imagePath != null &&
            widget.item.imagePath!.isNotEmpty) {
          imageWidget = Image.asset(
            widget.item.imagePath!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
          );
        } else {
          imageWidget = Container(
            color: Colors.grey[200],
            width: double.infinity,
            height: 180,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.grey, size: 80),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 80), // add bottom padding for button
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // You may want to add a drag handle here
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  imageWidget,
                  Hero(
                    tag: widget.item.heroTag,
                    child: Container(
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3), // TODO: If you want to avoid deprecation, use .withAlpha(77) or .withValues().
                            spreadRadius: 2,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: widget.decodedImage != null
                            ? widget.decodedImage!
                            : (widget.item.imagePath?.startsWith('http') ??
                                    false)
                                ? CachedNetworkImage(
                                    imageUrl: widget.item.imagePath ?? '',
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Center(
                                        child: CircularProgressIndicator()),
                                    errorWidget: (context, url, error) {
                                      print(
                                          "Error loading network image: $url, $error");
                                      return Image.asset(
                                        'assets/images/DrugRG.png',
                                        fit: BoxFit.cover,
                                      );
                                    },
                                  )
                                : Image.asset(
                                    widget.item.imagePath ?? 'assets/images/DrugRG.png',

                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, st) =>
                                        const Center(
                                            child: Icon(Icons.error_outline,
                                                color: errorIconColor,
                                                size: 60)),
                                  ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.name,
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor),
                            ),
                            Text(
                              'ugx ${widget.item.price != null ? widget.item.price!.toStringAsFixed(2) :'0'}',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: priceColor),
                            ),
                          ],
                        ),
                      ),
                      _buildFavoriteButton(),
                      _buildCartButton(),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    widget.item.description != null
                        ? widget.item.description!
                        : '',
                    style: TextStyle(fontSize: 16, color: secondaryTextColor),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Producers:',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor),
                  ),
                  _buildProducersSection(),
                  SizedBox(height: 30),
                  // The button is now handled outside the column
                ],
              ),
            ),
          ),
          // Place the button at the bottom, above the padding
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildProceedToCartButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFavoriteButton() {
    return Tooltip(
      message: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
      child: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_outline,
          color: isFavorite ? primaryTeal : primaryTextColor,
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
      ),
    );
  }

  Widget _buildCartButton() {
    return Tooltip(
      message: isInCart ? 'Already in Cart' : 'Add to Cart',
      child: IconButton(
        icon: Icon(
          isInCart ? Icons.shopping_cart : Icons.shopping_cart_outlined,
          color: isInCart ? primaryTeal : primaryTextColor,
        ),
        onPressed: () async {
          if (isInCart) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${widget.item.name} is already in your cart!')));
            return;
          }
          await _showProducerSelector();
        },
      ),
    );
  }

  Widget _buildProducersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedProducer != null)
          Card(
            color: Colors.teal[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Icons.person, color: primaryTeal),
              title: Text(selectedProducer!['name'] ?? 'Producer'),
              subtitle: Text(selectedProducer!['location'] ?? ''),
              trailing: IconButton(
                icon: Icon(Icons.close, color: Colors.red),
                onPressed: () {
                  setState(() {
                    selectedProducer = null;
                  });
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: OutlinedButton.icon(
            icon: Icon(Icons.store, color: primaryTeal),
            label: Text(selectedProducer == null
                ? 'Select Producer'
                : 'Change Producer'),
            onPressed: _showProducerSelector,
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryTeal,
              side: BorderSide(color: primaryTeal),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProceedToCartButton() {
    // Style and placement copied from cart.dart _buildCheckoutButton
    return Visibility(
      visible: selectedProducer != null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12) +
            EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom * 0.5),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, -2))
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: selectedProducer != null
                ? () {
                    if (selectedProducer != null) {
                      if (!isInCart) {
                        _addToCartWithProducer(selectedProducer!);
                        setState(() {
                          isInCart = true;
                        });
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => cart.ShoppingCartScreen()),
                      );
                    }
                  }
                : null,
            child: Text('Proceed to Cart'),
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedProducer != null ? Colors.teal[700] : Colors.grey,
              foregroundColor: Colors.white,
              minimumSize: Size(double.infinity, 48),
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              elevation: selectedProducer != null ? 2 : 0,
            ),
          ),
        ),
      ),
    );
  }
}
