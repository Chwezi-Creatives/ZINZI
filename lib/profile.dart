import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math'; // Import for min function
import 'dart:async'; // Import for TimeoutException
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/allmeals.dart';
import 'package:zinzi2/blogview.dart';
import 'package:zinzi2/cart.dart' as cart; // Use prefix for clarity
import 'package:zinzi2/onboard.dart';
import 'package:zinzi2/signup_or_Login.dart';
// import 'package:zinzi2/splash.dart'; // Replaced with LandingPage for logout
import 'package:zinzi2/useranalytics.dart';
import 'social.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For network images
import 'package:shimmer/shimmer.dart'; // For loading effect
import 'package:intl/intl.dart'; // For date formatting

// --- Re-add Color Constants (or import from a shared file) ---
const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Clean background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
// Shimmer Colors
final Color kShimmerBaseColor = Colors.grey.shade300;
final Color kShimmerHighlightColor = Colors.grey.shade100;
// --- End Color Constants ---

// Use environment variable for API base URL
final apiBaseUrl = dotenv.env['API_BASE_URL'] ??
    dotenv.env['API_BASE_URL-intranet'] ??
    'https://default.url';

class ProfilePage extends StatefulWidget {
  // Use const constructor
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // --- Caching ---
  static Map<String, dynamic> _userDetailsCache = {};
  static DateTime? _userDetailsCacheTimestamp;
  static const Duration _userCacheDuration = Duration(minutes: 10);

  int? _userId;
  String? _userType;
  Map<String, dynamic> _userMetrics = {};
  Map<String, dynamic> _userPreferences = {};
  Map<String, dynamic> _userDetails = {};
  bool _isLoadingUserDetails = true; // Add this variable to track loading state
  bool _isLoading = true;
  String _fetchError = ''; // To store fetch errors

  // Image state
  String? _profileImagePath; // Local path for picked image
  String? _profileImageUrl; // To store the URL fetched from backend

  // Editing state
  final TextEditingController _weightController = TextEditingController();
  bool _isEditingWeight = false;
  String _originalWeight = ''; // Store original weight before editing

  @override
  void initState() {
    super.initState();
    _initializeProfile();
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _initializeProfile() async {
    await _loadUserIdAndType();
    await _loadImageFromPrefs(); // Load local image path first
    if (_userId != null) {
      // Use cache if available and fresh, otherwise fetch
      final now = DateTime.now();
      if (_userDetailsCache.isNotEmpty &&
          _userDetailsCacheTimestamp != null &&
          now.difference(_userDetailsCacheTimestamp!) < _userCacheDuration) {
        setState(() {
          _userDetails = Map<String, dynamic>.from(_userDetailsCache);
          _isLoadingUserDetails = false;
          _isLoading = false;
        });
      } else {
        await _fetchData();
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false); // Stop loading if no user ID
        _showErrorSnackBar('User not logged in.');
        // Optionally navigate to login screen
        // Navigator.of(context).pushReplacement(...);
      }
    }
  }

