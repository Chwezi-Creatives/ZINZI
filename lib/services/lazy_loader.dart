//cspell:disable
import 'package:flutter/material.dart';
import 'dart:async';

class LazyLoader {
  static const _lazyLoadDelay = Duration(milliseconds: 500);
  static final Map<String, Timer> _timers = {};

  static void loadImage(String assetPath, BuildContext context) {
    if (!_timers.containsKey(assetPath)) {
      _timers[assetPath] = Timer(_lazyLoadDelay, () {
        precacheImage(AssetImage(assetPath), context);
        _timers.remove(assetPath);
      });
    }
  }

  static void cancelLoad(String assetPath) {
    final timer = _timers[assetPath];
    if (timer != null) {
      timer.cancel();
      _timers.remove(assetPath);
    }
  }

  static GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  static Widget lazyImage(String assetPath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (_navigatorKey.currentContext == null) {
      return Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: fit,
      );
    }
    
    return FutureBuilder(
      future: precacheImage(AssetImage(assetPath), _navigatorKey.currentContext!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[200],
          );
        }
        return Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: fit,
        );
      },
    );
  }
}
