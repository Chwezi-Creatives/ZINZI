import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for input formatters if needed
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Import for TimeoutException
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/produ_dash22.dart';
import 'notifications/fcm_service.dart';

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
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url/api';
final String? imgurClientId = dotenv.env['IMGUR_CLIENT_ID'];

class ProducerSignUpPage extends StatefulWidget {
  const ProducerSignUpPage({super.key});

  @override
  _ProducerSignUpPageState createState() => _ProducerSignUpPageState();
}

class _ProducerSignUpPageState extends State<ProducerSignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationDisplayController =
      TextEditingController(); // For display only
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false; // General loading state for signup
  bool _isFetchingLocation = false; // Specific state for location fetching
  bool _isUploadingImage = false; // Specific state for image uploading

  File? _profileImageFile; // The selected image file
  String? _uploadedImageUrl; // The URL after uploading to Imgur

  String _locationCoordinates = ''; // Stores "lat,lon"
  String _humanReadableAddress = ''; // Stores the address string

  // --- Producer Types ---
  final List<String> _producerTypes = [
    'Individual',
    'Company',
  ];
  String? _selectedProducerType; // Initially null

  final ImagePicker _picker = ImagePicker(); // Instance of Image Picker

  @override
  void dispose() {
    _nameController.dispose();
    _locationDisplayController.dispose();
    _phoneNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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
      return;
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

      final streamedResponse = await request.send();
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
    // Clear previous values while fetching
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
        // Optionally, offer to open app settings
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
        final String geocodeUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http
            .get(Uri.parse(geocodeUrl))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _humanReadableAddress = data['display_name'] ?? 'Address not found';
        } else {
          _humanReadableAddress = 'Could not fetch address';
          print("Reverse geocode error: ${response.statusCode}");
          _showSnackBar('Could not fetch readable address. Using coordinates.',
              isError: true); // Added snackbar
        }
      } catch (e) {
        _humanReadableAddress = 'Could not fetch address';
        print("Reverse geocode exception: $e");
        _showSnackBar('Could not fetch readable address. Using coordinates.',
            isError: true); // Added snackbar
      }

      setState(() {
        // Display address or fallback to coordinates if address fetch failed
        _locationDisplayController.text = _humanReadableAddress.isNotEmpty &&
                _humanReadableAddress != 'Could not fetch address'
            ? _humanReadableAddress
            : 'Location Acquired (${_locationCoordinates})'; // Changed fallback text
        _isFetchingLocation = false;
      });
      _showSnackBar('Location acquired successfully!', isError: false);
    } on TimeoutException catch (_) {
      _showSnackBar('Getting location timed out. Please try again.',
          isError: true);
      setState(() => _isFetchingLocation = false);
    } catch (e) {
      print("Location error: $e");
      _showSnackBar('Error getting location: $e', isError: true);
      setState(() {
        _isFetchingLocation = false;
        _locationDisplayController.text =
            'Failed to get location'; // Indicate failure in field
      });
    }
  }

  // --- Form Submission ---
  Future<void> _submitForm() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() ?? false) {
      // Check if producer type is selected
      if (_selectedProducerType == null) {
        _showSnackBar('Please select a producer type.', isError: true);
        return;
      }
      // Check if location was acquired
      if (_locationCoordinates.isEmpty) {
        _showSnackBar('Please acquire your location using the button.',
            isError: true);
        return;
      }
      // Check if image was uploaded (optional based on requirements)
      if (_profileImageFile != null &&
          _uploadedImageUrl == null &&
          !_isUploadingImage) {
        _showSnackBar(
            'Profile image is still uploading or failed. Please wait or try again.',
            isError: true);
        return; // Or retry upload here: await _uploadToImgur(); if(!_uploadedImageUrl...) return;
      }
      if (_isUploadingImage) {
        _showSnackBar('Profile image is uploading. Please wait.',
            isError: true);
        return;
      }

      setState(() => _isLoading = true);

      try {
        final Uri signupUri =
            Uri.parse('$apibaseurl/rr/aproducers'); // Example endpoint

        final response = await http.post(
          signupUri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'name': _nameController.text.trim(),
            // Combine human-readable address and coordinates, fallback to just coordinates
            'location': _humanReadableAddress.isNotEmpty &&
                    _humanReadableAddress != 'Could not fetch address'
                ? "$_humanReadableAddress ($_locationCoordinates)"
                : _locationCoordinates,
            'phone_number': _phoneNumberController.text.trim(),
            'email': _emailController.text.trim().toLowerCase(),
            'password': _passwordController.text,
            'producer_type': _selectedProducerType,
            'image': _uploadedImageUrl,
          }),
        );

        setState(() =>
            _isLoading = false); // Stop loading indicator regardless of outcome

        if (response.statusCode == 200 || response.statusCode == 201) {
          // --- SUCCESS ---
          final responseData = json.decode(response.body);

          // Store user info/token if returned by backend
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'producer_id', responseData['producer_id'].toString()); // Example
          await prefs.setString('user_type', 'producer');
          await prefs.setBool('is_logged_in', true);
          // Register FCM token with user info (async, do not await)
          FCMService.registerTokenWithUserInfo();

          _showSnackBar('Sign up successful!', isError: false);

          // Navigate to the next screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProducerDash22()),
          );
        } else {
          // --- FAILURE ---
          String errorMessage = 'Sign up failed. Please try again.';
          try {
            final responseData = json.decode(response.body);
            errorMessage = responseData['message'] ??
                responseData['error'] ??
                errorMessage;
          } catch (_) {
            errorMessage =
                'Sign up failed (Code: ${response.statusCode}). Please try again.';
          }
          _showErrorSnackBar(errorMessage);
        }
      } catch (e) {
        print("Signup exception: $e");
        setState(() => _isLoading = false);
        _showSnackBar('An error occurred during sign up: $e', isError: true);
      }
    } else {
      _showSnackBar('Please fill all required fields correctly.',
          isError: true);
    }
  }

  // --- Helper for SnackBar ---
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
        .removeCurrentSnackBar(); // Remove previous snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? errorColor : accentTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  // --- Helper to Show Specific Error Snackbar ---
  void _showErrorSnackBar(String message) {
    _showSnackBar(message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Become A Producer',
            style: TextStyle(color: whiteColor, fontWeight: FontWeight.w600)),
        backgroundColor: primaryTeal, // Hardcoded teal
        elevation: 1.0,
        iconTheme: const IconThemeData(color: whiteColor), // Back button color
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0), // Consistent padding
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 10),
                // --- Profile Image Picker ---
                _buildProfileImagePicker(),
                const SizedBox(height: 30),

                // --- Producer Name ---
                _buildTextFormField(
                  controller: _nameController,
                  labelText: "Producer Name",
                  hintText: "your name or company name",
                  icon: Icons.storefront_outlined,
                  validator: (value) => (value == null || value.isEmpty)
                      ? "Enter producer name"
                      : null,
                ),
                const SizedBox(height: 16),

                // --- Producer Type Dropdown ---
                _buildProducerTypeDropdown(),
                const SizedBox(height: 16),

                // --- Location Field (Read-only + Button) ---
                GestureDetector(
                  onTap: _isFetchingLocation ? null : _getCurrentLocation,
                  child: AbsorbPointer(
                    child: _buildLocationField(),
                  ),
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
                    if (value == null || value.isEmpty)
                      return "Enter phone number";
                    return null;
                  },
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
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value))
                      return "Enter a valid email address";
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
                    if (value.length < 6)
                      return "Password must be at least 6 characters";
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
                    if (value == null || value.isEmpty)
                      return "Confirm password";
                    if (value != _passwordController.text)
                      return "Passwords do not match";
                    return null;
                  },
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

  // --- Reusable TextFormField Builder ---
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
      style: const TextStyle(color: darkTeal),
      decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          labelStyle:
              const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          hintStyle: const TextStyle(color: subtleTextColor),
          prefixIcon: Icon(icon, color: primaryTeal, size: 20),
          suffixIcon: suffixIcon,
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
            borderSide: const BorderSide(color: primaryTeal, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.0),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
          errorStyle: const TextStyle(color: errorColor, fontSize: 11)),
      validator: validator,
    );
  }

  // --- Location Field Specific Builder ---
  Widget _buildLocationField() {
    // Wrap the TextFormField with AnimatedOpacity for a smooth fade effect
    return AnimatedOpacity(
      opacity: _isFetchingLocation ? 0.6 : 1.0, // Fade slightly when fetching
      duration: const Duration(milliseconds: 300), // Animation duration
      child: TextFormField(
        controller: _locationDisplayController,
        readOnly: true, // Make it read-only
        style: const TextStyle(color: darkTeal, fontSize: 14),
        decoration: InputDecoration(
          labelText: "Business Location",
          labelStyle:
              const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          hintText: _isFetchingLocation
              ? "Fetching location..."
              : "Click button to acquire location",
          hintStyle: const TextStyle(
              color: subtleTextColor, fontStyle: FontStyle.italic),
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
            borderSide: const BorderSide(color: primaryTeal, width: 1.5),
          ),
          contentPadding: const EdgeInsets.fromLTRB(16.0, 14.0, 0.0, 14.0),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: _isFetchingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.0, color: primaryTeal))
                  : const Icon(Icons.my_location_rounded, color: accentTeal),
              tooltip: 'Get Current Location',
              onPressed: _isFetchingLocation ? null : _getCurrentLocation,
            ),
          ),
        ),
        validator: (_) {
          if (_locationCoordinates.isEmpty) {
            return 'Please acquire location';
          }
          return null;
        },
      ),
    );
  }

  // --- Producer Type Dropdown Builder ---
  Widget _buildProducerTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedProducerType,
      items: _producerTypes.map((String type) {
        return DropdownMenuItem<String>(
          value: type,
          child: Text(type, style: const TextStyle(color: darkTeal)),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() => _selectedProducerType = newValue);
      },
      style: const TextStyle(color: darkTeal),
      dropdownColor: whiteColor,
      decoration: InputDecoration(
          labelText: 'Producer Type',
          labelStyle:
              const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          prefixIcon:
              const Icon(Icons.category_outlined, color: primaryTeal, size: 20),
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
            borderSide: const BorderSide(color: primaryTeal, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.0),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
          errorStyle: const TextStyle(color: errorColor, fontSize: 11)),
      icon: const Icon(Icons.arrow_drop_down_rounded, color: primaryTeal),
      isExpanded: true,
      validator: (value) =>
          value == null ? 'Please select a producer type' : null,
    );
  }

  // --- Profile Image Picker Widget ---
  Widget _buildProfileImagePicker() {
    return Center(
      child: Stack(
        children: [
          // The main circle avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: lightTeal, width: 2),
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: lighterTeal,
              backgroundImage: _profileImageFile != null
                  ? FileImage(_profileImageFile!)
                  : null,
              child: _profileImageFile == null && !_isUploadingImage
                  ? const Icon(Icons.person_outline,
                      size: 50, color: primaryTeal)
                  : null,
            ),
          ),
          // Loading indicator overlay
          if (_isUploadingImage)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),
          // Edit/Upload button overlay
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: primaryTeal,
              shape: const CircleBorder(),
              elevation: 2.0,
              child: InkWell(
                onTap: _isUploadingImage ? null : _showImageSourceActionSheet,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(Icons.edit, color: whiteColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Sign Up Button Builder ---
  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading || _isUploadingImage || _isFetchingLocation
            ? null
            : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentTeal,
          foregroundColor: whiteColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 2,
          disabledBackgroundColor: disabledColor.withOpacity(0.5),
          disabledForegroundColor: whiteColor.withOpacity(0.7),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(whiteColor),
                ),
              )
            : const Text("Create Account",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
