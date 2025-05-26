import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
// Make sure this import is correct
// import 'package:zinzi2/verification.dart';
// Placeholder for verification page if the above is wrong:
import 'package:flutter/cupertino.dart'; // Using Cupertino for placeholder
import 'package:shared_preferences/shared_preferences.dart';

// --- Placeholder Verification Page ---
class EmailVerificationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Verify Email")),
      body: Center(child: Text("Verification screen placeholder")),
    );
  }
}
// --- End Placeholder ---

// Assuming API_BASE_URL-intranet is set, provide a fallback
final apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://your.fallback.api.url';

// --- Color Palette (Teal Based) ---
const Color kColorPrimary = Color(0xFF00796B); // Teal Primary
const Color kColorPrimaryDark = Color(0xFF004D40); // Darker Teal
const Color kColorPrimaryLight = Color(0xFFB2DFDB); // Lighter Teal
const Color kColorAccent = Color(0xFFFFAB40); // Orange Accent (example)
const Color kColorBackground = Color(0xFFF5F5F5); // Light Grey Background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary = Color(0xFF757575);
const Color kColorError = Color(0xFFD32F2F);
const Color kColorDivider = Color(0xFFE0E0E0);
// --- End Color Palette ---

class StakeholderSignUpPage extends StatefulWidget {
  const StakeholderSignUpPage({super.key});

  @override
  _StakeholderSignUpPageState createState() => _StakeholderSignUpPageState();
}

