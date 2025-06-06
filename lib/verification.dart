import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/transooter_dash_before_mapbox.dart';
import 'user_metrics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chef_dash8888.dart'; // Import for Chef Dashboard
import 'produ_dash22.dart'; // Import for Producer Dashboard

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url'; // Ensure API base URL is available

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  _EmailVerificationPageState createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _userId; // Initialize userId as nullable string
  String? _userType; // Initialize userType as nullable string
  String? _transporterId; // Add state variable for transporter ID
  bool _isUserDataLoaded =
      false; // Track whether user data (ID and type) has been loaded

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Load user data on initialization
  }

  Future<void> _loadUserData() async {
    print('🔍 Loading user data from SharedPreferences...');
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get user_id as string
      final userIdString = prefs.getString('user_id');
      print('🔍 user_id from prefs: $userIdString');
      
      // Get other user data
      final userType = prefs.getString('user_type');
      final transporterId = prefs.getString('transporter_id');

      print('📥 Loaded user data:');
      print('   - User ID: $userIdString');
      print('   - User Type: $userType');
      print('   - Transporter ID: $transporterId');

      // Validate user ID
      if (userIdString == null || userIdString.isEmpty) {
        print('❌ user_id is null or empty in SharedPreferences');
      } else {
        // Try to parse to int to validate it's a valid number
        try {
          final userIdInt = int.parse(userIdString);
          print('✅ Valid user ID (parsed as int): $userIdInt');
        } catch (e) {
          print('⚠️ user_id is not a valid integer: $userIdString');
        }
      }

      setState(() {
        _userId = userIdString; // Store as string in the state
        _userType = userType;
        _transporterId = transporterId ?? userIdString;
        _isUserDataLoaded = true; // Always mark as loaded to prevent infinite loading
      });
      
      print('✅ User data loading completed');
    } catch (e, stackTrace) {
      print('❌ Error loading user data:');
      print('   - Error: $e');
      print('   - Stack trace: $stackTrace');
      setState(() {
        _isUserDataLoaded = true; // Still mark as loaded to avoid infinite loading
      });
    }
  }

  Future<void> _verifyEmail() async {
    print('🔐 Starting email verification...');
    print('   - _isUserDataLoaded: $_isUserDataLoaded');
    print('   - _userId: $_userId');
    print('   - _userType: $_userType');
    print('   - Code entered: ${_codeController.text.trim()}');
    
    // Check form validation
    final isFormValid = _formKey.currentState?.validate() ?? false;
    print('   - Form validation: $isFormValid');
    
    // Ensure user data and form state are valid before proceeding
    if (!_isUserDataLoaded || _userId == null || _userType == null || !isFormValid) {
      print('❌ Validation failed:');
      if (!_isUserDataLoaded) print('      - User data not loaded');
      if (_userId == null) print('      - User ID is null');
      if (_userType == null) print('      - User type is null');
      if (!isFormValid) print('      - Form validation failed');
      
      // Reload user data in case it failed to load previously
      if (!_isUserDataLoaded || _userId == null || _userType == null) {
        print('🔄 Attempting to reload user data...');
        await _loadUserData();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please make sure you have entered the code and user data is available.'),
      ));
      return;
    }
    
    print('✅ All validations passed, proceeding with verification...');

    setState(() {
      _isLoading = true; // Set loading state
    });

    try {
      // Convert user ID to int for the API
      final userIdInt = int.tryParse(_userId!);

      if (userIdInt == null) {
        print('❌ Invalid user ID format: "$_userId"');
        throw Exception('Invalid user ID format. Expected a number but got: $_userId');
      }

      final requestBody = {
        'user_id': userIdInt,
        'verification_code': _codeController.text.trim(),
        'user_type': _userType,
      };
      
      print('📤 Sending verification request to: $apibaseurl/rr/verify_user');
      print('   - Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/verify_user'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      
      print('📥 Received response:');
      print('   - Status code: ${response.statusCode}');
      print('   - Body: ${response.body}');

      if (response.statusCode == 200) {
        // Navigate based on user type
        Widget nextPage;
        switch (_userType) {
          case 'user':
            nextPage = const UserMetricsPage();
            break;
          case 'chef':
            nextPage = const ChefDash88new();
            break;
          case 'producer':
            nextPage = const ProducerDash22();
            break;
          case 'transporter':
            // Pass transporterId to the Transporter dashboard
            if (_transporterId != null) {
              nextPage = TransporterDashNew(
                  transporterId:
                      _transporterId!); // Assuming TransporterDashBeforeMapbox takes transporterId
            } else {
              // Handle case where transporterId is not available
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Transporter ID not found.'),
              ));
              setState(() {
                _isLoading = false; // Reset loading state
              });
              return; // Stop navigation
            }
            break;
          default:
            // Default navigation or error handling for unknown user types
            nextPage = const UserMetricsPage(); // Or an error page
            break;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => nextPage),
        );
      } else {
        final responseData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(responseData['message'] ?? 'Verification failed'),
        ));
      }
    } catch (error, stackTrace) {
      print('❌ Error during verification:');
      print('   - Error: $error');
      print('   - Stack trace: $stackTrace');
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${error.toString()}'),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      setState(() {
        _isLoading = false; // Reset loading state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Display loading dialog until user ID is loaded
    if (!_isUserDataLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Email Verification'),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Verification'),
        backgroundColor: Colors.teal,
      ),
      body: Stack(
        children: [
          // Background image within a container
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/soft.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Overlaying content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Verification image
                  Container(
                    height: 100,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/verification.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                  const Text(
                    'Enter your verification code:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: 'Verification Code',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyEmail,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 32),
                      backgroundColor: Colors.teal,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('VERIFY',
                            style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Didn't receive a code? Check your email it could take a few seconds to arrive.",
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