  Future<void> _loadUserIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
    // No setState needed here if values are only used in async methods later
    _userId = prefs.getInt('user_id');
    _userType = prefs.getString('user_type');
    print("Loaded User ID: $_userId, User Type: $_userType");
  }

  Future<void> _fetchData() async {
    if (!mounted) return; // Ensure widget is still mounted
    setState(() {
      _isLoading = true;
      _fetchError = ''; // Reset error on new fetch
    });
    try {
      // Fetch data concurrently for better performance
      await Future.wait([
        _fetchUserDetails(),
        _fetchMetrics(),
        _fetchPreferences(),
      ]);
      // Check for specific errors after fetches if needed
    } catch (e) {
      if (mounted) {
        print("Error during initial data fetch: $e");
        setState(() {
          _fetchError = "Failed to load profile data. Please try again.";
        });
      }
    } finally {
      // Ensure loading state is turned off even if there's an error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchUserDetails() async {
    if (_userId == null) return;
    final url =
        '$apiBaseUrl/rr/rusers/$_userId'; // Use path parameter style if API supports it
    // final url = '$apiBaseUrl/rr/rusers?user_id=$_userId'; // Or keep query param
    print("Fetching User Details from URL: $url");
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("User Details Response: ${response.statusCode} - ${response.body}");

      if (!mounted) return; // Check mounted after await

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        Map<String, dynamic>? userMap;

        // Handle different possible API response structures
        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('data')) {
            if (responseData['data'] is List &&
                responseData['data'].isNotEmpty &&
                responseData['data'][0] is Map) {
              userMap = Map<String, dynamic>.from(responseData['data'][0]);
            } else if (responseData['data'] is Map) {
              // API might return single user in 'data' map
              userMap = Map<String, dynamic>.from(responseData['data']);
            }
          } else if (!responseData.containsKey('message') &&
              responseData.isNotEmpty) {
            // Assume the map itself is the user data if no 'data' key and not just a message
            userMap = responseData;
          }
        } else if (responseData is List &&
            responseData.isNotEmpty &&
            responseData[0] is Map) {
          // Handle if API returns a list directly for single user query
          userMap = Map<String, dynamic>.from(responseData[0]);
        }
        if (userMap != null) {
          // Use .get with defaults for safety
          setState(() {
            _userDetails = {
              'User_Id': userMap!['user_id']?.toString() ??
                  userMap!['user_id']?.toString() ??
                  'N/A', // Check both cases
              'Name': userMap!['name'] ?? userMap!['name'] ?? 'N/A',
              'Email': userMap!['email'] ?? userMap!['email'] ?? 'N/A',
              'Phone_Number':
                  userMap!['phone_number'] ?? userMap!['phone_number'] ?? 'N/A',
              'Location': userMap!['location'] ?? userMap!['location'] ?? 'N/A',
              'Registration_Date': userMap!['registration_date'] ??
                  userMap!['registration_date'] ??
                  'N/A',
              // Extract profile picture URL if available (adjust key if needed)
              'profile_picture':
                  userMap!['profile_picture'] ?? userMap!['image'],
            };
            _isLoadingUserDetails = false; // Update loading state
            // Store the fetched image URL
            _profileImageUrl = _userDetails['profile_picture'];
            });
            _userDetailsCache = Map<String, dynamic>.from(_userDetails); // Update cache
            _userDetailsCacheTimestamp = DateTime.now();
        } else {
          print("User details parsing failed or data empty: $responseData");
          _showErrorSnackBar('Could not parse user details.');
        }
      } else {
        _showErrorSnackBar(
            'Failed to fetch user details. Status: ${response.statusCode}');
      }
    } on TimeoutException {
      print("Timeout fetching user details.");
      if (mounted)
        _showErrorSnackBar('Could not reach server. Please check connection.');
    } catch (error) {
      print("Error fetching user details: $error");
      if (mounted)
        _showErrorSnackBar('An error occurred fetching user details.');
    }
  }

  Future<void> _fetchMetrics() async {
    if (_userId == null) return;
    final url =
        '$apiBaseUrl/rr/metrics?user_id=$_userId'; // Assuming endpoint exists
    print("Fetching Metrics from URL: $url");
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("Metrics Response: ${response.statusCode} - ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Expecting list of metrics, take the first/latest one
        List<dynamic>? metricsList;
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('data') &&
            responseData['data'] is List) {
          metricsList = responseData['data'];
        } else if (responseData is List) {
          // Handle direct list response
          metricsList = responseData;
        }

        if (metricsList != null &&
            metricsList.isNotEmpty &&
            metricsList[0] is Map) {
          final metrics = Map<String, dynamic>.from(metricsList[0]);
          // Use .get with defaults and check case variations
          setState(() {
            _userMetrics = {
              'height':
                  (metrics['height'] ?? metrics['height'])?.toString() ?? 'N/A',
              'weight':
                  (metrics['weight'] ?? metrics['weight'])?.toString() ?? 'N/A',
              'bmi': (metrics['bmi'] ?? metrics['bmi'])?.toString() ??
                  '0', // Default BMI 0
              // Add other metrics as needed
            };
            // Initialize weight controller if editing is not active
            if (!_isEditingWeight) {
              _weightController.text = _userMetrics['weight'] ?? '';
              _originalWeight = _userMetrics['weight'] ?? ''; // Store original
            }
          });
        } else {
          print("Metrics data parsing failed or empty: $responseData");
          // Don't show snackbar, maybe profile can exist without metrics
        }
      } else {
        print('Could not fetch metrics. Status: ${response.statusCode}');
        // Optionally show snackbar, but might be too noisy if metrics are optional
        // _showErrorSnackBar('Could not fetch metrics.');
      }
    } on TimeoutException {
      print("Timeout fetching metrics.");
      if (mounted) _showErrorSnackBar('Could not reach server for metrics.');
    } catch (error) {
      print("Error fetching metrics: $error");
      if (mounted) _showErrorSnackBar('An error occurred fetching metrics.');
    }
  }

  Future<void> _fetchPreferences() async {
    if (_userId == null) return;
    // Adjust endpoint if necessary
    final url =
        '$apiBaseUrl/rr/preferences?user_id=$_userId'; // Assuming endpoint maps to list_preferences
    // final url = '$apiBaseUrl/rr/fetch_user_preferences?user_id=$_userId'; // Original
    print("Fetching Preferences from URL: $url");
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print("Preferences Response: ${response.statusCode} - ${response.body}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Expecting list of preferences, take the first one
        List<dynamic>? preferencesList;
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('data') &&
            responseData['data'] is List) {
          preferencesList = responseData['data'];
        } else if (responseData is List) {
          // Handle direct list response
          preferencesList = responseData;
        }

        if (preferencesList != null &&
            preferencesList.isNotEmpty &&
            preferencesList[0] is Map) {
          final preferences = Map<String, dynamic>.from(preferencesList[0]);
          // Use .get with defaults and check case variations
          setState(() {
            _userPreferences = {
              'goals': preferences['goals'] ?? preferences['goals'] ?? 'N/A',
              'diet_type':
                  preferences['diet_type'] ?? preferences['diet_type'] ?? 'N/A',
              'food_restrictions': preferences['food_restrictions'] ??
                  preferences['food_restrictions'] ??
                  'N/A',
              // Add other preferences
            };
          });
        } else {
          print("Preferences data parsing failed or empty: $responseData");
          // Don't show snackbar, maybe profile can exist without preferences
        }
      } else {
        print('Could not fetch preferences. Status: ${response.statusCode}');
        // _showErrorSnackBar('Could not fetch preferences.');
      }
    } on TimeoutException {
      print("Timeout fetching preferences.");
      if (mounted)
        _showErrorSnackBar('Could not reach server for preferences.');
    } catch (error) {
      print("Error fetching preferences: $error");
      if (mounted)
        _showErrorSnackBar('An error occurred fetching preferences.');
    }
  }

  Future<void> _pickImage() async {
    final imagePicker = ImagePicker();
    try {
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, // Compress image slightly
        maxWidth: 800, // Resize image
      );
      if (pickedFile != null && mounted) {
        setState(() {
          _profileImagePath = pickedFile.path;
        });
        _saveImageToPrefs(pickedFile.path);
        // TODO: Add logic here to upload the pickedFile.path to your backend/storage
        // await _uploadProfilePicture(File(pickedFile.path));
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) _showErrorSnackBar("Could not pick image: $e");
    }
  }

  // --- Placeholder for image upload ---
  // Future<void> _uploadProfilePicture(File imageFile) async {
  //   if (_userId == null) return;
  //   final url = '$apibaseurl/rr/users/$_userId/profile_picture'; // Example endpoint
  //   try {
  //     var request = http.MultipartRequest('POST', Uri.parse(url));
  //     request.files.add(await http.MultipartFile.fromPath('profile_pic', imageFile.path));
  //     // Add headers if needed (e.g., authorization)
  //     // request.headers.addAll({'Authorization': 'Bearer your_token'});
  //     var response = await request.send();
  //     if (response.statusCode == 200) {
  //       print("Profile picture uploaded successfully");
  //       // Optionally refetch user details to get the new URL
  //       // await _fetchUserDetails();
  //     } else {
  //        print("Profile picture upload failed: ${response.statusCode}");
  //        _showErrorSnackBar('Failed to upload profile picture.');
  //        // Revert local image display if upload fails?
  //        // setState(() => _profileImagePath = null); // Or load previous URL
  //     }
  //   } catch (e) {
  //     print("Error uploading profile picture: $e");
  //      _showErrorSnackBar('Error uploading profile picture.');
  //   }
  // }

  Future<void> _saveImageToPrefs(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image_path', imagePath); // Use distinct key
  }

  Future<void> _loadImageFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _profileImagePath = prefs.getString('profile_image_path');
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green[700]),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  // --- Weight Update Logic ---
  void _startEditingWeight() {
    setState(() {
      _originalWeight =
          _userMetrics['weight']?.toString() ?? ''; // Store current value
      _weightController.text = _originalWeight; // Set controller text
      _isEditingWeight = true;
    });
  }

  void _cancelEditingWeight() {
    setState(() {
      _weightController.text = _originalWeight; // Restore original value
      _isEditingWeight = false;
    });
  }

  Future<void> _saveWeight() async {
    if (_userId == null) return;
    final String newWeightString = _weightController.text.trim();
    double? newWeight;

    if (newWeightString.isEmpty) {
      _showErrorSnackBar('Weight cannot be empty.');
      return;
    }

    try {
      newWeight = double.parse(newWeightString);
      if (newWeight <= 0) {
        _showErrorSnackBar('Weight must be a positive number.');
        return;
      }
    } catch (e) {
      _showErrorSnackBar('Invalid weight format. Please enter a valid number.');
      return;
    }

    // --- Optimistic UI Update ---
    final currentMetrics =
        Map<String, dynamic>.from(_userMetrics); // Copy current state
    final wasEditing = _isEditingWeight; // Store current edit state
    setState(() {
      _userMetrics['weight'] =
          newWeight.toString(); // Update local state immediately
      // Recalculate BMI optimistically
      try {
        double heightCm = double.parse(currentMetrics['height'] ?? '0');
        if (heightCm > 0) {
          double heightM = heightCm / 100.0;
          double bmi = newWeight! / (heightM * heightM);
          _userMetrics['bmi'] = bmi.toStringAsFixed(1);
        } else {
          _userMetrics['bmi'] = 'N/A'; // Cannot calculate BMI without height
        }
      } catch (_) {
        _userMetrics['bmi'] = 'N/A'; // Handle parsing errors
      }
      _isEditingWeight = false; // Exit edit mode
    });
    // --- End Optimistic UI Update ---

    // --- API Call to Update Backend ---
    // TODO: Replace with your actual API endpoint and structure
    final url =
        '$apiBaseUrl/rr/metrics/$_userId'; // Example update endpoint (might need metric_id)
    final body = json.encode({'weight': newWeight});

    try {
      final response = await http
          .put(
            // Or PATCH
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        _showSuccessSnackBar('Weight updated successfully!');
        // Optional: Re-fetch metrics to confirm, or rely on optimistic update
        // await _fetchMetrics();
      } else {
        // --- Revert Optimistic Update on Error ---
        setState(() {
          _userMetrics = currentMetrics; // Restore previous metrics
          _isEditingWeight =
              wasEditing; // Restore previous edit state if needed
          _weightController.text = _originalWeight; // Restore controller
        });
        _showErrorSnackBar(
            'Failed to update weight. Server error: ${response.statusCode}');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _userMetrics = currentMetrics;
          _isEditingWeight = wasEditing;
          _weightController.text = _originalWeight;
        });
        _showErrorSnackBar('Failed to update weight: Connection timed out.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userMetrics = currentMetrics;
          _isEditingWeight = wasEditing;
          _weightController.text = _originalWeight;
        });
        _showErrorSnackBar('An error occurred while updating weight: $e');
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear user session data
    if (mounted) {
      // Check if widget is still mounted before navigating
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (context) =>
                SignUpOrLoginPage()), // Navigate to Landing/Login
        (Route<dynamic> route) => false, // Remove all routes behind it
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground, // Use clean background
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: kColorPrimaryDark, // Use consistent dark teal
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0, // Subtle elevation
        centerTitle: true, // Center title for a balanced look
      ),
      drawer: _buildDrawer(context), // Reuse drawer logic
      body: RefreshIndicator(
        // Allow pull-to-refresh
        onRefresh: _fetchData,
        color: kColorPrimary,
        child: _isLoading
            ? _buildLoadingShimmer() // Show shimmer while loading
            : _fetchError.isNotEmpty
                ? _buildErrorState(_fetchError) // Show error state
                : ListView(
                    // Use ListView for scrollable content
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      _buildProfileHeader(),
                      const SizedBox(height: 24.0), // Increased spacing
                      _buildUserDetailsCard(),
                      const SizedBox(height: 16.0),
                      _buildMetricsCard(),
                      const SizedBox(height: 16.0),
                      _buildPreferencesCard(),
                      const SizedBox(height: 24.0), // Space at the bottom
                    ],
                  ),
      ),
    );
  }

  // --- Shimmer Loading Widget ---
  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: kShimmerBaseColor,
      highlightColor: kShimmerHighlightColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Shimmer for Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CircleAvatar(radius: 60, backgroundColor: Colors.white),
              const SizedBox(height: 12),
              Container(height: 20, width: 150, color: Colors.white),
              const SizedBox(height: 8),
              Container(height: 16, width: 200, color: Colors.white),
            ],
          ),
          const SizedBox(height: 24.0),
          // Shimmer for Cards
          _buildShimmerCard(itemCount: 5), // User Details placeholder
          const SizedBox(height: 16.0),
          _buildShimmerCard(itemCount: 3), // Metrics placeholder
          const SizedBox(height: 16.0),
          _buildShimmerCard(itemCount: 3), // Preferences placeholder
        ],
      ),
    );
  }

  Widget _buildShimmerCard({required int itemCount}) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: kColorSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              height: 20, width: 120, color: Colors.white), // Title placeholder
          const SizedBox(height: 12),
          const Divider(color: kColorDivider, height: 1),
          const SizedBox(height: 12),
          ...List.generate(
              itemCount,
              (index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Container(
                            height: 16,
                            width: 16,
                            color: Colors.white), // Icon placeholder
                        const SizedBox(width: 8),
                        Container(
                            height: 16,
                            width: 80,
                            color: Colors.white), // Label placeholder
                        const Spacer(),
                        Container(
                            height: 16,
                            width: 100,
                            color: Colors.white), // Value placeholder
                      ],
                    ),
                  )),
        ],
      ),
    );
  }

  // --- Error State Widget ---
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.red.shade700),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
              onPressed: _fetchData, // Retry fetching all data
              style: ElevatedButton.styleFrom(
                foregroundColor: kColorTextOnPrimary,
                backgroundColor: kColorPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- Refined Widgets ---

  Widget _buildProfileHeader() {
    ImageProvider<Object> avatarImage;
    // Prioritize fetched network image URL
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      avatarImage = CachedNetworkImageProvider(_profileImageUrl!);
    }
    // Fallback to locally picked image path
    else if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        avatarImage = FileImage(file);
      } else {
        avatarImage = const AssetImage(
            'assets/images/proffr.png'); // Default if local file missing
      }
    }
    // Default asset image
    else {
      avatarImage = const AssetImage('assets/images/proffr.png');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment
                .center, // Center the overlay icon relative to the stack
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor:
                    kColorPrimaryLightest, // Placeholder background
                backgroundImage: avatarImage,
                onBackgroundImageError: (exception, stackTrace) {
                  print("Error loading profile image: $exception");
                  // Optionally set state to show default if network image fails
                },
                // Add a fallback icon if image fails to load?
                // child: avatarImage == null ? Icon(Icons.person, size: 60, color: kColorPrimary) : null,
              ),
              // Edit icon overlay - more subtle
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: kColorPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_outlined,
                      size: 18, color: kColorTextOnPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16), // Increased spacing
        Text(
          // Provide default 'User' more gracefully
          _userDetails.isNotEmpty ? (_userDetails['Name'] ?? 'User') : 'User',
          style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: kColorTextPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        if (_userDetails.isNotEmpty && _userDetails['Email'] != 'N/A')
          Text(
            _userDetails['Email'] ?? '',
            style:
                GoogleFonts.poppins(fontSize: 15, color: kColorTextSecondary),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  // --- Refined Card Builders ---

  Widget _buildStyledCard(
      {required String title, required List<Widget> children}) {
    return Card(
      elevation: 2.0, // Softer elevation
      shadowColor: kColorPrimaryLighter.withOpacity(0.5),
      margin: EdgeInsets.zero, // Margin handled by SizedBox outside
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Consistent rounding
        // Optional: Add subtle border
        // side: BorderSide(color: kColorBorder.withOpacity(0.7), width: 1),
      ),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kColorPrimaryDark),
            ),
            const Divider(
                color: kColorDivider,
                thickness: 1,
                height: 24), // Themed divider
            ...children, // Spread the list of child widgets
          ],
        ),
      ),
    );
  }

  // Helper function to format the date string
  String _formatJoinedDate(String? dateString) {
    if (dateString == null || dateString == 'N/A') {
      return 'N/A';
    }
    try {
      final dateTime = DateTime.parse(dateString);
      // Format: Apr 14, 2025\n6:18 AM
      return DateFormat('MMM d, yyyy\nh:mm a').format(dateTime);
    } catch (e) {
      print("Error parsing date: $e");
      return dateString; // Return original string if parsing fails
    }
  }

  Widget _buildUserDetailsCard() {
    return _buildStyledCard(
      title: 'User Details',
      children: [
        _buildInfoRow(
            icon: Icons.badge_outlined,
            label: 'User ID',
            value: _userDetails['User_Id']?.toString() ?? 'N/A'),
        _buildInfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: _userDetails['Email'] ?? 'N/A'),
        _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: _userDetails['Phone_Number'] ?? 'N/A'),
        _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: _userDetails['Location'] ?? 'N/A'),
        _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Joined',
            // Format the date here before passing
            value: _formatJoinedDate(_userDetails['Registration_Date'])),
      ],
    );
  }

  Widget _buildMetricsCard() {
    return _buildStyledCard(
      title: 'Health Metrics',
      children: [
        _buildInfoRow(
            icon: Icons.height_outlined,
            label: 'Height',
            value: '${_userMetrics['height'] ?? 'N/A'} cm'),
        _buildInfoRow(
          icon: Icons.fitness_center_outlined,
          label: 'Weight',
          value: _isEditingWeight
              ? null
              : '${_userMetrics['weight'] ?? 'N/A'} kg', // Show value only when not editing
          isEditing: _isEditingWeight,
          controller: _weightController,
          keyboardType:
              TextInputType.numberWithOptions(decimal: true), // Allow decimals
          onEdit: _startEditingWeight,
          onSave: _saveWeight,
          onCancel: _cancelEditingWeight,
        ),
        _buildInfoRow(
            icon: Icons.monitor_weight_outlined,
            label: 'BMI',
            value: _userMetrics['bmi'] ?? 'N/A'),
        const SizedBox(height: 8), // Add space before BMI indicator if desired
        if (_userMetrics['bmi'] != null && _userMetrics['bmi'] != 'N/A')
          _buildBmiVisualIndicator(), // Show indicator only if BMI available
      ],
    );
  }

  Widget _buildPreferencesCard() {
    return _buildStyledCard(
      title: 'Preferences',
      children: [
        _buildInfoRow(
            icon: Icons.flag_outlined,
            label: 'Goals',
            value: _userPreferences['goals'] ?? 'Not Set'),
        _buildInfoRow(
            icon: Icons.restaurant_menu_outlined,
            label: 'Diet Type',
            value: _userPreferences['diet_type'] ?? 'Not Set'),
        _buildInfoRow(
            icon: Icons.no_food_outlined,
            label: 'Restrictions',
            value: _userPreferences['food_restrictions'] ??
                'None'), // Use 'None' if empty/N/A
        const SizedBox(height: 16), // Space before button
        Center(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AllMealsScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kColorPrimary, // Use themed button color
              foregroundColor: kColorTextOnPrimary, // Ensure text is white
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 20),
            label:
                Text('View Meal Recommendations', style: GoogleFonts.poppins()),
          ),
        ),
      ],
    );
  }

  // Refined Info Row Widget
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String? value, // Value can be null if editing
    bool isEditing = false,
    TextEditingController? controller,
    TextInputType? keyboardType,
    VoidCallback? onEdit,
    VoidCallback? onSave,
    VoidCallback? onCancel,
  }) {
    final labelStyle = GoogleFonts.poppins(
        fontWeight: FontWeight.w500, color: kColorTextSecondary, fontSize: 15);
    final valueStyle =
        GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 15);
    final editingInputDecoration = InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kColorBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kColorPrimary, width: 1.5)),
      // hintText: 'Enter $label',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 10.0), // Increased vertical padding
      child: Row(
        crossAxisAlignment: CrossAxisAlignment
            .start, // Align items to the top for multi-line text
        children: [
          Icon(icon, color: kColorPrimary, size: 22), // Themed icon
          const SizedBox(width: 12),
          Text(label, style: labelStyle),
          const Spacer(), // Pushes value/editing tools to the right
          if (isEditing && controller != null)
            Expanded(
              // Allow TextField to take available space
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    // TextField takes most space
                    child: TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      style: valueStyle,
                      textAlign: TextAlign.right, // Align text right
                      decoration: editingInputDecoration,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Save Button
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline,
                        color: Colors.green),
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: "Save",
                    onPressed: onSave,
                  ),
                  // Cancel Button
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: "Cancel",
                    onPressed: onCancel,
                  ),
                ],
              ),
            )
          else
            Row(
              // Display value and edit button
              children: [
                Text(value ?? 'N/A',
                    style: valueStyle, textAlign: TextAlign.right),
                if (onEdit !=
                    null) // Show edit button only if callback provided
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: kColorTextSecondary),
                    padding: const EdgeInsets.only(
                        left: 8), // Add padding to the left
                    constraints: const BoxConstraints(),
                    tooltip: "Edit $label",
                    onPressed: onEdit,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // BMI Indicator (Minor style tweaks)
  Widget _buildBmiVisualIndicator() {
    double bmiValue = 0;
    try {
      bmiValue = double.parse(_userMetrics['bmi'] ?? '0');
    } catch (_) {/* Ignore parsing errors, defaults to 0 */}

    // Define thresholds (can be constants)
    const double underweightThreshold = 18.5;
    const double normalThreshold = 24.9;
    const double overweightThreshold = 29.9;
    const double obesityThreshold =
        40.0; // Define an upper reasonable limit for visualization

    // Normalize BMI to a 0-1 scale based on categories
    double positionFactor;
    Color indicatorColor;

    if (bmiValue < underweightThreshold) {
      positionFactor = 0.1; // Position within underweight zone
      indicatorColor = Colors.blue.shade300;
    } else if (bmiValue < normalThreshold) {
      positionFactor = 0.35 +
          0.3 *
              ((bmiValue - underweightThreshold) /
                  (normalThreshold -
                      underweightThreshold)); // Position within normal zone (approx 0.35-0.65)
      indicatorColor = Colors.green.shade400;
    } else if (bmiValue < overweightThreshold) {
      positionFactor = 0.65 +
          0.2 *
              ((bmiValue - normalThreshold) /
                  (overweightThreshold -
                      normalThreshold)); // Position within overweight zone (approx 0.65-0.85)
      indicatorColor = Colors.orange.shade400;
    } else {
      // Position within obesity zone, capped at 1.0
      positionFactor = min(
          1.0,
          0.85 +
              0.15 *
                  ((bmiValue - overweightThreshold) /
                      (obesityThreshold - overweightThreshold)));
      indicatorColor = Colors.red.shade400;
    }
    // Clamp positionFactor just in case
    positionFactor = positionFactor.clamp(0.0, 1.0);

    return Container(
      height: 8, // Thinner bar
      // width: 150, // No need for fixed width if using Row/Spacer layout
      clipBehavior: Clip.antiAlias, // Clip indicator dot
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade300,
            Colors.green.shade400,
            Colors.orange.shade400,
            Colors.red.shade400
          ],
          stops: const [
            0.1,
            0.35,
            0.65,
            0.85
          ], // Adjusted stops visually map better
        ),
      ),
      // Optional: Add a marker instead of filling the bar
      // child: Align(
      //   alignment: Alignment(positionFactor * 2 - 1, 0), // Map 0-1 to -1 to 1 for Alignment
      //   child: Container(
      //     width: 10, height: 10,
      //     decoration: BoxDecoration(shape: BoxShape.circle, color: indicatorColor, border: Border.all(color: Colors.white, width: 1.5)),
      //   ),
      // ),
    );
  }

  // Refined Drawer Widget
  Widget _buildDrawer(BuildContext context) {
    // (Implementation remains the same as the one provided in the previous fix for AllMealsScreen)
    // Use UserAccountsDrawerHeader, _buildDrawerTile helper, themed icons/colors
    final textTheme = Theme.of(context).textTheme;
    String userName = _isLoadingUserDetails
        ? "Loading..."
        : (_userDetails['Name'] ?? 'User Name');
    String userEmail =
        _isLoadingUserDetails ? "" : (_userDetails['Email'] ?? '');
    String? currentProfileImage = _profileImagePath; // Use local path first
    // TODO: Prioritize fetched URL if implemented: String? currentProfileImage = _profileImageUrl ?? _profileImagePath;

    ImageProvider<Object> avatarImage;
    // Prioritize fetched network image URL from state
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      avatarImage = CachedNetworkImageProvider(_profileImageUrl!);
    }
    // Fallback to locally picked image path from state
    else if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (file.existsSync()) {
        avatarImage = FileImage(file);
      } else {
        print("Local profile image file not found: $_profileImagePath");
        avatarImage = const AssetImage(
            'assets/images/proffr.png'); // Default if local file missing
      }
    }
    // Default asset image
    else {
      avatarImage = const AssetImage('assets/images/proffr.png');
    }

    // Helper for list tiles
    Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon,
            color: color ?? kColorPrimary), // Use primary color by default
        title: Text(title,
            style: GoogleFonts.poppins(
                color: color ?? kColorTextPrimary,
                fontSize: 15)), // Use Poppins
        onTap: onTap,
        dense: true, // Make tiles slightly more compact
      );
    }

    return Drawer(
      child: Container(
        color: kColorSurface, // Use surface color for drawer background
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                userName,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: kColorTextOnPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              accountEmail: userEmail.isNotEmpty
                  ? Text(
                      userEmail,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: kColorTextOnPrimary.withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              currentAccountPicture: CircleAvatar(
                radius: 35,
                backgroundColor: kColorSurface.withOpacity(0.8),
                backgroundImage: avatarImage,
                onBackgroundImageError: (_, __) {
                  print("Error loading profile picture.");
                },
                child: _isLoadingUserDetails && currentProfileImage == null
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(kColorPrimary)))
                    : null,
              ),
              decoration: const BoxDecoration(
                color: kColorPrimaryDark,
              ), // Dark teal header
              margin: EdgeInsets.zero,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerTile(Icons.person_outline, 'Profile', () {
                    Navigator.pop(context); /* Already on profile */
                  }),
                  _buildDrawerTile(
                      Icons.analytics_outlined, 'Analytics Dashboard', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const UserAnalyticsDashboard()));
                  }),
                  _buildDrawerTile(Icons.restaurant_menu_outlined, 'Meals', () {
                    // Link back to Meals
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AllMealsScreen()));
                  }),
                  const Divider(height: 1, color: kColorDivider),
                  _buildDrawerTile(
                      Icons.shopping_cart_outlined, 'Shopping Cart', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => cart.ShoppingCartScreen()));
                  }),
                  _buildDrawerTile(Icons.article_outlined, 'Blog', () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const BlogScreen(
                                url: 'https://artchwezi.blogspot.com/')));
                  }),
                  _buildDrawerTile(
                      Icons.groups_outlined, 'Wellness Communities', () {
                    // Changed Icon
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                SocialMediaScreen())); // Navigate to Social
                  }),
                  _buildDrawerTile(Icons.help_outline, 'Help', () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Help Section Coming Soon!')));
                  }),
                  const Divider(height: 1, color: kColorDivider),
                  _buildDrawerTile(Icons.logout, 'Logout', _logout,
                      color: Colors.red.shade700), // Specific color
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
