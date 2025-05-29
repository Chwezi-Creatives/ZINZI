import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
// import 'package:zinzi2/Transporter_login.dart';
// import 'package:zinzi2/transooter_dash_before_mapbox.dart';
import 'package:zinzi2/verification.dart'; // Import verification page
import 'notifications/fcm_service.dart';

// --- Hardcoded Colors ---
const Color primaryTeal = Color(0xFF00796B);
const Color lightTeal = Color(0xFFB2DFDB);
const Color lighterTeal = Color(0xFFE0F2F1);
const Color darkTeal = Color(0xFF004D40);
const Color accentTeal = Color(0xFF009688);
const Color whiteColor = Colors.white;
const Color lightBackgroundColor = Color(0xFFF5F5F5);
const Color textFieldFillColor = Color(0x8AFFFFFF);
const Color subtleTextColor = Color(0xFF757575);
const Color errorColor = Color(0xFFD32F2F);
const Color disabledColor = Colors.grey;

// --- API Base URL & Imgur ID (Ensure dotenv is loaded in main.dart) ---
final String apibaseurl =
    dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url/api';
final String? imgurClientId = dotenv.env['IMGUR_CLIENT_ID'];

class TransporterSignUpPage extends StatefulWidget {
  const TransporterSignUpPage({super.key});

  @override
  _TransporterSignUpPageState createState() => _TransporterSignUpPageState();
}

