// create_gig_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'create_gig_screen_helpers.dart';
import 'package:intl/intl.dart'; // For date/time formatting
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/cart.dart' as cart; // Use prefix
import 'dart:convert'; // For json.decode

// Re-use color constants (or import from a central theme file)
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorSurface = Colors.white;
const Color kColorPrimaryLight = Color(0xFF48A999); // Define kColorPrimaryLight
const Color kColorBackground = Color(0xFFFAFAFA);
const Color kColorPrimaryLightest = Color(0xFFB2DFDB); // Define kColorPrimaryLightest
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary = Color(0xFF757575);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorDivider = Color(0xFFEEEEEE);
const Color kColorAccent = Color(0xFF00BFA5);
const double kRadiusMedium = 12.0;
const double kRadiusSmall = 8.0; // Define kRadiusSmall

class CreateGigScreen extends StatefulWidget {
  final Map<String, dynamic> chefData;
  const CreateGigScreen({super.key, required this.chefData});
  @override
  State<CreateGigScreen> createState() => _CreateGigScreenState();
}

class _CreateGigScreenState extends State<CreateGigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form State Variables
  String? _selectedGigType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedNumPeopleKey;
  double? _calculatedPrice;

  // **** NEW State Variables for Custom Validation ****
  bool _showDateError = false;
  bool _showTimeError = false;
  // **** END NEW State Variables ****

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isLoading = false;

  // Extracted Pricing Info
  Map<String, dynamic>? _perGigPricing;
  List<String> _numberOfPeopleOptions = [];

  // Standard Gig Types
  final List<String> _gigTypes = [ 'Birthday Party', 'Anniversary Dinner', 'Thanksgiving Feast', 'Corporate Meeting', 'Private Celebration', 'Holiday Gathering', 'Other Special Event', ];

  @override
  void initState() {
    super.initState();
    _extractPricingOptions();
    print("CreateGigScreen received chefData: ${widget.chefData}");
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _extractPricingOptions() {
    // (Keep existing _extractPricingOptions logic - unchanged)
     Map<String, dynamic>? pricingData;
    final dynamic pricingRaw = widget.chefData['pricing'];
    if (pricingRaw is String) {
      try { pricingData = json.decode(pricingRaw); }
      catch (e) { print("Error decoding pricing JSON string in CreateGigScreen: $e"); pricingData = null; }
    } else if (pricingRaw is Map<String, dynamic>) {
      pricingData = pricingRaw;
    } else { pricingData = null; }
    _perGigPricing = pricingData?['per_gig'] is Map<String, dynamic> ? pricingData!['per_gig'] : null;
    if (_perGigPricing != null && _perGigPricing!.isNotEmpty) {
      _numberOfPeopleOptions = _perGigPricing!.keys.toList();
      _numberOfPeopleOptions.sort((a, b) {
        final numA = int.tryParse(a.split('_').first) ?? 0;
        final numB = int.tryParse(b.split('_').first) ?? 0;
        return numA.compareTo(numB);
      });
    } else { print("Warning: 'per_gig' pricing data is missing or empty for this chef."); _numberOfPeopleOptions = []; }
  }

  // --- Date Picker --- (Keep existing _selectDate logic - unchanged)
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker( context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) { return Theme( data: Theme.of(context).copyWith( colorScheme: const ColorScheme.light( primary: kColorPrimary, onPrimary: kColorTextOnPrimary, onSurface: kColorTextPrimary,),
            textButtonTheme: TextButtonThemeData( style: TextButton.styleFrom(foregroundColor: kColorPrimary),),), child: child!,);},);
    if (picked != null && picked != _selectedDate) {
      setState(() { _selectedDate = picked;
        // Reset date error when a new date is picked
        if (_showDateError) _showDateError = false; });
    }
  }

  // --- Time Picker --- 
 Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker( context: context, initialTime: _selectedTime ?? TimeOfDay.now(),
       builder: (context, child) { return Theme( data: Theme.of(context).copyWith( colorScheme: const ColorScheme.light( primary: kColorPrimary, onPrimary: kColorTextOnPrimary, onSurface: kColorTextPrimary, ),
              timePickerTheme: TimePickerThemeData( dialHandColor: kColorPrimaryLight, hourMinuteTextColor: WidgetStateColor.resolveWith((states) =>
          states.contains(WidgetState.disabled) ? kColorPrimary.withAlpha(128) : kColorPrimaryDark), hourMinuteColor: WidgetStateColor.resolveWith((states) =>
          states.contains(WidgetState.disabled) ? kColorPrimaryLightest.withAlpha(128) : kColorPrimaryLightest),),), child: child!,);},);
    if (picked != null && picked != _selectedTime) {
      setState(() { _selectedTime = picked;
        // Reset time error when a new time is picked
        if (_showTimeError) _showTimeError = false; });
    }
  }

  // --- Price Calculation --- (Keep existing _calculateAndUpdatePrice logic - unchanged)
 void _calculateAndUpdatePrice(String? selectedKey) {
    if (selectedKey == null || _perGigPricing == null || !_perGigPricing!.containsKey(selectedKey)) {
      setState(() { _calculatedPrice = null; }); return; }
    setState(() { _calculatedPrice = (_perGigPricing![selectedKey] as num?)?.toDouble(); });
    print("Calculated Price: $_calculatedPrice for key: $selectedKey");
  }

  // --- Form Submission ---
  Future<void> _submitGig() async {
    print("DEBUG: _submitGig started.");

    // 1. Validate Form Fields FIRST
    final bool formIsValid = _formKey.currentState!.validate();

    // 2. **NEW**: Check Date and Time AFTER form validation attempt
    final bool dateIsValid = _selectedDate != null;
    final bool timeIsValid = _selectedTime != null;
    final bool priceIsValid = _calculatedPrice != null && _calculatedPrice! > 0;

    // Update error states based on checks
    bool needsSetState = false;
    if (_showDateError != !dateIsValid) {
      _showDateError = !dateIsValid;
      needsSetState = true;
    }
     if (_showTimeError != !timeIsValid) {
      _showTimeError = !timeIsValid;
      needsSetState = true;
    }
    if (needsSetState && mounted) {
      setState(() {}); // Update UI to show/hide custom errors if needed
    }

    // 3. Check if ALL validations passed
    if (!formIsValid || !dateIsValid || !timeIsValid || !priceIsValid) {
      print("DEBUG: Validation failed. Form: $formIsValid, Date: $dateIsValid, Time: $timeIsValid, Price: $priceIsValid");
       if (!priceIsValid && formIsValid && dateIsValid && timeIsValid) {
         _showErrorSnackBar("Could not calculate price. Please select number of guests.");
       } else {
         _showErrorSnackBar("Please fill in all required fields correctly.");
       }
      return; // Stop if any validation fails
    }

    // --- ALL VALIDATIONS PASSED ---
    print("DEBUG: All validations passed. Proceeding with submission.");
    if (mounted) setState(() { _isLoading = true; });

    try {
      print("DEBUG: Getting SharedPreferences...");
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      print("DEBUG: Read 'user_id'. Value: $userId");

      if (userId == null) {
         print("DEBUG: User ID is null. Aborting submission.");
         _showErrorSnackBar("Login error. Please log in again.", showLoginAction: true);
         if(mounted) setState(() { _isLoading = false; });
         return;
      }

      final chefId = widget.chefData['chefid'];
      final chefName = widget.chefData['name'] ?? 'Unknown Chef';

      if (chefId == null) {
          print("DEBUG: Chef ID is missing in chefData. Aborting.");
          _showErrorSnackBar("Error retrieving chef details. Cannot book gig.");
          if (mounted) setState(() { _isLoading = false; });
          return;
      }
       print("DEBUG: Chef ID: $chefId, Chef Name: $chefName");

      print("DEBUG: Constructing gigDetails map...");
      // Construct Gig Details Map - INCLUDING CHEF NAME
      final gigDetails = {
        'user_id': userId,
        'chef_id': chefId, // Keep ID for backend/relations
        'chef_name': chefName, // **** ADD CHEF NAME FOR DISPLAY ****
        'producer_id': null, 'producer_name': null, // Placeholders
        'gig_type': _selectedGigType,
        'location': _locationController.text.trim(),
        'scheduled_date': DateFormat('yyyy-MM-dd').format(_selectedDate!),
        'time': _selectedTime!.format(context),
        'estimated_duration': null,
        'number_of_people': _selectedNumPeopleKey,
        'price': _calculatedPrice,
        'detailed_description': _descriptionController.text.trim(),
      };
      print("DEBUG: gigDetails map constructed: $gigDetails");

      print("DEBUG: Calling ShoppingCart.addGig...");
      cart.ShoppingCart.addGig(gigDetails); // Add to cart
      print("DEBUG: ShoppingCart.addGig called successfully.");

      // Show Success and Navigate Back
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar( SnackBar(
            content: Text('$_selectedGigType with $chefName booked successfully! Please proceed to checkout'),
            backgroundColor: kColorAccent, duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)), margin: const EdgeInsets.all(10),),);
          Navigator.of(context).pop(true); // Indicate success
      }

    } catch (e, stackTrace) {
      print("DEBUG: Error caught in _submitGig: $e");
      print("Stack trace: $stackTrace");
      if (mounted) _showErrorSnackBar("An unexpected error occurred. Please try again.");
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
        print("DEBUG: _submitGig finished.");
      }
    }
  }

  void _showErrorSnackBar(String message, {bool showLoginAction = false}) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar( SnackBar(
         content: Text(message), backgroundColor: Colors.red.shade700,
         action: showLoginAction ? SnackBarAction(label: 'Log In', onPressed: () {
             // TODO: Navigate to login screen if needed
         }) : null,
         behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)), margin: const EdgeInsets.all(10),),);
  }

  // Helper to format the number of people option for display
  String _formatPeopleOption(String key) {
     // (Keep existing _formatPeopleOption logic - unchanged)
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    String numberPart = parts.first; String suffix = parts.length > 1 ? parts.sublist(1).join(' ') : 'people';
    suffix = suffix.replaceAll('plus', '+'); suffix = suffix[0].toUpperCase() + suffix.substring(1);
    return "$numberPart $suffix";
  }

  @override
  Widget build(BuildContext context) {
    String chefName = widget.chefData['name'] ?? 'Selected Chef';

    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar( title: Text('Book $chefName'), backgroundColor: kColorPrimaryDark, foregroundColor: kColorTextOnPrimary, elevation: 2,),
      body: Form( key: _formKey,
        child: SingleChildScrollView( padding: const EdgeInsets.all(16.0),
          child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text( "Event Details", style: GoogleFonts.poppins( fontSize: 20, fontWeight: FontWeight.w600, color: kColorPrimaryDark),),
              const SizedBox(height: 16),

              // --- Gig Type ---
              DropdownButtonFormField<String>( value: _selectedGigType, items: _gigTypes.map((String type) => DropdownMenuItem<String>( value: type, child: Text(type), )).toList(),
                onChanged: (String? newValue) { setState(() { _selectedGigType = newValue; }); },
                decoration: inputDecorationHelper('Gig Type / Occasion', Icons.celebration_outlined),
                validator: (value) => value == null ? 'Please select a gig type' : null, ),
              const SizedBox(height: 16),

              // --- Location ---
              TextFormField( controller: _locationController, decoration: inputDecorationHelper('Event Location Address', Icons.location_on_outlined),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter the event location' : null, textCapitalization: TextCapitalization.words,),
              const SizedBox(height: 16),

              // --- Date & Time Row ---
              Row( children: [
                  // Date Picker
                  Expanded( child: InkWell( onTap: () => _selectDate(context),
                      child: InputDecorator(
                        decoration: inputDecorationHelper('Date', Icons.calendar_today_outlined).copyWith(
                          // **** NEW: Show red border if _showDateError is true ****
                          enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(kRadiusMedium), borderSide: BorderSide(color: _showDateError ? Colors.red.shade700 : kColorDivider, width: _showDateError ? 1.5 : 1.0),),
                          focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(kRadiusMedium), borderSide: BorderSide(color: _showDateError ? Colors.red.shade700 : kColorPrimary, width: 1.5),),
                        ),
                        child: Text( _selectedDate == null ? 'Select Date' : DateFormat('EEE, MMM d, yyyy').format(_selectedDate!),
                           style: TextStyle(color: _selectedDate == null ? kColorTextSecondary : kColorTextPrimary, fontSize: 16) ), ), ), ),
                  const SizedBox(width: 12),
                   // Time Picker
                  Expanded( child: InkWell( onTap: () => _selectTime(context),
                       child: InputDecorator(
                        decoration: inputDecorationHelper('Time', Icons.access_time_outlined).copyWith(
                          // **** NEW: Show red border if _showTimeError is true ****
                           enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(kRadiusMedium), borderSide: BorderSide(color: _showTimeError ? Colors.red.shade700 : kColorDivider, width: _showTimeError ? 1.5 : 1.0),),
                           focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(kRadiusMedium), borderSide: BorderSide(color: _showTimeError ? Colors.red.shade700 : kColorPrimary, width: 1.5),),
                        ),
                        child: Text( _selectedTime == null ? 'Select Time' : _selectedTime!.format(context),
                           style: TextStyle(color: _selectedTime == null ? kColorTextSecondary : kColorTextPrimary, fontSize: 16) ), ), ), ), ], ),

              // **** NEW: Conditional Error Text Display ****
              if (_showDateError)
                 Padding( padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                   child: Text( 'Date is required', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),),),
              if (_showTimeError)
                 Padding( padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                    child: Text( 'Time is required', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),),),
              // **** END NEW ****

              const SizedBox(height: 16),

              // --- Number of People ---
              if (_numberOfPeopleOptions.isNotEmpty) ...[
                DropdownButtonFormField<String>( value: _selectedNumPeopleKey, items: _numberOfPeopleOptions.map((String key) => DropdownMenuItem<String>( value: key, child: Text(_formatPeopleOption(key)), )).toList(),
                  onChanged: (String? newValue) { setState(() { _selectedNumPeopleKey = newValue; _calculateAndUpdatePrice(newValue); }); },
                  decoration: inputDecorationHelper('Number of Guests', Icons.people_outline),
                  validator: (value) => value == null ? 'Please select the number of guests' : null, ),
              ] else ...[ // Show message if pricing options are unavailable
                 Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                   decoration: BoxDecoration( border: Border.all(color: Colors.orange.shade200), borderRadius: BorderRadius.circular(kRadiusMedium), color: Colors.orange.shade50,),
                   child: Row( children: [ Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 18), const SizedBox(width: 8),
                        Expanded( child: Text( "Guest pricing options are not available for this chef.", style: TextStyle(color: Colors.orange.shade900, fontStyle: FontStyle.italic),),),], ), ), ],
               const SizedBox(height: 16),

              // --- Calculated Price Display ---
              Container( padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: kColorPrimaryLightest.withAlpha((0.3 * 255).toInt()),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  border: Border.all(color: kColorPrimaryLight.withAlpha((0.5 * 255).toInt())),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Estimated Price:",
                      style: GoogleFonts.poppins(fontSize: 16, color: kColorTextSecondary),
                    ),
                    Text(
                      _calculatedPrice == null ? "Select Guests" : 'ugx ${_calculatedPrice!.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _calculatedPrice == null ? kColorTextSecondary : kColorPrimaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Detailed Description ---
              TextFormField(
                controller: _descriptionController,
                decoration: inputDecorationHelper('Additional Details (Optional)', Icons.notes_outlined, isDense: false).copyWith(
                  hintText: 'Any specific requests, dietary needs, or event notes...',
                ),
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 30), // Extra space
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea( child: buildConfirmButton(
        isLoading: _isLoading,
        calculatedPrice: _calculatedPrice,
        onSubmit: _submitGig,
      ), ),
    );
  }
}