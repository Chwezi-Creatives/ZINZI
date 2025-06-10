//cspell:disable
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'create_gig_screen.dart';

// Helper for consistent InputDecoration
InputDecoration inputDecorationHelper(String label, IconData icon, {bool isDense = true}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: kColorTextSecondary),
    hintText: 'Enter $label',
    hintStyle: const TextStyle(color: Colors.grey),
    prefixIcon: Icon(icon, color: kColorPrimary, size: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMedium),
      borderSide: BorderSide(color: kColorDivider, width: 1.0),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMedium),
      borderSide: BorderSide(color: kColorDivider, width: 1.0),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMedium),
      borderSide: const BorderSide(color: kColorPrimary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMedium),
      borderSide: BorderSide(color: Colors.red.shade700, width: 1.0),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMedium),
      borderSide: BorderSide(color: Colors.red.shade700, width: 1.5),
    ),
    isDense: isDense,
    contentPadding: isDense
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
  );
}

// Bottom Confirmation Button
Widget buildConfirmButton({
  required bool isLoading,
  required double? calculatedPrice,
  required VoidCallback? onSubmit,
}) {
  bool canSubmit = !isLoading && calculatedPrice != null && calculatedPrice > 0;
  return Container(
    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
    decoration: BoxDecoration(
      color: kColorSurface,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha((0.08 * 255).toInt()),
          blurRadius: 10,
          offset: const Offset(0, -3),
        ),
      ],
    ),
    child: ElevatedButton.icon(
      icon: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: const CircularProgressIndicator(
                color: kColorTextOnPrimary,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.check_circle_outline_rounded, size: 20),
      label: Text(isLoading ? 'Booking...' : 'Confirm Gig Booking'),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            canSubmit ? kColorPrimaryDark : Colors.grey.shade500,
        foregroundColor: kColorTextOnPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMedium),
        ),
        textStyle:
            GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
        elevation: canSubmit ? 2 : 0,
      ),
      onPressed: canSubmit ? onSubmit : null,
    ),
  );
}