class _StakeholderSignUpPageState extends State<StakeholderSignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _imageUrlController =
      TextEditingController(); // Keeps track of the uploaded URL
  final TextEditingController _phoneNumberController = TextEditingController();

  bool _isLoading = false; // For main sign-up process
  bool _isFetchingLocation = false; // Specific for location fetching
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  String locationCoordinates = '';
  String humanReadableAddress = '';
  File? _profileImage; // Holds the selected image file

  // --- Focus Nodes for keyboard navigation (Optional but good UX) ---
  final FocusNode _fullNameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  // ---

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _locationController.dispose();
    _imageUrlController.dispose();
    _phoneNumberController.dispose();
    _fullNameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  // --- Image Handling ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 70); // Add quality

      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
        // Optional: Immediately attempt upload or wait until final sign-up
        // For simplicity, we'll assume upload happens elsewhere or is mocked here.
        // String imageUrl = await uploadImageToServer(_profileImage!); // Uncomment if you have upload logic
        // _imageUrlController.text = imageUrl;
        _imageUrlController.text =
            "https://placeholder.com/profile.jpg"; // Placeholder/Mock URL
        _showSnackbar("Profile image selected.", success: true);
      }
    } catch (e) {
      _showSnackbar("Error picking image: $e");
    }
  }

  // Mock/Placeholder - Replace with your actual image upload logic
  Future<String> uploadImageToServer(File image) async {
    _showSnackbar("Uploading image (mock)...");
    await Future.delayed(const Duration(seconds: 2)); // Simulate network delay
    // Replace with actual API call to upload image and get URL
    return "https://your-server.com/uploads/${DateTime.now().millisecondsSinceEpoch}.jpg";
  }
  // --- End Image Handling ---

  // --- Location Handling ---
  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return; // Prevent concurrent calls

    setState(() {
      _isFetchingLocation = true;
    });
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackbar('Location services are disabled. Please enable them.');
        setState(() {
          _isFetchingLocation = false;
        });
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _showSnackbar('Location permissions are denied.');
          setState(() {
            _isFetchingLocation = false;
          });
          return;
        }
      }

      // Fetch position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15) // Add timeout
          );

      await _getHumanReadableAddress(position);
    } on TimeoutException {
      _showSnackbar('Location request timed out. Try again.');
    } catch (e) {
      _showSnackbar('Error getting location: $e');
    } finally {
      // Ensure loading state is always turned off
      if (mounted) {
        // Check if widget is still in the tree
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  Future<void> _getHumanReadableAddress(Position position) async {
    // Using geocode.maps.co (free, requires attribution if used heavily)
    // Consider using other services like OpenStreetMap Nominatim or a paid service if needed.
    final String apiUrl =
        'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}'; // Add API Key if you get one
    humanReadableAddress = "Fetching address..."; // Initial feedback
    locationCoordinates =
        "${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}"; // Format coords
    _locationController.text =
        humanReadableAddress; // Show fetching status immediately

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        humanReadableAddress = data['display_name'] ?? "Address not found";
        _showSnackbar("Location acquired!", success: true);
      } else {
        humanReadableAddress =
            "Unable to fetch address (Code: ${response.statusCode})";
        _showSnackbar(humanReadableAddress);
      }
    } catch (e) {
      humanReadableAddress = "Address lookup failed.";
      _showSnackbar("Error fetching address details.");
      debugPrint("Geocoding error: $e");
    } finally {
      // Update text field ONLY IF the widget is still mounted
      if (mounted) {
        setState(() {
          _locationController.text =
              "$humanReadableAddress ($locationCoordinates)";
        });
      }
    }
  }
  // --- End Location Handling ---

  // --- Sign Up Logic ---
  Future<void> _signUp() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showSnackbar("Please fix the errors in the form.");
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackbar('Passwords do not match.');
      return;
    }

    // Optional: Check if image was selected/uploaded
    if (_profileImage == null || _imageUrlController.text.isEmpty) {
      _showSnackbar('Please select a profile image.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate image upload if not done earlier
      if (_imageUrlController.text.startsWith("https://placeholder.com")) {
        // Only upload if it's still the placeholder and image exists
        if (_profileImage != null) {
          _imageUrlController.text = await uploadImageToServer(_profileImage!);
        } else {
          throw Exception(
              "Profile image missing for upload."); // Should have been caught earlier
        }
      }

      final response = await http
          .post(
            Uri.parse(
                '$apibaseurl/rr/create_stakeholders'), // Ensure endpoint is correct
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'Name': _usernameController.text.trim(),
              'Full_Name': _fullNameController.text.trim(),
              'Email': _emailController.text
                  .trim()
                  .toLowerCase(), // Send lowercase email
              'Password': _passwordController.text.trim(),
              // Sending both human-readable and coordinates might be useful
              'Location_Address': humanReadableAddress,
              'Location_Coordinates': locationCoordinates,
              'Image': _imageUrlController.text.trim(), // URL from upload
              'Phone_Number': _phoneNumberController.text.trim(),
              'Is_Active': true, // Default to active
              'Rating': 0, // Default rating
            }),
          )
          .timeout(const Duration(seconds: 20)); // Add timeout to the Future

      if (!mounted) return; // Check if widget is still mounted after await

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Allow 200 OK as well
        final responseData = json.decode(response.body);
        final stakeholderId =
            responseData['stakeholder_id']; // Adjust key if needed

        if (stakeholderId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'stakeholder_user_id', stakeholderId.toString());
          print(
              "Stakeholder ID saved: $stakeholderId"); // Optional: for debugging
          _showSnackbar("Sign up successful!", success: true);
          // Navigate to dashboard page
          Navigator.pushReplacement(
              // Use pushReplacement if you don't want user coming back here
              context,
              MaterialPageRoute(builder: (context) => EmailVerificationPage()));
        } else {
          _showSnackbar("Signup successful, but failed to retrieve user ID.");
          // Optionally navigate to login or show an error specific to missing ID
        }
      } else {
        // Try to parse error message from API
        String errorMessage = 'Signup failed. Please try again.';
        try {
          final errorResponse = json.decode(response.body);
          // Adjust keys based on your actual API error response structure
          errorMessage = errorResponse['message'] ??
              errorResponse['error'] ??
              'Signup failed (Code: ${response.statusCode})';
        } catch (e) {
          errorMessage =
              'Signup failed (Code: ${response.statusCode}). Invalid response from server.';
          debugPrint("Error parsing error response: ${response.body}");
        }
        _showSnackbar(errorMessage);
      }
    } on TimeoutException {
      _showSnackbar(
          'Request timed out. Please check your connection and try again.');
    } catch (error) {
      _showSnackbar('An error occurred: ${error.toString()}.');
      debugPrint("Signup error: $error");
    } finally {
      // Ensure loading state is always turned off if widget is mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  // --- End Sign Up Logic ---

  // --- Helper Methods ---
  void _showSnackbar(String message, {bool success = false}) {
    if (!mounted) return; // Don't show snackbar if widget is disposed
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: success ? Colors.green.shade600 : kColorError,
        behavior: SnackBarBehavior.floating, // More modern look
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon,
      {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: kColorTextSecondary),
      prefixIcon: Icon(icon, color: kColorPrimary, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: kColorSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: kColorDivider, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: kColorDivider, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: kColorPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: kColorError, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: kColorError, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
    );
  }
  // --- End Helper Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: Text('Create Stakeholder Account',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: kColorPrimary, // Themed AppBar
        foregroundColor: kColorSurface, // White title
        elevation: 2,
      ),
      body: SafeArea(
        // Ensure content avoids notches/status bars
        child: SingleChildScrollView(
          // Use SingleChildScrollView for forms
          padding: const EdgeInsets.all(20.0), // Generous padding
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch, // Make button full width
              children: [
                const SizedBox(height: 10),

                // --- Profile Image Picker ---
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 55, // Slightly larger
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: _profileImage != null
                            ? FileImage(_profileImage!)
                            : null,
                        child: _profileImage == null
                            ? const Icon(Icons.person_outline,
                                size: 50, color: kColorTextSecondary)
                            : null,
                      ),
                      Positioned(
                        // Edit button overlay
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: kColorPrimary,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            onTap: _pickImage,
                            customBorder: const CircleBorder(),
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(Icons.edit,
                                  size: 18, color: kColorSurface),
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // --- Input Fields ---
                TextFormField(
                  controller: _usernameController,
                  decoration:
                      _buildInputDecoration("Username", Icons.person_outline),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Please enter a username"
                      : null,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_fullNameFocus),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _fullNameController,
                  focusNode: _fullNameFocus,
                  decoration:
                      _buildInputDecoration("Full Name", Icons.badge_outlined),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? "Please enter your full name"
                      : null,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_phoneFocus),
                ),
                const SizedBox(height: 16),

                // --- Location Input ---
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start, // Align items top
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _locationController,
                        readOnly: true, // Make it clearly read-only
                        decoration: _buildInputDecoration(
                                "Location", Icons.location_on_outlined)
                            .copyWith(
                          hintText: "Tap button to get location",
                          fillColor: Colors.grey
                              .shade100, // Different background for read-only
                        ),
                        style: GoogleFonts.poppins(
                            color: kColorTextSecondary, fontSize: 14),
                        validator: (value) => (value == null ||
                                value.isEmpty ||
                                value == "Fetching address...")
                            ? "Please select a location"
                            : null,
                        maxLines: 2, // Allow address to wrap slightly
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Location Fetch Button
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 5), // Align button vertically
                      child: SizedBox(
                        height: 50, width: 50, // Make button squarish
                        child: ElevatedButton(
                          onPressed:
                              _isFetchingLocation ? null : _getCurrentLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kColorPrimaryLight,
                            foregroundColor: kColorPrimaryDark,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.zero, // Remove default padding
                            elevation: 1,
                          ),
                          child: _isFetchingLocation
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kColorPrimaryDark))
                              : const Icon(Icons.my_location_rounded, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneNumberController,
                  focusNode: _phoneFocus,
                  decoration: _buildInputDecoration(
                      "Phone Number", Icons.phone_outlined),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return "Please enter phone number";
                    // Basic phone number validation (optional)
                    // if (!RegExp(r'^\+?[0-9]{10,}$').hasMatch(value)) return "Enter a valid phone number";
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_emailFocus),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  decoration:
                      _buildInputDecoration("Email", Icons.email_outlined),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty)
                      return "Please enter your email";
                    // Basic email validation
                    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value))
                      return "Enter a valid email address";
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_passwordFocus),
                ),
                const SizedBox(height: 16),

                // --- Password ---
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: !_passwordVisible,
                  decoration: _buildInputDecoration(
                    "Password",
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: kColorTextSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return "Please enter a password";
                    if (value.length < 6)
                      return "Password must be at least 6 characters"; // Example length check
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context)
                      .requestFocus(_confirmPasswordFocus),
                ),
                const SizedBox(height: 16),

                // --- Confirm Password ---
                TextFormField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocus,
                  obscureText: !_confirmPasswordVisible,
                  decoration: _buildInputDecoration(
                    "Confirm Password",
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: kColorTextSecondary,
                        size: 20,
                      ),
                      onPressed: () => setState(() =>
                          _confirmPasswordVisible = !_confirmPasswordVisible),
                    ),
                  ),
                  style: GoogleFonts.poppins(color: kColorTextPrimary),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return "Please confirm your password";
                    if (value != _passwordController.text)
                      return "Passwords do not match";
                    return null;
                  },
                  textInputAction:
                      TextInputAction.done, // Done action for the last field
                  onFieldSubmitted: (_) =>
                      _isLoading ? null : _signUp(), // Trigger sign up on done
                ),
                const SizedBox(height: 30),

                // --- Sign Up Button ---
                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        kColorPrimaryDark, // Use darker primary for main action
                    foregroundColor: kColorSurface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    textStyle: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: kColorSurface,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text("Sign Up"),
                ),
                const SizedBox(height: 20), // Bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }
}
