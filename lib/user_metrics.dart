import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zinzi/user_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart'; // Import for SystemChrome
import 'package:flutter/gestures.dart'; // Import for TapGestureRecognizer if needed for ToggleButtons styling

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// Define colors matching other pages
const Color lightTeal = Color(0xFFB2DFDB);
const Color lighterTeal = Color(0xFFE0F2F1);
const Color primaryTeal = Color(0xFF00796B);
const Color darkTeal = Color(0xFF004D40);
const Color subtleTextColor = Color(0xFF616161);
const Color errorColor = Color(0xFFD32F2F);


class UserMetricsPage extends StatefulWidget {
  const UserMetricsPage({super.key});

  @override
  _UserMetricsPageState createState() => _UserMetricsPageState();
}

class _UserMetricsPageState extends State<UserMetricsPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? _ageRange;

  // --- Weight ---
  double _weight = 0; // Stores weight always in KG for backend
  String _weightUnit = 'kg'; // 'kg' or 'lbs'
  final TextEditingController _weightController = TextEditingController();
  List<bool> _weightSelection = [true, false]; // Index 0: kg, Index 1: lbs

  // --- Height ---
  double _height = 0; // Stores height always in CM for backend
  String _heightUnit = 'cm'; // 'cm' or 'ft'
  final TextEditingController _heightCmController = TextEditingController();
  final TextEditingController _heightFeetController = TextEditingController();
  final TextEditingController _heightInchesController = TextEditingController();
  List<bool> _heightSelection = [true, false]; // Index 0: cm, Index 1: ft

  // --- Other Metrics ---
  double _cholesterolLevel = 0;
  double _sysBp = 0;
  double _diaBp = 0;
  double _pulse = 0;
  String? _sex;
  String? _activityLevel;

  int? _userId;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _ageRanges = [
    '5-10', // Added range
    '10-17',    // Added range
    '18-25',
    '26-35',
    '36-45',
    '46-55',
    '56-65',
    '66+'
  ];

  final List<String> _sexs = ['Male', 'Female'];

  final List<String> _activityLevels = [
    'Sedentary',
    'Lightly Active',
    'Moderately Active',
    'Very Active'
  ];

  @override
  void dispose() {
    _weightController.dispose();
    _heightCmController.dispose();
    _heightFeetController.dispose();
    _heightInchesController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // Adjusted duration
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, -1), end: const Offset(0, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

      _controller.forward();
      // Add listeners to update backend values when text changes
      _weightController.addListener(_onWeightInputChanged);
      _heightCmController.addListener(_onHeightCmInputChanged);
      _heightFeetController.addListener(_onHeightFtInInputChanged);
      _heightInchesController.addListener(_onHeightFtInInputChanged);
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
    });

    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID not found. Please log in again.'),
      ));
    }
  }

  Future<void> _submitMetrics() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('User ID is missing. Cannot submit metrics.'),
      ));
      return;
    }

    // Ensure latest values from controllers are parsed before submitting
    _parseAndUpdateWeight();
    _parseAndUpdateHeight();


    if (_formKey.currentState!.validate()) { // Validate before submitting
      try {
        final response = await http.post(
          Uri.parse('$apibaseurl/rr/metrics'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _userId,
          'age_range': _ageRange,
          'weight': _weight,
          'height': _height,
          'cholesterol_level': _cholesterolLevel,
          'sys_bp': _sysBp,
          'dia_bp': _diaBp,
          'pulse': _pulse,
          'sex': _sex,
          'activity_level': _activityLevel,
          }),
        );

        if (response.statusCode == 201) {
          Navigator.pushReplacement( // Use pushReplacement if appropriate
            context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                UserPreferencesPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit metrics data. Please try again.'),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error submitting metrics: $e'),
      ));
      }
    } else {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please fix the errors in the form.'),
        backgroundColor: errorColor,
      ));
    }
  }


  // --- Conversion and Update Logic ---

  void _onWeightInputChanged() {
     _parseAndUpdateWeight();
  }

  void _parseAndUpdateWeight() {
    final String text = _weightController.text.trim();
    final double? value = double.tryParse(text);
    if (value != null) {
      if (_weightUnit == 'kg') {
        _weight = value;
      } else { // lbs
        _weight = value * 0.453592; // Convert lbs to kg
      }
    } else if (text.isEmpty) {
       _weight = 0; // Reset if empty
    }
    // No need to call setState unless other UI depends directly on _weight
  }


  void _onHeightCmInputChanged() {
    _parseAndUpdateHeight();
  }

  void _onHeightFtInInputChanged() {
     _parseAndUpdateHeight();
  }

   void _parseAndUpdateHeight() {
    if (_heightUnit == 'cm') {
      final String text = _heightCmController.text.trim();
      final double? value = double.tryParse(text);
      if (value != null) {
        _height = value;
      } else if (text.isEmpty) {
        _height = 0; // Reset if empty
      }
    } else { // ft
      final String feetText = _heightFeetController.text.trim();
      final String inchesText = _heightInchesController.text.trim();
      final double? feet = double.tryParse(feetText);
      final double? inches = double.tryParse(inchesText);

      double totalCm = 0;
      if (feet != null) {
        totalCm += feet * 30.48;
      }
      if (inches != null) {
        totalCm += inches * 2.54;
      }
       _height = totalCm;
    }
     // No need to call setState unless other UI depends directly on _height
  }


  void _updateWeightUnit(int index) {
    setState(() {
      _weightSelection = [false, false];
      _weightSelection[index] = true;
      _weightUnit = (index == 0) ? 'kg' : 'lbs';

      // Convert the stored KG value to the new unit for display
      if (_weightUnit == 'kg') {
        _weightController.text = _weight > 0 ? _weight.toStringAsFixed(1) : '';
      } else { // lbs
        double lbs = _weight / 0.453592;
        _weightController.text = lbs > 0 ? lbs.toStringAsFixed(1) : '';
      }
       // Manually trigger validation after unit change if needed
      _formKey.currentState?.validate();
    });
  }

 void _updateHeightUnit(int index) {
    setState(() {
      _heightSelection = [false, false];
      _heightSelection[index] = true;
      _heightUnit = (index == 0) ? 'cm' : 'ft';

      // Convert the stored CM value to the new unit for display
      if (_heightUnit == 'cm') {
        _heightCmController.text = _height > 0 ? _height.toStringAsFixed(1) : '';
        _heightFeetController.clear();
        _heightInchesController.clear();
      } else { // ft
        if (_height > 0) {
          double totalInches = _height / 2.54;
          // Explicitly convert results to double
          double feet = (totalInches ~/ 12).toDouble(); // Convert int result to double
          double inches = (totalInches % 12).toDouble(); // Convert result to double
          _heightFeetController.text = feet.toStringAsFixed(0);
          _heightInchesController.text = inches.toStringAsFixed(1);
        } else {
           _heightFeetController.clear();
           _heightInchesController.clear();
        }
        _heightCmController.clear();
      }
       // Manually trigger validation after unit change if needed
       _formKey.currentState?.validate();
    });
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
          child: const Text('Health Metrics',
              style: TextStyle(color: darkTeal)), // Use consistent color
        ),
        leading: IconButton( // Add back button if needed
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
                        child: Container(
                          height: 120, // Slightly smaller image
                          width: 120,
                          child: Image.asset('assets/images/health-picsay.png'), // Consider if this image works on light bg
                        ),
                      ),
                      const SizedBox(height: 10), // Adjust spacingr
                      // Keep explanation text animation
                      SlideTransition(
                        position: _slideAnimation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            "Provide your health metrics for a personalized experience",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: darkTeal.withOpacity(0.9), // Use consistent color
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30), // Adjust spacing
                      // Form Fields Column
                      Column(
                        children: [
                          // Update Dropdown styling
                          DropdownButtonFormField<String>(
                            decoration: _buildInputDecoration('Age Range'), // Use helper
                            value: _ageRange,
                            items: _ageRanges.map((ageRange) {
                              return DropdownMenuItem<String>(
                                value: ageRange,
                                child: Text(ageRange, style: const TextStyle(color: darkTeal)), // Style text
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _ageRange = value),
                            validator: (value) => value == null
                                ? 'Please select your age range'
                                : null,
                            style: const TextStyle(color: darkTeal), // Style dropdown itself
                            iconEnabledColor: primaryTeal, // Style icon
                            dropdownColor: lighterTeal, // Style dropdown background
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            decoration: _buildInputDecoration('Sex'), // Use helper
                            value: _sex,
                            items: _sexs.map((sex) {
                              return DropdownMenuItem<String>(
                                value: sex,
                                child: Text(sex, style: const TextStyle(color: darkTeal)), // Style text
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _sex = value),
                            validator: (value) => value == null
                                ? 'Please select your sex'
                                : null,
                            style: const TextStyle(color: darkTeal), // Style dropdown itself
                            iconEnabledColor: primaryTeal, // Style icon
                            dropdownColor: lighterTeal, // Style dropdown background
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            decoration: _buildInputDecoration('Activity Level'), // Use helper
                            value: _activityLevel,
                            items: _activityLevels.map((activityLevel) {
                              return DropdownMenuItem<String>(
                                value: activityLevel,
                                child: Text(activityLevel, style: const TextStyle(color: darkTeal)), // Style text
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _activityLevel = value),
                            validator: (value) => value == null
                                ? 'Please select your activity level'
                                : null,
                            style: const TextStyle(color: darkTeal), // Style dropdown itself
                            iconEnabledColor: primaryTeal, // Style icon
                            dropdownColor: lighterTeal, // Style dropdown background
                          ),
                          const SizedBox(height: 16),
                          // --- Weight Input Row ---
                          _buildWeightInputRow(),
                          const SizedBox(height: 16),
                           // --- Height Input Row ---
                          _buildHeightInputRow(),
                          const SizedBox(height: 16),
                           // --- Other TextFormFields ---
                          _buildTextFormField('Cholesterol Level (Optional)', (value) {
                            _cholesterolLevel = double.tryParse(value) ?? 0.0; // Use 0.0
                          }, isOptional: true), // Mark as optional
                          const SizedBox(height: 16),
                          _buildTextFormField('Systolic BP (Optional)', (value) { // Made optional
                            _sysBp = double.tryParse(value) ?? 0.0; // Use 0.0
                          }, isOptional: true), // Mark as optional
                          const SizedBox(height: 16),
                          _buildTextFormField('Diastolic BP (Optional)', (value) { // Made optional
                            _diaBp = double.tryParse(value) ?? 0.0; // Use 0.0
                          }, isOptional: true), // Mark as optional
                          const SizedBox(height: 16),
                          _buildTextFormField('Pulse (Optional)', (value) { // Made optional
                            _pulse = double.tryParse(value) ?? 0.0; // Use 0.0
                          }, isOptional: true), // Mark as optional
                          const SizedBox(height: 30),
                          // Update Button style
                          ScaleTransition(
                            scale: CurvedAnimation(
                              parent: _controller,
                              curve: Curves.easeOutBack, // Add bounce effect
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  _submitMetrics();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                backgroundColor: primaryTeal,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 52),
                                textStyle: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              child: const Text('Submit Metrics'),
                            ),
                          ),
                        ],
                      ),
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
      hintText: label,
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
      contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10), // Added horizontal padding
      isDense: true, // Make it more compact
    );
  }

  // Helper for standard TextFormFields (Cholesterol, BP, Pulse)
  Widget _buildTextFormField(String label, Function(String) onChanged, {bool isOptional = false}) {
     // Use a local controller if the main state doesn't need the text directly
     // final controller = TextEditingController();
    return TextFormField(
       // controller: controller, // Use if needed
      decoration: _buildInputDecoration(label),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
      onChanged: onChanged, // This updates the main state variables like _cholesterolLevel
      validator: (value) {
        final trimmedValue = value?.trim() ?? '';
        if (!isOptional && trimmedValue.isEmpty) {
          return 'Please enter $label';
        }
        if (trimmedValue.isNotEmpty && double.tryParse(trimmedValue) == null) {
          return 'Please enter a valid number';
        }
        return null;
      },
      style: const TextStyle(color: darkTeal),
    );
  }


 // --- Input Row Builders ---

  Widget _buildWeightInputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
      children: [
        Expanded(
          child: TextFormField(
            controller: _weightController,
            decoration: _buildInputDecoration('Weight'), // Label changes dynamically below
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
            // onChanged handled by listener (_onWeightInputChanged)
            validator: (value) {
               final trimmedValue = value?.trim() ?? '';
               if (trimmedValue.isEmpty) {
                 return 'Enter weight';
               }
               if (double.tryParse(trimmedValue) == null) {
                 return 'Invalid number';
               }
               return null;
            },
            style: const TextStyle(color: darkTeal),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 8.0), // Align with text field content
          child: ToggleButtons(
            isSelected: _weightSelection,
            onPressed: _updateWeightUnit,
            borderRadius: BorderRadius.circular(8.0),
            selectedColor: Colors.white,
            color: primaryTeal,
            fillColor: primaryTeal,
            constraints: const BoxConstraints(minHeight: 30.0, minWidth: 40.0), // Adjust size
            children: const <Widget>[
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('kg')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('lbs')),
            ],
          ),
        ),
      ],
    );
  }


 Widget _buildHeightInputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // Conditionally display CM or FT/IN fields
          child: _heightUnit == 'cm'
              ? TextFormField(
                  controller: _heightCmController,
                  decoration: _buildInputDecoration('Height (cm)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                  // onChanged handled by listener
                   validator: (value) {
                      final trimmedValue = value?.trim() ?? '';
                      if (trimmedValue.isEmpty) {
                        return 'Enter height';
                      }
                      if (double.tryParse(trimmedValue) == null) {
                        return 'Invalid number';
                      }
                      return null;
                   },
                  style: const TextStyle(color: darkTeal),
                )
              : Row( // FT + IN fields
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _heightFeetController,
                        decoration: _buildInputDecoration('ft'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                         // onChanged handled by listener
                         validator: (value) {
                            final trimmedValue = value?.trim() ?? '';
                            if (trimmedValue.isEmpty && _heightInchesController.text.trim().isEmpty) {
                              return 'Enter ft/in'; // Combined message
                            }
                            if (trimmedValue.isNotEmpty && int.tryParse(trimmedValue) == null) {
                              return 'Invalid';
                            }
                            return null;
                         },
                        style: const TextStyle(color: darkTeal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _heightInchesController,
                        decoration: _buildInputDecoration('in'),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                         // onChanged handled by listener
                         validator: (value) {
                            final trimmedValue = value?.trim() ?? '';
                             if (trimmedValue.isEmpty && _heightFeetController.text.trim().isEmpty) {
                               return null; // Allow empty if feet is also empty, handled by feet validator
                             }
                            if (trimmedValue.isNotEmpty && double.tryParse(trimmedValue) == null) {
                              return 'Invalid';
                            }
                             final inches = double.tryParse(trimmedValue);
                             if (inches != null && inches >= 12) {
                               return '< 12'; // Inches should be less than 12
                             }
                            return null;
                         },
                        style: const TextStyle(color: darkTeal),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 10),
         Padding(
           padding: const EdgeInsets.only(top: 8.0),
           child: ToggleButtons(
            isSelected: _heightSelection,
            onPressed: _updateHeightUnit,
            borderRadius: BorderRadius.circular(8.0),
            selectedColor: Colors.white,
            color: primaryTeal,
            fillColor: primaryTeal,
            constraints: const BoxConstraints(minHeight: 30.0, minWidth: 40.0),
            children: const <Widget>[
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('cm')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('ft')), // Label is 'ft' but represents ft+in mode
            ],
                 ),
         ),
      ],
    );
  }

}
