import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class PerformanceService {
  static const _startupTimeout = Duration(seconds: 10);
  static final _startupTimer = Stopwatch();
  static final _startupEvents = <String, Duration>{};

  static void startTimer() {
    _startupTimer.start();
  }

  static void recordEvent(String event) {
    if (_startupTimer.isRunning) {
      _startupEvents[event] = _startupTimer.elapsed;
    }
  }

  static void endTimer() {
    if (_startupTimer.isRunning) {
      _startupTimer.stop();
      debugPrint('Startup completed in ${_startupTimer.elapsed}');
      debugPrint('Startup events:');
      _startupEvents.forEach((event, duration) {
        debugPrint('$event: ${duration.toString().split('.')[0]}');
      });
    }
  }

  static bool isStartupComplete() {
    return !_startupTimer.isRunning;
  }

  static Future<T> timedOperation<T>(String event, Future<T> Function() operation) async {
    recordEvent('Start $event');
    final result = await operation();
    recordEvent('End $event');
    return result;
  }

  static GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> initialize() {
    return timedOperation('Performance Service', () async {
      // Pre-cache important assets
      if (kIsWeb && _navigatorKey.currentContext != null) {
        await precacheImage(const AssetImage('assets/images/logo.png'), _navigatorKey.currentContext!);
        // Add other important assets here
      }
    });
  }
}
