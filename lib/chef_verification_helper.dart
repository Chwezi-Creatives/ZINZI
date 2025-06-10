//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Color constants
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color errorColor = Color(0xFFD32F2F); // Red 700 for errors
const Color subtleTextColor = Color(0xFF757575); // Grey 600

/// Helper class for handling gig verification in the chef dashboard
class ChefVerificationHelper {
  /// Shows a verification dialog for gigs that need verification
  static Future<bool> showVerificationDialog(
      BuildContext context, dynamic order) async {
    final TextEditingController codeController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    String? errorMessage;

    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text('Verify Gig Completion',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: primaryTeal)),
            content: Form(
                key: formKey,
                child: SingleChildScrollView(
                    child: ListBody(children: <Widget>[
                  Text(
                      'Please ask the customer for the verification code to mark this gig as completed:',
                      style: TextStyle(color: subtleTextColor)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: codeController,
                    decoration: InputDecoration(
                        labelText: 'Verification Code',
                        border: OutlineInputBorder(),
                        hintText: 'Enter 6-digit code'),
                    keyboardType: TextInputType.number,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Please enter verification code'
                        : (value.length != 6 || int.tryParse(value) == null)
                            ? 'Please enter a valid 6-digit code'
                            : null,
                  ),
                  if (errorMessage != null && errorMessage!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Text(
                        errorMessage!,
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ]))),
            actions: <Widget>[
              TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.of(dialogContext).pop(false)),
              ElevatedButton(
                  child: const Text('Verify'),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      try {
                        final success = await _verifyGigCode(
                            orderId: order.orderId,
                            verificationCode: codeController.text.trim());

                        if (success) {
                          Navigator.of(dialogContext).pop(true);
                        } else {
                          setState(() {
                            errorMessage =
                                'Invalid verification code. Please try again.';
                          });
                        }
                      } catch (e) {
                        setState(() {
                          errorMessage = 'Error: ${e.toString()}';
                        });
                      }
                    }
                  }),
            ],
          );
        });
      },
    );

    return result ?? false;
  }

  /// Verifies the gig completion code with the API
  static Future<bool> _verifyGigCode(
      {required int orderId, required String verificationCode}) async {
    try {
      // Get API base URL from environment
      String apiBaseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';

      // Get user type and ID from shared preferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userType = prefs.getString('user_type');
      String? userId = prefs.getString('user_id');
      String? chefId = prefs.getString('chef_user_id');

      String? idToSend;
      String idKey;
      if (userType != null && userType.toLowerCase() == 'transporter') {
        idToSend = userId;
        idKey = 'transporter_id';
      } else {
        idToSend = chefId;
        idKey = 'chef_id';
      }

      if (idToSend == null) {
        throw Exception('User ID not found. Please log in again.');
      }

      // Create the API endpoint URL
      final Uri uri = Uri.parse('$apiBaseUrl/rr/orders/$orderId/status');

      // Make the API request as PATCH
      final response = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              idKey: idToSend,
              'completion_code': verificationCode,
              'order_status': 'completed',
            }),
          )
          .timeout(const Duration(seconds: 15));

      // Handle the response
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data['success'] == true;
      } else if (response.statusCode == 400) {
        // Invalid code
        return false;
      } else {
        throw Exception('Failed to verify code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error verifying gig code: $e');
      throw Exception('Verification failed: ${e.toString()}');
    }
  }

  /// Updates the order status after successful verification
  static Future<bool> updateOrderStatusAfterVerification(
      int orderId, String newStatus) async {
    try {
      // Get API base URL from environment
      String apiBaseUrl =
          dotenv.env['API_BASE_URL-intranet'] ?? 'https://api.example.com';

      // Get user type and ID from shared preferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userType = prefs.getString('user_type');
      String? userId = prefs.getString('user_id');
      String? chefId = prefs.getString('chef_user_id');

      String? idToSend;
      String idKey;
      if (userType != null && userType.toLowerCase() == 'transporter') {
        idToSend = userId;
        idKey = 'transporter_id';
      } else {
        idToSend = chefId;
        idKey = 'chef_id';
      }

      if (idToSend == null) {
        throw Exception('User ID not found. Please log in again.');
      }

      // Create the API endpoint URL
      final Uri uri = Uri.parse('$apiBaseUrl/rr/orders/$orderId/status');

      // Make the API request
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              idKey: idToSend,
              'status': newStatus,
            }),
          )
          .timeout(const Duration(seconds: 15));

      // Handle the response
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Failed to update status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating order status: $e');
      throw Exception('Status update failed: ${e.toString()}');
    }
  }
}
