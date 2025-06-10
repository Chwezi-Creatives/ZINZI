//cspell:disable
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for system UI overlay style
import 'dart:ui'; // For ImageFilter

// Import your page routes (Assuming these paths are correct)
import 'package:zinzi/chefsignup222.dart';
import 'package:zinzi/Transporter_login.dart';
import 'package:zinzi/transporter_signup.dart';
import 'package:zinzi/chef_login_modular.dart';
import 'package:zinzi/prodsignup.dart';
import 'package:zinzi/producer_login_modular.dart';
import 'package:zinzi/signup_page.dart';
import 'package:zinzi/user_login_modular.dart';
import 'package:zinzi/stakeholdersignup.dart' as stakeholder_signup;
import 'package:zinzi/stk_login_modular.dart';

// --- Constants ---
// Refined Color Palette (kept similar for consistency)
const Color primaryTeal = Color(0xFF00796B); // Main action color
const Color darkTeal = Color(0xFF004D40); // Headings and important text
const Color accentTeal = Color(0xFF009688); // Secondary actions, highlights
const Color lightTeal = Color(0xFFB2DFDB); // Borders, subtle backgrounds
const Color lighterTeal = Color(0xFFE0F2F1); // Background gradient
const Color whiteColor = Colors.white;
const Color subtleTextColor =
    Color(0xFF616161); // Adjusted for slightly better contrast
const Color errorColor = Color(0xFFD32F2F);
const Color disabledColor = Colors.grey;
const Color cardBackgroundColor =
    Colors.white70; // Slightly opaque white for the card

// --- Main Widget ---
class SignUpOrLoginPage extends StatefulWidget {
  const SignUpOrLoginPage({super.key});

  @override
  State<SignUpOrLoginPage> createState() => _SignUpOrLoginPageState();
}

