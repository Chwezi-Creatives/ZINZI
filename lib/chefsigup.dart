import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Import for TimeoutException
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/verification.dart'; // Assuming this is your verification page

// --- Hardcoded Colors ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color lighterTeal = Color(0xFFE0F2F1); // Teal 50
const Color darkTeal = Color(0xFF004D40); // Teal 900
const Color accentTeal = Color(0xFF009688); // Teal 500
const Color whiteColor = Colors.white;
const Color lightBackgroundColor = Color(0xFFF5F5F5); // Very light grey/white
const Color textFieldFillColor = Color(0x8AFFFFFF); // Semi-transparent white
const Color subtleTextColor = Color(0xFF757575); // Grey 600
const Color errorColor = Color(0xFFD32F2F); // Red 700 for errors
const Color disabledColor = Colors.grey; // For disabled elements

// --- API Base URL ---
final String apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
final String? imgurClientId =
    dotenv.env['IMGUR_CLIENT_ID']; // Add your Imgur Client ID to .env

class ChefSignUpPage extends StatefulWidget {
  const ChefSignUpPage({super.key});

  @override
  _ChefSignUpPageState createState() => _ChefSignUpPageState();
}

class _ChefSignUpPageState extends State<ChefSignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _locationDisplayController =
      TextEditingController(); // For display only

  bool _isLoading = false; // General loading state for signup
  bool _isFetchingLocation = false; // Specific state for location fetching
  bool _isUploadingImage = false; // Specific state for image uploading

  File? _profileImageFile; // The selected image file
  String? _uploadedImageUrl; // The URL after uploading (e.g., to Imgur)

  String _locationCoordinates = ''; // Stores "lat,lon"
  String _humanReadableAddress = ''; // Stores the address string

  final ImagePicker _picker = ImagePicker(); // Instance of Image Picker

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneNumberController.dispose();
    _locationDisplayController.dispose();
    super.dispose();
  }

  // Save user details in SharedPreferences
  Future<void> saveUserDetails(String userId, String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('chef_user_id', userId);
    await prefs.setString('chef_user_type', userType);
    print('Chef details saved: ID $userId, Type $userType'); // Debug log
  }

  // --- Image Picking ---
  Future<void> _pickImage(ImageSource source) async {
    if (_isUploadingImage) return; // Prevent picking while uploading

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70, // Compress image slightly
        maxWidth: 800, // Resize image
      );

      if (pickedFile != null) {
        setState(() {
          _profileImageFile = File(pickedFile.path);
          _uploadedImageUrl = null; // Reset uploaded URL if new image is picked
        });
        // Immediately try to upload after picking
        _uploadToImgur();
      }
    } catch (e) {
      print("Image picking error: $e");
      _showSnackBar("Failed to pick image. Please try again.", isError: true);
    }
  }

  // --- Show Image Source Options ---
  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15.0)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library, color: primaryTeal),
                title: const Text('Gallery', style: TextStyle(color: darkTeal)),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: primaryTeal),
                title: const Text('Camera', style: TextStyle(color: darkTeal)),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Upload to Imgur ---
  Future<void> _uploadToImgur() async {
    if (_profileImageFile == null) return;
    if (imgurClientId == null || imgurClientId!.isEmpty) {
      _showSnackBar("Image upload configuration missing.", isError: true);
      // Allow signup without image if upload isn't configured? Or enforce it?
      // For now, we just warn and don't set _isUploadingImage.
      // If image is REQUIRED, you might want to prevent signup here.
      print("Warning: Imgur Client ID not configured in .env");
      return; // Or handle differently if image is mandatory
    }

    setState(() => _isUploadingImage = true);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.imgur.com/3/image'),
      );
      request.headers['Authorization'] = 'Client-ID $imgurClientId';
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          _profileImageFile!.path,
        ),
      );

      // Add timeout to the request
      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 30)); // 30 second timeout for upload
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['data'] != null &&
            responseData['data']['link'] != null) {
          setState(() {
            _uploadedImageUrl = responseData['data']['link'];
            _isUploadingImage = false;
          });
          _showSnackBar("Profile image uploaded successfully!", isError: false);
        } else {
          throw Exception('Imgur upload failed: Invalid response structure.');
        }
      } else {
        throw Exception(
            'Imgur upload failed: ${response.statusCode} ${response.body}');
      }
    } on TimeoutException catch (_) {
      print("Imgur upload timeout");
      setState(() => _isUploadingImage = false);
      _showSnackBar("Image upload timed out. Please try again.", isError: true);
    } catch (e) {
      print("Imgur upload error: $e");
      setState(() => _isUploadingImage = false);
      _showSnackBar("Failed to upload image. Please try again.", isError: true);
    }
  }

  // --- Location Fetching ---
  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return; // Prevent multiple requests

    setState(() => _isFetchingLocation = true);
    // Clear previous values while fetching// --- Location Fetching --- (Continuing from previous part)
    _locationDisplayController.clear();
    _locationCoordinates = '';
    _humanReadableAddress = '';

    LocationPermission permission;
    bool serviceEnabled;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Location services are disabled. Please enable them.',
            isError: true);
        setState(() => _isFetchingLocation = false);
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied.', isError: true);
          setState(() => _isFetchingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar(
            'Location permission permanently denied. Please enable in settings.',
            isError: true);
        setState(() => _isFetchingLocation = false);
        // Optionally, offer to open app settings here
        return;
      }

      // Fetch position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15) // Add a timeout
          );

      _locationCoordinates = "${position.latitude}, ${position.longitude}";

      // Reverse Geocode (using a free service - consider rate limits/alternatives)
      try {
        // Using geocode.maps.co as in the original example
        final String geocodeUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http
            .get(Uri.parse(geocodeUrl))
            .timeout(const Duration(seconds: 10)); // Geocoding timeout

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _humanReadableAddress = data['display_name'] ?? 'Address not found';
        } else {
          _humanReadableAddress = 'Could not fetch address';
          print("Reverse geocode error: ${response.statusCode}");
          _showSnackBar('Could not fetch readable address. Using coordinates.',
              isError: true);
        }
      } catch (e) {
        _humanReadableAddress = 'Could not fetch address';
        print("Reverse geocode exception: $e");
        _showSnackBar('Could not fetch readable address. Using coordinates.',
            isError: true);
      }

      setState(() {
        // Display address or fallback to coordinates if address fetch failed
        _locationDisplayController.text = _humanReadableAddress.isNotEmpty &&
                _humanReadableAddress != 'Could not fetch address'
            ? _humanReadableAddress
            : 'Location Acquired (${_locationCoordinates})';
        _isFetchingLocation = false;
      });
      _showSnackBar('Location acquired successfully!', isError: false);
    } on TimeoutException catch (_) {
      _showSnackBar('Getting location timed out. Please try again.',
          isError: true);
      setState(() => _isFetchingLocation = false);
    } catch (e) {
      print("Location error: $e");
      _showSnackBar('Error getting location. Please try again.', isError: true);
      setState(() {
        _isFetchingLocation = false;
        _locationDisplayController.text =
            'Failed to get location'; // Indicate failure in field
      });
    }
  }

  // --- Form Submission (Chef Sign Up) ---
  Future<void> _signUp() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fill all required fields correctly.',
          isError: true);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    // Check if location was acquired
    if (_locationCoordinates.isEmpty) {
      _showSnackBar('Please acquire your location using the button.',
          isError: true);
      return;
    }

    // Check if image is still uploading (if an image was selected)
    if (_profileImageFile != null && _isUploadingImage) {
      _showSnackBar('Profile image is still uploading. Please wait.',
          isError: true);
      return;
    }
    // Optional: Check if upload failed and image is required
    // if (_profileImageFile != null && _uploadedImageUrl == null && !_isUploadingImage) {
    //    _showSnackBar('Profile image upload failed. Please try uploading again.', isError: true);
    //    // Optionally trigger retry: await _uploadToImgur(); if(_uploadedImageUrl == null) return;
    //    return;
    // }

    setState(() {
      _isLoading = true; // Show loading indicator on button
    });

    try {
      final Uri signupUri =
          Uri.parse('$apibaseurl/rr/achef'); // Chef signup endpoint

      final response = await http
          .post(
            signupUri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'Name': _nameController.text.trim(),
              'Email': _emailController.text.trim().toLowerCase(),
              'Hashed_Password': _passwordController
                  .text, // Send plain text, backend should hash
              'Phone_Number': _phoneNumberController.text.trim(),
              // Combine human-readable address and coordinates
              'Location': _humanReadableAddress.isNotEmpty &&
                      _humanReadableAddress != 'Could not fetch address'
                  ? "$_humanReadableAddress ($_locationCoordinates)"
                  : _locationCoordinates, // Fallback to just coordinates
              'Image': _uploadedImageUrl ??
                  '', // Send Imgur URL or empty string if none/failed
            }),
          )
          .timeout(const Duration(seconds: 20)); // Network request timeout

      if (response.statusCode == 201) {
        // Chef creation successful
        // --- SUCCESS ---
        final responseBody = json.decode(response.body);
        // Ensure the keys match your backend response
        final userId = responseBody['id']?.toString();
        final userType = responseBody['type']?.toString();

        if (userId != null && userType != null) {
          await saveUserDetails(userId, userType);
          _showSnackBar('Sign up successful! Redirecting to verification.',
              isError: false);
          // Navigate to verification page
          Navigator.pushReplacement(
            // Use pushReplacement so user can't go back to signup
            context,
            MaterialPageRoute(
                builder: (context) =>
                    const EmailVerificationPage()), // Ensure VerificationPage exists
          );
        } else {
          print(
              "Error: Missing 'id' or 'type' in response body: ${response.body}");
          _showSnackBar(
              'Sign up partially successful, but failed to retrieve user details.',
              isError: true);
        }
      } else {
        // --- FAILURE ---
        String errorMessage = 'Sign up failed. Please try again.';
        try {
          final responseData = json.decode(response.body);
          errorMessage =
              responseData['message'] ?? responseData['error'] ?? errorMessage;
        } catch (_) {
          // Handle cases where response body is not valid JSON or empty
          errorMessage =
              'Sign up failed (Code: ${response.statusCode}). Please try again.';
          print(
              "Signup failed with status code ${response.statusCode}. Response: ${response.body}");
        }
        _showSnackBar(errorMessage, isError: true);
      }
    } on TimeoutException catch (_) {
      _showSnackBar(
          'The request timed out. Please check your connection and try again.',
          isError: true);
    } catch (error) {
      print("Signup exception: $error");
      _showSnackBar(
          'An unexpected error occurred during sign up. Please try again later.',
          isError: true);
    } finally {
      // Ensure loading indicator is always turned off
      if (mounted) {
        // Check if the widget is still in the tree
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Helper for SnackBar ---
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return; // Don't show snackbar if widget is disposed
    ScaffoldMessenger.of(context)
        .removeCurrentSnackBar(); // Remove previous snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: whiteColor)),
        backgroundColor: isError ? errorColor : accentTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(15),
        duration:
            Duration(seconds: isError ? 4 : 3), // Longer duration for errors
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Become A Chef',
            style: TextStyle(color: whiteColor, fontWeight: FontWeight.w600)),
        backgroundColor: primaryTeal,
        elevation: 1.0,
        iconTheme: const IconThemeData(color: whiteColor),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 10),
                // --- Profile Image Picker ---
                _buildProfileImagePicker(),
                const SizedBox(height: 30),

                // --- Chef Name ---
                _buildTextFormField(
                  controller: _nameController,
                  labelText: "Chef Name",
                  hintText: "Enter your full name",
                  icon: Icons.person_outline,
                  validator: (value) => (value == null || value.isEmpty)
                      ? "Enter your name"
                      : null,
                ),
                const SizedBox(height: 16),

                // --- Email ---
                _buildTextFormField(
                  controller: _emailController,
                  labelText: "Email Address",
                  hintText: "your.email@example.com",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return "Enter email";
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(value)) {
                      return "Enter a valid email address";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- Password ---
                _buildTextFormField(
                  controller: _passwordController,
                  labelText: "Password",
                  hintText: "Choose a strong password",
                  icon: Icons.lock_outline,
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return "Enter password";
                    if (value.length < 6) {
                      return "Password must be at least 6 characters";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- Confirm Password ---
                _buildTextFormField(
                  controller: _confirmPasswordController,
                  labelText: "Confirm Password",
                  hintText: "Re-enter your password",
                  icon: Icons.lock_outline,
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Confirm password";
                    }
                    if (value != _passwordController.text) {
                      return "Passwords do not match";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- Phone Number ---
                _buildTextFormField(
                  controller: _phoneNumberController,
                  labelText: "Phone Number",
                  hintText: "Enter your contact number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Enter phone number";
                    }
                    // Basic phone number validation (optional)
                    // if (!RegExp(r'^\+?[0-9]{10,}$').hasMatch(value)) {
                    //   return "Enter a valid phone number";
                    // }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- Location Field (Read-only + Button) ---
                GestureDetector(
                  // AbsorbPointer prevents taps on the text field itself,
                  // but the GestureDetector captures taps on the whole area.
                  onTap: _isFetchingLocation ? null : _getCurrentLocation,
                  child: AbsorbPointer(
                    child: _buildLocationField(),
                  ),
                ),
                const SizedBox(height: 30),

                // --- Sign Up Button ---
                _buildSignUpButton(),
                const SizedBox(height: 20), // Space at the bottom
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Reusable TextFormField Builder (Copied from Producer) ---
  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      style: const TextStyle(color: darkTeal), // Input text color
      decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          labelStyle:
              const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          hintStyle: const TextStyle(color: subtleTextColor, fontSize: 14),
          prefixIcon: Icon(icon, color: primaryTeal, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: textFieldFillColor, // Semi-transparent white fill
          // Border styles
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: lightTeal, width: 1.0), // Default border
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: lightTeal, width: 1.0), // Border when enabled
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: primaryTeal, width: 1.5), // Border when focused
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: errorColor, width: 1.0), // Border on error
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: errorColor, width: 1.5), // Border on error + focused
          ),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 14.0, horizontal: 16.0), // Inner padding
          errorStyle: const TextStyle(
              color: errorColor, fontSize: 11)), // Error text style
      validator: validator,
    );
  }

  // --- Location Field Specific Builder (Adapted from Producer) ---
  Widget _buildLocationField() {
    return AnimatedOpacity(
      opacity: _isFetchingLocation ? 0.6 : 1.0, // Fade slightly when fetching
      duration: const Duration(milliseconds: 300),
      child: TextFormField(
        controller: _locationDisplayController,
        readOnly: true, // Make it read-only
        style: const TextStyle(color: darkTeal, fontSize: 14),
        decoration: InputDecoration(
            labelText: "Your Location",
            labelStyle: const TextStyle(
                color: primaryTeal, fontWeight: FontWeight.w500),
            hintText: _isFetchingLocation
                ? "Acquiring location..."
                : "Tap icon to get current location",
            hintStyle: const TextStyle(
                color: subtleTextColor,
                fontStyle: FontStyle.italic,
                fontSize: 14),
            prefixIcon: const Icon(Icons.location_on_outlined,
                color: primaryTeal, size: 20),
            filled: true,
            fillColor: textFieldFillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: lightTeal, width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: lightTeal, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: primaryTeal, width: 1.5), // Keep focus style
            ),
            errorBorder: OutlineInputBorder(
              // Add error border style
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: errorColor, width: 1.0),
            ),
            focusedErrorBorder: OutlineInputBorder(
              // Add focused error border style
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: errorColor, width: 1.5),
            ),
            contentPadding: const EdgeInsets.fromLTRB(
                16.0, 14.0, 0.0, 14.0), // Adjust padding for icon
            suffixIcon: Padding(
              padding: const EdgeInsets.only(
                  right: 8.0), // Padding for the suffix icon
              child: IconButton(
                icon: _isFetchingLocation
                    ? const SizedBox(
                        // Show progress indicator inside button space
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.0, color: primaryTeal))
                    : const Icon(Icons.my_location_rounded,
                        color: accentTeal), // Location icon
                tooltip: 'Get Current Location',
                // Disable button while fetching
                onPressed: _isFetchingLocation ? null : _getCurrentLocation,
              ),
            ),
            errorStyle: const TextStyle(
                color: errorColor, fontSize: 11) // Error text style
            ),
        // Validator checks if coordinates are present (set after successful fetching)
        validator: (_) {
          // Use underscore as value is not needed
          if (_locationCoordinates.isEmpty && !_isFetchingLocation) {
            // Only show error if not currently fetching
            return 'Please acquire your location';
          }
          return null;
        },
      ),
    );
  }

  // --- Profile Image Picker Widget (Copied from Producer) ---
  Widget _buildProfileImagePicker() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The main circle avatar
          Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: lightTeal, width: 2), // Teal border
                boxShadow: [
                  // Subtle shadow for depth
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]),
            child: CircleAvatar(
              radius: 60, // Size of the avatar
              backgroundColor: lighterTeal, // Light teal background
              // Display the selected image file if available
              backgroundImage: _profileImageFile != null
                  ? FileImage(_profileImageFile!)
                  : null,
              // Show person icon if no image and not uploading
              child: _profileImageFile == null && !_isUploadingImage
                  ? const Icon(Icons.person_add_alt_1,
                      size: 50, color: primaryTeal) // Changed icon slightly
                  : null, // Otherwise, show nothing (backgroundImage will be used)
            ),
          ),
          // Loading indicator overlay (shows during upload)
          if (_isUploadingImage)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5), // Dark overlay
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                        whiteColor), // White spinner
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          // Edit/Upload button overlay (pencil icon)
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: primaryTeal, // Teal background for the button
              shape: const CircleBorder(),
              elevation: 3.0, // Button shadow
              child: InkWell(
                onTap: _isUploadingImage
                    ? null
                    : _showImageSourceActionSheet, // Disable tap during upload
                customBorder: const CircleBorder(),
                splashColor: lightTeal.withOpacity(0.5), // Splash effect on tap
                child: const Padding(
                  padding: EdgeInsets.all(8.0), // Padding inside the button
                  child: Icon(Icons.edit,
                      color: whiteColor, size: 20), // Edit icon
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Sign Up Button Builder (Adapted from Producer) ---
  Widget _buildSignUpButton() {
    // Determine if the button should be disabled
    final bool isDisabled =
        _isLoading || _isUploadingImage || _isFetchingLocation;

    return SizedBox(
      width: double.infinity, // Make button full width
      child: ElevatedButton(
        // Disable onPressed if any loading operation is in progress
        onPressed: isDisabled ? null : _signUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentTeal, // Button background color
          foregroundColor: whiteColor, // Text/Icon color
          padding: const EdgeInsets.symmetric(vertical: 14), // Button padding
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)), // Rounded corners
          elevation: isDisabled ? 0 : 2, // Remove shadow when disabled
          // Style for the disabled state
          disabledBackgroundColor: disabledColor.withOpacity(0.6),
          disabledForegroundColor: whiteColor.withOpacity(0.8),
        ),
        child: _isLoading // Show spinner if general signup is loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                ),
              )
            // Otherwise, show the text
            : const Text("Create Chef Account",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
