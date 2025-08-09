import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../features/subscription/subscription_provider.dart';
import '../../features/subscription/subscription_service.dart';

class SubscriptionPaymentDialog extends StatefulWidget {
  final SubscriptionPlan plan;
  final Function()? onPaymentSuccess;

  const SubscriptionPaymentDialog({
    Key? key,
    required this.plan,
    this.onPaymentSuccess,
  }) : super(key: key);

  @override
  _SubscriptionPaymentDialogState createState() => _SubscriptionPaymentDialogState();
}

class _SubscriptionPaymentDialogState extends State<SubscriptionPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String _selectedPaymentMethod = 'MTN';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserPhoneNumber();
  }

  Future<void> _loadUserPhoneNumber() async {
    try {
      debugPrint('🔍 Loading phone number from SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      debugPrint('📱 All SharedPreferences keys: ${prefs.getKeys()}');
      
      // Try different possible keys that might contain the phone number
      final possibleKeys = ['phone_number', 'user_phone', 'phone', 'phoneNumber', 'userPhone'];
      String? phoneNumber;
      String? foundInKey;
      
      for (final key in possibleKeys) {
        if (prefs.containsKey(key)) {
          final value = prefs.getString(key);
          debugPrint('🔑 Found key "$key" with value: $value');
          if (value != null && value.isNotEmpty) {
            phoneNumber = value;
            foundInKey = key;
            break;
          }
        }
      }
      
      if (phoneNumber != null && mounted) {
        debugPrint('✅ Using phone number from SharedPreferences (key: $foundInKey): $phoneNumber');
        setState(() {
          _phoneController.text = phoneNumber!;
        });
      } else {
        debugPrint('⚠️ No valid phone number found in SharedPreferences');
        debugPrint('Available keys with values:');
        for (final key in prefs.getKeys()) {
          debugPrint('  - $key: ${prefs.get(key)}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading phone number: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get the subscription provider
      final subscriptionProvider = context.read<SubscriptionProvider>();
      
      // Process the subscription
      final success = await subscriptionProvider.subscribeToPlan(
        planId: widget.plan.id,
        paymentTransactionId: '${DateTime.now().millisecondsSinceEpoch}',
        paymentMethod: _selectedPaymentMethod,
        phoneNumber: _phoneController.text.trim(),
      );

      if (success && mounted) {
        // Save the phone number for future use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('phone_number', _phoneController.text.trim());
        
        // Close the dialog and call the success callback
        Navigator.of(context).pop(true);
        widget.onPaymentSuccess?.call();
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Failed to process payment. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Payment error: $e');
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Complete Subscription',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF004D40),
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plan: ${widget.plan.name}\n'
                'Price: UGX ${widget.plan.price.toInt()}',
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixText: '+256 ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  // Basic phone number validation (7-9 digits after +256)
                  if (!RegExp(r'^[0-9]{9,10}$').hasMatch(value)) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Select Payment Method',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentMethodButton(
                      'MTN',
                      'assets/images/mtn.png',
                      _selectedPaymentMethod == 'MTN',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPaymentMethodButton(
                      'Airtel',
                      'assets/images/airtel.png',
                      _selectedPaymentMethod == 'Airtel',
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...{
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _processPayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00796B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Pay UGX ${widget.plan.price.toInt()}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodButton(String method, String assetPath, bool isSelected) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFFE0F2F1) : Colors.white,
        side: BorderSide(
          color: isSelected ? const Color(0xFF00796B) : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            assetPath,
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.payment, size: 24),
          ),
          const SizedBox(width: 8),
          Text(
            method,
            style: GoogleFonts.poppins(
              color: isSelected ? const Color(0xFF00796B) : Colors.black87,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}
