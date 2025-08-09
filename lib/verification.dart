//cspell:disable
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zinzi/transooter_dash_before_mapbox.dart';
import 'user_metrics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chef_dash8888.dart'; // Import for Chef Dashboard
import 'produ_dash22.dart'; // Import for Producer Dashboard
import 'package:flutter/foundation.dart';

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
    debugPrint('🔍 Loading user data from SharedPreferences...');
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
            debugPrint('🔍 Converted int user_id to string: $userIdString');
          }
        } catch (e) {
          debugPrint('⚠️ Error reading user_id as int: $e');
        }
      }
      
      // Get other user data
      final userType = prefs.getString('user_type');
      final transporterId = prefs.getString('transporter_id');

      debugPrint('📥 Loaded user data:');
      debugPrint('   - User ID: $userIdString');
      debugPrint('   - User Type: $userType');
      debugPrint('   - Transporter ID: $transporterId');

      // Validate required fields
      if (userIdString == null || userIdString.isEmpty) {
        debugPrint('❌ user_id is null or empty in SharedPreferences');
      } else {
        debugPrint('✅ Valid user ID: $userIdString');
      }

      setState(() {
        _userId = userIdString; // Store as string in the state
        _userType = userType;
        // Use transporterId if available, otherwise fall back to user_id
        _transporterId = transporterId ?? userIdString ?? '';
        _isUserDataLoaded = true; // Mark as loaded to prevent infinite loading
      });
      
      debugPrint('✅ User data loading completed');
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading user data:');
      debugPrint('   - Error: $e');
      debugPrint('   - Stack trace: $stackTrace');
      setState(() {
        _isUserDataLoaded = true; // Still mark as loaded to avoid infinite loading
      });
    }
  }

  Future<void> _verifyEmail() async {
    debugPrint('🔐 Starting email verification...');
    debugPrint('   - _isUserDataLoaded: $_isUserDataLoaded');
    debugPrint('   - _userId: $_userId');
    debugPrint('   - _userType: $_userType');
    debugPrint('   - Code entered: ${_codeController.text.trim()}');
    
    // Check form validation
    final isFormValid = _formKey.currentState?.validate() ?? false;
    debugPrint('   - Form validation: $isFormValid');
    
    // Ensure user data and form state are valid before proceeding
    if (!_isUserDataLoaded || _userId == null || _userType == null || !isFormValid) {
      debugPrint('❌ Validation failed:');
      if (!_isUserDataLoaded) debugPrint('      - User data not loaded');
      if (_userId == null) debugPrint('      - User ID is null');
      if (_userType == null) debugPrint('      - User type is null');
      if (!isFormValid) debugPrint('      - Form validation failed');
      
      // Reload user data in case it failed to load previously
      if (!_isUserDataLoaded || _userId == null || _userType == null) {
        debugPrint('🔄 Attempting to reload user data...');
        await _loadUserData();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Please make sure you have entered the code and user data is available.'),
      ));
      return;
    }
    
    debugPrint('✅ All validations passed, proceeding with verification...');

    setState(() {
      _isLoading = true; // Set loading state
    });

    try {
      // Convert user ID to int for the API
      final userIdInt = int.tryParse(_userId!);

      if (userIdInt == null) {
        debugPrint('❌ Invalid user ID format: "$_userId"');
        throw Exception('Invalid user ID format. Expected a number but got: $_userId');
      }

      final requestBody = {
        'user_id': userIdInt,
        'verification_code': _codeController.text.trim(),
        'user_type': _userType,
      };
      
      debugPrint('📤 Sending verification request to: $apibaseurl/rr/verify_user');
      debugPrint('   - Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/verify_user'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      
      debugPrint('📥 Received response:');
      debugPrint('   - Status code: ${response.statusCode}');
      debugPrint('   - Body: ${response.body}');

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
      debugPrint('❌ Error during verification:');
      debugPrint('   - Error: $error');
      debugPrint('   - Stack trace: $stackTrace');
      
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
    debugPrint('🔄 Starting verification code resend process...');
    
    if (!_isUserDataLoaded || _userId == null || _userType == null) {
      final errorMsg = '❌ User information not available. ' +
          'isUserDataLoaded: $_isUserDataLoaded, ' +
          'userId: $_userId, userType: $_userType';
      debugPrint(errorMsg);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('User information not available. Please try again.'),
      ));
      return;
    }

    debugPrint('🔍 User data loaded:');
    debugPrint('   - User ID: $_userId (type: ${_userId.runtimeType})');
    debugPrint('   - User Type: $_userType (type: ${_userType.runtimeType})');
    debugPrint('   - Transporter ID: $_transporterId');

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
      debugPrint('📤 Preparing verification code resend request:');
      debugPrint('   - Endpoint: $apibaseurl/rr/resend_verification_email');
      debugPrint('   - Headers: {Content-Type: application/json}');
      debugPrint('   - Request body:');
      debugPrint('     - user_id: $userIdInt (type: ${userIdInt.runtimeType})');
      debugPrint('     - user_type: "$_userType" (type: ${_userType.runtimeType})');
      debugPrint('   - Full JSON payload: ${jsonEncode(requestBody)}');
      
      final stopwatch = Stopwatch()..start();
      debugPrint('   - Sending request...');
      
      final response = await http.post(
        Uri.parse('$apibaseurl/rr/resend_verification_email'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      stopwatch.stop();
      debugPrint('📥 Received response:');
      debugPrint('   - Status code: ${response.statusCode}');
      debugPrint('   - Response time: ${stopwatch.elapsedMilliseconds}ms');
      debugPrint('   - Headers: ${response.headers}');
      debugPrint('   - Response body:');
      debugPrint('     ${response.body}');
      
      // Log the raw response for debugging
      if (response.body.isNotEmpty) {
        try {
          final jsonResponse = jsonDecode(response.body);
          debugPrint('   - Parsed JSON response: $jsonResponse');
        } catch (e) {
          debugPrint('   - Could not parse response as JSON: $e');
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
      debugPrint('❌ Error resending verification code:');
      debugPrint('   - Error type: ${error.runtimeType}');
      debugPrint('   - Error message: $error');
      if (error is http.ClientException) {
        debugPrint('   - Request URI: ${error.uri}');
        debugPrint('   - Request method: ${error.message}');
      }
      debugPrint('   - Stack trace: $stackTrace');
      
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
          title: Text(
            'Email Verification',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Email Verification',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.teal,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Background with subtle gradient
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.teal[50]!,
                    ],
                  ),
                ),
              ),
              // Overlaying content
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                    minWidth: constraints.maxWidth,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth > 500 
                            ? constraints.maxWidth * 0.15 
                            : 24.0,
                        vertical: 24.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Verification image with better spacing
                          Container(
                            height: constraints.maxHeight * 0.15,
                            margin: const EdgeInsets.only(top: 16.0, bottom: 40.0),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/verification.jpg',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  // Main heading with better hierarchy
                  Text(
                    'Verify Your Email',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.teal[900],
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Subtitle text
                  Text(
                    'We\'ve sent a verification code to your email',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: 'Verification Code',
                        labelStyle: GoogleFonts.poppins(
                          color: Colors.teal[800],
                          fontSize: 15,
                        ),
                        floatingLabelStyle: GoogleFonts.poppins(
                          color: Colors.teal[700],
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.teal[700]!, 
                            width: 2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[400]!,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[400]!,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        errorStyle: GoogleFonts.poppins(
                          color: Colors.red[600],
                          fontSize: 13,
                        ),
                      ),
                      style: GoogleFonts.poppins(
                        color: Colors.black87,
                        fontSize: 15,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the verification code';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // Clear any existing error when user types
                        if (_formKey.currentState?.validate() ?? false) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Verify button with loading state
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[700],
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        // Add shadow and animation
                        shadowColor: Colors.teal.withOpacity(0.3),
                        animationDuration: const Duration(milliseconds: 200),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'VERIFY EMAIL',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Resend code or status message
                  if (_verificationFailed) ...[
                    Column(
                      children: [
                        Text(
                          'Code not received?',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[700],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _isLoading ? null : _resendVerificationCode,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            backgroundColor: Colors.teal[50],
                          ),
                          child: Text(
                            'Resend Verification Code',
                            style: GoogleFonts.poppins(
                              color: Colors.teal[800],
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  ] else
                    Text(
                      "If you don't see the email, check your spam folder or wait a moment.",
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  
                  // Add some bottom padding for better scrolling on small devices
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}