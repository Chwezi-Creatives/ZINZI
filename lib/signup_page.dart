import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/user_metrics.dart';
import 'package:zinzi2/verification.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class UserSignUpPage extends StatefulWidget {
  @override
  const UserSignUpPage({super.key});

  @override
  _UserSignUpPageState createState() => _UserSignUpPageState();
}

class _UserSignUpPageState extends State<UserSignUpPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();

  bool _isLoading = false; 
  File? _profileImage; // Variable to hold the selected profile image

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
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
    _imageUrlController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String password) {
    if (password.isEmpty || password.length < 4) {
      setState(() {
        _passwordStrengthMessage = 'Too short';
        _passwordStrengthColor = Colors.red;
      });
    } else if (password.length < 6) {
      setState(() {
        _passwordStrengthMessage = 'Weak';
        _passwordStrengthColor = Colors.orange;
      });
    } else if (password.length >= 7 && 
                RegExp(r'(?=.*[0-9])(?=.*[!@#\$&*~])').hasMatch(password)) {
      setState(() {
        _passwordStrengthMessage = 'Moderate';
        _passwordStrengthColor = Colors.deepPurple;
      });
    } else if (password.length >= 10 && 
                RegExp(r'(?=.*[0-9])(?=.*[!@#\$&*~])(?=.*[A-Z])(?=.*[a-z])').hasMatch(password)) {
      setState(() {
        _passwordStrengthMessage = 'Strong';
        _passwordStrengthColor = Colors.green;
      });
    } else {
      setState(() {
        _passwordStrengthMessage = 'Moderate';
        _passwordStrengthColor = Colors.deepPurple;
      });
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
      });

      String imageUrl = await uploadImageToImgur(_profileImage!);
      _imageUrlController.text = imageUrl; // Set the image URL in the controller
    }
  }

  Future<String> uploadImageToImgur(File image) async {
    final String uploadUrl = 'https://api.imgur.com/3/image';
    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = 'Client-ID [YOUR_IMGUR_CLIENT_ID]'; // Use a valid Imgur Client ID
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final response = await request.send();
    final responseData = await http.Response.fromStream(response);

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(responseData.body);
      return jsonResponse['data']['link']; // Returns the image URL
    } else {
      throw Exception('Failed to upload image to Imgur');
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true; 
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/signup_user'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'image': _imageUrlController.text.trim(),
          'user_type': 'User', // Set the user type explicitly for this signup page
        }),
      );

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final int userId = responseData['user_id'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', userId);

        Navigator.push(
          context,
          _createSlideFadeTransition(const UserMetricsPage()),
        );
      } else {
        final errorResponse = json.decode(response.body);
        final errorMessage = errorResponse['message'] ?? 'Signup failed. Try again!';
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorMessage),
        ));
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An error occurred. Please try again later.'),
      ));
    } finally {
      setState(() {
        _isLoading = false; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Sign Up',
          style: TextStyle(color: Colors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.teal,
        elevation: 5,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.teal.withOpacity(0.2),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            // Circular Profile Image Selection Section
                            GestureDetector(
                              onTap: pickImage,
                              child: CircleAvatar(
                                radius: 60, // Adjust the radius for size
                                backgroundColor: Colors.grey[300],
                                backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                                child: _profileImage == null
                                    ? const Icon(Icons.add_a_photo, size: 30)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 20), // Spacing after image
                            Card(
                              elevation: 3,
                              color: Colors.teal[50],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Text(
                                      "Create your account",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Join us to personalize, track, and achieve your health goals and more!",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.teal[900],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 70),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              label: "Name",
                              icon: Icons.person,
                              validator: (value) => value?.isEmpty ?? true ? "Enter your name" : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _emailController,
                              label: "Email",
                              icon: Icons.email,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return "Enter your email";
                                }
                                final emailRegex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
                                if (!emailRegex.hasMatch(value)) {
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
                                if (trimmedValue == null || trimmedValue.isEmpty) {
                                  return "Enter your password";
                                }
                                return null;
                              },
                              onChanged: (value) {
                                _checkPasswordStrength(value);
                              },
                            ),
                            const SizedBox(height: 10),
                            if (_passwordController.text.isNotEmpty) ...[
                              Text(
                                _passwordStrengthMessage,
                                style: TextStyle(color: _passwordStrengthColor),
                              ),
                              SizedBox(height: 5),
                              LinearProgressIndicator(
                                value: _passwordStrengthMessage == 'Strong'
                                    ? 1.0
                                    : _passwordStrengthMessage == 'Moderate' 
                                        ? 0.7 
                                        : _passwordStrengthMessage == 'Weak'
                                            ? 0.4 
                                            : 0.2,
                                backgroundColor: Colors.grey.shade300,
                                color: _passwordStrengthColor,
                              ),
                            ],
                            const SizedBox(height: 40),
                            FadeTransition(
                              opacity: _buttonFadeAnimation,
                              child: ScaleTransition(
                                scale: _buttonScaleAnimation,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _signUp,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    backgroundColor: Colors.teal,
                                  ),
                                  child: _isLoading
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : const Text(
                                          "Sign Up",
                                          style: TextStyle(fontSize: 16, color: Colors.white),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    required String? Function(String?) validator,
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.teal.shade700),
        filled: true,
        fillColor: Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        prefixIcon: Icon(icon, color: Colors.teal),
      ),
      obscureText: obscureText,
      style: const TextStyle(color: Colors.teal),
      validator: validator,
    );
  }

  PageRouteBuilder _createSlideFadeTransition(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOut;

        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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