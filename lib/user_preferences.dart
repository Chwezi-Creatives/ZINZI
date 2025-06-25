//cspell:disable
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi/onboard.dart'; //navigate to this landing page on sucess
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

// --- CHANGE 1: Use TickerProviderStateMixin for multiple AnimationControllers ---
class _UserPreferencesPageState extends State<UserPreferencesPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _goals = '';
  String _dietType = '';
  String _foodRestrictions = '';
  String _cuisinePreferences = '';
  String? _userId;
  bool _isLoading = false;

  // --- Animation Controllers ---
  late AnimationController _controller; // For initial page load animation
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // --- NEW: Animation controller for the breathing effect ---
  late AnimationController _breathingController;
  late Animation<double> _scaleAnimation;

  // --- Form Options ---
  final List<String> _goalsOptions = [
    "Lose Weight", "Boost Energy Levels", "Gain Muscle", "Satiety", "Detox and Cleanse",
    "Enhance Metabolic Health", "Improve Sleep Quality", "Improved eye health", "Improved immune",
    "Joint Pain", "Manage Stress Through Nutrition", "Postpartum recovery", "Reduced inflamation",
    "Skin and hair improvement", "Control Chronic Conditions (e.g. diabetes and hypertension)",
  ];
  final List<String> _dietTypeOptions = [
    "Anti Inflamatory", "Diabetic Diet", "High blood pressure", "Keto (Low-Carb and High-Fat)",
    "Muscle Repair", "Normal Diet", "Renal Diet"
  ];
  final List<String> _foodRestrictionsOptions = [
    "None", "Meat Allergy (e.g. beef)", "Milk/Dairy Allergy", "Soy Allergy",
    "Spice Allergy (e.g. cinnamon and paprika)", "Wheat Allergy", "Citrus Allergy (e.g. oranges and lemons)",
    "Corn Allergy", "Egg Allergy", "Fish Allergy", "Gluten Allergy", "Histamine Intolerance",
    "Latex-Fruit Syndrome (e.g. bananas)", "Legume Allergy (e.g. lentils and chickpeas)",
    "Nightshade Allergy (e.g. tomatoes and potatoes)", "Peanut Allergy", "Sesame Allergy",
    "Shellfish Allergy (e.g. shrimp and lobster)",
  ];
  final List<String> _cuisinePreferencesOptions = [
    "Any", "African", "American", "Asian", "Caribbean", "European", "Indian", "Italian",
    "Mediterranean", "Mexican", "Middle Eastern", "South American", "Other"
  ];

  @override
  void initState() {
    super.initState();
    // Setup for initial page load animations
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -0.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();

    // --- CHANGE 2: Setup the new breathing animation ---
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));
    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.00).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOut,
      ),
    );
    // Make the animation loop back and forth
    _breathingController.repeat(reverse: true);

    _loadUserId();
  }

  @override
  void dispose() {
    _controller.dispose();
    _breathingController.dispose(); // --- CHANGE 3: Dispose the new controller ---
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userId = prefs.getString('user_id');
      });
      if (_userId == null || _userId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'User ID not found. Cannot proceed. Please log in again.',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: errorColor,
          ));
        }
      }
    }
  }

  Future<void> _submitPreferences() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please fill out all fields.', style: GoogleFonts.poppins()),
        backgroundColor: errorColor,
      ));
      return;
    }

    if (_userId == null || _userId!.isEmpty) {
      debugPrint('❌ User ID is missing or empty');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID is missing. Cannot submit preferences.', style: GoogleFonts.poppins()),
        backgroundColor: errorColor,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final payload = {
        'goals': _goals, 'diet_type': _dietType, 'food_restrictions': _foodRestrictions,
        'cuisine_preferences': _cuisinePreferences,
      };

      debugPrint('📤 PREFERENCES PAYLOAD: ${jsonEncode(payload)}');
      final url = '$apibaseurl/rr/users/$_userId/preferences';
      debugPrint('🌐 Sending request to: $url');

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      debugPrint('📥 PREFERENCES RESPONSE: Status ${response.statusCode}, Body: ${response.body}');
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ Preferences saved successfully');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Preferences saved successfully!', style: GoogleFonts.poppins()),
          backgroundColor: primaryTeal,
        ));
        
        if (mounted) {
          Navigator.of(context).pushReplacement(LandingPage.createRoute());
        }
      } else {
        final errorData = json.decode(response.body);
        final errorMessage = errorData['message'] ?? 'Failed to submit preferences data.';
        debugPrint('❌ Failed to save preferences. Status: ${response.statusCode}, Message: $errorMessage');
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$errorMessage Please try again.', style: GoogleFonts.poppins()),
          backgroundColor: errorColor,
        ));
      }
    } catch (e) {
      debugPrint('❌ Error submitting preferences: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('An error occurred: $e', style: GoogleFonts.poppins()),
        backgroundColor: errorColor,
      ));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: SlideTransition(
          position: _slideAnimation,
          child: Text(
            'Diet Preferences',
            style: GoogleFonts.poppins(
              color: darkTeal,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      extendBodyBehindAppBar: true,
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
               padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // --- CHANGE 4: Apply the breathing effect using ScaleTransition ---
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: SlideTransition(
                            position: _slideAnimation,
                            child: SizedBox(
                                height: 150,
                                width: 150,
                                child: Image.asset('assets/images/hh.png'))),
                      ),
                       const SizedBox(height: 15),
                       Text(
                         "Tell us about your diet",
                         textAlign: TextAlign.center,
                         style: GoogleFonts.poppins(
                           fontSize: 24, 
                           color: darkTeal.withOpacity(0.9),
                           fontWeight: FontWeight.w600,
                         ),
                       ),
                       const SizedBox(height: 4),
                       Text(
                         "This helps us tailor your experience.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16, 
                            color: subtleTextColor,
                          ),
                       ),
                      const SizedBox(height: 30),
                      
                      _buildDropdownField('Health Goals', _goalsOptions, (value) {
                          if (value != null) setState(() => _goals = value);
                        }, _goals),
                      const SizedBox(height: 16),
                      _buildDropdownField('Diet Type', _dietTypeOptions, (value) {
                          if (value != null) setState(() => _dietType = value);
                        }, _dietType),
                      const SizedBox(height: 16),
                      _buildDropdownField('Food Restrictions', _foodRestrictionsOptions, (value) {
                          if (value != null) setState(() => _foodRestrictions = value);
                        }, _foodRestrictions),
                      const SizedBox(height: 16),
                      _buildDropdownField('Cuisine Preference', _cuisinePreferencesOptions, (value) {
                          if (value != null) setState(() => _cuisinePreferences = value);
                        }, _cuisinePreferences),
                      const SizedBox(height: 50),

                      ScaleTransition(
                        scale: CurvedAnimation(
                            parent: _controller, curve: Curves.easeOutBack),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitPreferences,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            backgroundColor: primaryTeal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            textStyle: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20, width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.0))
                              : const Text('Save Preferences'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: primaryTeal, fontSize: 18),
      hintText: 'Select your $label',
      hintStyle: GoogleFonts.poppins(color: subtleTextColor.withOpacity(0.5), fontSize: 14),
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
    );
  }

  Widget _buildDropdownField(String label, List<String> items,
      Function(String?) onChanged, String currentValue) {
    String? displayValue = currentValue.isEmpty || !items.contains(currentValue)
        ? null
        : currentValue;

    return DropdownButtonFormField<String>(
      decoration: _buildInputDecoration(label),
      value: displayValue,
      onChanged: onChanged,
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(item,
                    style: GoogleFonts.poppins(
                        color: darkTeal, fontSize: 16)),
              ))
          .toList(),
      validator: (value) =>
          value == null || value.isEmpty ? 'Please select an option for $label' : null,
      style: GoogleFonts.poppins(color: darkTeal, fontSize: 14),
      iconEnabledColor: primaryTeal,
      dropdownColor: lighterTeal,
      isExpanded: true,
    );
  }
}