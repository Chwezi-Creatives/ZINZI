import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi2/transooter_dash_before_mapbox.dart';
import 'package:zinzi2/transporter_signup.dart';
import 'notifications/fcm_service.dart';
//import 'transoorter_dash_new.dartp'; // being tested for now

// --- Hardcoded Colors (Copied) ---
const Color primaryTeal = Color(0xFF00796B);
const Color lightTeal = Color(0xFFB2DFDB);
// const Color lighterTeal = Color(0xFFE0F2F1); // Not needed here
const Color darkTeal = Color(0xFF004D40);
const Color accentTeal = Color(0xFF009688);
const Color whiteColor = Colors.white;
const Color lightBackgroundColor = Color(0xFFF5F5F5);
const Color textFieldFillColor = Color(0x8AFFFFFF);
const Color subtleTextColor = Color(0xFF757575);
const Color errorColor = Color(0xFFD32F2F);
const Color disabledColor = Colors.grey;

// --- API Base URL (Ensure dotenv is loaded in main.dart) ---
final String apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url/api';


class TransporterLoginPage extends StatefulWidget {
  const TransporterLoginPage({super.key});

  @override
  _TransporterLoginPageState createState() => _TransporterLoginPageState();
}

class _TransporterLoginPageState extends State<TransporterLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Login Submission ---
  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);

       // --- Actual API Call ---
       try {
         final Uri uri = Uri.parse('$apibaseurl/rr/transporters/login');
         final response = await http.post(
           uri,
           headers: {'Content-Type': 'application/json; charset=UTF-8'},
           body: json.encode({
             'identifier': _identifierController.text.trim(),
             'password': _passwordController.text
           }),
         );

         if (!mounted) return;
         setState(() => _isLoading = false);

         if (response.statusCode == 200 || response.statusCode == 201) {
           final responseData = json.decode(response.body);
           final data = responseData['data'] as Map<String, dynamic>?;

           if (data != null && data.containsKey('transporter_id')) {
             final String transporterId = data['transporter_id'].toString();
             final String userType = 'transporter'; // Hardcoded for this page
             final bool verified = data['verified'] as bool? ?? false;
             final String email = data['email'] as String? ?? '';
             final String transporterName = data['transporter_name'] as String? ?? '';
             final String? phone = data['phone'] as String?; // Extract phone number if available

             // Save to SharedPreferences
             SharedPreferences prefs = await SharedPreferences.getInstance();
             await prefs.setString('transporter_id', transporterId);
             await prefs.setString('transporter_email', email);
             await prefs.setString('transporter_name', transporterName);
             await prefs.setString('user_type', userType);
             await prefs.setString('user_id', transporterId); // Standard key for splash
             if (phone != null) {
               await prefs.setString('user_phone', phone);
               print('Phone number saved: $phone');
             }
             await prefs.setBool('is_logged_in', true);
             // Register FCM token with user info (async, do not await)
             FCMService.registerTokenWithUserInfo();

             await Future.delayed(const Duration(milliseconds: 100)); // Small delay

             // Navigate ONLY if ID is valid and widget is still mounted
             if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransporterDashNew(transporterId: transporterId)//TransporterDashboardScreen(transporterId: transporterId), // Pass the non-null ID ths page ha sbeen  //commented out temporraliry to test a new page 
                  ),
                );
             }
           } else {
              // Handle case where ID is missing in response
              if (mounted) {
                 _showErrorSnackBar('Login successful, but failed to retrieve Transporter ID.');
              }
           }
           // Removed navigation from outside the null check (lines 94-95 were leftovers and are now removed)
         } else {
           String errorMessage = 'Login failed.';
           try {
             final responseData = json.decode(response.body);
             errorMessage = responseData['message'] ?? responseData['error'] ?? 'wrong password or name (Code: ${response.statusCode})';
           } catch (_) {}
           if (!mounted) return;
            _showErrorSnackBar(errorMessage);
         }
       } catch (e) {
         print("Login Exception: $e");
         if (mounted) {
           setState(() => _isLoading = false);
           if (!mounted) return;
            _showErrorSnackBar('An error occurred during login: $e');
         }
       }
       // --- End Actual API Call ---
       
    } else {
       if (!mounted) return;
     _showSnackBar('Please enter email and password.', isError: true);
    }
  }

  // --- Helper for SnackBar ---
  void _showSnackBar(String message, {bool isError = false}) {
  if (!mounted) return;
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
  void _showErrorSnackBar(String message) { _showSnackBar(message, isError: true); }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
         title: const Text('Transporter Login', style: TextStyle(color: whiteColor, fontWeight: FontWeight.w600)),
         backgroundColor: primaryTeal,
         elevation: 0,
         automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon( Icons.local_shipping_outlined, size: 80, color: primaryTeal, ),
                  const SizedBox(height: 25),
                  const Text( "Welcome Back, Rider!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkTeal), ),
                  const SizedBox(height: 8),
                  const Text( "Log in to manage your deliveries.", style: TextStyle(fontSize: 15, color: subtleTextColor), textAlign: TextAlign.center, ),
                  const SizedBox(height: 35),
                  _buildTextFormField(
                    controller: _identifierController,
                    labelText: "Email or Username",
                    hintText: "Enter your email or username",
                    icon: Icons.person_outline,
                    keyboardType: TextInputType.text,
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Enter your email or username";
                      // Accept either a valid email or a non-empty username
                      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!emailRegex.hasMatch(v) && v.length < 3) {
                        return "Enter a valid email or username";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextFormField( controller: _passwordController, labelText: "Password", hintText: "Enter your password", icon: Icons.lock_outline, obscureText: _obscurePassword, validator: (v) => (v == null || v.isEmpty) ? "Enter password" : null, suffixIcon: IconButton( icon: Icon( _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: primaryTeal.withOpacity(0.7), size: 20, ), onPressed: () => setState(() => _obscurePassword = !_obscurePassword), ), ),
                  const SizedBox(height: 10),
                  Align( alignment: Alignment.centerRight, child: TextButton( onPressed: () { _showSnackBar("Forgot Password tapped (Not Implemented)", isError: false); }, style: TextButton.styleFrom( padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, ), child: const Text("Forgot Password?", style: TextStyle(color: subtleTextColor, fontSize: 13)), ), ),
                  const SizedBox(height: 25),
                  _buildLoginButton(),
                  const SizedBox(height: 30),
                  _buildSignUpLink(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

   // --- UI Building Helpers ---
   Widget _buildTextFormField({ required TextEditingController controller, required String labelText, required String hintText, required IconData icon, TextInputType keyboardType = TextInputType.text, bool obscureText = false, String? Function(String?)? validator, Widget? suffixIcon, }) { return TextFormField( controller: controller, keyboardType: keyboardType, obscureText: obscureText, style: const TextStyle(color: darkTeal), decoration: InputDecoration( labelText: labelText, hintText: hintText, labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500), hintStyle: const TextStyle(color: subtleTextColor), prefixIcon: Icon(icon, color: primaryTeal, size: 20), suffixIcon: suffixIcon, filled: true, fillColor: textFieldFillColor, border: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: lightTeal, width: 1.0), ), enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: lightTeal, width: 1.0), ), focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryTeal, width: 1.5), ), errorBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: errorColor, width: 1.0), ), focusedErrorBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: errorColor, width: 1.5), ), contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0), errorStyle: const TextStyle(color: errorColor, fontSize: 11) ), validator: validator, ); }
   Widget _buildLoginButton() { return SizedBox( width: double.infinity, child: ElevatedButton( onPressed: _isLoading ? null : _submitLogin, style: ElevatedButton.styleFrom( backgroundColor: accentTeal, foregroundColor: whiteColor, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 2, disabledBackgroundColor: disabledColor.withOpacity(0.5), disabledForegroundColor: whiteColor.withOpacity(0.7), ), child: _isLoading ? const SizedBox( height: 20, width: 20, child: CircularProgressIndicator( strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(whiteColor), ), ) : const Text( "Log In", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), ), ); }
   Widget _buildSignUpLink() { return Row( mainAxisAlignment: MainAxisAlignment.center, children: [ const Text("Don't have an account?", style: TextStyle(color: subtleTextColor)), TextButton( onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransporterSignUpPage())); }, style: TextButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, ), child: const Text("Sign Up", style: TextStyle(color: primaryTeal, fontWeight: FontWeight.bold)), ), ], ); }
}