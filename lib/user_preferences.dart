//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi/onboard.dart';
import 'package:zinzi/profile.dart';
import 'package:flutter/services.dart'; // Import for SystemChrome

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// Define colors matching other pages
const Color lightTeal = Color(0xFFB2DFDB);
const Color lighterTeal = Color(0xFFE0F2F1);
const Color primaryTeal = Color(0xFF00796B);
const Color darkTeal = Color(0xFF004D40);
const Color subtleTextColor = Color(0xFF616161);
const Color errorColor = Color(0xFFD32F2F);


class UserPreferencesPage extends StatefulWidget {
  const UserPreferencesPage({super.key});

  @override
  _UserPreferencesPageState createState() => _UserPreferencesPageState();
}

class _UserPreferencesPageState extends State<UserPreferencesPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _goals = ''; // Renamed for clarity
  String _dietType = '';
  String _foodRestrictions = '';
  String? _userId;
  bool _isLoading = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _goalsOptions = [ // Renamed for clarity
    'Weight Loss',
    'Muscle Gain',
    'Maintain Weight'
  ];
  final List<String> _dietTypeOptions = [
    'All',
    'Vegeterian',
    'Vegan',
    'Omnivore'
  ];
  final List<String> _foodRestrictionsOptions = [
    'Gluten-Free',
    'Dairy-Free',
    'Nut-Free',
    'None'
  ];

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1)); // Adjusted duration
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -0.5), end: Offset.zero) // Slide from top
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    _loadUserId();
  }

   @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    // Ensure setState is called only if the widget is still mounted
    if (mounted) {
      setState(() {
        _userId = prefs.getString('user_id');
      });
      if (_userId == null || _userId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('User ID not found. Please log in again.'),
            backgroundColor: errorColor,
          ));
        }
      }
    }
  }

  Future<void> _submitPreferences() async {
    if (!_formKey.currentState!.validate()) return; // Validate form first

    if (_userId == null || _userId!.isEmpty) {
      debugPrint('❌ User ID is missing or empty');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('User ID is missing. Cannot submit preferences.'),
        backgroundColor: errorColor,
      ));
      return;
    }

    setState(() => _isLoading = true); // Start loading

    try {
      final payload = {
        'user_id': _userId,
        'goals': _goals,
        'diet_type': _dietType,
        'food_restrictions': _foodRestrictions,
      };

      // Log the payload being sent
      debugPrint('📤 PREFERENCES PAYLOAD: ${jsonEncode(payload)}');
      debugPrint('🌐 Sending request to: $apibaseurl/rr/preferences');

      final response = await http.post(
        Uri.parse('$apibaseurl/rr/preferences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      // Log the response
      debugPrint('📥 PREFERENCES RESPONSE:');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 201) {
        debugPrint('✅ Preferences saved successfully');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preferences saved successfully!'),
          backgroundColor: primaryTeal,
        ));
        
        // Navigate to Profile Page after successful submission
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                LandingPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
              final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn));

              return FadeTransition(
                opacity: animation.drive(fadeTween),
                child: SlideTransition(position: animation.drive(tween), child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['message'] ?? 'Failed to submit preferences data.';
        debugPrint('❌ Failed to save preferences. Status: ${response.statusCode}, Message: $errorMessage');
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$errorMessage Please try again.'),
          backgroundColor: errorColor,
        ));
      }
    } catch (e) {
      debugPrint('❌ Error submitting preferences: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('An error occurred: $e'),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false); // Stop loading
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      // Transparent AppBar
      appBar: AppBar(
        title: SlideTransition(
          position: _slideAnimation,
          child: const Text(
            'Diet Preferences',
            style: TextStyle(color: darkTeal), // Use consistent color
          ),
        ),
         leading: IconButton( // Add back button
          icon: const Icon(Icons.arrow_back, color: darkTeal),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      // Gradient Background Container
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [lighterTeal, lightTeal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        // SafeArea and Content
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
               padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Form( // Keep Form
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Keep image animation
                      SlideTransition(
                          position: _slideAnimation,
                          child: SizedBox(
                              height: 150, // Adjust size if needed
                              width: 150,
                              child: Image.asset(
                                  'assets/images/hh.png'))), // Consider image visibility
                       const SizedBox(height: 15),
                       Text(
                         "Tell us about your diet",
                         textAlign: TextAlign.center,
                         style: TextStyle(
                           fontSize: 18,
                           color: darkTeal.withOpacity(0.9),
                           fontWeight: FontWeight.w600,
                         ),
                       ),
                      const SizedBox(height: 30),
                      // Form Fields Column
                      Column(
                        children: [
                          _buildDropdownField(
                            'Goals',
                            _goalsOptions, // Use updated name
                            (value) {
                              if (value != null) setState(() => _goals = value); // Use updated name
                            },
                            _goals, // Use updated name
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(
                            'Diet Type',
                            _dietTypeOptions,
                            (value) {
                              if (value != null) setState(() => _dietType = value);
                            },
                            _dietType,
                          ),
                          const SizedBox(height: 16),
                          _buildDropdownField(
                            'Food Restrictions',
                            _foodRestrictionsOptions,
                            (value) {
                              if (value != null) setState(() => _foodRestrictions = value);
                            },
                            _foodRestrictions,
                          ),
                          const SizedBox(height: 50),
                          // Update Button style
                          ScaleTransition(
                            scale: CurvedAnimation(
                                parent: _controller, curve: Curves.easeOutBack), // Add bounce
                            child: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      if (_formKey.currentState!.validate()) {
                                        _submitPreferences();
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15)), // Match other screens
                                backgroundColor: primaryTeal, // Consistent color
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 52), // Consistent height
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20, width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.0))
                                  : const Text('Submit Preferences'),
                            ),
                          ),
                        ],
                      ), // End Form Fields Column
                    ],
                  ),
                ), // Close Form
              ), // Close FadeTransition
            ), // Close SingleChildScrollView
          ), // Close Center
        ), // Close SafeArea
      ), // Close Container
    ); // Close Scaffold
  }

  // Helper for InputDecoration (consistent style)
  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: primaryTeal),
      hintText: 'Select $label', // Add hint text
      hintStyle: TextStyle(color: subtleTextColor.withOpacity(0.5)),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: primaryTeal, size: 20) : null,
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: subtleTextColor.withOpacity(0.5)),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: subtleTextColor.withOpacity(0.5)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: primaryTeal, width: 2.0),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 1.0),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 2.0),
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 0),
    );
  }


  // Updated Dropdown helper using the new InputDecoration helper
  Widget _buildDropdownField(String label, List<String> items,
      Function(String?) onChanged, String currentValue) {
    // Determine the value to display: null if empty, otherwise the current value
    String? displayValue = currentValue.isEmpty ? null : currentValue;
    // Ensure the displayValue exists in the items list, otherwise set to null
    if (displayValue != null && !items.contains(displayValue)) {
      displayValue = null;
    }

    return DropdownButtonFormField<String>(
      decoration: _buildInputDecoration(label), // Use helper
      value: displayValue, // Use the potentially null displayValue
      onChanged: onChanged,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(color: darkTeal))))
          .toList(),
      validator: (value) =>
          value == null || value.isEmpty ? 'Please select $label' : null,
      style: const TextStyle(color: darkTeal), // Style dropdown itself
      iconEnabledColor: primaryTeal, // Style icon
      dropdownColor: lighterTeal, // Style dropdown background
      isExpanded: true, // Ensure dropdown takes full width
    );
  }
}