class _TransporterSignUpPageState extends State<TransporterSignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _licensePlateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  bool _isLoading = false;
  bool _isUploadingImage = false;
  bool _isFetchingLocation = false;

  File? _profileImageFile;
  String? _uploadedImageUrl;

  String _locationCoordinates = ''; // Stores "lat,lon" (optional for signup)
  String _humanReadableAddress = ''; // Optional

  final List<String> _vehicleTypes = [
    'Motorbike',
    'Bicycle',
    'Car',
    'Truck',
    'Other'
  ];
  String? _selectedVehicleType;

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licensePlateController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // --- Image Picking ---
  Future<void> _pickImage(ImageSource source) async {
    if (_isUploadingImage) return;
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 800,
      );
      if (pickedFile != null) {
        setState(() {
          _profileImageFile = File(pickedFile.path);
          _uploadedImageUrl = null;
        });
        _uploadToImgur(); // Start upload immediately
      }
    } catch (e) {
      _showSnackBar("Failed to pick image.", isError: true);
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
    _uploadedImageUrl = null; // Clear previous URL

    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('https://api.imgur.com/3/image'));
      request.headers['Authorization'] = 'Client-ID $imgurClientId';
      request.files.add(
          await http.MultipartFile.fromPath('image', _profileImageFile!.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['data']?['link'] != null) {
          if (mounted) {
            setState(() => _uploadedImageUrl = responseData['data']['link']);
            _showSnackBar("Image uploaded.", isError: false);
          }
        } else {
          throw Exception('Imgur upload failed: Invalid response structure.');
        }
      } else {
        throw Exception(
            'Imgur upload failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print("Imgur upload error: $e");
      if (mounted) _showSnackBar("Failed to upload image.", isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // --- Location Fetching (Optional) ---
  Future<void> _fetchLocationOptional() async {
    if (_isFetchingLocation) return;
    setState(() => _isFetchingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isFetchingLocation = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          setState(() => _isFetchingLocation = false);
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10));
      _locationCoordinates = "${position.latitude}, ${position.longitude}";
      // Optional Reverse Geocode
      try {
        final String geocodeUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http
            .get(Uri.parse(geocodeUrl))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          _humanReadableAddress =
              json.decode(response.body)['display_name'] ?? '';
        }
      } catch (_) {}
      // Set the location controller text for display
      _locationController.text = _humanReadableAddress.isNotEmpty
          ? "$_humanReadableAddress ($_locationCoordinates)"
          : _locationCoordinates;
      print("Optional location fetched: $_locationCoordinates");
      if (mounted) _showSnackBar("Location approximated.", isError: false);
    } catch (e) {
      print("Optional location fetch error: $e");
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  // --- Form Submission ---
  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() ?? false) {
      if (_selectedVehicleType == null) {
        _showSnackBar('Please select vehicle type.', isError: true);
        return;
      }
      if (_isUploadingImage) {
        _showSnackBar('Image is uploading. Please wait.', isError: true);
        return;
      }

      setState(() => _isLoading = true);

      Map<String, dynamic> signupData = {
        'name': _nameController.text.trim(),
        'phone_number': _phoneNumberController.text.trim(),
        'email': _emailController.text.trim().toLowerCase(),
        'password': _passwordController.text,
        'vehicle_type': _selectedVehicleType,
        'license_plate': _licensePlateController.text.trim().isEmpty
            ? null
            : _licensePlateController.text.trim(),
        'profile_image_url': _uploadedImageUrl,
        'location_coordinates':
            _locationCoordinates.isNotEmpty ? _locationCoordinates : null,
        'address':
            _humanReadableAddress.isNotEmpty ? _humanReadableAddress : null,
        'user_type': 'Transporter',
      };

      // --- Actual API Call ---
      try {
        // Use the correct endpoint as per user instruction
        final Uri uri = Uri.parse('$apibaseurl/rr/transporters/signup');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: json.encode(signupData),
        );

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          // Extract transporter_id and store in SharedPreferences
          final transporterId =
              responseData['transporter_id'] ?? responseData['id'];
          if (transporterId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('transporter_id', transporterId.toString());
            await prefs.setString('user_id', transporterId.toString());
            await prefs.setString('user_type',
                'transporter'); // Changed to lowercase for consistency
            await prefs.setBool('is_logged_in', true);

            await Future.delayed(
                const Duration(milliseconds: 100)); // Small delay
// Register FCM token with user info (async, do not await)
            FCMService.registerTokenWithUserInfo();
          }
          if (!mounted) return; // Check mount status again after delay
          _showSnackBar('Signup successful!',
              isError: false); // Changed message slightly
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  EmailVerificationPage(), // Navigate to verification page
            ),
          );
        } else {
          String errorMessage = 'Signup failed.';
          try {
            final responseData = json.decode(response.body);
            if (response.statusCode == 409) {
              errorMessage = 'An account with this email already exists. Please log in or use a different email.';
            } else {
              errorMessage = responseData['message'] ??
                  responseData['error'] ??
                  'Signup failed (Code: ${response.statusCode})';
            }
          } catch (_) {
            if (response.statusCode == 409) {
              errorMessage = 'An account with this email already exists. Please log in or use a different email.';
            } else {
              errorMessage = 'Signup failed (Code: ${response.statusCode}). Please try again.';
            }
          }
          _showErrorSnackBar(errorMessage);
        }
      } catch (e) {
        print("Signup exception: $e");
        if (mounted) {
          setState(() => _isLoading = false);
          _showErrorSnackBar('An error occurred during sign up: $e');
        }
      }
      // --- End Actual API Call ---

      /*
      // --- *** ACTUAL API CALL (Commented Out) *** ---
      try {
        // **VERIFY ENDPOINT**: e.g., /transporters/signup or /riders/register
        final Uri uri = Uri.parse('$apibaseurl/transporters/signup'); // ADJUST ENDPOINT

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json; charset=UTF-8'},
          body: json.encode(signupData),
        );

        if (!mounted) return; // Check after await
        setState(() => _isLoading = false);

        if (response.statusCode == 200 || response.statusCode == 201) {
          _showSnackBar('Signup successful! Please log in.', isError: false);
          Navigator.pushReplacement(
             context,
             MaterialPageRoute(builder: (context) => const TransporterLoginPage()),
          );
        } else {
          String errorMessage = 'Signup failed.';
          try {
            final responseData = json.decode(response.body);
            errorMessage = responseData['message'] ?? responseData['error'] ?? 'Signup failed (Code: ${response.statusCode})';
          } catch (_) {}
          _showErrorSnackBar(errorMessage);
        }
      } catch (e) {
        print("Signup exception: $e");
        if (mounted) {
           setState(() => _isLoading = false);
           _showErrorSnackBar('An error occurred during sign up: $e');
        }
      }
      // --- *** END ACTUAL API CALL *** ---
      */
    } else {
      _showSnackBar('Please fill all required fields correctly.',
          isError: true);
    }
  }

  // --- Helper for SnackBar ---
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
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

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Transporter Account Setup',
            style: TextStyle(color: whiteColor, fontWeight: FontWeight.w600)),
        backgroundColor: primaryTeal,
        elevation: 1.0,
        iconTheme: const IconThemeData(
            color: whiteColor), // Ensure back button is white if needed
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 10),
                _buildProfileImagePicker(),
                const SizedBox(height: 30),
                _buildTextFormField(
                    controller: _nameController,
                    labelText: "Full Name",
                    hintText: "Enter your full name",
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? "Name is required" : null),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _phoneNumberController,
                    labelText: "Phone Number",
                    hintText: "e.g., 07...",
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.isEmpty)
                        ? "Phone number is required"
                        : null),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _emailController,
                    labelText: "Email Address",
                    hintText: "your.email@example.com",
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Email is required";
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v))
                        return "Enter a valid email";
                      return null;
                    }),
                const SizedBox(height: 16),
                // Location field (entire field is tappable)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _fetchLocationOptional,
                  child: AbsorbPointer(
                    child: _buildTextFormField(
                      controller: _locationController,
                      labelText: "Location (Tap to acquire)",
                      hintText: "Tap to get your current location",
                      icon: Icons.location_on_outlined,
                      validator: (value) => (value == null || value.isEmpty)
                          ? "Select a location"
                          : null,
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildVehicleTypeDropdown(),
                const SizedBox(height: 16),
                _buildTextFormField(
                  controller: _licensePlateController,
                  labelText: "License Plate (Optional)",
                  hintText: "e.g., UXX 123X",
                  icon: Icons.badge_outlined,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _passwordController,
                    labelText: "Password",
                    hintText: "Minimum 6 characters",
                    icon: Icons.lock_outline,
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Password is required";
                      if (v.length < 6) return "Password too short";
                      return null;
                    }),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _confirmPasswordController,
                    labelText: "Confirm Password",
                    hintText: "Re-enter password",
                    icon: Icons.lock_outline,
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return "Please confirm password";
                      if (v != _passwordController.text)
                        return "Passwords don't match";
                      return null;
                    }),
                const SizedBox(height: 30),
                _buildSignUpButton(),
                const SizedBox(height: 20),
                _buildLoginLink(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Building Helpers ---
  Widget _buildProfileImagePicker() {
    return Center(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: lightTeal, width: 2),
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: lighterTeal,
              child: _isUploadingImage
                  ? null
                  : (_uploadedImageUrl != null
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: _uploadedImageUrl!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Shimmer.fromColors(
                              baseColor: Colors.grey.shade300,
                              highlightColor: Colors.grey.shade100,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                                Icons.error,
                                color: errorColor,
                                size: 50),
                          ),
                        )
                      : (_profileImageFile != null
                          ? ClipOval(
                              child: Image.file(
                                _profileImageFile!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.delivery_dining_outlined,
                              size: 50, color: primaryTeal))),
            ),
          ),
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
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.edit, color: whiteColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      readOnly: readOnly,
      style: const TextStyle(color: darkTeal),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        labelStyle:
            const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: subtleTextColor),
        prefixIcon: Icon(icon, color: primaryTeal, size: 20),
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
        errorStyle: const TextStyle(color: errorColor, fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildVehicleTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedVehicleType,
      items: _vehicleTypes.map((String type) {
        return DropdownMenuItem<String>(
          value: type,
          child: Text(type, style: const TextStyle(color: darkTeal)),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() => _selectedVehicleType = newValue);
      },
      style: const TextStyle(color: darkTeal),
      dropdownColor: whiteColor,
      decoration: InputDecoration(
          labelText: 'Primary Vehicle Type *',
          labelStyle:
              const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.directions_bike_outlined,
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
      validator: (value) => value == null ? 'Please select vehicle type' : null,
    );
  }

  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading || _isUploadingImage ? null : _submitForm,
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

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Already have an account?",
            style: TextStyle(color: subtleTextColor)),
        TextButton(
          onPressed: () {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const EmailVerificationPage()));
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text("Log In",
              style:
                  TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
