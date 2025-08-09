//cspell:disable
import 'package:flutter/material.dart';

class OverlayUtils {
  static void showErrorOverlay({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    try {
      // Use safeOverlayOperation to handle the overlay
      safeOverlayOperation(
        context: context,
        operation: () {
          // Check if the widget is still in the tree and get overlay state
          if (!context.mounted) return;
          
          // Get the overlay state - safe because we've checked mounted
          final overlay = Overlay.of(context);

          // Create overlay entry
          final overlayEntry = OverlayEntry(
            builder: (BuildContext context) => Positioned(
              bottom: MediaQuery.of(context).viewInsets.bottom + 100,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          // Insert the overlay
          overlay.insert(overlayEntry);

          // Remove the overlay after duration
          Future.delayed(duration, () {
            try {
              if (overlayEntry.mounted) {
                overlayEntry.remove();
              }
            } catch (e) {
              // Ignore any errors when removing the overlay
            }
          });
        },
      );
    } catch (e) {
      // Ignore any errors during overlay creation
    }
  }


  // Helper method to safely handle overlay operations with mounted check
  static void safeOverlayOperation({
    required BuildContext context,
    required VoidCallback operation,
  }) {
    if (context.mounted) {
      try {
        operation();
      } catch (e) {
        // Ignore any errors
      }
    }
  }
}
