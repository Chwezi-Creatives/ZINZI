import 'dart:async';
import 'dart:ui';

/// A utility class that debounces a function call by a specified delay.
class Debouncer {
  final Duration delay;
  Timer? _timer;
  final VoidCallback? onComplete;

  Debouncer({Duration? delay, this.onComplete}) : delay = delay ?? const Duration(milliseconds: 300);

  /// Runs the given [action] after the delay has passed.
  /// If [runImmediately] is true, the action will run immediately and reset the timer.
  void run(VoidCallback action, {bool runImmediately = false}) {
    if (runImmediately) {
      _timer?.cancel();
      action();
      onComplete?.call();
      return;
    }

    _timer?.cancel();
    _timer = Timer(delay, () {
      action();
      onComplete?.call();
    });
  }

  /// Cancels any pending debounced calls.
  void cancel() {
    _timer?.cancel();
  }

  /// Whether there is a pending debounced call.
  bool get isRunning => _timer?.isActive ?? false;
}