class _SignUpOrLoginPageState extends State<SignUpOrLoginPage>
    with TickerProviderStateMixin {
  // --- State ---
  late AnimationController _entryAnimationController;
  late Animation<Offset> _slideAnimationCard;
  late Animation<double>
      _fadeAnimationContent; // Fade in card content + buttons

  late AnimationController _mascotController;
  late Animation<Offset> _mascotFloat;

  final List<String> roles = const [
    // Made const
    "User",
    "Chef",
    "Producer",
    "Transporter / Rider",
    "Stakeholder"
  ];
  String? selectedRole = "User"; // Initialize with "User" as default
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // --- Initialization and Disposal ---
  @override
  void initState() {
    super.initState();

    // Combined entry animation controller
    _entryAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
          milliseconds: 900), // Slightly longer for smoother feel
    );

    // Card slides up
    _slideAnimationCard = Tween<Offset>(
      begin: const Offset(0.0, 0.5), // Start lower
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryAnimationController,
        curve: Curves.easeOutQuart, // Smoother curve
      ),
    );

    // Content fades in after slide starts
    _fadeAnimationContent = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryAnimationController,
        curve: const Interval(0.3, 1.0,
            curve: Curves.easeIn), // Start fade after 30% of slide
      ),
    );

    // Mascot animation
    _mascotController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Slower float
    )..repeat(reverse: true);

    _mascotFloat = Tween<Offset>(
      begin: const Offset(0, -0.05), // Subtler float
      end: const Offset(0, 0.05),
    ).animate(
        CurvedAnimation(parent: _mascotController, curve: Curves.easeInOut));

    // Start animations after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _entryAnimationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entryAnimationController.dispose();
    _mascotController.dispose();
    super.dispose();
  }

  // --- Navigation ---
  void _navigateToPage(Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0); // Slide from right
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: Curves.easeInOutCubic)); // Smooth curve
          final offsetAnimation = animation.drive(tween);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration:
            const Duration(milliseconds: 450), // Slightly longer duration
      ),
    );
  }

  // --- Event Handlers ---
  void _handleLoginTap() {
    if (_formKey.currentState?.validate() ?? false) {
      Widget? targetPage; // Use nullable Widget
      switch (selectedRole) {
        case 'User':
          targetPage = const UserLoginPageModular();
          break;
        case 'Chef':
          targetPage = const ChefLoginPageModular();
          break;
        case 'Producer':
          targetPage = const ProducerLoginPageModular();
          break;
        case 'Transporter / Rider':
          targetPage = const TransporterLoginPage();
          break;
        case 'Stakeholder':
          targetPage = const StakeholderLoginPageModular();
          break;
      }
      if (targetPage != null) {
        _navigateToPage(targetPage);
      }
    } else {
      _showValidationError();
    }
  }

  void _handleSignUpTap() {
    if (_formKey.currentState?.validate() ?? false) {
      Widget? targetPage; // Use nullable Widget
      switch (selectedRole) {
        case 'User':
          targetPage = const UserSignUpPage();
          break;
        case 'Chef':
          // Consider renaming ChefSignUpPageBetterNew if it's the final version
          targetPage = ChefSignUpPageBetterNew();
          break;
        case 'Producer':
          targetPage = const ProducerSignUpPage();
          break;
        case 'Transporter / Rider':
          targetPage = const TransporterSignUpPage();
          break;
        case 'Stakeholder':
          targetPage = const stakeholder_signup.StakeholderSignUpPage();
          break;
      }
      if (targetPage != null) {
        _navigateToPage(targetPage);
      }
    } else {
      _showValidationError();
    }
  }

  void _showValidationError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please select your role first.'),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating, // Modern look
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Set status bar style for better integration with the gradient
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent, // Make status bar transparent
      statusBarIconBrightness:
          Brightness.dark, // Icons dark for light background
    ));

    return Scaffold(
      // No AppBar needed, extend body behind status bar handled by SafeArea
      body: Container(
        // Use a simpler, cleaner gradient
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [lighterTeal, lightTeal], // Subtle transition
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          // Ensures content is below status bar
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0), // Consistent padding
              // Add ConstrainedBox to limit the width of the content column
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: 500), // Set a max width (adjust as needed)
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Optional Mascot
                      SlideTransition(
                        position: _mascotFloat,
                        child: Image.asset(
                          "assets/images/acc.png", // Ensure this path is correct
                          height: 70, // Slightly smaller
                        ),
                      ),
                      const SizedBox(height: 20), // Increased spacing

                      // Animated Card
                      SlideTransition(
                        position: _slideAnimationCard,
                        child: _buildRoleSelectionCard(),
                      ),
                      const SizedBox(height: 35), // Increased spacing

                      // Animated Buttons
                      FadeTransition(
                        opacity:
                            _fadeAnimationContent, // Fade buttons in with content
                        child: _buildActionButtons(),
                      ),
                      const SizedBox(height: 20), // Bottom padding
                    ],
                  ),
                ), // Close Form
              ), // Close ConstrainedBox
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  /// Builds the main card for role selection with glassmorphism effect.
  Widget _buildRoleSelectionCard() {
    // Removed tablet check and cardWidth, width is now controlled by parent ConstrainedBox
    // final isTablet = MediaQuery.of(context).size.width > 600;
    // final cardWidth = isTablet ? 500.0 : null; // Let it expand on mobile

    return ClipRRect(
      // Clip the BackdropFilter effect
      borderRadius: BorderRadius.circular(25.0), // Softer corners
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // More subtle blur
        child: Container(
          // width: cardWidth, // Removed width property
          padding: const EdgeInsets.symmetric(
              horizontal: 24.0, vertical: 30.0), // Generous padding
          decoration: BoxDecoration(
            // Removed color, border, and boxShadow to blend with background
            color: Colors.transparent, // Explicitly set to transparent
            borderRadius: BorderRadius.circular(25.0),
            // border: Border.all(color: whiteColor.withOpacity(0.2), width: 1.0), // Subtle border - REMOVED
            // boxShadow: [ // Soft shadow for depth - REMOVED
            //    BoxShadow(
            //      color: Colors.black.withOpacity(0.08),
            //      blurRadius: 20,
            //      spreadRadius: -5,
            //      offset: const Offset(0, 5),
            //    ),
            // ]
          ),
          child: FadeTransition(
            opacity: _fadeAnimationContent, // Fade content inside the card
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title Text
                Text(
                  "Welcome!", // Simpler title
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: darkTeal,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtitle Text
                Text(
                  "Select your role to get started",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: subtleTextColor,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25), // Increased spacing

                // Role Dropdown
                _buildRoleDropdown(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the styled DropdownButtonFormField for role selection.
  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedRole,
      validator: (value) => value == null ? 'Please select a role' : null,
      // Improved styling
      decoration: InputDecoration(
        // labelText: 'I am a...', // Removed labelText
        // labelStyle: const TextStyle(color: primaryTeal), // Removed labelStyle
        hintText: 'Select Your Role', // Keep hint text as placeholder
        hintStyle: TextStyle(color: subtleTextColor.withOpacity(0.8)),
        prefixIcon:
            const Icon(Icons.person_outline, color: primaryTeal, size: 22),
        filled: false, // Set to false to make it transparent
        // fillColor: whiteColor.withOpacity(0.8), // Removed fill color
        contentPadding: const EdgeInsets.symmetric(
            vertical: 16.0, horizontal: 16.0), // Comfortable padding
        // Use UnderlineInputBorder for a minimalist look
        border: UnderlineInputBorder(
          // Default border (usually not visible)
          borderSide: BorderSide(color: subtleTextColor.withOpacity(0.5)),
        ),
        enabledBorder: UnderlineInputBorder(
          // Border when enabled but not focused
          borderSide: BorderSide(color: subtleTextColor.withOpacity(0.5)),
        ),
        focusedBorder: const UnderlineInputBorder(
          // Border when focused
          borderSide:
              BorderSide(color: primaryTeal, width: 2.0), // Thicker highlight
        ),
        errorBorder: const UnderlineInputBorder(
          // Border when there's an error
          borderSide: BorderSide(color: errorColor, width: 1.0),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          // Border when focused with an error
          borderSide: BorderSide(
              color: errorColor, width: 2.0), // Thicker error highlight
        ),
      ),
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: primaryTeal), // Rounded icon
      dropdownColor: lighterTeal, // Match background theme slightly
      // Add a disabled header item to the list
      items: [
        // Non-selectable header item
        DropdownMenuItem<String>(
          value: null, // Use null or a unique value that won't be selected
          enabled: false, // Make it non-selectable
          child: Text(
            'I am a...',
            style: TextStyle(
              fontSize: 16,
              color: subtleTextColor.withOpacity(0.7), // Slightly faded color
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Selectable role items
        ...roles.map((String role) {
          return DropdownMenuItem<String>(
            value: role,
            child: Text(
              role,
              style:
                  const TextStyle(fontSize: 16, color: darkTeal), // Clear text
            ),
          );
        }),
      ],
      onChanged: (String? newValue) {
        // Prevent setting state if the disabled header (null value) is somehow passed
        if (newValue != null) {
          setState(() {
            selectedRole = newValue;
          });
        }
        // Alternatively, handle the null case explicitly if needed,
        // but `enabled: false` should prevent selection.
      },
    );
  }

  /// Builds the Sign Up and Log In action buttons.
  Widget _buildActionButtons() {
    // Common Button Style
    final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: primaryTeal,
      foregroundColor: whiteColor,
      minimumSize: const Size(double.infinity, 52), // Consistent height
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), // Match dropdown/card
      ),
      elevation: 3,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );

    // Removed outlinedButtonStyle as it's no longer needed for the primary layout

    return Column(
      children: [
        // Log In Button (Primary Action)
        ElevatedButton(
          onPressed: _handleLoginTap, // Changed to login handler
          style: elevatedButtonStyle,
          child: const Text("Log In"), // Changed text
        ),
        const SizedBox(height: 20), // Adjusted spacing

        // "Don't have an account?" Row
        Row(
          mainAxisAlignment:
              MainAxisAlignment.center, // Center the text and button
          children: [
            Text(
              "Don't have an account?",
              style: TextStyle(
                  fontSize: 14, color: subtleTextColor.withOpacity(0.9)),
            ),
            const SizedBox(width: 6), // Space between text and button
            // Sign Up Text Button (Secondary Action)
            TextButton(
              onPressed: _handleSignUpTap, // Changed to signup handler
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero, // Remove default padding
                minimumSize: Size.zero, // Allow minimum size
                tapTargetSize:
                    MaterialTapTargetSize.shrinkWrap, // Reduce tap area
                foregroundColor: accentTeal, // Use accent color for the link
              ),
              child: const Text(
                "Sign Up",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold, // Make it stand out slightly
                  // decoration: TextDecoration.underline, // Optional: Add underline
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
