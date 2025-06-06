import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for SystemChrome
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:zinzi/user_metrics.dart';
import 'package:zinzi/verification.dart'; // Import verification page
import 'notifications/fcm_service.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

// Define colors matching signup_or_Login.dart
const Color lightTeal = Color(0xFFB2DFDB);
const Color lighterTeal = Color(0xFFE0F2F1);
const Color primaryTeal = Color(0xFF00796B);
const Color darkTeal = Color(0xFF004D40);
const Color subtleTextColor = Color(0xFF616161);
const Color errorColor = Color(0xFFD32F2F);
const Color appBarColor =
    Color(0xFF004D40); // Darker teal for AppBar like login
const Color whiteColor = Colors.white;

// Get Imgur Client ID from environment variables (same as chef signup)
final imgurClientID =
    dotenv.env['IMGUR_CLIENT_ID'] ?? ''; // Keep image upload logic for now

class UserSignUpPage extends StatefulWidget {
  const UserSignUpPage({super.key});

  @override
  _UserSignUpPageState createState() => _UserSignUpPageState();
}

class _UserSignUpPageState extends State<UserSignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController(); // Controller for confirm password
  final TextEditingController _imageUrlController = TextEditingController();

  bool _isLoading = false; // General loading for final submit
  bool _isUploadingProfileImage = false; // Specific loading for image upload
  File? _profileImage; // Variable to hold the selected profile image

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _profilePicScaleAnimation; // Animation for profile pic
  late Animation<double> _buttonFadeAnimation;
  late Animation<double> _buttonScaleAnimation;

  String _passwordStrengthMessage = '';
  Color _passwordStrengthColor = Colors.red;

  @override
  void initState() {
    super.initState();

    // Initializing animations
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    // Profile Pic Scale Animation (starts slightly earlier)
    _profilePicScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.7,
            curve: Curves.easeOutBack), // Staggered start, overshoot effect
      ),
    );

    _buttonFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    );

    _buttonScaleAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); // Dispose the new controller
    _imageUrlController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String password) {
    // Simplified logic for example, adjust as needed
    setState(() {
      if (password.isEmpty) {
        _passwordStrengthMessage = '';
      } else if (password.length < 6) {
        _passwordStrengthMessage = 'Weak';
        _passwordStrengthColor = Colors.red;
      } else if (password.length < 10) {
        _passwordStrengthMessage = 'Moderate';
        _passwordStrengthColor = Colors.orange;
      } else {
        _passwordStrengthMessage = 'Strong';
        _passwordStrengthColor = Colors.green;
      }
    });
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
          _isUploadingProfileImage = true;
        });

        try {
          String imageUrl = await uploadImageToImgur(_profileImage!);
          _imageUrlController.text = imageUrl; // Set the actual Imgur URL
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Profile image uploaded successfully!'),
              backgroundColor: primaryTeal,
            ));
          }
        } catch (e) {
          print("Image upload error: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Image upload failed. You can try again or continue without an image.'),
              backgroundColor: errorColor,
            ));
          }
          // Don't clear the selected image, let user retry
          _imageUrlController.clear();
        } finally {
          if (mounted) {
            setState(() {
              _isUploadingProfileImage = false;
            });
          }
        }
      }
    } catch (e) {
      print("Image picker error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to pick image. Please try again.'),
          backgroundColor: errorColor,
        ));
      }
    }
  }

  // Actual Imgur upload implementation
  Future<String> uploadImageToImgur(File image) async {
    if (imgurClientID.isEmpty) {
      throw Exception('Imgur Client ID is not configured in .env file.');
    }

    final String uploadUrl = 'https://api.imgur.com/3/image';
    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    // Use the client ID loaded from .env
    request.headers['Authorization'] = 'Client-ID $imgurClientID';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final response = await request
        .send()
        .timeout(const Duration(seconds: 30)); // Add timeout
    final responseData = await http.Response.fromStream(response);

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(responseData.body);
      if (jsonResponse['success'] == true &&
          jsonResponse['data']?['link'] != null) {
        return jsonResponse['data']['link']; // Returns the image URL
      } else {
        throw Exception('Imgur upload failed: Invalid response structure.');
      }
    } else {
      print('Failed to upload image: ${responseData.body}');
      throw Exception(
          'Failed to upload image. Status Code: ${response.statusCode}');
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    // Show confirmation dialog if no image was uploaded
    if (_imageUrlController.text.trim().isEmpty) {
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('No Profile Image'),
          content: const Text(
              'You can add a profile image later from your profile settings. Would you like to continue without a profile image?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Go Back'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        return; // User chose to go back
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/signup_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          if (_imageUrlController.text.trim().isNotEmpty) 'image': _imageUrlController.text.trim(),
          'user_type': 'User', // Set the user type explicitly
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final int userId = responseData['user_id'];
        final String? phoneNumber = responseData['phone'] as String?;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', userId);
        await prefs.setString('user_type', 'User');
        await prefs.setString('user_email', _emailController.text.trim());
        await prefs.setBool('is_logged_in', true);
        
        // Save phone number if available in the response
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          await prefs.setString('user_phone', phoneNumber);
        }

        // Register FCM token with user info (async, do not await)
        FCMService.registerTokenWithUserInfo();

        // Navigate using the transition method
        Navigator.pushReplacement(
          // Use pushReplacement if you don't want to go back here
          context,
          _createSlideFadeTransition(
              const EmailVerificationPage()), // Navigate to verification page
        );
      } else {
        // Improved error handling for specific backend messages
        String displayMessage = 'Signup failed. Please try again.'; // Default message
        try {
          if (response.statusCode == 409) {
            displayMessage = 'An account with this email already exists. Please log in or use a different email.';
          } else {
            final errorResponse = json.decode(response.body);
            final backendMessage = errorResponse['message'] as String?;

            if (backendMessage != null) {
              // Check for the specific "already registered" error
              if (backendMessage.toLowerCase().contains('is already registered')) {
                displayMessage = 'This email address is already registered. Please use a different email or log in.';
              } else {
                // Use the backend message if it's not the specific one we handled
                displayMessage = backendMessage;
              }
            }
          }
        } catch (e) {
          // If parsing the error response fails, check status code
          print("Error parsing error response: $e");
          if (response.statusCode == 409) {
            displayMessage = 'An account with this email already exists. Please log in or use a different email.';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(displayMessage),
          backgroundColor: errorColor,
        ));
      }
    } catch (error) {
      print("Signup Error: $error"); // Log the error
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An error occurred. Please try again later.'),
        backgroundColor: errorColor,
      ));
    } finally {
      // Ensure isLoading is set to false even if the widget is disposed during async operation
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar style - Icons should be light on dark background
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: appBarColor, // Match AppBar color
      statusBarIconBrightness:
          Brightness.light, // Icons light for dark background
    ));

    return Scaffold(
      // AppBar like the login screen
      appBar: AppBar(
        title: const Text(
          'User Sign Up', // Title can remain specific to the page
          style: TextStyle(color: whiteColor), // White text
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: whiteColor), // White icon
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: appBarColor, // Dark teal background
        elevation: 0, // No shadow
      ),
      // No longer extend body behind AppBar
      // extendBodyBehindAppBar: true, // Removed
      // Use Container with gradient as the body background
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [lighterTeal, lightTeal], // Use the same gradient
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        // Use SafeArea to avoid overlap with status bar/notches
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, vertical: 20.0), // Add vertical padding
              child: FadeTransition(
                // Keep fade animation
                opacity: _fadeAnimation,
                child: Form(
                  // Wrap content in Form
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center, // Center content vertically
                    children: [
                      // Keep Slide animation for the top section
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          // Keep original structure for image/card
                          children: [
                            // Wrap GestureDetector in ScaleTransition and add loading indicator
                            ScaleTransition(
                              scale: _profilePicScaleAnimation,
                              child: Stack(
                                // Use Stack to overlay loading indicator
                                alignment: Alignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: _isUploadingProfileImage
                                        ? null
                                        : pickImage, // Disable tap during upload
                                    child: CircleAvatar(
                                      radius: 60, // Adjust the radius for size
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage: _profileImage != null
                                          ? FileImage(_profileImage!)
                                          : null,
                                      child: (_profileImage == null &&
                                              !_isUploadingProfileImage)
                                          ? const Icon(Icons.add_a_photo,
                                              size: 30, color: darkTeal)
                                          : null,
                                    ),
                                  ),
                                  // Loading indicator overlay
                                  if (_isUploadingProfileImage)
                                    Container(
                                      width: 120,
                                      height:
                                          120, // Match CircleAvatar diameter
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 15), // Spacing after image
                            // Removed the extra card around the text
                            Text(
                              "Create your account",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: darkTeal, // Use consistent color
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Join us to personalize, track, and achieve your health goals!",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: darkTeal
                                    .withOpacity(0.8), // Use consistent color
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                          height: 20), // Reduced spacing to push content up
                      // Form fields Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextField(
                            controller: _nameController,
                            label: "Name",
                            icon: Icons.person,
                            validator: (value) => value?.trim().isEmpty ?? true
                                ? "Enter your name"
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _emailController,
                            label: "Email",
                            icon: Icons.email,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Enter your email";
                              }
                              final emailRegex = RegExp(
                                  r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                              if (!emailRegex.hasMatch(value.trim())) {
                                return "Enter a valid email address";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _passwordController,
                            label: "Password",
                            icon: Icons.lock,
                            obscureText: true,
                            validator: (value) {
                              final trimmedValue = value?.trim();
                              if (trimmedValue == null ||
                                  trimmedValue.isEmpty) {
                                return "Enter your password";
                              }
                              // Add more password validation if needed
                              return null;
                            },
                            onChanged:
                                _checkPasswordStrength, // Pass function directly
                          ),
                          const SizedBox(
                              height: 16), // Spacing before confirm password
                          // Add Confirm Password Field
                          _buildTextField(
                            controller: _confirmPasswordController,
                            label: "Confirm Password",
                            icon: Icons.lock_outline, // Slightly different icon
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please confirm your password";
                              }
                              if (value.trim() !=
                                  _passwordController.text.trim()) {
                                return "Passwords do not match";
                              }
                              return null;
                            },
                            // No onChanged needed for confirm password strength
                          ),
                          const SizedBox(height: 10),
                          // Password strength indicator (remains linked to the first password field)
                          if (_passwordController.text.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 12.0), // Align with text field
                              child: Text(
                                _passwordStrengthMessage,
                                style: TextStyle(
                                    color: _passwordStrengthColor,
                                    fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 5),
                            LinearProgressIndicator(
                              value: _passwordStrengthMessage == 'Strong'
                                  ? 1.0
                                  : _passwordStrengthMessage == 'Moderate'
                                      ? 0.66 // Adjusted value
                                      : _passwordStrengthMessage == 'Weak'
                                          ? 0.33 // Adjusted value
                                          : 0.1, // Small value for 'Too short'
                              backgroundColor: Colors.grey.shade300,
                              color: _passwordStrengthColor,
                              minHeight: 5, // Make it slightly thicker
                            ),
                          ],
                          const SizedBox(height: 40),
                          // Button animations and style
                          FadeTransition(
                            opacity: _buttonFadeAnimation,
                            child: ScaleTransition(
                              scale: _buttonScaleAnimation,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signUp,
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        12), // Match login style
                                  ),
                                  backgroundColor:
                                      Colors.teal, // Match login style
                                  foregroundColor: Colors.white, // Text color
                                  minimumSize: const Size(
                                      double.infinity, 60), // Match login style
                                  textStyle: GoogleFonts.poppins(
                                      // Match login style
                                      fontSize: 16,
                                      fontWeight: FontWeight
                                          .bold, // Keep bold from signup
                                      color: Colors.white),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.0,
                                        ),
                                      )
                                    : const Text("Sign Up"),
                              ),
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

  // Helper widget for text fields, using UnderlineInputBorder
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    required String? Function(String?) validator, // Make validator required
    Function(String)? onChanged, // Keep onChanged optional
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.poppins(color: Colors.teal), // Match login style
        // hintText: label, // Remove hint text like login
        // hintStyle: TextStyle(color: subtleTextColor.withOpacity(0.5)), // Remove hint style
        // Use OutlineInputBorder like login
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), // Match login style
          borderSide: BorderSide.none, // Match login style
        ),
        enabledBorder: OutlineInputBorder(
          // Add enabledBorder for consistency
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          // Add focusedBorder for consistency
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          // Add errorBorder for consistency
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedErrorBorder: OutlineInputBorder(
          // Add focusedErrorBorder for consistency
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        prefixIcon: Icon(icon, color: Colors.teal), // Match login style
        filled: true, // Match login style
        fillColor: Colors.white.withOpacity(0.6), // Match login style
        contentPadding: const EdgeInsets.symmetric(
            vertical: 16.0, horizontal: 10.0), // Adjust padding if needed
      ),
      obscureText: obscureText,
      style: const TextStyle(color: darkTeal), // Keep text color
      validator: validator,
    );
  }

  // Re-add the missing transition method
  PageRouteBuilder _createSlideFadeTransition(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOut;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);
        var fadeAnimation = animation.drive(CurveTween(curve: curve));

        return SlideTransition(
            position: offsetAnimation,
            child: FadeTransition(opacity: fadeAnimation, child: child));
      },
      transitionDuration: const Duration(milliseconds: 500),
    );
  }
}
