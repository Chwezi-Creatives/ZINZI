import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// App colors
const Color primaryTeal = Color(0xFF00796B);
const Color darkTeal = Color(0xFF00695C);
const Color lightTeal = Color(0xFFB2DFDB);
const Color textOnTeal = Colors.white;
const Color errorColor = Color(0xFFC62828);
const Color subtleTextColor = Color(0xFF757575);
const Color textFieldFillColor = Color(0xFFF5F5F5);

// API base URL with fallback to prevent null errors
final String apibaseurl = dotenv.get('API_BASE_URL-intranet', fallback: 'https://your-default-api-url.com');

class PasswordRecoveryScreen extends StatefulWidget {
  final String userType;
  final String? email;

  const PasswordRecoveryScreen({
    Key? key,
    required this.userType,
    this.email,
  }) : super(key: key);

  @override
  _PasswordRecoveryScreenState createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  // Separate FormKeys for each step
  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyCode = GlobalKey<FormState>();
  final _formKeyPassword = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _verificationEmail; // Will store the canonical (trimmed, lowercased) email
  String? _verificationCode;

  void _debugPrint(String message) {
    if (kDebugMode) {
      debugPrint('PasswordRecoveryScreen: $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _debugPrint('initState called');
    if (widget.email != null) {
      _debugPrint('Initial email set to ${widget.email}');
      _emailController.text = widget.email!;
      // For consistency, if an initial email is provided, _verificationEmail could also be set
      // to its canonical form, though it will be properly set upon the first request.
      // _verificationEmail = widget.email!.trim().toLowerCase(); // Optional: if needed before first API call
    }
    _debugPrint('Current userType: ${widget.userType}');
  }

  @override
  void dispose() {
    _debugPrint('Disposing controllers');
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestPasswordReset() async {
    _debugPrint('Starting password reset request');
    // Validate only the email form
    if (_formKeyEmail.currentState == null || !_formKeyEmail.currentState!.validate()) {
      _debugPrint('Email form validation failed');
      return;
    }

    _debugPrint('Setting loading state for password reset request');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase(); // Use canonical email
    final userType = widget.userType;
    final url = '$apibaseurl/auth/request-password-reset';
    
    _debugPrint('Sending request to $url with Email: $email, UserType: $userType');
    
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'user_type': userType,
        }),
      );

      _debugPrint('Response status: ${response.statusCode}');
      _debugPrint('Response body: ${response.body}');

      if (response.statusCode == 202) {
        setState(() {
          _verificationEmail = email; // Store the canonical email
          _currentStep = 1;
          _codeController.clear(); // Clear previous code if any
        });
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to send verification code');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    _debugPrint('Starting code verification');
    // Validate only the code form
    if (_formKeyCode.currentState == null || !_formKeyCode.currentState!.validate()) {
      _debugPrint('Code form validation failed');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/auth/verify-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _verificationEmail, // Use stored canonical email
          'code': _codeController.text.trim(),
          'user_type': widget.userType,
        }),
      );

