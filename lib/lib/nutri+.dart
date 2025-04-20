import 'package:flutter/material.dart';

// Color constants
const Color cardBackgroundColor = Colors.white;
const Color lightTeal = Color(0xFFE0F2F1);
const Color errorIconColor = Colors.grey;
const Color primaryTextColor = Colors.black87;
const Color priceColor = Color(0xFF2E7D32);

class NutritionItem {
  final String name;
  final double price;
  final String imagePath;
  final String heroTag;

  NutritionItem({
    required this.name,
    required this.price,
    required this.imagePath,
    required this.heroTag,
  });
}

class NutritionItemCard extends StatelessWidget {
  final NutritionItem item;
  final String? defaultImagePath;

  const NutritionItemCard({Key? key, required this.item, this.defaultImagePath})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _buildItemCard(item, context, defaultImagePath: defaultImagePath);
  }

  Widget _buildItemCard(NutritionItem item, BuildContext context,
      {String? defaultImagePath}) {
    final borderRadius = BorderRadius.circular(15.0);
    final heroTag = item.heroTag;

    return Card(
      elevation: 3.0,
      shadowColor: Colors.grey.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      color: cardBackgroundColor,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: lightTeal.withOpacity(0.3),
          highlightColor: lightTeal.withOpacity(0.1),
          onTap: () {
            // Navigation temporarily disabled
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Hero(
                  tag: heroTag,
                  flightShuttleBuilder: (
                    BuildContext flightContext,
                    Animation<double> animation,
                    HeroFlightDirection flightDirection,
                    BuildContext fromHeroContext,
                    BuildContext toHeroContext,
                  ) {
                    final Hero toHero = toHeroContext.widget as Hero;
                    return FadeTransition(
                      opacity: animation.drive(
                          Tween<double>(begin: 0.85, end: 1.0)
                              .chain(CurveTween(curve: Curves.easeInOut))),
                      child: toHero.child,
                    );
                  },
                  child: Material(
                    type: MaterialType.transparency,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(15.0)),
                      child: Image.asset(
                        item.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (BuildContext context, Object error,
                            StackTrace? stackTrace) {
                          if (defaultImagePath != null &&
                              defaultImagePath.isNotEmpty) {
                            return Image.asset(
                              defaultImagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, st) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                    child: Icon(Icons.error_outline,
                                        color: errorIconColor, size: 40.0)),
                              ),
                            );
                          } else {
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: errorIconColor,
                                  size: 40.0,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 8.0, 10.0, 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        color: primaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      '\$${item.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: priceColor,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
