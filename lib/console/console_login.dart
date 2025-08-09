// lib/console/console_login.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'console_api_service.dart';
import 'console.dart';

// --- Color Constants ---
const kTealColor = Colors.teal;
const kWhiteColor = Colors.white;
const kGreyColor = Color(0xFFF2F2F2);
const kDarkTextColor = Color(0xFF333333);

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  _AdminLoginPageState createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        // Save admin login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_type', 'admin');
        await prefs.setBool('is_logged_in', true);
        
        // Initialize and register FCM token in background
        Future.microtask(() async {
          try {
            final notificationService = NotificationService();
            await notificationService.initialize();
            final token = await notificationService.getFcmToken();
            if (token != null) {
              debugPrint('FCM token obtained for admin, registering with backend...');
              await notificationService.registerPendingFcmToken();
              debugPrint('FCM token registered with user info');
            }
          } catch (e) {
            debugPrint('Error registering FCM token: $e');
            // Continue with login even if FCM registration fails
          }
        });
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminConsolePage()),
          );
        }
      } else {
        // Build the error message including the retry after duration if available
        final errorMessage = result.error ?? 'Login failed. Please try again.';
        final retryMessage = result.retryAfter != null 
            ? '\n${result.formattedRetryAfter}'
            : '';
            
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('$errorMessage$retryMessage'),
              duration: const Duration(seconds: 5), // Longer duration to read the message
              showCloseIcon: true,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error during login: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('An error occurred. Please try again.'),
            duration: Duration(seconds: 5),
            showCloseIcon: true,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreyColor,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(32.0),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: kTealColor, size: 60),
                const SizedBox(height: 20),
                const Text(
                  'Admin Console Login',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kDarkTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'If you landed here by accident, please go back to login as the correct user type.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 30),
                _buildTextField(_usernameController, 'Username', Icons.person_outline),
                const SizedBox(height: 20),
                _buildTextField(_passwordController, 'Password', Icons.lock_outline_rounded, isPassword: true),
                const SizedBox(height: 40),
                _isLoading
                    ? const CircularProgressIndicator(color: kTealColor)
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kTealColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Login',
                            style: TextStyle(fontSize: 18, color: kWhiteColor),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextField _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kTealColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kTealColor, width: 2),
        ),
      ),
    );
  }
}