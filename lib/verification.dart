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
  final bool isNewUser;
  
  const EmailVerificationPage({
    super.key,
    this.isNewUser = false,
  });

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
  bool _verificationFailed = false; // Track if verification has failed

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Load user data on initialization
  }

  Future<void> _loadUserData() async {
    print('🔍 Loading user data from SharedPreferences...');
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // First, try to get user_id as string (preferred method)
      String? userIdString = prefs.getString('user_id');
      
      // If string is not available, try to get as int and convert to string
      if (userIdString == null || userIdString.isEmpty) {
        try {
          final userIdInt = prefs.getInt('user_id');
          if (userIdInt != null) {
            userIdString = userIdInt.toString();
            print('🔍 Converted int user_id to string: $userIdString');
          }
        } catch (e) {
          print('⚠️ Error reading user_id as int: $e');
        }
      }
      
      // Get other user data
      final userType = prefs.getString('user_type');
      final transporterId = prefs.getString('transporter_id');

      print('📥 Loaded user data:');
      print('   - User ID: $userIdString');
      print('   - User Type: $userType');
      print('   - Transporter ID: $transporterId');

      // Validate required fields
      if (userIdString == null || userIdString.isEmpty) {
        print('❌ user_id is null or empty in SharedPreferences');
      } else {
        print('✅ Valid user ID: $userIdString');
      }

      setState(() {
        _userId = userIdString; // Store as string in the state
        _userType = userType;
        // Use transporterId if available, otherwise fall back to user_id
        _transporterId = transporterId ?? userIdString ?? '';
        _isUserDataLoaded = true; // Mark as loaded to prevent infinite loading
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
        // Navigate based on user type and whether it's a new user
        Widget nextPage;
        
        // If it's a new user, always navigate to UserMetricsPage
        if (widget.isNewUser) {
          nextPage = const UserMetricsPage();
        } else {
          // Existing logic for non-new users
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
              if (_transporterId != null) {
                nextPage = TransporterDashNew(transporterId: _transporterId!);
              } else {
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
              nextPage = const UserMetricsPage();
              break;
          }
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => nextPage),
        );
      } else {
        final responseData = json.decode(response.body);
        setState(() {
          _verificationFailed = true; // Show resend option
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(responseData['message'] ?? 'Verification failed'),
          duration: const Duration(seconds: 5),
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

  Future<void> _resendVerificationCode() async {
    print('🔄 Starting verification code resend process...');
    
    if (!_isUserDataLoaded || _userId == null || _userType == null) {
      final errorMsg = '❌ User information not available. ' +
          'isUserDataLoaded: $_isUserDataLoaded, ' +
          'userId: $_userId, userType: $_userType';
      print(errorMsg);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('User information not available. Please try again.'),
      ));
      return;
    }

    print('🔍 User data loaded:');
    print('   - User ID: $_userId (type: ${_userId.runtimeType})');
    print('   - User Type: $_userType (type: ${_userType.runtimeType})');
    print('   - Transporter ID: $_transporterId');

    setState(() {
      _isLoading = true;
    });

    try {
      // Convert user ID to int for the API
      final userIdInt = int.tryParse(_userId!);
      if (userIdInt == null) {
        throw Exception('Invalid user ID format');
      }

      final requestBody = {
        'user_id': userIdInt,
        'user_type': _userType,
      };

      // Detailed debug logging
      print('📤 Preparing verification code resend request:');
      print('   - Endpoint: $apibaseurl/rr/resend_verification_email');
      print('   - Headers: {Content-Type: application/json}');
      print('   - Request body:');
      print('     - user_id: $userIdInt (type: ${userIdInt.runtimeType})');
      print('     - user_type: "$_userType" (type: ${_userType.runtimeType})');
      print('   - Full JSON payload: ${jsonEncode(requestBody)}');
      
      final stopwatch = Stopwatch()..start();
      print('   - Sending request...');
      
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/resend_verification_email'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      stopwatch.stop();
      print('📥 Received response:');
      print('   - Status code: ${response.statusCode}');
      print('   - Response time: ${stopwatch.elapsedMilliseconds}ms');
      print('   - Headers: ${response.headers}');
      print('   - Response body:');
      print('     ${response.body}');
      
      // Log the raw response for debugging
      if (response.body.isNotEmpty) {
        try {
          final jsonResponse = jsonDecode(response.body);
          print('   - Parsed JSON response: $jsonResponse');
        } catch (e) {
          print('   - Could not parse response as JSON: $e');
        }
      }

      if (response.statusCode == 202) {
        final responseData = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(responseData['message'] ?? 'New verification code sent'),
          backgroundColor: Colors.green,
        ));
        setState(() {
          _verificationFailed = false; // Hide resend option after successful request
        });
      } else {
        final responseData = json.decode(response.body);
        throw Exception(responseData['message'] ?? 'Failed to resend verification code');
      }
    } catch (error, stackTrace) {
      print('❌ Error resending verification code:');
      print('   - Error type: ${error.runtimeType}');
      print('   - Error message: $error');
      if (error is http.ClientException) {
        print('   - Request URI: ${error.uri}');
        print('   - Request method: ${error.message}');
      }
      print('   - Stack trace: $stackTrace');
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${error.toString()}'),
        backgroundColor: Colors.red,
      ));
    } finally {
      setState(() {
        _isLoading = false;
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
                  if (_verificationFailed) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _isLoading ? null : _resendVerificationCode,
                      child: const Text(
                        'Resend Verification Code',
                        style: TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else
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
