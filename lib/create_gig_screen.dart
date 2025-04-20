// create_gig_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // For date/time formatting
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/cart.dart' as cart; // Use prefix

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
  String? _selectedNumPeopleKey; // e.g., "5_people", "10_people"
  double? _calculatedPrice; // Stores the calculated price

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isLoading = false; // For submit button loading state

  // Extracted Pricing Info
  Map<String, dynamic>? _perGigPricing;
  List<String> _numberOfPeopleOptions = []; // List of keys like "5_people"

  // Standard Gig Types (customize as needed)
  final List<String> _gigTypes = [
    'Birthday Party',
    'Anniversary Dinner',
    'Thanksgiving Feast',
    'Corporate Meeting',
    'Private Celebration',
    'Holiday Gathering',
    'Other Special Event',
  ];

  @override
  void initState() {
    super.initState();
    _extractPricingOptions();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _extractPricingOptions() {
    final pricingData = widget.chefData['pricing'] as Map<String, dynamic>?;
    _perGigPricing = pricingData?['per_gig'] as Map<String, dynamic>?;

    if (_perGigPricing != null && _perGigPricing!.isNotEmpty) {
      _numberOfPeopleOptions = _perGigPricing!.keys.toList();

      // Sort options numerically for better display
      _numberOfPeopleOptions.sort((a, b) {
        final numA = int.tryParse(a.split('_').first) ?? 0;
        final numB = int.tryParse(b.split('_').first) ?? 0;
        return numA.compareTo(numB);
      });
    } else {
      // Handle case where per_gig pricing is missing or empty
      print("Warning: 'per_gig' pricing data is missing or empty for this chef.");
      _numberOfPeopleOptions = []; // Ensure it's empty
    }
  }

  // --- Date Picker ---
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)), // Default to tomorrow
      firstDate: DateTime.now(), // Cannot book in the past
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)), // Allow booking 2 years ahead
      builder: (context, child) { // Optional: Theming the picker
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: kColorPrimary, // header background color
                onPrimary: kColorTextOnPrimary, // header text color
                onSurface: kColorTextPrimary, // body text color
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: kColorPrimary, // button text color
                ),
              ),
            ),
            child: child!,
          );
        },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // --- Time Picker ---
  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
       builder: (context, child) { // Optional: Theming the picker
          return Theme(
            data: Theme.of(context).copyWith(
               colorScheme: const ColorScheme.light(
                 primary: kColorPrimary,
                 onPrimary: kColorTextOnPrimary,
                 onSurface: kColorTextPrimary,
               ),
              timePickerTheme: TimePickerThemeData(
                 // Customize further if needed
                 dialHandColor: kColorPrimaryLight,
                 hourMinuteTextColor: MaterialStateColor.resolveWith((states) =>
                      states.contains(MaterialState.selected) ? kColorPrimaryDark : kColorTextSecondary),
                  hourMinuteColor: MaterialStateColor.resolveWith((states) =>
                      states.contains(MaterialState.selected) ? kColorPrimaryLightest : Colors.grey.shade200),
              ),
            ),
            child: child!,
          );
        },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  // --- Price Calculation ---
  void _calculateAndUpdatePrice(String? selectedKey) {
    if (selectedKey == null || _perGigPricing == null || !_perGigPricing!.containsKey(selectedKey)) {
      setState(() {
        _calculatedPrice = null; // Reset price if selection is invalid
      });
      return;
    }
    setState(() {
      _calculatedPrice = (_perGigPricing![selectedKey] as num?)?.toDouble();
    });
  }

  // --- Form Submission ---
  Future<void> _submitGig() async {
    print("DEBUG: _submitGig started."); // Log: Start of function
    // 1. Validate Form
    if (!_formKey.currentState!.validate()) {
      print("DEBUG: Form validation failed."); // Log: Validation fail
      _showErrorSnackBar("Please fill in all required fields correctly.");
      return;
    }
    // Extra validation for date/time (since they aren't FormFields)
    if (_selectedDate == null) {
      print("DEBUG: Date validation failed."); // Log: Validation fail
      _showErrorSnackBar("Please select a date for the gig.");
      return;
    }
     if (_selectedTime == null) {
      print("DEBUG: Time validation failed."); // Log: Validation fail
      _showErrorSnackBar("Please select a time for the gig.");
      return;
    }
     if (_calculatedPrice == null || _calculatedPrice! <= 0) {
       print("DEBUG: Price validation failed."); // Log: Validation fail
       _showErrorSnackBar("Could not calculate price. Please select number of guests.");
       return;
     }

    print("DEBUG: All validations passed. Setting loading state."); // Log: Validation success
    setState(() { _isLoading = true; });

    try {
      print("DEBUG: Inside try block. Getting SharedPreferences..."); // Log: Entering try
      // 2. Get User ID
      final prefs = await SharedPreferences.getInstance();
      print("DEBUG: SharedPreferences instance obtained."); // Log: Prefs obtained
      print("DEBUG: Attempting to read 'user_id' from SharedPreferences..."); // Log: Before reading user_id
      // final userId = prefs.getString('user_id'); // <<< THIS IS THE LIKELY ERROR LOCATION
      // --- CORRECTED CODE ---
      final userId = prefs.getInt('user_id'); // Use getInt()
      print("DEBUG: Read 'user_id'. Value: $userId, Type: ${userId.runtimeType}"); // Log: After reading user_id

      // if (userId == null || userId.isEmpty) { // Old check for String
      if (userId == null) { // Correct check for int?
         print("DEBUG: User ID is null. Aborting submission."); // Log: User ID null
         // This check should ideally happen before showing the booking button,
         // but double-check here.
        _showErrorSnackBar("Login error. Please log in again.", showLoginAction: true);
        setState(() { _isLoading = false; });
        return;
      }
      print("DEBUG: User ID check passed. User ID: $userId"); // Log: User ID valid

      print("DEBUG: Constructing gigDetails map..."); // Log: Before map construction
      // 3. Construct Gig Details Map
      final gigDetails = {
        'user_id': userId,
        'chef_id': widget.chefData['chefid'], // Passed via constructor
        'producer_id': null, // Explicitly null for chef booking
        'gig_type': _selectedGigType,
        'location': _locationController.text.trim(),
        'scheduled_date': DateFormat('yyyy-MM-dd').format(_selectedDate!), // Format date
        'time': _selectedTime!.format(context), // Format time
        'estimated_duration': null, // Not collected in this form, add if needed
        'number_of_people': _selectedNumPeopleKey, // The key, e.g., "10_people"
        'price': _calculatedPrice, // The calculated price
        'detailed_description': _descriptionController.text.trim(),
      };
      print("DEBUG: gigDetails map constructed: $gigDetails"); // Log: After map construction

      print("DEBUG: Calling ShoppingCart.addGig..."); // Log: Before adding to cart
      // 4. Add to Cart (using your static method)
      cart.ShoppingCart.addGig(gigDetails);
      print("DEBUG: ShoppingCart.addGig called successfully."); // Log: After adding to cart

      // 5. Show Success and Navigate Back
      print("DEBUG: Showing success SnackBar and navigating back."); // Log: Success path
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_selectedGigType ?? 'Gig'} booked successfully!'),
          backgroundColor: kColorAccent,
          duration: const Duration(seconds: 3),
           behavior: SnackBarBehavior.floating,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
           margin: const EdgeInsets.all(10),
        ),
      );
      // Ensure navigation happens only if the widget is still mounted
      if (mounted) {
         Navigator.of(context).pop(); // Go back to the chef detail screen
      }

    } catch (e, stackTrace) { // Capture stack trace for more details
      print("DEBUG: Error caught in _submitGig."); // Log: Error caught
      print("Error submitting gig: $e");
      print("Stack trace: $stackTrace"); // Log: Print stack trace
      _showErrorSnackBar("An unexpected error occurred. Please try again.");
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  void _showErrorSnackBar(String message, {bool showLoginAction = false}) {
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: Colors.red.shade700,
          action: showLoginAction ? SnackBarAction(label: 'Log In', onPressed: () {
             // TODO: Navigate to login screen
          }) : null,
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSmall)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  // Helper to format the number of people option for display
  String _formatPeopleOption(String key) {
    // Example: "5_people" -> "5 People"
    // Example: "20_plus_people" -> "20+ People"
    return key
      .replaceAll('_', ' ')
      .replaceAll('plus', '+')
      .split(' ')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    String chefName = widget.chefData['name'] ?? 'Selected Chef';

    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: Text('Book Gig with $chefName'),
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 2,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Event Details",
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: kColorPrimaryDark),
              ),
              const SizedBox(height: 16),

              // --- Gig Type ---
              DropdownButtonFormField<String>(
                value: _selectedGigType,
                items: _gigTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGigType = newValue;
                  });
                },
                decoration: _inputDecoration('Gig Type / Occasion', Icons.celebration_outlined),
                validator: (value) => value == null ? 'Please select a gig type' : null,
              ),
              const SizedBox(height: 16),

              // --- Location ---
              TextFormField(
                controller: _locationController,
                decoration: _inputDecoration('Event Location Address', Icons.location_on_outlined),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Please enter the event location'
                    : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),

              // --- Date & Time Row ---
              Row(
                children: [
                  // Date Picker
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context),
                      child: InputDecorator(
                        decoration: _inputDecoration('Date', Icons.calendar_today_outlined)
                                     .copyWith(errorText: _selectedDate == null ? '' : null), // Handle validation display slightly differently
                        child: Text(
                          _selectedDate == null
                              ? 'Select Date'
                              : DateFormat('EEE, MMM d, yyyy').format(_selectedDate!),
                           style: TextStyle(color: _selectedDate == null ? kColorTextSecondary : kColorTextPrimary, fontSize: 16)
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                   // Time Picker
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(context),
                       child: InputDecorator(
                        decoration: _inputDecoration('Time', Icons.access_time_outlined)
                                     .copyWith(errorText: _selectedTime == null ? '' : null),
                        child: Text(
                          _selectedTime == null
                              ? 'Select Time'
                              : _selectedTime!.format(context), // Localized format
                           style: TextStyle(color: _selectedTime == null ? kColorTextSecondary : kColorTextPrimary, fontSize: 16)
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Manual validation message display for date/time
               if (_formKey.currentState?.validate() == false && (_selectedDate == null || _selectedTime == null))
                 Padding(
                   padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                   child: Text(
                     _selectedDate == null ? 'Date is required' : 'Time is required',
                     style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                   ),
                 ),

              const SizedBox(height: 16),

              // --- Number of People ---
              if (_numberOfPeopleOptions.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: _selectedNumPeopleKey,
                  items: _numberOfPeopleOptions.map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(_formatPeopleOption(key)), // Display formatted text
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedNumPeopleKey = newValue;
                       _calculateAndUpdatePrice(newValue); // Recalculate price on change
                    });
                  },
                  decoration: _inputDecoration('Number of Guests', Icons.people_outline),
                  validator: (value) => value == null ? 'Please select the number of guests' : null,
                ),
              ] else ...[
                // Show message if pricing options are unavailable
                 Padding(
                   padding: const EdgeInsets.symmetric(vertical: 8.0),
                   child: Text(
                     "Guest pricing options are not available for this chef.",
                      style: TextStyle(color: Colors.orange.shade800, fontStyle: FontStyle.italic),
                   ),
                 ),
              ],
              const SizedBox(height: 16),

              // --- Calculated Price Display ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Estimated Price:",
                    style: GoogleFonts.poppins(fontSize: 16, color: kColorTextSecondary),
                  ),
                  Text(
                    _calculatedPrice == null ? "Select Guests" : '\$${_calculatedPrice!.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _calculatedPrice == null ? kColorTextSecondary : kColorPrimaryDark),
                  ),
                ],
              ),
              const SizedBox(height: 20),

               // --- Detailed Description ---
               TextFormField(
                controller: _descriptionController,
                decoration: _inputDecoration(
                  'Additional Details (Optional)',
                  Icons.notes_outlined,
                  isDense: false, // Allow more vertical space
                ).copyWith(
                  hintText: 'Any specific requests, dietary needs, or event notes...'
                ),
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                 // No validator needed as it's optional
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildConfirmButton(),
    );
  }

   // Helper for consistent InputDecoration
  InputDecoration _inputDecoration(String label, IconData icon, {bool isDense = true}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: kColorPrimary, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusMedium)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
        borderSide: BorderSide(color: kColorDivider, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMedium),
        borderSide: const BorderSide(color: kColorPrimary, width: 1.5),
      ),
       isDense: isDense,
       contentPadding: isDense ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
                              : const EdgeInsets.symmetric(horizontal: 12, vertical: 16) ,
    );
  }

   // Bottom Confirmation Button
  Widget _buildConfirmButton() {
    bool canSubmit = _calculatedPrice != null && _calculatedPrice! > 0; // Basic check

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: kColorSurface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -3))
        ],
      ),
      child: ElevatedButton.icon(
        icon: _isLoading
            ? Container(
                width: 20,
                height: 20,
                padding: const EdgeInsets.all(2.0),
                child: const CircularProgressIndicator(
                  color: kColorTextOnPrimary,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.check_circle_outline_rounded, size: 20),
        label: Text(_isLoading ? 'Booking...' : 'Confirm Gig Booking'),
        style: ElevatedButton.styleFrom(
          backgroundColor: canSubmit ? kColorPrimaryDark : Colors.grey.shade500,
          foregroundColor: kColorTextOnPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMedium)),
          textStyle: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        onPressed: (_isLoading || !canSubmit) ? null : _submitGig, // Disable if loading or cannot submit
      ),
    );
  }
}