      _debugPrint('Verify code response status: ${response.statusCode}');
      _debugPrint('Verify code response body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _verificationCode = _codeController.text.trim();
          _currentStep = 2;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Invalid verification code');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    _debugPrint('Starting password reset');
    // Validate only the password form
    if (_formKeyPassword.currentState == null || !_formKeyPassword.currentState!.validate()) {
      _debugPrint('Password form validation failed');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$apibaseurl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _verificationEmail, // Use stored canonical email
          'code': _verificationCode,
          'user_type': widget.userType,
          'new_password': _passwordController.text,
        }),
      );
      
      _debugPrint('Reset password response status: ${response.statusCode}');
      _debugPrint('Reset password response body: ${response.body}');

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop(true); // Indicate success
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to reset password');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null; // Clear error when navigating steps
      });
    }
  }

  void _nextStep() {
    _debugPrint('Next button pressed. Current step: $_currentStep');
    
    bool isStepValid = false;
    switch (_currentStep) {
      case 0:
        if (_formKeyEmail.currentState != null) {
          isStepValid = _formKeyEmail.currentState!.validate();
        }
        break;
      case 1:
        if (_formKeyCode.currentState != null) {
          isStepValid = _formKeyCode.currentState!.validate();
        }
        break;
      case 2:
        if (_formKeyPassword.currentState != null) {
          isStepValid = _formKeyPassword.currentState!.validate();
        }
        break;
      default:
        _debugPrint('Unknown step: $_currentStep for validation');
        return;
    }

    if (!isStepValid) {
      _debugPrint('Form validation failed for step $_currentStep');
      return;
    }
    
    // Proceed with action for the current step
    // API call methods (_requestPasswordReset, etc.) internally re-validate their specific forms,
    // which is fine (belt-and-suspenders).
    switch (_currentStep) {
      case 0:
        _debugPrint('Proceeding to request password reset');
        _requestPasswordReset();
        break;
      case 1:
        _debugPrint('Proceeding to verify code');
        _verifyCode();
        break;
      case 2:
        _debugPrint('Proceeding to reset password');
        _resetPassword();
        break;
      default:
        _debugPrint('Unknown step action: $_currentStep');
    }
  }

  // This function checks current input values to enable/disable the 'Continue' button.
  // It does not show validation errors; that's the job of TextFormField validators.
  bool _validateCurrentStepForButton() {
    // _debugPrint('Validating inputs for button enable/disable, step $_currentStep');
    switch (_currentStep) {
      case 0: // Email step
        return _emailController.text.isNotEmpty &&
               RegExp(r'^[^@]+@[^\s@]+\.[^\s@]+$').hasMatch(_emailController.text.trim());
      case 1: // Code step
        final code = _codeController.text.trim();
        return code.isNotEmpty &&
               code.length == 6 &&
               RegExp(r'^[0-9]+$').hasMatch(code);
      case 2: // Password step
        final password = _passwordController.text;
        return password.isNotEmpty &&
               password.length >= 8 &&
               password.contains(RegExp(r'[A-Z]')) &&
               password.contains(RegExp(r'[0-9]')) &&
               password == _confirmPasswordController.text;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: primaryTeal,
        foregroundColor: textOnTeal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep > 0) {
              _previousStep();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        // The main Form widget is removed from here.
        // Each step will have its own Form.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(primaryTeal),
              minHeight: 6,
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  _buildEmailStep(),
                  _buildVerificationStep(),
                  _buildPasswordStep(),
                ],
              ),
            ),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: errorColor, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 24),
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _previousStep,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryTeal,
                        side: const BorderSide(color: primaryTeal),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading || !_validateCurrentStepForButton()
                        ? null
                        : _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryTeal,
                      foregroundColor: textOnTeal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: primaryTeal.withOpacity(0.5),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(textOnTeal),
                            ),
                          )
                        : Text(_currentStep < 2 ? 'Continue' : 'Reset Password'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _formKeyEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reset Password',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith( // headlineSmall is more appropriate
              color: primaryTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your existing email to receive a verification code.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: subtleTextColor,
            ),
          ),
          const SizedBox(height: 24),
          
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'Enter your email',
              labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
              hintStyle: const TextStyle(color: subtleTextColor),
              prefixIcon: const Icon(Icons.email_outlined, color: primaryTeal),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              errorStyle: const TextStyle(color: errorColor, fontSize: 11)
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email address';
              }
              if (!RegExp(r'^[^@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
            onChanged: (value) {
              // Call setState to re-evaluate _validateCurrentStepForButton for button's enabled state
              _debugPrint('Email field changed. Triggering setState for button update.');
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    return Form(
      key: _formKeyCode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter Verification Code',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: primaryTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // Use _verificationEmail (canonical form) if available
            'We sent a 6-digit code to ${_verificationEmail ?? _emailController.text}.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: subtleTextColor,
            ),
          ),
          const SizedBox(height: 24),
          
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(
              labelText: 'Verification Code',
              hintText: 'Enter 6-digit code',
              counterText: "", // Hide the default counter
              labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
              hintStyle: const TextStyle(color: subtleTextColor),
              prefixIcon: const Icon(Icons.sms_outlined, color: primaryTeal),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              errorStyle: const TextStyle(color: errorColor, fontSize: 11)
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter the verification code';
              }
              if (value.trim().length != 6) {
                return 'Code must be 6 digits';
              }
              if (!RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
                return 'Code must contain only numbers';
              }
              return null;
            },
            onChanged: (value) {
              _debugPrint('Code field changed. Triggering setState for button update.');
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // Adjusted alignment
            children: [
              TextButton(
                onPressed: _isLoading ? null : () {
                  setState(() {
                    _currentStep = 0; // Go back to email step
                    _errorMessage = null;
                    // _codeController.clear(); // Already cleared when moving to step 1 or on resend
                  });
                },
                style: TextButton.styleFrom(foregroundColor: primaryTeal),
                child: const Text('Change Email'),
              ),
              TextButton(
                onPressed: _isLoading ? null : () {
                    _debugPrint('Resend code pressed.');
                    // _codeController.clear(); // No need to clear here, _requestPasswordReset will handle step change
                    _requestPasswordReset(); // This will use _emailController.text
                  },
                style: TextButton.styleFrom(foregroundColor: primaryTeal),
                child: const Text('Resend Code'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _formKeyPassword,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create New Password',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: primaryTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your new password must be at least 8 characters long and include an uppercase letter and a number.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: subtleTextColor, // Changed from Colors.grey[600] for consistency
                ),
          ),
          const SizedBox(height: 24),
          
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New Password',
              hintText: 'Enter your new password',
              labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
              hintStyle: const TextStyle(color: subtleTextColor),
              prefixIcon: const Icon(Icons.lock_outline, color: primaryTeal),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              errorStyle: const TextStyle(color: errorColor, fontSize: 11)
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a password';
              }
              if (value.length < 8) {
                return 'Password must be at least 8 characters';
              }
              if (!value.contains(RegExp(r'[A-Z]'))) {
                return 'Include at least one uppercase letter';
              }
              if (!value.contains(RegExp(r'[0-9]'))) {
                return 'Include at least one number';
              }
              // Also validate against confirm password if it has been touched, to provide instant feedback.
              // However, the main confirm password check is in its own validator and _validateCurrentStepForButton.
              // if (_confirmPasswordController.text.isNotEmpty && value != _confirmPasswordController.text) {
              //   return 'Passwords do not match';
              // }
              return null;
            },
            onChanged: (value) {
              _debugPrint('Password field changed. Triggering setState for button update.');
              setState(() {
                // If you want confirm password to re-validate when password changes:
                // if (_formKeyPassword.currentState != null && _confirmPasswordController.text.isNotEmpty) {
                //   _formKeyPassword.currentState!.validate();
                // }
              });
            },
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              hintText: 'Re-enter your new password',
              labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
              hintStyle: const TextStyle(color: subtleTextColor),
              prefixIcon: const Icon(Icons.lock_outline, color: primaryTeal),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
              errorStyle: const TextStyle(color: errorColor, fontSize: 11)
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
            onChanged: (value) {
              _debugPrint('Confirm password field changed. Triggering setState for button update.');
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}